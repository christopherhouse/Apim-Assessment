$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Validated collection resume and isolation' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)

        $script:resumeRepoRoot = $RepoRoot

        BeforeAll {
        function Write-SyntheticCollectorOutput {
            param([string] $RunPath, [string] $Name)

            $files = @{
                Service = @('raw/service.json')
                Apis = @('raw/apis.json')
                Products = @('raw/products.json')
                Subscriptions = @('raw/subscriptions.json')
                SecurityAssets = @('raw/namedValues.json', 'raw/backends.json', 'raw/certificates.json')
                Diagnostics = @('raw/loggers.json', 'raw/diagnostics.json')
                Network = @('raw/network/apimSubnet.json', 'raw/network/nsgs.json',
                    'raw/network/privateEndpoints.json', 'raw/network/privateDnsZones.json',
                    'raw/network/routeTables.json', 'raw/network/publicIps.json',
                    'raw/network/frontDoors.json')
                Policies = @('policies/index.json')
            }
            foreach ($file in $files[$Name]) {
                $payload = if ($Name -eq 'Service') {
                    [pscustomobject]@{ name = 'synthetic-service' }
                }
                elseif ($Name -eq 'Policies') {
                    [pscustomobject]@{
                        schemaVersion = '1.0'
                        policies = @([pscustomobject]@{
                                scopeType = 'Global'
                                scope = 'global'
                                file = 'policies/global.xml'
                                exists = $false
                                sha256 = $null
                                hardcodedSecretLocations = @()
                            })
                    }
                }
                else { [pscustomobject]@{ value = @() } }
                $null = Write-RunFile -RunPath $RunPath -RelativePath $file `
                    -InputObject $payload
            }
            $items = switch ($Name) {
                Service { 1 }
                Policies { 1 }
                Network { 7 }
                default { 0 }
            }
            Set-RunCollectorStatus -RunPath $RunPath -Name $Name `
                -Status Completed -Items $items
        }
        }

        BeforeEach {
            $script:resumeConfig = Import-PowerShellDataFile (
                Join-Path $script:resumeRepoRoot 'config/sample.psd1'
            )
            $script:resumeConfig.Output.Root = Join-Path $TestDrive (
                [guid]::NewGuid().ToString('N')
            )
            $script:resumeConfig.Environments[0].AppGateways = @()
            $script:tenant = '00000000-0000-0000-0000-000000000010'
            Mock Invoke-ApimServiceCollector {
                Write-SyntheticCollectorOutput -RunPath $RunPath -Name Service
            }
            Mock Invoke-ApimApiCatalogCollector {
                Write-SyntheticCollectorOutput -RunPath $RunPath -Name Apis
            }
            Mock Invoke-ApimProductCollector {
                Write-SyntheticCollectorOutput -RunPath $RunPath -Name Products
            }
            Mock Invoke-ApimSubscriptionCollector {
                Write-SyntheticCollectorOutput -RunPath $RunPath -Name Subscriptions
            }
            Mock Invoke-ApimSecurityAssetCollector {
                Write-SyntheticCollectorOutput -RunPath $RunPath -Name SecurityAssets
            }
            Mock Invoke-ApimDiagnosticsCollector {
                Write-SyntheticCollectorOutput -RunPath $RunPath -Name Diagnostics
            }
            Mock Invoke-ApimPolicyCollector {
                Write-SyntheticCollectorOutput -RunPath $RunPath -Name Policies
            }
            Mock Invoke-ApimNetworkCollector {
                Write-SyntheticCollectorOutput -RunPath $RunPath -Name Network
            }
            Mock Invoke-ApimArm { throw 'Unexpected Azure access.' }
        }

        It 'reuses all validated output without invoking collectors or Azure' {
            $initial = Invoke-ApimCollection -Config $script:resumeConfig `
                -EnvironmentName Prod -TenantId $script:tenant
            $initial.ExitCode | Should -Be 0
            $path = Join-Path $script:resumeConfig.Output.Root $initial.RunId
            Set-RunStageStatus -RunPath $path -Stage analyze -Status Completed
            Set-RunStageStatus -RunPath $path -Stage report -Status Completed
            $result = Invoke-ApimCollection -Config $script:resumeConfig `
                -EnvironmentName Prod -TenantId $script:tenant -ResumeRunPath $path
            $result.RunId | Should -Be $initial.RunId
            $result.ExitCode | Should -Be 0
            @($result.Checks | Where-Object Reused -EQ $true).Count | Should -Be 8
            (Get-RunManifest -RunPath $path).stages.report | Should -Be Completed
            foreach ($check in Get-ApimCollectorRegistry) {
                Should -Invoke $check.Function -Times 1 -Exactly
            }
            Should -Invoke Invoke-ApimArm -Times 0 -Exactly
        }

        It 'marks unconfigured or explicitly excluded Git Skipped without invoking Git (<Configured>)' `
            -TestCases @(@{ Configured = $false }, @{ Configured = $true }) {
            param($Configured)
            if ($Configured) { $script:resumeConfig.Environments[0].GitRepoPath = $TestDrive }
            Mock Get-ApimGitPolicySnapshot { throw 'Unexpected Git access.' }
            $arguments = @{}
            if ($Configured) { $arguments.SkipGit = $true }
            $result = Invoke-ApimCollection -Config $script:resumeConfig `
                -EnvironmentName Prod -TenantId $script:tenant @arguments
            $result.ExitCode | Should -Be 0
            $path = Join-Path $script:resumeConfig.Output.Root $result.RunId
            ((Get-RunManifest -RunPath $path).collectors | Where-Object name -CEQ Git).status |
                Should -Be Skipped
            Should -Invoke Get-ApimGitPolicySnapshot -Times 0 -Exactly
        }

        It 'reuses a pinned Git snapshot and invalidates downstream state on HEAD changes or failure' {
            $script:resumeConfig.Environments[0].GitRepoPath = $TestDrive
            $script:gitCommit = 'a' * 40
            Mock Get-ApimGitPolicySnapshot {
                [ordered]@{ schemaVersion = '1.0'; commitSha = $script:gitCommit
                    scopeTypes = @('Global'); policies = @() }
            }
            Mock Invoke-ApimGitCollector {
                $null = Write-RunFile -RunPath $RunPath -RelativePath 'git/policyHashes.json' `
                    -InputObject (Get-ApimGitPolicySnapshot -Environment $Environment)
                Set-RunCollectorStatus -RunPath $RunPath -Name Git -Status Completed
            }
            $first = Invoke-ApimCollection -Config $script:resumeConfig `
                -EnvironmentName Prod -TenantId $script:tenant
            $first.ExitCode | Should -Be 0
            $path = Join-Path $script:resumeConfig.Output.Root $first.RunId
            $arguments = @{ Config = $script:resumeConfig; EnvironmentName = 'Prod'
                TenantId = $script:tenant; ResumeRunPath = $path }
            Set-RunStageStatus -RunPath $path -Stage report -Status Completed
            (Invoke-ApimCollection @arguments).ExitCode | Should -Be 0
            (Get-RunManifest -RunPath $path).stages.report | Should -Be Completed
            Should -Invoke Invoke-ApimGitCollector -Times 1 -Exactly
            $script:gitCommit = 'b' * 40
            (Invoke-ApimCollection @arguments).ExitCode | Should -Be 0
            Should -Invoke Invoke-ApimGitCollector -Times 2 -Exactly
            (Get-RunManifest -RunPath $path).stages.report | Should -Be NotStarted
            $manifest = Get-RunManifest -RunPath $path
            $manifest.modelSafe.build = 'Completed'
            $manifest.modelSafe.validation = 'Passed'
            $manifest.modelSafe.promotion = 'Completed'
            $manifest.modelSafe.packageSha256 = 'c' * 64
            $null = Save-RunManifest -RunPath $path -Manifest $manifest
            Mock Get-ApimGitPolicySnapshot { throw 'private-git-canary' }
            $failed = Invoke-ApimCollection @arguments
            $failed.ExitCode | Should -Be 3
            $manifest = Get-RunManifest -RunPath $path
            ($manifest.collectors | Where-Object name -CEQ Git).status | Should -Be Failed
            $manifest.modelSafe.promotion | Should -Be NotStarted
            $manifest.modelSafe.packageSha256 | Should -BeNullOrEmpty
            (ConvertTo-Json $failed) | Should -Not -Match 'canary'
        }

        It 'reruns damaged API output and its dependents but retains independent checks' {
            $initial = Invoke-ApimCollection -Config $script:resumeConfig `
                -EnvironmentName Prod -TenantId $script:tenant
            $path = Join-Path $script:resumeConfig.Output.Root $initial.RunId
            Set-Content -LiteralPath (Join-Path $path 'raw/apis.json') -Value '{bad'
            Set-RunStageStatus -RunPath $path -Stage analyze -Status Completed
            Set-RunStageStatus -RunPath $path -Stage report -Status Completed
            $result = Invoke-ApimCollection -Config $script:resumeConfig `
                -EnvironmentName Prod -TenantId $script:tenant -ResumeRunPath $path
            $result.ExitCode | Should -Be 0
            @($result.Checks | Where-Object Reused -EQ $false).Name |
                Should -Be @('Apis', 'Diagnostics', 'Policies')
            Should -Invoke Invoke-ApimApiCatalogCollector -Times 2 -Exactly
            Should -Invoke Invoke-ApimDiagnosticsCollector -Times 2 -Exactly
            Should -Invoke Invoke-ApimPolicyCollector -Times 2 -Exactly
            Should -Invoke Invoke-ApimNetworkCollector -Times 1 -Exactly
            (Get-RunManifest -RunPath $path).stages.analyze | Should -Be NotStarted
            (Get-RunManifest -RunPath $path).stages.report | Should -Be NotStarted
        }

        It 'does not trust a completed policy collector with an incomplete scope index' {
            $initial = Invoke-ApimCollection -Config $script:resumeConfig `
                -EnvironmentName Prod -TenantId $script:tenant
            $path = Join-Path $script:resumeConfig.Output.Root $initial.RunId
            $null = Write-RunFile -RunPath $path -RelativePath 'policies/index.json' `
                -InputObject ([pscustomobject]@{ schemaVersion = '1.0'; policies = @() })
            Set-RunCollectorStatus -RunPath $path -Name Policies -Status Completed
            $result = Invoke-ApimCollection -Config $script:resumeConfig `
                -EnvironmentName Prod -TenantId $script:tenant -ResumeRunPath $path
            $result.ExitCode | Should -Be 0
            Should -Invoke Invoke-ApimPolicyCollector -Times 2 -Exactly
        }

        It 'continues unrelated checks and returns exit 3 on a prerequisite failure' {
            Mock Invoke-ApimApiCatalogCollector { throw 'synthetic-private-canary' }
            $result = Invoke-ApimCollection -Config $script:resumeConfig `
                -EnvironmentName Prod -TenantId $script:tenant
            $result.Status | Should -Be Partial
            $result.ExitCode | Should -Be 3
            ($result.Checks | Where-Object Name -EQ Apis).Status | Should -Be Failed
            ($result.Checks | Where-Object Name -EQ Policies).Status | Should -Be Skipped
            ($result.Checks | Where-Object Name -EQ Diagnostics).Status | Should -Be Skipped
            ($result.Checks | Where-Object Name -EQ Network).Status | Should -Be Completed
            Should -Invoke Invoke-ApimPolicyCollector -Times 0 -Exactly
            Should -Invoke Invoke-ApimNetworkCollector -Times 1 -Exactly
            $json = ConvertTo-Json -InputObject $result -Depth 10
            $json | Should -Not -Match 'canary|00000000|raw/|restricted/'
        }

        It 'rejects changed config or tenant before invoking any resumed collector' `
            -TestCases @(@{ Kind = 'config' }, @{ Kind = 'tenant' }) {
            param($Kind)
            $initial = Invoke-ApimCollection -Config $script:resumeConfig `
                -EnvironmentName Prod -TenantId $script:tenant
            $path = Join-Path $script:resumeConfig.Output.Root $initial.RunId
            if ($Kind -eq 'config') { $script:resumeConfig.Thresholds.CertExpiryDays++ }
            else { $script:tenant = '00000000-0000-0000-0000-000000000011' }
            {
                Invoke-ApimCollection -Config $script:resumeConfig `
                    -EnvironmentName Prod -TenantId $script:tenant -ResumeRunPath $path
            } | Should -Throw '*incompatible*'
            Should -Invoke Invoke-ApimServiceCollector -Times 1 -Exactly
        }

        It 'clears stale owned files before rerunning a collector' {
            $initial = Invoke-ApimCollection -Config $script:resumeConfig `
                -EnvironmentName Prod -TenantId $script:tenant
            $path = Join-Path $script:resumeConfig.Output.Root $initial.RunId
            $null = Write-RunFile -RunPath $path -RelativePath 'policies/global.xml' `
                -InputObject '<policies />' -Format Text
            $result = Invoke-ApimCollection -Config $script:resumeConfig `
                -EnvironmentName Prod -TenantId $script:tenant -ResumeRunPath $path
            $result.ExitCode | Should -Be 0
            Test-Path -LiteralPath (Join-Path $path 'policies/global.xml') |
                Should -BeFalse
            Should -Invoke Invoke-ApimPolicyCollector -Times 2 -Exactly
        }

        It 'rejects modified saved settings before recollection' {
            $initial = Invoke-ApimCollection -Config $script:resumeConfig `
                -EnvironmentName Prod -TenantId $script:tenant
            $path = Join-Path $script:resumeConfig.Output.Root $initial.RunId
            $settings = (Get-ApimRunSetting -RunPath $path).Settings
            $settings.certExpiryDays++
            $null = Write-RunFile -RunPath $path `
                -RelativePath 'restricted/run-settings.json' -InputObject $settings
            {
                Invoke-ApimCollection -Config $script:resumeConfig `
                    -EnvironmentName Prod -TenantId $script:tenant -ResumeRunPath $path
            } | Should -Throw '*incompatible*'
            Should -Invoke Invoke-ApimServiceCollector -Times 1 -Exactly
        }
    }
}
