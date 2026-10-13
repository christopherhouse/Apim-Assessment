$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixtureRoot = Join-Path $repoRoot 'tests/fixtures/synthetic-reference/raw'
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'APIM security asset collector' {
    InModuleScope ApimAssessment -Parameters @{ FixtureRoot = $fixtureRoot } {
        param($FixtureRoot)

        $script:securityAssetFixtureRoot = $FixtureRoot

        BeforeAll {
            function ConvertTo-SecurityAssetCompactJson {
                param(
                    [Parameter(Mandatory)]
                    [string] $Json
                )

                return [System.Text.Json.Nodes.JsonNode]::Parse(
                    $Json
                ).ToJsonString()
            }
        }

        BeforeEach {
            $script:environment = @{
                Name = 'Prod'
                SubscriptionId = '00000000-0000-0000-0000-000000000001'
                ApimResourceGroup = 'rg-synthetic-prod'
                ApimName = 'apim-synthetic-prod'
            }
            $config = @{
                Customer = 'Synthetic Customer'
                Environments = @($script:environment)
                Windows = @{
                    UsageDays = 90; SecurityLogDays = 30; CostMonths = 6
                }
                Edge = @{
                    Provider = 'SyntheticEdge'; Mode = 'AssumedReachable'
                }
                Output = @{
                    Root = Join-Path $TestDrive (
                        [guid]::NewGuid().ToString('N')
                    )
                }
            }
            $script:run = New-ApimRun -Config $config -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000010' `
                -Operator 'synthetic.operator@example.invalid' `
                -RunId '2026-10-13_2300_Prod'
            $script:requestUris = @()

            Mock Invoke-ApimArm {
                $script:requestUris += $Uri
                if ($Uri -match '/namedValues\?') {
                    return [pscustomobject]@{
                        value = @(
                            [pscustomobject]@{
                                name = 'public-label'
                                properties = [pscustomobject]@{
                                    displayName = 'Public label'
                                    secret = $false
                                    value = 'synthetic public metadata'
                                    tags = @()
                                    unknownField = 'drop-me'
                                }
                            }
                            [pscustomobject]@{
                                name = 'partner-api-key'
                                properties = [pscustomobject]@{
                                    displayName = 'Partner API key'
                                    secret = $false
                                    value = 'synthetic-secret-value'
                                    tags = @('security', 'partner')
                                }
                            }
                            [pscustomobject]@{
                                name = 'key-vault-reference'
                                properties = [pscustomobject]@{
                                    displayName = 'Key Vault reference'
                                    secret = $true
                                    value = 'must-never-persist'
                                    keyVault = [pscustomobject]@{
                                        secretIdentifier = (
                                            'https://synthetic-vault.invalid/' +
                                            'secrets/backend-credential'
                                        )
                                        lastStatus = [pscustomobject]@{
                                            code = 'Success'
                                            message = 'drop-me'
                                        }
                                    }
                                    tags = @('security')
                                }
                            }
                        )
                    }
                }
                if ($Uri -match '/backends\?') {
                    return [pscustomobject]@{
                        value = @(
                            [pscustomobject]@{
                                name = 'status-backend'
                                properties = [pscustomobject]@{
                                    url = 'http://status.synthetic.invalid'
                                    protocol = 'http'
                                    tls = [pscustomobject]@{
                                        validateCertificateChain = $false
                                        validateCertificateName = $false
                                    }
                                }
                            }
                            [pscustomobject]@{
                                name = 'orders-backend'
                                properties = [pscustomobject]@{
                                    url = (
                                        'https://synthetic-user:' +
                                        'synthetic-password@' +
                                        'orders.synthetic.invalid/api?' +
                                        'sig=synthetic-signature'
                                    )
                                    protocol = 'http'
                                    tls = [pscustomobject]@{
                                        validateCertificateChain = $true
                                        validateCertificateName = $true
                                    }
                                    credentials = [pscustomobject]@{
                                        authorization = [pscustomobject]@{
                                            scheme = 'Basic'
                                            parameter = 'must-never-persist'
                                        }
                                        certificate = @(
                                            '/certificates/synthetic'
                                        )
                                        header = [pscustomobject]@{
                                            'x-api-key' = @(
                                                'must-never-persist'
                                            )
                                        }
                                        query = [pscustomobject]@{
                                            sig = @('must-never-persist')
                                        }
                                        futureCredential = [pscustomobject]@{
                                            value = 'must-never-persist'
                                        }
                                    }
                                    circuitBreaker = [pscustomobject]@{
                                        rules = @([pscustomobject]@{
                                                name = 'synthetic'
                                            })
                                    }
                                    pool = [pscustomobject]@{
                                        services = @(
                                            [pscustomobject]@{ id = 'one' }
                                            [pscustomobject]@{ id = 'two' }
                                        )
                                    }
                                    type = 'Single'
                                }
                            }
                        )
                    }
                }
                if ($Uri -match '/certificates\?') {
                    return [pscustomobject]@{
                        value = @(
                            [pscustomobject]@{
                                name = 'uploaded-certificate'
                                properties = [pscustomobject]@{
                                    expirationDate = '2026-11-01T00:00:00Z'
                                    data = 'must-never-persist'
                                    password = 'must-never-persist'
                                }
                            }
                            [pscustomobject]@{
                                name = 'key-vault-certificate'
                                properties = [pscustomobject]@{
                                    expirationDate = '2027-10-13T00:00:00Z'
                                    keyVault = [pscustomobject]@{
                                        secretIdentifier = (
                                            'https://synthetic-vault.invalid/' +
                                            'secrets/apim-certificate'
                                        )
                                        identityClientId = 'drop-me'
                                    }
                                    privateKey = 'must-never-persist'
                                }
                            }
                        )
                    }
                }
                throw 'Unexpected synthetic URI.'
            }
        }

        It 'writes three deterministic allowlisted files without secret values' {
            $paths = @(Invoke-ApimSecurityAssetCollector `
                    -RunPath $script:run.Path -Environment $script:environment)

            $paths.Count | Should -Be 3
            $script:requestUris | Should -Be @(
                '/subscriptions/00000000-0000-0000-0000-000000000001/' +
                'resourceGroups/rg-synthetic-prod/providers/' +
                'Microsoft.ApiManagement/service/apim-synthetic-prod/' +
                'namedValues?api-version=2024-05-01'
                '/subscriptions/00000000-0000-0000-0000-000000000001/' +
                'resourceGroups/rg-synthetic-prod/providers/' +
                'Microsoft.ApiManagement/service/apim-synthetic-prod/' +
                'backends?api-version=2024-05-01'
                '/subscriptions/00000000-0000-0000-0000-000000000001/' +
                'resourceGroups/rg-synthetic-prod/providers/' +
                'Microsoft.ApiManagement/service/apim-synthetic-prod/' +
                'certificates?api-version=2024-05-01'
            )

            foreach ($file in @(
                    'namedValues.json', 'backends.json', 'certificates.json'
                )) {
                $actual = Get-Content -LiteralPath (
                    Join-Path $script:run.Path "raw/$file"
                ) -Raw
                $expected = Get-Content -LiteralPath (
                    Join-Path $script:securityAssetFixtureRoot $file
                ) -Raw
                ConvertTo-SecurityAssetCompactJson $actual |
                    Should -Be (ConvertTo-SecurityAssetCompactJson $expected)
            }

            $persisted = @(
                foreach ($path in $paths) {
                    Get-Content -LiteralPath $path -Raw
                }
            ) -join "`n"
            $persisted | Should -Not -Match (
                '(?i)must-never-persist|synthetic-secret-value|' +
                'synthetic-password|synthetic-signature|' +
                'privateKey|password|"data"\s*:'
            )
            $manifest = Get-RunManifest -RunPath $script:run.Path
            $collector = $manifest.collectors |
                Where-Object name -EQ 'SecurityAssets'
            $collector.status | Should -Be 'Completed'
            $collector.items | Should -Be 7
            $collector.errors | Should -Be 0
        }

        It 'records only derived named-value secret pattern locations' {
            $paths = @(Invoke-ApimSecurityAssetCollector `
                    -RunPath $script:run.Path -Environment $script:environment)
            $payload = Get-Content -LiteralPath (
                $paths | Where-Object { $_ -match 'namedValues\.json$' }
            ) -Raw | ConvertFrom-Json -Depth 100
            $candidate = $payload.value |
                Where-Object name -EQ 'partner-api-key'
            $candidate.properties.secret | Should -BeFalse
            $candidate.properties.secretPatternLocations | Should -Be @(
                'displayName', 'value'
            )
            $candidate.properties.PSObject.Properties.Name |
                Should -Not -Contain 'value'
        }

        It 'does not write any file when a later response is malformed' {
            Mock Invoke-ApimArm {
                if ($Uri -match '/namedValues\?') {
                    return [pscustomobject]@{ value = @() }
                }
                if ($Uri -match '/backends\?') {
                    return [pscustomobject]@{
                        value = @(
                            [pscustomobject]@{
                                name = 'invalid'
                                properties = [pscustomobject]@{
                                    url = 'https://synthetic.invalid'
                                    protocol = 'http'
                                    tls = [pscustomobject]@{
                                        validateCertificateChain = 'true'
                                    }
                                }
                            }
                        )
                    }
                }
                return [pscustomobject]@{ value = @() }
            }

            {
                Invoke-ApimSecurityAssetCollector `
                    -RunPath $script:run.Path `
                    -Environment $script:environment
            } | Should -Throw
            foreach ($file in @(
                    'namedValues.json', 'backends.json', 'certificates.json'
                )) {
                Test-Path -LiteralPath (
                    Join-Path $script:run.Path "raw/$file"
                ) | Should -BeFalse
            }
            $collector = (Get-RunManifest -RunPath $script:run.Path).collectors |
                Where-Object name -EQ 'SecurityAssets'
            $collector.status | Should -Be 'Failed'
        }

        It 'rejects duplicate resource names before persistence' {
            Mock Invoke-ApimArm {
                [pscustomobject]@{
                    value = @(
                        [pscustomobject]@{ name = 'duplicate' }
                        [pscustomobject]@{ name = 'duplicate' }
                    )
                }
            }

            {
                Invoke-ApimSecurityAssetCollector `
                    -RunPath $script:run.Path `
                    -Environment $script:environment
            } | Should -Throw '*duplicate resource names*'
            Test-Path -LiteralPath (
                Join-Path $script:run.Path 'raw/namedValues.json'
            ) | Should -BeFalse
        }
    }
}
