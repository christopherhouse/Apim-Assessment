$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Versioned telemetry evidence contracts' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:telemetryContractRepository = $Repository

        BeforeEach {
            $script:telemetryContractConfig = Import-PowerShellDataFile (
                Join-Path $script:telemetryContractRepository 'config/sample.psd1'
            )
            $script:telemetryContractConfig.Output.Root = Join-Path $TestDrive (
                [guid]::NewGuid().ToString('N')
            )
            $script:telemetryContractRun = New-ApimRun `
                -Config $script:telemetryContractConfig -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000010' -Operator Synthetic `
                -RunId synthetic-telemetry-contract -IncludeTelemetry `
                -StartedUtc ([datetimeoffset] '2026-10-15T17:00:00-05:00')
        }

        It 'binds equivalent UTC instants and extended scalars identically after JSON replay' {
            $source = @{
                timestamp = [datetimeoffset] '2026-10-15T17:00:00-05:00'
                targets = @('target-a', 'target-b' | Sort-Object)
            }
            $roundTrip = ConvertFrom-Json (ConvertTo-Json $source) -AsHashtable
            Get-ApimConfigDigest -Config $source | Should -Be (Get-ApimConfigDigest -Config $roundTrip)
            $source.timestamp = [datetimeoffset] '2026-10-15T22:00:00Z'
            Get-ApimConfigDigest -Config $source | Should -Be (Get-ApimConfigDigest -Config $roundTrip)
            $roundTrip.targets[0] = 'target-c'
            Get-ApimConfigDigest -Config $source | Should -Not -Be (Get-ApimConfigDigest -Config $roundTrip)
        }

        It 'round trips the run anchor, metric window and normalized replay targets and opt-outs' {
            Save-ApimRunSetting -RunPath $script:telemetryContractRun.Path `
                -Config $script:telemetryContractConfig `
                -Environment $script:telemetryContractConfig.Environments[0] -SkipLogs
            $saved = Get-ApimRunSetting -RunPath $script:telemetryContractRun.Path
            $saved.Manifest.schemaVersion | Should -BeExactly '1.2'
            $saved.Manifest.windows.metricDays | Should -Be 90
            ([datetimeoffset] $saved.Manifest.startedUtc).UtcDateTime.ToString('O') |
                Should -BeExactly '2026-10-15T22:00:00.0000000Z'
            $saved.Manifest.evidenceWindows.Count | Should -Be 0
            $saved.Settings.schemaVersion | Should -BeExactly '1.1'
            $saved.Settings.telemetry.skipLogs | Should -BeTrue
            $saved.Settings.telemetry.skipCost | Should -BeFalse
            $saved.Config.Windows.MetricDays | Should -Be 90
            $saved.Config.Thresholds.UnusedDays | Should -Be 90
            $saved.Environment.ApimName | Should -BeExactly 'apim-example-prod'
            $saved.Environment.LogAnalyticsWorkspaceIds |
                Should -Be $script:telemetryContractConfig.Environments[0].LogAnalyticsWorkspaceIds
            $saved.Environment.CostScopes[0] | Should -BeExactly (
                '/subscriptions/00000000-0000-0000-0000-000000000001/resourcegroups/rg-example-prod'
            )
        }

        It 'validates retention-capped evidence and rejects changed effective dates or duplicate targets' {
            $manifest = Get-RunManifest -RunPath $script:telemetryContractRun.Path
            $window = Get-ApimEvidenceWindow -EndUtc $manifest.startedUtc -Kind Usage `
                -Length 90 -RetentionDays 30
            $entry = [ordered]@{
                kind = 'Usage'; target = '00000000-0000-0000-0000-000000000002'
                schema = 'ResourceSpecific'
                requestedStartUtc = $window.requestedStartUtc
                startUtc = $window.startUtc; endUtc = $window.endUtc
                retentionDays = 30; isCapped = $true
                status = 'Completed'; reason = 'None'
            }
            $manifest.evidenceWindows = @([pscustomobject] $entry)
            $null = Save-RunManifest -RunPath $script:telemetryContractRun.Path -Manifest $manifest
            $roundTrip = Get-RunManifest -RunPath $script:telemetryContractRun.Path
            $roundTrip.evidenceWindows[0].isCapped | Should -BeTrue
            $manifest.evidenceWindows[0].startUtc = $window.requestedStartUtc
            { Test-RunManifest -Manifest $manifest } | Should -Throw '*UTC run anchor*'
            $manifest.evidenceWindows[0].startUtc = $window.startUtc
            $manifest.evidenceWindows += $manifest.evidenceWindows[0]
            { Test-RunManifest -Manifest $manifest } | Should -Throw '*duplicate targets*'
        }

        It 'rejects unknown fields and version-shape mismatches without replacing saved evidence' {
            $manifest = Get-RunManifest -RunPath $script:telemetryContractRun.Path
            $manifest.schemaVersion = '1.1'
            { Test-RunManifest -Manifest $manifest } | Should -Throw
            $manifest.schemaVersion = '1.2'
            $settings = Get-ApimRunSettingSnapshot -RunPath $script:telemetryContractRun.Path `
                -Config $script:telemetryContractConfig `
                -Environment $script:telemetryContractConfig.Environments[0]
            $settings.telemetry.rawResponse = 'SYNTHETIC_DISALLOWED_FIELD'
            { Test-ApimRunSetting -Json (ConvertTo-Json $settings -Depth 20) -Manifest $manifest } |
                Should -Throw
            $settings.telemetry.Remove('rawResponse')
            $settings.schemaVersion = '1.0'
            { Test-ApimRunSetting -Json (ConvertTo-Json $settings -Depth 20) -Manifest $manifest } |
                Should -Throw
        }

        It 'preserves legacy manifests and settings without introducing telemetry defaults' {
            $legacy = New-ApimRun -Config $script:telemetryContractConfig -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000010' -Operator Synthetic `
                -RunId synthetic-legacy-contract
            Save-ApimRunSetting -RunPath $legacy.Path -Config $script:telemetryContractConfig `
                -Environment $script:telemetryContractConfig.Environments[0]
            $saved = Get-ApimRunSetting -RunPath $legacy.Path
            $saved.Manifest.schemaVersion | Should -BeExactly '1.1'
            $saved.Settings.schemaVersion | Should -BeExactly '1.0'
            $saved.Settings.Contains('telemetry') | Should -BeFalse
            $saved.Config.Contains('Windows') | Should -BeFalse
            { Save-ApimRunSetting -RunPath $legacy.Path -Config $script:telemetryContractConfig `
                    -Environment $script:telemetryContractConfig.Environments[0] -SkipCost } |
                Should -Throw '*legacy run settings*'
        }

        It 'rejects success-shaped missing coverage and retention on a cost window' {
            $manifest = Get-RunManifest -RunPath $script:telemetryContractRun.Path
            $window = Get-ApimEvidenceWindow -EndUtc $manifest.startedUtc -Kind Cost -Length 6
            $manifest.evidenceWindows = @([pscustomobject]@{
                kind = 'Cost'; target = '/subscriptions/00000000-0000-0000-0000-000000000001'
                schema = 'NotApplicable'
                requestedStartUtc = $window.requestedStartUtc
                startUtc = $window.startUtc; endUtc = $window.endUtc
                retentionDays = $null; isCapped = $false
                status = 'Completed'; reason = 'None'
            })
            Test-RunManifest -Manifest $manifest
            $manifest.evidenceWindows[0].reason = 'Unavailable'
            { Test-RunManifest -Manifest $manifest } | Should -Throw '*coverage is inconsistent*'
            $manifest.evidenceWindows[0].reason = 'None'
            $manifest.evidenceWindows[0].retentionDays = 30
            { Test-RunManifest -Manifest $manifest } | Should -Throw '*Retention capping*'
        }
    }
}
