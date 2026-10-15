$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Governance replay settings' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:governanceSettingsRepository = $Repository

        BeforeEach {
            $script:governanceConfig = Import-PowerShellDataFile (
                Join-Path $script:governanceSettingsRepository 'config/sample.psd1'
            )
            $script:governanceConfig.Output.Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $script:governanceConfig.Output.ModelSafeRoot = Join-Path $TestDrive 'analysis'
            $run = New-ApimRun -Config $script:governanceConfig -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000002' `
                -Operator Synthetic -RunId 'synthetic-governance-settings'
            $script:governanceRunPath = $run.Path
        }

        It 'preserves absent intent and explicit empty critical targets independently' {
            Save-ApimRunSetting -RunPath $script:governanceRunPath `
                -Config $script:governanceConfig -Environment $script:governanceConfig.Environments[0]
            $legacy = Get-ApimRunSetting -RunPath $script:governanceRunPath
            $legacy.Settings.Contains('governance') | Should -BeFalse
            $legacy.Config.Contains('Governance') | Should -BeFalse
            $script:governanceConfig.Governance = @{ CriticalApiIds = @() }
            Save-ApimRunSetting -RunPath $script:governanceRunPath `
                -Config $script:governanceConfig -Environment $script:governanceConfig.Environments[0]
            $saved = Get-ApimRunSetting -RunPath $script:governanceRunPath
            $saved.Config.Governance.Contains('CriticalApiIds') | Should -BeTrue
            $saved.Config.Governance.CriticalApiIds.Count | Should -Be 0
            $saved.Config.Governance.Contains('Products') | Should -BeFalse
        }

        It 'round trips explicit product intent without introducing owner identities' {
            $script:governanceConfig.Governance = @{
                Products = @(@{ ProductId = 'partner'; HasOwner = $false; IsExternal = $true })
                CriticalApiIds = @('orders-v1')
            }
            Save-ApimRunSetting -RunPath $script:governanceRunPath `
                -Config $script:governanceConfig -Environment $script:governanceConfig.Environments[0]
            $saved = Get-ApimRunSetting -RunPath $script:governanceRunPath
            $saved.Settings.governance.products[0].hasOwner | Should -BeFalse
            $saved.Config.Governance.Products[0].IsExternal | Should -BeTrue
            $saved.Config.Governance.CriticalApiIds | Should -Be @('orders-v1')
        }

        It 'rejects unknown or duplicate intent in saved settings' {
            $settings = Get-ApimRunSettingSnapshot -RunPath $script:governanceRunPath `
                -Config $script:governanceConfig -Environment $script:governanceConfig.Environments[0]
            $manifest = Get-RunManifest -RunPath $script:governanceRunPath
            $settings.governance = @{ criticalApiIds = @('orders', 'ORDERS') }
            { Test-ApimRunSetting -Json (ConvertTo-Json $settings -Depth 20) -Manifest $manifest } |
                Should -Throw
            $settings.governance = @{ ownerIdentity = 'SYNTHETIC_DISALLOWED_FIELD' }
            { Test-ApimRunSetting -Json (ConvertTo-Json $settings -Depth 20) -Manifest $manifest } |
                Should -Throw
        }

        It 'rejects identity storage before direct <Command> run creation or ARM calls' -ForEach @(
            @{ Command = 'Invoke-ApimCollection' }
            @{ Command = 'Invoke-ApimSmoke' }
        ) {
            Mock New-ApimRun { throw 'Run creation must not occur.' }
            Mock Invoke-ApimArm { throw 'ARM must not occur.' }
            $script:governanceConfig.Privacy.StoreUserIdentities = $true
            { & $Command -Config $script:governanceConfig -EnvironmentName Prod `
                    -TenantId '00000000-0000-0000-0000-000000000002' } |
                Should -Throw '*aggregate counts only*'
            Should -Invoke New-ApimRun -Exactly -Times 0
            Should -Invoke Invoke-ApimArm -Exactly -Times 0
        }

        It 'rejects identity storage before public <Stage> authentication' -ForEach @(
            @{ Stage = 'Collect' }
            @{ Stage = 'All' }
        ) {
            Mock Get-Config { $script:governanceConfig }
            Mock Import-Module { throw 'Authentication imports must not occur.' }
            Mock Invoke-ApimCollection { throw 'Collection must not occur.' }
            $script:governanceConfig.Privacy.StoreUserIdentities = $true
            $result = Invoke-ApimAssessment -Config 'synthetic.psd1' -Environment Prod -Stage $Stage
            $result.ErrorCode | Should -Be 'CONFIG_OR_CAPABILITY_ERROR'
            $result.ExitCode | Should -Be 1
            Should -Invoke Import-Module -Exactly -Times 0
            Should -Invoke Invoke-ApimCollection -Exactly -Times 0
        }
    }
}
