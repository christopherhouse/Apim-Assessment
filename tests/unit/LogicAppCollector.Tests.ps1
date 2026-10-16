$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force
AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Cost-only Logic Apps collection' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:logicRepository = $Repository
        BeforeEach {
            $script:logicConfig = Import-PowerShellDataFile (Join-Path $script:logicRepository config/sample.psd1)
            $script:logicConfig.Windows.MetricDays = 1
            $script:logicConfig.Output.Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $script:logicRun = New-ApimRun -Config $script:logicConfig -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000010' -Operator Synthetic `
                -RunId synthetic-logic -IncludeTelemetry -StartedUtc '2026-10-15T00:00:00Z'
            Save-ApimRunSetting -RunPath $script:logicRun.Path -Config $script:logicConfig `
                -Environment $script:logicConfig.Environments[0]
            $script:logicPrefix = "/subscriptions/$($script:logicConfig.Environments[0].SubscriptionId)/resourceGroups/rg-example-prod/providers"
            Mock Invoke-ApimResourceGraphQuery {
                if ($Query -match 'skuName=') {
                    [pscustomobject]@{ id = "$script:logicPrefix/Microsoft.Web/serverfarms/plan-synthetic"; skuName = 'WS1'; instances = 2 }
                } else {
                    [pscustomobject]@{ id = "$script:logicPrefix/Microsoft.Logic/workflows/logic-synthetic"; type = 'microsoft.logic/workflows'; planId = '' }
                    [pscustomobject]@{ id = "$script:logicPrefix/Microsoft.Web/sites/logic-standard"; type = 'microsoft.web/sites'; planId = "$script:logicPrefix/Microsoft.Web/serverfarms/plan-synthetic" }
                }
            }
            Mock Invoke-ApimMetricSeries {
                $count = if ($Definition.Interval -ceq 'P1D') { 1 } else { 24 }
                [pscustomobject]@{
                    name = $Definition.Name; unit = $Definition.Unit; interval = $Definition.Interval
                    expectedPoints = $count; status = 'Completed'
                    points = @(
                        for ($index = 0; $index -lt $count; $index++) {
                            [pscustomobject]@{
                                timestamp = ([datetimeoffset] $Window.startUtc).AddHours($index).ToString('O')
                                average = if ($Definition.Aggregations -contains 'Average') { 10.0 } else { $null }
                                maximum = $null
                                total = if ($Definition.Aggregations -contains 'Total') { 1000.0 } else { $null }
                            }
                        }
                    )
                }
            }
            Mock Invoke-ApimArm { throw 'Workflow definitions must never be read.' }
        }

        It 'projects Consumption and Standard plan evidence without reading any workflow definition' {
            Invoke-ApimLogicAppCollector -RunPath $script:logicRun.Path -Environment $script:logicConfig.Environments[0]
            $record = @((Get-RunManifest -RunPath $script:logicRun.Path).collectors | Where-Object name -CEQ LogicApps)[0]
            $record.status | Should -Be Completed
            Test-ApimLogicAppSavedOutput -RunPath $script:logicRun.Path -Collector $record | Should -Be 2
            $payload = Read-ApimLogicAppEvidence -RunPath $script:logicRun.Path
            ($payload.groups[0].resources | Where-Object kind -CEQ Standard).sku | Should -Be WS1
            Should -Invoke Invoke-ApimArm -Exactly -Times 0
            Should -Invoke Invoke-ApimMetricSeries -Exactly -Times 1 -ParameterFilter {
                $ResourceId -like '*/serverfarms/plan-synthetic'
            }
            $payload.groups[0].resources[0] | Add-Member -NotePropertyName definition -NotePropertyValue 'SYNTHETIC_FORBIDDEN'
            $null = Write-RunFile -RunPath $script:logicRun.Path -RelativePath cost/logicApps.json -InputObject $payload
            { Test-ApimLogicAppSavedOutput -RunPath $script:logicRun.Path -Collector $record } | Should -Throw
        }

        It 'retains failed metric coverage and isolates inventory failures without inventing zero usage' {
            Mock Invoke-ApimMetricSeries { throw 'Synthetic unsupported metric.' }
            Invoke-ApimLogicAppCollector -RunPath $script:logicRun.Path -Environment $script:logicConfig.Environments[0]
            $record = @((Get-RunManifest -RunPath $script:logicRun.Path).collectors | Where-Object name -CEQ LogicApps)[0]
            $record.status | Should -Be Partial
            Test-ApimLogicAppSavedOutput -RunPath $script:logicRun.Path -Collector $record | Should -Be 2
            Mock Invoke-ApimResourceGraphQuery { throw 'Synthetic missing inventory.' }
            Invoke-ApimLogicAppCollector -RunPath $script:logicRun.Path -Environment $script:logicConfig.Environments[0]
            $record = @((Get-RunManifest -RunPath $script:logicRun.Path).collectors | Where-Object name -CEQ LogicApps)[0]
            Test-ApimLogicAppSavedOutput -RunPath $script:logicRun.Path -Collector $record | Should -Be 0
            $record.status | Should -Be Partial
        }

        It 'honors SkipCost before inventory or metrics are requested' {
            Save-ApimRunSetting -RunPath $script:logicRun.Path -Config $script:logicConfig `
                -Environment $script:logicConfig.Environments[0] -SkipCost
            Invoke-ApimLogicAppCollector -RunPath $script:logicRun.Path -Environment $script:logicConfig.Environments[0]
            $record = @((Get-RunManifest -RunPath $script:logicRun.Path).collectors | Where-Object name -CEQ LogicApps)[0]
            $record.status | Should -Be Skipped
            Test-ApimLogicAppSavedOutput -RunPath $script:logicRun.Path -Collector $record | Should -Be 0
            Should -Invoke Invoke-ApimResourceGraphQuery -Exactly -Times 0
            Should -Invoke Invoke-ApimMetricSeries -Exactly -Times 0
        }
    }
}
