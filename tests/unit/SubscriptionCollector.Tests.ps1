$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixturePath = Join-Path $repoRoot (
    'tests/fixtures/synthetic-reference/raw/subscriptions.json'
)
$scoring = (Import-PowerShellDataFile (
        Join-Path $repoRoot 'config/sample.psd1'
    )).Scoring
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'APIM subscription collector' {
    InModuleScope ApimAssessment -Parameters @{
        FixturePath = $fixturePath
        Scoring = $scoring
    } {
        param($FixturePath, $Scoring)

        $script:subscriptionFixturePath = $FixturePath
        $script:subscriptionScoring = $Scoring

        BeforeAll {
            function ConvertTo-SubscriptionCompactJson {
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
                Scoring = $script:subscriptionScoring
                Output = @{
                    Root = Join-Path $TestDrive (
                        [guid]::NewGuid().ToString('N')
                    )
                }
            }
            $script:run = New-ApimRun -Config $config -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000010' `
                -Operator 'synthetic.operator@example.invalid' `
                -RunId '2026-10-12_2300_Prod'
            $script:requestUris = @()

            Mock Invoke-ApimArm {
                $script:requestUris += $Uri
                $expected = Get-Content -LiteralPath (
                    $script:subscriptionFixturePath
                ) -Raw | ConvertFrom-Json -Depth 100
                $ownerIndex = 0
                $value = @(
                    foreach ($subscription in @($expected.value |
                            Sort-Object name -Descending)) {
                        $ownerId = switch (
                            [string] $subscription.properties.ownerType
                        ) {
                            'User' {
                                "/users/synthetic-user-$ownerIndex"
                            }
                            'Unknown' {
                                '/groups/synthetic-group'
                            }
                            default {
                                $null
                            }
                        }
                        $ownerIndex++
                        [pscustomobject] @{
                            id = "/synthetic/$($subscription.name)"
                            name = $subscription.name
                            type = 'Microsoft.ApiManagement/service/subscriptions'
                            properties = [pscustomobject] @{
                                displayName = $subscription.properties.displayName
                                scope = $subscription.properties.scope
                                state = $subscription.properties.state
                                ownerId = $ownerId
                                createdDate = $subscription.properties.createdDate
                                expirationDate = (
                                    $subscription.properties.expirationDate
                                )
                                allowTracing = (
                                    $subscription.properties.allowTracing
                                )
                                primaryKey = 'synthetic-primary-key'
                                secondaryKey = 'synthetic-secondary-key'
                                unknownField = 'must-not-persist'
                            }
                        }
                    }
                )
                [pscustomobject] @{ value = $value }
            }
        }

        It 'writes only allowlisted non-identifying subscription metadata' {
            $path = Invoke-ApimSubscriptionCollector `
                -RunPath $script:run.Path -Environment $script:environment

            $script:requestUris | Should -Be @(
                '/subscriptions/00000000-0000-0000-0000-000000000001/' +
                'resourceGroups/rg-synthetic-prod/providers/' +
                'Microsoft.ApiManagement/service/apim-synthetic-prod/' +
                'subscriptions?api-version=2024-05-01'
            )
            $actualJson = Get-Content -LiteralPath $path -Raw
            $expectedJson = Get-Content -LiteralPath (
                $script:subscriptionFixturePath
            ) -Raw
            ConvertTo-SubscriptionCompactJson $actualJson |
                Should -Be (
                    ConvertTo-SubscriptionCompactJson $expectedJson
                )
            $actualJson | Should -Not -Match (
                '(?i)primaryKey|secondaryKey|ownerId|unknownField|' +
                'synthetic-user|synthetic-group'
            )

            $manifest = Get-RunManifest -RunPath $script:run.Path
            $collector = $manifest.collectors |
                Where-Object name -EQ 'Subscriptions'
            $collector.status | Should -Be 'Completed'
            $collector.items | Should -Be 6
            $collector.errors | Should -Be 0
        }

        It 'records a failed collector without success-shaped output' {
            Mock Invoke-ApimArm {
                throw [System.InvalidOperationException]::new(
                    'ARM request failed with HTTP status 503 after 6 attempt(s).'
                )
            }

            {
                Invoke-ApimSubscriptionCollector `
                    -RunPath $script:run.Path `
                    -Environment $script:environment
            } | Should -Throw '*HTTP status 503*'

            Test-Path -LiteralPath (
                Join-Path $script:run.Path 'raw/subscriptions.json'
            ) | Should -BeFalse
            $manifest = Get-RunManifest -RunPath $script:run.Path
            $collector = $manifest.collectors |
                Where-Object name -EQ 'Subscriptions'
            $collector.status | Should -Be 'Failed'
            $collector.errors | Should -Be 1
        }

        It 'preserves missing optional metadata without inventing tracing controls' {
            Mock Invoke-ApimArm {
                [pscustomobject]@{
                    value = @(
                        [pscustomobject]@{
                            name = 'synthetic-unnamed'
                            properties = [pscustomobject]@{
                                scope = (
                                    '/subscriptions/00000000-0000-0000-0000-000000000001/' +
                                    'resourceGroups/rg-synthetic-prod/providers/' +
                                    'Microsoft.ApiManagement/service/apim-synthetic-prod'
                                )
                                state = 'active'
                            }
                        }
                    )
                }
            }

            $path = Invoke-ApimSubscriptionCollector `
                -RunPath $script:run.Path -Environment $script:environment
            $payload = Get-Content -LiteralPath $path -Raw |
                ConvertFrom-Json -Depth 100
            $subscription = $payload.value[0].properties
            $subscription.displayName | Should -BeNullOrEmpty
            $subscription.allowTracing | Should -BeNullOrEmpty
            $subscription.createdDate | Should -BeNullOrEmpty

            $model = @(Get-ApimSubscriptionModel -SubscriptionsPayload $payload)
            $model.Count | Should -Be 1
            $model[0].allowTracing | Should -BeNullOrEmpty
            $model[0].flags | Should -Not -Contain 'AllowTracing'
            $model[0].missingInputs | Should -Be @(
                'allowTracing', 'createdDate', 'displayName', 'usage'
            )
            {
                Write-ApimSubscriptionModel -RunPath $script:run.Path `
                    -Records $model
            } | Should -Not -Throw
        }

        It 'normalizes blank optional display name to unavailable metadata' {
            $resource = [pscustomobject]@{
                name = 'synthetic-blank'
                properties = [pscustomobject]@{
                    displayName = '  '
                    scope = '/apis'
                    state = 'active'
                    allowTracing = $false
                }
            }
            $collected = ConvertTo-ApimCollectedSubscription `
                -Resource $resource

            $collected.properties.displayName | Should -BeNullOrEmpty
            $model = @(Get-ApimSubscriptionModel `
                    -SubscriptionsPayload ([pscustomobject]@{
                        value = @($collected)
                    }))
            $model[0].scopeType | Should -Be 'AllApis'
            $model[0].missingInputs | Should -Contain 'displayName'
            $model[0].allowTracing | Should -BeFalse
        }

        It 'rejects missing scope or malformed optional tracing before writing' `
            -TestCases @(
                @{ Field = 'scope'; Value = '' }
                @{ Field = 'allowTracing'; Value = 'false' }
            ) {
            param($Field, $Value)
            $script:invalidField = $Field
            $script:invalidValue = $Value
            Mock Invoke-ApimArm {
                $properties = [pscustomobject]@{
                    scope = '/apis'
                    state = 'active'
                    allowTracing = $false
                }
                $properties.$script:invalidField = $script:invalidValue
                [pscustomobject]@{
                    value = @(
                        [pscustomobject]@{
                            name = 'synthetic-invalid'
                            properties = $properties
                        }
                    )
                }
            }

            {
                Invoke-ApimSubscriptionCollector `
                    -RunPath $script:run.Path -Environment $script:environment
            } | Should -Throw
            Test-Path -LiteralPath (
                Join-Path $script:run.Path 'raw/subscriptions.json'
            ) | Should -BeFalse
        }

        It 'rejects duplicate subscription names before persistence' {
            Mock Invoke-ApimArm {
                [pscustomobject] @{
                    value = @(
                        [pscustomobject] @{ name = 'duplicate' }
                        [pscustomobject] @{ name = 'duplicate' }
                    )
                }
            }

            {
                Invoke-ApimSubscriptionCollector `
                    -RunPath $script:run.Path `
                    -Environment $script:environment
            } | Should -Throw '*duplicate resource names*'
            Test-Path -LiteralPath (
                Join-Path $script:run.Path 'raw/subscriptions.json'
            ) | Should -BeFalse
        }
    }
}
