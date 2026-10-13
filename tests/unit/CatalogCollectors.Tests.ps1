$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixtureRoot = Join-Path $repoRoot 'tests/fixtures/synthetic-reference/raw'
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'APIM catalog collectors' {
    InModuleScope ApimAssessment -Parameters @{ FixtureRoot = $fixtureRoot } {
        param($FixtureRoot)

        $script:catalogFixtureRoot = $FixtureRoot

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
            $script:parallelThrottle = $null
            $script:parallelRequests = @()
            $script:rootUris = @()

            Mock Invoke-ApimArm {
                $script:rootUris += $Uri
                $relativePath = if ($Uri -match '/apis\?') {
                    'apis.json'
                }
                elseif ($Uri -match '/products\?') {
                    'products.json'
                }
                else {
                    throw 'Unexpected synthetic root request.'
                }
                Get-Content -LiteralPath (
                    Join-Path $script:catalogFixtureRoot $relativePath
                ) -Raw | ConvertFrom-Json -Depth 100
            }
            Mock Invoke-ApimParallelArmRequest {
                $script:parallelThrottle = $ThrottleLimit
                $script:parallelRequests = @($Requests)
                @(
                    foreach ($request in $Requests | Sort-Object Index) {
                        $relativePath = $request.RelativePath.Substring(4)
                        [pscustomobject]@{
                            index        = $request.Index
                            relativePath = $request.RelativePath
                            success      = $true
                            payload      = Get-Content -LiteralPath (
                                Join-Path $script:catalogFixtureRoot $relativePath
                            ) -Raw | ConvertFrom-Json -Depth 100
                        }
                    }
                )
            }
        }

        It 'writes API catalog files matching the synthetic fixtures' {
            $paths = @(Invoke-ApimApiCatalogCollector `
                    -RunPath $script:run.Path `
                    -Environment $script:environment -ThrottleLimit 2)

            $paths.Count | Should -Be 7
            $script:parallelThrottle | Should -Be 2
            $script:parallelRequests.Count | Should -Be 6
            $script:rootUris | Should -Be @(
                '/subscriptions/00000000-0000-0000-0000-000000000001/' +
                'resourceGroups/rg-synthetic-prod/providers/' +
                'Microsoft.ApiManagement/service/apim-synthetic-prod/' +
                'apis?api-version=2024-05-01&expandApiVersionSet=true'
            )
            $script:parallelRequests[0].Uri | Should -Be (
                '/subscriptions/00000000-0000-0000-0000-000000000001/' +
                'resourceGroups/rg-synthetic-prod/providers/' +
                'Microsoft.ApiManagement/service/apim-synthetic-prod/' +
                'apis/orders-v1/revisions?api-version=2024-05-01'
            )

            $apis = Get-Content -LiteralPath (
                Join-Path $script:run.Path 'raw/apis.json'
            ) -Raw | ConvertFrom-Json -Depth 100
            $apis.value.Count | Should -Be 2
            $operations = Get-Content -LiteralPath (
                Join-Path $script:run.Path 'raw/operations/orders-v1.json'
            ) -Raw | ConvertFrom-Json -Depth 100
            $operations.value[0].properties.method | Should -Be 'GET'

            $manifest = Get-RunManifest -RunPath $script:run.Path
            $collector = $manifest.collectors |
                Where-Object name -EQ 'Apis'
            $collector.status | Should -Be 'Completed'
            $collector.items | Should -Be 2
            $collector.errors | Should -Be 0
        }

        It 'records partial API collection when a child request fails' {
            Mock Invoke-ApimParallelArmRequest {
                $exception = [System.InvalidOperationException]::new(
                    'One or more parallel ARM requests failed.'
                )
                $exception.Data['FailureCount'] = 2
                throw $exception
            }

            {
                Invoke-ApimApiCatalogCollector -RunPath $script:run.Path `
                    -Environment $script:environment
            } | Should -Throw '*parallel ARM requests failed*'

            Test-Path -LiteralPath (
                Join-Path $script:run.Path 'raw/apis.json'
            ) | Should -BeTrue
            Test-Path -LiteralPath (
                Join-Path $script:run.Path 'raw/apiRevisions/orders-v1.json'
            ) | Should -BeFalse
            $manifest = Get-RunManifest -RunPath $script:run.Path
            $collector = $manifest.collectors |
                Where-Object name -EQ 'Apis'
            $collector.status | Should -Be 'Partial'
            $collector.errors | Should -Be 2
            $manifest.warnings | Should -Contain (
                'API catalog collector failed; see the restricted run log.'
            )
        }

        It 'writes product relationship files matching the synthetic fixtures' {
            $paths = @(Invoke-ApimProductCollector -RunPath $script:run.Path `
                    -Environment $script:environment -ThrottleLimit 3)

            $paths.Count | Should -Be 5
            $script:parallelThrottle | Should -Be 3
            $script:parallelRequests.Count | Should -Be 4
            $script:rootUris | Should -Be @(
                '/subscriptions/00000000-0000-0000-0000-000000000001/' +
                'resourceGroups/rg-synthetic-prod/providers/' +
                'Microsoft.ApiManagement/service/apim-synthetic-prod/' +
                'products?api-version=2024-05-01'
            )
            $products = Get-Content -LiteralPath (
                Join-Path $script:run.Path 'raw/products.json'
            ) -Raw | ConvertFrom-Json -Depth 100
            $products.value.Count | Should -Be 2
            $groups = Get-Content -LiteralPath (
                Join-Path $script:run.Path 'raw/productGroups/partner.json'
            ) -Raw | ConvertFrom-Json -Depth 100
            $groups.value[0].name | Should -Be 'partners'

            $manifest = Get-RunManifest -RunPath $script:run.Path
            $collector = $manifest.collectors |
                Where-Object name -EQ 'Products'
            $collector.status | Should -Be 'Completed'
            $collector.items | Should -Be 2
        }

        It 'records failed product collection without success-shaped output' {
            Mock Invoke-ApimArm {
                throw [System.InvalidOperationException]::new(
                    'ARM request failed with HTTP status 503 after 6 attempt(s).'
                )
            }

            {
                Invoke-ApimProductCollector -RunPath $script:run.Path `
                    -Environment $script:environment
            } | Should -Throw '*HTTP status 503*'

            Test-Path -LiteralPath (
                Join-Path $script:run.Path 'raw/products.json'
            ) | Should -BeFalse
            $manifest = Get-RunManifest -RunPath $script:run.Path
            $collector = $manifest.collectors |
                Where-Object name -EQ 'Products'
            $collector.status | Should -Be 'Failed'
            $collector.errors | Should -Be 1
        }

    }
}
