$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixturePath = Join-Path $repoRoot 'tests/fixtures/brother-like/raw/service.json'
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'APIM service collector' {
    InModuleScope ApimAssessment -Parameters @{ FixturePath = $fixturePath } {
        param($FixturePath)

        $script:serviceFixturePath = $FixturePath

        BeforeEach {
            $script:environment = @{
                Name              = 'Prod'
                SubscriptionId    = '00000000-0000-0000-0000-000000000001'
                ApimResourceGroup = 'rg-synthetic-prod'
                ApimName          = 'apim-synthetic-prod'
            }
            $config = @{
                Customer = 'Synthetic Customer'
                Environments = @($script:environment)
                Windows = @{
                    UsageDays = 90; SecurityLogDays = 30; CostMonths = 6
                }
                Edge = @{ Provider = 'SyntheticEdge'; Mode = 'AssumedReachable' }
                Output = @{
                    Root = (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
                }
            }
            $script:run = New-ApimRun -Config $config -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000010' `
                -Operator 'synthetic.operator@example.invalid' `
                -RunId '2026-10-12_2300_Prod'
            $script:serviceFixture = Get-Content `
                -LiteralPath $script:serviceFixturePath -Raw |
                ConvertFrom-Json -Depth 100
            $script:invokedUri = $null
            $script:invokedLogPath = $null
            Mock Invoke-ApimArm {
                $script:invokedUri = $Uri
                $script:invokedLogPath = $LogPath
                return $script:serviceFixture
            }
        }

        It 'writes raw service data matching the synthetic fixture' {
            $path = Invoke-ApimServiceCollector -RunPath $script:run.Path `
                -Environment $script:environment

            $actual = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100
            $actual.name | Should -Be $script:serviceFixture.name
            $actual.properties.virtualNetworkType |
                Should -Be $script:serviceFixture.properties.virtualNetworkType
            $actual.properties.hostnameConfigurations[0].hostName |
                Should -Be 'api.synthetic.invalid'
            Should -Invoke Invoke-ApimArm -Times 1 -Exactly
            $script:invokedUri | Should -Be (
                '/subscriptions/00000000-0000-0000-0000-000000000001/' +
                'resourceGroups/rg-synthetic-prod/providers/' +
                'Microsoft.ApiManagement/service/apim-synthetic-prod' +
                '?api-version=2024-05-01'
            )
            $script:invokedLogPath |
                Should -Be (Join-Path $script:run.Path 'logs/run.log')

            $manifest = Get-RunManifest -RunPath $script:run.Path
            $manifest.stages.collect | Should -Be 'InProgress'
            $manifest.collectors.Count | Should -Be 1
            $manifest.collectors[0].name | Should -Be 'Service'
            $manifest.collectors[0].status | Should -Be 'Completed'
            $manifest.collectors[0].items | Should -Be 1
            Test-Path -LiteralPath $script:run.LogPath | Should -BeTrue
        }

        It 'records a failed collector without creating success-shaped output' {
            Mock Invoke-ApimArm {
                throw [System.InvalidOperationException]::new(
                    'ARM request failed with HTTP status 503 after 6 attempt(s).'
                )
            }

            {
                Invoke-ApimServiceCollector -RunPath $script:run.Path `
                    -Environment $script:environment
            } | Should -Throw '*HTTP status 503*'

            Test-Path -LiteralPath (
                Join-Path $script:run.Path 'raw/service.json'
            ) | Should -BeFalse
            $manifest = Get-RunManifest -RunPath $script:run.Path
            $manifest.collectors[0].status | Should -Be 'Failed'
            $manifest.collectors[0].errors | Should -Be 1
            $manifest.warnings | Should -Contain (
                'Service collector failed; see the restricted run log.'
            )
            (Get-Content -LiteralPath $script:run.LogPath -Raw) |
                Should -Not -Match '503'
        }
    }
}
