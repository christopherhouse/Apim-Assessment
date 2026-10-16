$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Guarded resource metric collection' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:metricCollectorRepository = $Repository

        BeforeAll {
            function Get-SyntheticMetricResponse {
                param([string] $Uri)
                $metricName = [regex]::Match($Uri, 'metricnames=([^&]+)').Groups[1].Value
                $definition = @(
                    foreach ($kind in @('Apim', 'AppGateway')) {
                        Get-ApimMetricDefinition -Kind $kind | Where-Object Name -CEQ $metricName
                    }
                )[0]
                $count = if ($definition.Interval -ceq 'P1D') { 1 } else { 24 }
                $points = @(
                    for ($index = 0; $index -lt $count; $index++) {
                        $row = [ordered]@{
                            timeStamp = ([datetimeoffset] '2026-10-14T00:00:00Z').AddHours($index).ToString('O')
                            unknown = 'SYNTHETIC_DROP_SENTINEL'
                        }
                        foreach ($aggregation in $definition.Aggregations) {
                            $row[$aggregation.ToLowerInvariant()] = 10.0
                        }
                        [pscustomobject] $row
                    }
                )
                [pscustomobject]@{
                    value = @([pscustomobject]@{
                            name = @{ value = $metricName }; unit = $definition.Unit
                            timeseries = @([pscustomobject]@{ data = $points })
                            unknown = 'SYNTHETIC_DROP_SENTINEL'
                        })
                }
            }
        }

        BeforeEach {
            $script:metricConfig = Import-PowerShellDataFile (
                Join-Path $script:metricCollectorRepository 'config/sample.psd1'
            )
            $script:metricConfig.Windows.MetricDays = 1
            $script:metricConfig.Output.Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $script:metricRun = New-ApimRun -Config $script:metricConfig -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000010' -Operator Synthetic `
                -RunId synthetic-metrics -IncludeTelemetry -StartedUtc '2026-10-15T00:00:00Z'
            Save-ApimRunSetting -RunPath $script:metricRun.Path -Config $script:metricConfig `
                -Environment $script:metricConfig.Environments[0]
            Mock Invoke-ApimArm { Get-SyntheticMetricResponse -Uri $Uri }
        }

        It 'writes both resources with separate hourly/daily aggregations and no unknown response fields' {
            Invoke-ApimMetricsCollector -RunPath $script:metricRun.Path -Environment $script:metricConfig.Environments[0]
            $manifest = Get-RunManifest -RunPath $script:metricRun.Path
            $record = @($manifest.collectors | Where-Object name -CEQ Metrics)[0]
            $record.status | Should -BeExactly Completed
            $record.items | Should -Be 145
            $record.files | Should -Be @('metrics/apim.json', 'metrics/appgw.json')
            $coverage = @($manifest.evidenceWindows | Where-Object kind -CEQ Metric)
            $coverage.Count | Should -Be 2
            @($coverage | Where-Object { $_.isCapped -or $null -ne $_.retentionDays }).Count | Should -Be 0
            $apim = Read-ApimSmokeOutputJson -RunPath $script:metricRun.Path -RelativePath metrics/apim.json
            @($apim.resources[0].metrics | Where-Object name -CEQ Requests)[0].points.Count | Should -Be 1
            @($apim.resources[0].metrics | Where-Object name -CEQ Capacity)[0].points.Count | Should -Be 24
            foreach ($file in $record.files) {
                Get-Content -LiteralPath (Join-Path $script:metricRun.Path $file) -Raw |
                    Should -Not -Match 'SYNTHETIC_DROP_SENTINEL|unknown'
            }
            Should -Invoke Invoke-ApimArm -Exactly -Times 7 -ParameterFilter {
                $Uri -match '/providers/Microsoft.Insights/metrics\?' -and $Method -in @($null, '', 'GET')
            }
        }

        It 'isolates unsupported capacity while retaining request and gateway metrics' {
            Mock Invoke-ApimArm {
                if ($Uri -match 'metricnames=Capacity&') { throw 'Synthetic unsupported metric.' }
                Get-SyntheticMetricResponse -Uri $Uri
            }
            Invoke-ApimMetricsCollector -RunPath $script:metricRun.Path -Environment $script:metricConfig.Environments[0]
            $manifest = Get-RunManifest -RunPath $script:metricRun.Path
            @($manifest.collectors | Where-Object name -CEQ Metrics)[0].status | Should -BeExactly Partial
            $apim = Read-ApimSmokeOutputJson -RunPath $script:metricRun.Path -RelativePath metrics/apim.json
            @($apim.resources[0].metrics | Where-Object name -CEQ Capacity)[0].status | Should -BeExactly Failed
            @($apim.resources[0].metrics | Where-Object name -CEQ Requests)[0].status | Should -BeExactly Completed
            $gateway = Read-ApimSmokeOutputJson -RunPath $script:metricRun.Path -RelativePath metrics/appgw.json
            @($gateway.resources[0].metrics | Where-Object status -CNE Completed).Count | Should -Be 0
        }

        It 'retains null samples and qualifies missing bins rather than reporting zero utilization' {
            Mock Invoke-ApimArm {
                $result = Get-SyntheticMetricResponse -Uri $Uri
                $result.value[0].timeseries[0].data = @([pscustomobject]@{ timeStamp = '2026-10-14T00:00:00Z' })
                $result
            }
            Invoke-ApimMetricsCollector -RunPath $script:metricRun.Path -Environment $script:metricConfig.Environments[0]
            $apim = Read-ApimSmokeOutputJson -RunPath $script:metricRun.Path -RelativePath metrics/apim.json
            $capacity = @($apim.resources[0].metrics | Where-Object name -CEQ Capacity)[0]
            $capacity.status | Should -BeExactly Partial
            $capacity.expectedPoints | Should -Be 24
            $capacity.points[0].average | Should -BeNullOrEmpty
            $capacity.points[0].maximum | Should -BeNullOrEmpty
        }

        It 'rejects mismatched units and duplicate timestamps in a metric response' {
            $definition = @(Get-ApimMetricDefinition -Kind Apim | Where-Object Name -CEQ Capacity)[0]
            $window = Get-ApimEvidenceWindow -EndUtc '2026-10-15T00:00:00Z' -Kind Metric -Length 1
            Mock Invoke-ApimArm {
                $result = Get-SyntheticMetricResponse -Uri $Uri
                $result.value[0].unit = 'Seconds'
                $result
            }
            { Invoke-ApimMetricSeries -ResourceId '/synthetic' -Definition $definition -Window $window `
                    -LogPath (Join-Path $script:metricRun.Path logs/run.log) } | Should -Throw '*name or unit*'
            Mock Invoke-ApimArm {
                $result = Get-SyntheticMetricResponse -Uri $Uri
                $result.value[0].timeseries[0].data += $result.value[0].timeseries[0].data[0]
                $result
            }
            { Invoke-ApimMetricSeries -ResourceId '/synthetic' -Definition $definition -Window $window `
                    -LogPath (Join-Path $script:metricRun.Path logs/run.log) } | Should -Throw '*duplicate timestamps*'
        }

        It 'validates closed saved samples and rejects unknown fields or dishonest completeness' {
            Invoke-ApimMetricsCollector -RunPath $script:metricRun.Path -Environment $script:metricConfig.Environments[0]
            $record = @((Get-RunManifest -RunPath $script:metricRun.Path).collectors |
                    Where-Object name -CEQ Metrics)[0]
            Test-ApimMetricSavedOutput -RunPath $script:metricRun.Path -Collector $record | Should -Be 145
            $payload = Read-ApimMetricEvidence -RunPath $script:metricRun.Path -Kind Apim
            $payload.resources[0].metrics[0].points[0] |
                Add-Member -NotePropertyName rawResponse -NotePropertyValue 'SYNTHETIC_DISALLOWED_FIELD'
            $null = Write-RunFile -RunPath $script:metricRun.Path -RelativePath metrics/apim.json -InputObject $payload
            { Test-ApimMetricSavedOutput -RunPath $script:metricRun.Path -Collector $record } | Should -Throw
            $payload.resources[0].metrics[0].points[0].PSObject.Properties.Remove('rawResponse')
            $payload.resources[0].metrics[0].points = @()
            $null = Write-RunFile -RunPath $script:metricRun.Path -RelativePath metrics/apim.json -InputObject $payload
            { Test-ApimMetricSavedOutput -RunPath $script:metricRun.Path -Collector $record } |
                Should -Throw '*sample coverage*'
        }
    }
}
