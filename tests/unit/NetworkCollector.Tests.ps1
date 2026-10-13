$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixtureRoot = Join-Path $repoRoot 'tests/fixtures/synthetic-reference'
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'APIM network collector' {
    InModuleScope ApimAssessment -Parameters @{
        FixtureRoot = $fixtureRoot
    } {
        param($FixtureRoot)

        $script:networkCollectorFixtureRoot = $FixtureRoot

        BeforeAll {
            function Read-NetworkCollectorFixture {
                param(
                    [Parameter(Mandatory)]
                    [string] $RelativePath
                )

                return Get-Content -LiteralPath (
                    Join-Path $script:networkCollectorFixtureRoot $RelativePath
                ) -Raw | ConvertFrom-Json -Depth 100
            }

            function ConvertTo-NetworkCollectorJson {
                param(
                    [Parameter(Mandatory)]
                    [object] $InputObject
                )

                return ConvertTo-Json -InputObject $InputObject `
                    -Depth 100 -Compress
            }
        }

        BeforeEach {
            $script:networkEnvironment = @{
                Name = 'Prod'
                SubscriptionId = '00000000-0000-0000-0000-000000000001'
                ApimResourceGroup = 'rg-synthetic-prod'
                ApimName = 'apim-synthetic-prod'
                NetworkResourceGroups = @('rg-synthetic-network')
                AppGateways = @(
                    @{
                        ResourceGroup = 'rg-synthetic-network'
                        Name = 'agw-synthetic-prod'
                    }
                )
            }
            $config = @{
                Customer = 'Synthetic Customer'
                Environments = @($script:networkEnvironment)
                Windows = @{
                    UsageDays = 90; SecurityLogDays = 30; CostMonths = 6
                }
                Edge = @{
                    Provider = 'SyntheticEdge'
                    Mode = 'AssumedReachable'
                }
                Output = @{
                    Root = (Join-Path $TestDrive (
                            [guid]::NewGuid().ToString('N')
                        ))
                }
            }
            $script:networkRun = New-ApimRun -Config $config `
                -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000010' `
                -Operator 'synthetic.operator@example.invalid' `
                -RunId '2026-10-13_0100_Prod'
            Copy-Item -LiteralPath (
                Join-Path $script:networkCollectorFixtureRoot 'raw/service.json'
            ) -Destination (
                Join-Path $script:networkRun.Path 'raw/service.json'
            )

            $script:appGatewayFixture = Read-NetworkCollectorFixture (
                'raw/network/appgw.agw-synthetic-prod.json'
            )
            $script:wafFixture = Read-NetworkCollectorFixture (
                'raw/network/wafPolicy.waf-synthetic-prod.json'
            )
            $script:networkQueries = [System.Collections.Generic.List[string]]::new()
            $script:armUris = [System.Collections.Generic.List[string]]::new()

            Mock Invoke-ApimArm {
                $script:armUris.Add($Uri)
                if ($Uri -match (
                        '(?i)applicationGatewayWebApplicationFirewallPolicies'
                    )) {
                    return $script:wafFixture
                }
                return $script:appGatewayFixture
            }
            Mock Invoke-ApimResourceGraphQuery {
                $script:networkQueries.Add($Query)
                $relativePath = switch -Regex ($Query) {
                    'mv-expand subnet = properties\.subnets' {
                        'raw/network/apimSubnet.json'; break
                    }
                    'microsoft\.network/networksecuritygroups' {
                        'raw/network/nsgs.json'; break
                    }
                    'microsoft\.network/publicipaddresses' {
                        'raw/network/publicIps.json'; break
                    }
                    'microsoft\.network/privateendpoints' {
                        'raw/network/privateEndpoints.json'; break
                    }
                    'microsoft\.network/privatednszones' {
                        'raw/network/privateDnsZones.json'; break
                    }
                    'microsoft\.network/routetables' {
                        'raw/network/routeTables.json'; break
                    }
                    'microsoft\.network/frontdoors' {
                        'raw/network/frontDoors.json'; break
                    }
                    default {
                        throw 'Unexpected synthetic Resource Graph query.'
                    }
                }
                return @(
                    (Read-NetworkCollectorFixture $relativePath).value
                )
            }
        }

        It 'writes fixture-equivalent App Gateway, WAF, and graph evidence' {
            $paths = @(Invoke-ApimNetworkCollector `
                    -RunPath $script:networkRun.Path `
                    -Environment $script:networkEnvironment)

            $paths.Count | Should -Be 9
            Should -Invoke Invoke-ApimArm -Times 2 -Exactly
            Should -Invoke Invoke-ApimResourceGraphQuery -Times 7 -Exactly
            $script:armUris[0] | Should -Be (
                '/subscriptions/00000000-0000-0000-0000-000000000001/' +
                'resourceGroups/rg-synthetic-network/providers/' +
                'Microsoft.Network/applicationGateways/agw-synthetic-prod' +
                '?api-version=2024-05-01'
            )
            $script:armUris[1] | Should -Match (
                '(?i)/ApplicationGatewayWebApplicationFirewallPolicies/' +
                'waf-synthetic-prod\?api-version=2024-05-01$'
            )

            foreach ($relativePath in @(
                    'raw/network/appgw.agw-synthetic-prod.json',
                    'raw/network/wafPolicy.waf-synthetic-prod.json',
                    'raw/network/apimSubnet.json',
                    'raw/network/nsgs.json',
                    'raw/network/publicIps.json',
                    'raw/network/privateEndpoints.json',
                    'raw/network/privateDnsZones.json',
                    'raw/network/routeTables.json',
                    'raw/network/frontDoors.json'
                )) {
                $actual = Get-Content -LiteralPath (
                    Join-Path $script:networkRun.Path $relativePath
                ) -Raw | ConvertFrom-Json -Depth 100
                $expected = Read-NetworkCollectorFixture $relativePath
                ConvertTo-NetworkCollectorJson $actual |
                    Should -Be (ConvertTo-NetworkCollectorJson $expected)
            }

            $frontDoorQuery = $script:networkQueries |
                Where-Object { $_ -match 'microsoft\.network/frontdoors' }
            $frontDoorQuery | Should -Match (
                'pool\.properties\.backendAddresses'
            )
            $frontDoorQuery | Should -Match (
                'backend\.properties\.address'
            )
            $frontDoorQuery | Should -Not -Match 'propertiesText contains'
            $frontDoorQuery | Should -Match 'api\.synthetic\.invalid'
            $frontDoorQuery | Should -Match 'id !in~'

            $subnetQuery = $script:networkQueries |
                Where-Object { $_ -match 'mv-expand subnet' }
            $subnetQuery | Should -Match (
                'virtualNetworks/vnet-synthetic-prod'
            )
            $subnetQuery | Should -Match (
                "tostring\(subnet\.name\) =~ 'apim'"
            )

            $publicIpQuery = $script:networkQueries |
                Where-Object {
                    $_ -match 'microsoft\.network/publicipaddresses'
                }
            $publicIpQuery | Should -Match 'targetClassification = case'
            $publicIpQuery | Should -Match 'KnownOther'

            $manifest = Get-RunManifest -RunPath $script:networkRun.Path
            $manifest.collectors[0].name | Should -Be 'Network'
            $manifest.collectors[0].status | Should -Be 'Completed'
            $manifest.collectors[0].items | Should -Be 9
        }

        It 'stages collection before writing and records graph failures' {
            Mock Invoke-ApimResourceGraphQuery {
                throw [System.InvalidOperationException]::new(
                    'Synthetic Resource Graph failure.'
                )
            }

            {
                Invoke-ApimNetworkCollector `
                    -RunPath $script:networkRun.Path `
                    -Environment $script:networkEnvironment
            } | Should -Throw '*Synthetic Resource Graph failure*'

            Test-Path -LiteralPath (
                Join-Path $script:networkRun.Path 'raw/network'
            ) | Should -BeFalse
            $manifest = Get-RunManifest -RunPath $script:networkRun.Path
            $manifest.collectors[0].status | Should -Be 'Failed'
            $manifest.collectors[0].errors | Should -Be 1
            $manifest.warnings | Should -Contain (
                'Network collector failed; see the restricted run log.'
            )
            (Get-Content -LiteralPath $script:networkRun.LogPath -Raw) |
                Should -Not -Match 'Synthetic Resource Graph failure'
        }

        It 'rejects an out-of-scope WAF policy link before graph queries' {
            $script:appGatewayFixture.properties.firewallPolicy.id = (
                '/subscriptions/00000000-0000-0000-0000-000000000099/' +
                'resourceGroups/rg-synthetic-network/providers/' +
                'Microsoft.Network/' +
                'ApplicationGatewayWebApplicationFirewallPolicies/foreign'
            )

            {
                Invoke-ApimNetworkCollector `
                    -RunPath $script:networkRun.Path `
                    -Environment $script:networkEnvironment
            } | Should -Throw '*outside the expected scope*'

            Should -Invoke Invoke-ApimResourceGraphQuery -Times 0 -Exactly
            Test-Path -LiteralPath (
                Join-Path $script:networkRun.Path 'raw/network'
            ) | Should -BeFalse
        }

    }
}

Describe 'APIM Resource Graph query transport' {
    InModuleScope ApimAssessment {
        BeforeAll {
            function Search-AzGraph {
                [CmdletBinding()]
                param(
                    [Parameter(Mandatory)]
                    [string] $Query,
                    [string[]] $Subscription,
                    [int] $First,
                    [string] $SkipToken
                )

                $null = @($Query, $Subscription, $First, $SkipToken)
                throw 'Search-AzGraph test stub was not mocked.'
            }
        }

        It 'pages results through Search-AzGraph' {
            Mock Search-AzGraph {
                if ([string]::IsNullOrWhiteSpace($SkipToken)) {
                    return [pscustomobject]@{
                        Data = @(
                            [pscustomobject]@{
                                id = '/synthetic/resources/one'
                                name = 'one'
                            }
                        )
                        SkipToken = 'page-two'
                    }
                }
                return [pscustomobject]@{
                    Data = @(
                        [pscustomobject]@{
                            id = '/synthetic/resources/two'
                            name = 'two'
                        }
                    )
                    SkipToken = $null
                }
            }

            $results = @(Invoke-ApimResourceGraphQuery `
                    -Query 'resources | project id, name' `
                    -SubscriptionId (
                        '00000000-0000-0000-0000-000000000001'
                    ))

            $results.name | Should -Be @('one', 'two')
            Should -Invoke Search-AzGraph -Times 2 -Exactly
            Should -Invoke Search-AzGraph -Times 1 -Exactly `
                -ParameterFilter { $SkipToken -eq 'page-two' }
        }
    }
}
