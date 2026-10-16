$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Bounded daily cost collection' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:costCollectorRepository = $Repository

        BeforeAll {
            $script:costArmTransport = (Get-Command Invoke-ApimArm).ScriptBlock
            function Get-SyntheticCostResponse {
                param([string] $Body)
                $query = ConvertFrom-Json -InputObject $Body
                $detail = $query.dataset.grouping[1].name -ceq 'MeterSubCategory'
                $groupName = if ($detail) { 'MeterSubCategory' } else { 'MeterCategory' }
                $columns = @(
                    [pscustomobject]@{ name = 'Currency'; type = 'String' }
                    [pscustomobject]@{ name = $groupName; type = 'String' }
                    [pscustomobject]@{ name = 'ResourceId'; type = 'String' }
                    [pscustomobject]@{ name = 'UsageDate'; type = 'Number' }
                    [pscustomobject]@{ name = 'PreTaxCost'; type = 'Number' }
                    [pscustomobject]@{ name = 'UnwantedField'; type = 'String' }
                )
                $rows = @()
                if ($detail) {
                    $rows = @(
                        @('USD', 'Premium', $script:costResourceId, 20260901, 12.0, 'SYNTHETIC_DROP_SENTINEL'),
                        @('USD', 'Credit', $script:costResourceId, 20260901, -2.0, 'SYNTHETIC_DROP_SENTINEL')
                    )
                }
                else {
                    $rows = @(,@('USD', 'API Management', $script:costResourceId, 20260901, 10.0, 'SYNTHETIC_DROP_SENTINEL'))
                }
                [pscustomobject]@{
                    properties = [pscustomobject]@{ columns = $columns; rows = @($rows); nextLink = $null }
                }
            }
        }

        BeforeEach {
            $script:costConfig = Import-PowerShellDataFile (
                Join-Path $script:costCollectorRepository 'config/sample.psd1'
            )
            $script:costConfig.Windows.CostMonths = 2
            $script:costConfig.Output.Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $script:costRun = New-ApimRun -Config $script:costConfig -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000010' -Operator Synthetic `
                -RunId synthetic-cost -IncludeTelemetry -StartedUtc '2026-10-15T22:00:00Z'
            $script:costResourceId = (Get-RunManifest -RunPath $script:costRun.Path).apim.resourceId
            Save-ApimRunSetting -RunPath $script:costRun.Path -Config $script:costConfig `
                -Environment $script:costConfig.Environments[0]
            Mock Invoke-ApimArm { Get-SyntheticCostResponse -Body $Body }
        }

        It 'uses two grouping clauses, reconciles subcategories and preserves legitimate credits' {
            Invoke-ApimCostCollector -RunPath $script:costRun.Path -Environment $script:costConfig.Environments[0]
            $manifest = Get-RunManifest -RunPath $script:costRun.Path
            $record = @($manifest.collectors | Where-Object name -CEQ Cost)[0]
            $record.status | Should -BeExactly Completed
            $record.items | Should -Be 2
            $record.files | Should -Be @('cost/daily.json')
            $payload = Read-ApimSmokeOutputJson -RunPath $script:costRun.Path -RelativePath cost/daily.json
            @($payload.scopes[0].rows | Where-Object meterSubCategory -CEQ Credit)[0].cost | Should -Be -2
            @($payload.scopes[0].rows | Where-Object meterSubCategory -CEQ Premium)[0].meterCategory |
                Should -BeExactly 'API Management'
            Get-Content -LiteralPath (Join-Path $script:costRun.Path cost/daily.json) -Raw |
                Should -Not -Match 'SYNTHETIC_DROP_SENTINEL|UnwantedField'
            Should -Invoke Invoke-ApimArm -Exactly -Times 2 -ParameterFilter {
                $query = ConvertFrom-Json -InputObject $Body
                $Method -ceq 'POST' -and $Uri -match '/providers/Microsoft.CostManagement/query\?' -and
                $query.type -ceq 'ActualCost' -and $query.dataset.granularity -ceq 'Daily' -and
                $query.dataset.grouping.Count -eq 2 -and
                ([datetimeoffset] $query.timePeriod.from) -eq [datetimeoffset] '2026-08-01T00:00:00Z'
            }
        }

        It 'does not infer missing subcategory detail from category totals' {
            Mock Invoke-ApimArm {
                $result = Get-SyntheticCostResponse -Body $Body
                $query = ConvertFrom-Json -InputObject $Body
                if ($query.dataset.grouping[1].name -ceq 'MeterSubCategory') {
                    $result.properties.rows[0][4] = 100.0
                }
                $result
            }
            Invoke-ApimCostCollector -RunPath $script:costRun.Path -Environment $script:costConfig.Environments[0]
            $manifest = Get-RunManifest -RunPath $script:costRun.Path
            @($manifest.collectors | Where-Object name -CEQ Cost)[0].status | Should -BeExactly Partial
            @($manifest.evidenceWindows | Where-Object kind -CEQ Cost)[0].status | Should -BeExactly Failed
            $payload = Read-ApimSmokeOutputJson -RunPath $script:costRun.Path -RelativePath cost/daily.json
            $payload.scopes[0].rows.Count | Should -Be 0
        }

        It 'fails closed on cost continuation URLs without contacting their token-bearing endpoint' {
            Mock Invoke-ApimArm {
                $result = Get-SyntheticCostResponse -Body $Body
                $result.properties.nextLink = 'https://management.azure.com/synthetic/query?$skiptoken=synthetic'
                $result
            }
            Invoke-ApimCostCollector -RunPath $script:costRun.Path -Environment $script:costConfig.Environments[0]
            $record = @((Get-RunManifest -RunPath $script:costRun.Path).collectors |
                    Where-Object name -CEQ Cost)[0]
            $record.status | Should -BeExactly Partial
            $record.items | Should -Be 0
            Should -Invoke Invoke-ApimArm -Exactly -Times 1
            { Test-ApimArmRequest -Method POST -Uri (
                    '/subscriptions/synthetic/providers/Microsoft.CostManagement/query?$skiptoken=synthetic'
                ) } | Should -Throw '*prohibited*'
        }

        It 'implements cost opt-out before any cost request or invented zero amounts' {
            Save-ApimRunSetting -RunPath $script:costRun.Path -Config $script:costConfig `
                -Environment $script:costConfig.Environments[0] -SkipCost
            Invoke-ApimCostCollector -RunPath $script:costRun.Path -Environment $script:costConfig.Environments[0]
            $manifest = Get-RunManifest -RunPath $script:costRun.Path
            @($manifest.evidenceWindows | Where-Object kind -CEQ Cost)[0].reason | Should -BeExactly OptOut
            @($manifest.collectors | Where-Object name -CEQ Cost)[0].status | Should -BeExactly Skipped
            Test-Path -LiteralPath (Join-Path $script:costRun.Path cost/daily.json) | Should -BeFalse
            Should -Invoke Invoke-ApimArm -Exactly -Times 0
        }

        It 'rejects a response resource outside its requested scope' {
            $script:costResourceId = $script:costResourceId.Replace('rg-example-prod', 'rg-unrelated')
            Invoke-ApimCostCollector -RunPath $script:costRun.Path -Environment $script:costConfig.Environments[0]
            @((Get-RunManifest -RunPath $script:costRun.Path).collectors |
                    Where-Object name -CEQ Cost)[0].status | Should -BeExactly Partial
        }

        It 'rejects duplicate or malformed column mappings rather than using ordinal guesses' {
            $window = Get-ApimEvidenceWindow -EndUtc '2026-10-15T22:00:00Z' -Kind Cost -Length 2
            $payload = Get-SyntheticCostResponse -Body (Get-ApimCostQueryBody -Window $window)
            $payload.properties.columns[0].name = 'ResourceId'
            { ConvertTo-ApimCostQueryRow -Payload $payload -Scope $script:costConfig.Environments[0].CostScopes[0] `
                    -Window $window } | Should -Throw '*ambiguous*'
        }

        It 'inherits the cost-specific 429 retry header handling from the guarded ARM transport' {
            $script:costAttempt = 0
            Mock Start-Sleep {}
            Mock Invoke-ApimArmRequest {
                $script:costAttempt++
                if ($script:costAttempt -eq 1) {
                    return [pscustomobject]@{
                        StatusCode = 429
                        Headers = @{ 'x-ms-ratelimit-microsoft.costmanagement-entity-retry-after' = '9' }
                        Content = '{}'
                    }
                }
                [pscustomobject]@{
                    StatusCode = 200; Headers = @{}
                    Content = ConvertTo-Json -InputObject (Get-SyntheticCostResponse -Body $Body) -Depth 30
                }
            }
            Mock Invoke-ApimArm {
                & $script:costArmTransport -Method $Method -Uri $Uri -Body $Body -LogPath $LogPath
            }
            Invoke-ApimCostCollector -RunPath $script:costRun.Path -Environment $script:costConfig.Environments[0]
            @((Get-RunManifest -RunPath $script:costRun.Path).collectors |
                    Where-Object name -CEQ Cost)[0].status | Should -BeExactly Completed
            Should -Invoke Invoke-ApimArmRequest -Exactly -Times 3
            Should -Invoke Start-Sleep -Exactly -Times 1 -ParameterFilter { $Seconds -eq 9 }
        }

        It 'validates closed cost replay and rejects added fields or forged resource scope' {
            Invoke-ApimCostCollector -RunPath $script:costRun.Path -Environment $script:costConfig.Environments[0]
            $record = @((Get-RunManifest -RunPath $script:costRun.Path).collectors |
                    Where-Object name -CEQ Cost)[0]
            Test-ApimCostSavedOutput -RunPath $script:costRun.Path -Collector $record | Should -Be 2
            $payload = Read-ApimCostEvidence -RunPath $script:costRun.Path
            $payload.scopes[0].rows[0] |
                Add-Member -NotePropertyName rawResponse -NotePropertyValue 'SYNTHETIC_DISALLOWED_FIELD'
            $null = Write-RunFile -RunPath $script:costRun.Path -RelativePath cost/daily.json -InputObject $payload
            { Test-ApimCostSavedOutput -RunPath $script:costRun.Path -Collector $record } | Should -Throw
            $payload.scopes[0].rows[0].PSObject.Properties.Remove('rawResponse')
            $payload.scopes[0].rows[0].resourceId = $payload.scopes[0].rows[0].resourceId.Replace('rg-example-prod', 'rg-unrelated')
            $null = Write-RunFile -RunPath $script:costRun.Path -RelativePath cost/daily.json -InputObject $payload
            { Test-ApimCostSavedOutput -RunPath $script:costRun.Path -Collector $record } | Should -Throw '*outside its scope*'
        }
    }
}
