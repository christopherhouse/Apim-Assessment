$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixtureRoot = Join-Path $repoRoot 'tests/fixtures/synthetic-reference'
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'APIM policy collector' {
    InModuleScope ApimAssessment -Parameters @{ FixtureRoot = $fixtureRoot } {
        param($FixtureRoot)

        $script:policyFixtureRoot = $FixtureRoot

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
                -RunId '2026-10-13_0000_Prod'
            foreach ($relativePath in @(
                    'apis.json',
                    'products.json',
                    'operations/orders-v1.json',
                    'operations/status-v1.json'
                )) {
                $source = Join-Path $script:policyFixtureRoot "raw/$relativePath"
                $destination = Join-Path $script:run.Path "raw/$relativePath"
                [System.IO.Directory]::CreateDirectory(
                    (Split-Path $destination -Parent)
                ) | Out-Null
                Copy-Item -LiteralPath $source -Destination $destination
            }

            $script:fragmentListUri = $null
            $script:parallelThrottle = $null
            $script:policyRequests = @()
            Mock Invoke-ApimArm {
                $script:fragmentListUri = $Uri
                [pscustomobject]@{
                    value = @(
                        [pscustomobject]@{ name = 'common-auth' }
                    )
                }
            }
            Mock Invoke-ApimParallelArmRequest {
                $script:parallelThrottle = $ThrottleLimit
                $script:policyRequests = @($Requests)
                @(
                    foreach ($request in $Requests | Sort-Object Index) {
                        $missing = $request.RelativePath -in @(
                            'policies/product.internal.xml',
                            'policies/api.status-v1.xml',
                            'policies/op.status-v1.get-status.xml'
                        )
                        $payload = $null
                        if (-not $missing) {
                            $xml = Get-Content -LiteralPath (
                                Join-Path $script:policyFixtureRoot `
                                    $request.RelativePath
                            ) -Raw
                            if ($request.RelativePath -in @(
                                    'policies/api.orders-v1.xml',
                                    'policies/op.orders-v1.get-orders.xml'
                                )) {
                                $xml = $xml.Replace(
                                    '***REDACTED***',
                                    'synthetic-secret-value'
                                )
                            }
                            $payload = [pscustomobject]@{
                                properties = [pscustomobject]@{ value = $xml }
                            }
                        }
                        [pscustomobject]@{
                            index        = $request.Index
                            relativePath = $request.RelativePath
                            success      = $true
                            notFound     = $missing
                            payload      = $payload
                        }
                    }
                )
            }
        }

        It 'writes redacted policy files and a deterministic complete index' {
            $paths = @(Invoke-ApimPolicyCollector `
                    -RunPath $script:run.Path `
                    -Environment $script:environment -ThrottleLimit 2)

            $paths.Count | Should -Be 6
            $script:parallelThrottle | Should -Be 2
            $script:policyRequests.Count | Should -Be 8
            @($script:policyRequests | Where-Object {
                    -not $_.AllowNotFound
                }) | Should -BeNullOrEmpty
            @($script:policyRequests | Where-Object {
                    $_.Uri -notmatch '[?&]format=xml(?:&|$)'
                }) | Should -BeNullOrEmpty
            $script:fragmentListUri | Should -Be (
                '/subscriptions/00000000-0000-0000-0000-000000000001/' +
                'resourceGroups/rg-synthetic-prod/providers/' +
                'Microsoft.ApiManagement/service/apim-synthetic-prod/' +
                'policyFragments?api-version=2024-05-01'
            )
            $script:policyRequests[0].Uri | Should -Be (
                '/subscriptions/00000000-0000-0000-0000-000000000001/' +
                'resourceGroups/rg-synthetic-prod/providers/' +
                'Microsoft.ApiManagement/service/apim-synthetic-prod/' +
                'policies/policy?format=xml&api-version=2024-05-01'
            )

            foreach ($fixture in Get-ChildItem -LiteralPath (
                    Join-Path $script:policyFixtureRoot 'policies'
                ) -Filter '*.xml') {
                Get-Content -LiteralPath (
                    Join-Path $script:run.Path "policies/$($fixture.Name)"
                ) -Raw | Should -Be (
                    Get-Content -LiteralPath $fixture.FullName -Raw
                )
            }

            $index = Get-Content -LiteralPath (
                Join-Path $script:run.Path 'policies/index.json'
            ) -Raw | ConvertFrom-Json -Depth 100
            $expectedIndex = Get-Content -LiteralPath (
                Join-Path $script:policyFixtureRoot 'policies/index.json'
            ) -Raw | ConvertFrom-Json -Depth 100
            ($index | ConvertTo-Json -Depth 100 -Compress) |
                Should -Be ($expectedIndex | ConvertTo-Json -Depth 100 -Compress)
            $index.schemaVersion | Should -Be '1.0'
            $index.policies.Count | Should -Be 8
            @($index.policies | Where-Object exists).Count | Should -Be 5
            @($index.policies | Where-Object {
                    -not $_.exists -and $null -ne $_.sha256
                }) | Should -BeNullOrEmpty
            @($index.policies | Where-Object {
                    $_.exists -and $_.sha256 -notmatch '^[0-9a-f]{64}$'
                }) | Should -BeNullOrEmpty
            ($index.policies | Where-Object {
                    $_.file -eq 'policies/api.orders-v1.xml'
                }).hardcodedSecretLocations | Should -Be @(
                '/policies[1]/inbound[1]/set-header[1]/value[1]'
            )
            ($index.policies | Where-Object {
                    $_.file -eq 'policies/op.orders-v1.get-orders.xml'
                }).hardcodedSecretLocations | Should -Be @(
                '/policies[1]/backend[1]/authentication-basic[1]/@password'
            )

            $persistedRunContent = Get-ChildItem -LiteralPath (
                $script:run.Path
            ) -File -Recurse | ForEach-Object {
                Get-Content -LiteralPath $_.FullName -Raw
            }
            ($persistedRunContent -join "`n") |
                Should -Not -Match 'synthetic-secret-value'

            $manifest = Get-RunManifest -RunPath $script:run.Path
            $collector = $manifest.collectors |
                Where-Object name -EQ 'Policies'
            $collector.status | Should -Be 'Completed'
            $collector.items | Should -Be 8
            $collector.errors | Should -Be 0
            $manifest.warnings | Should -Contain (
                'Policy secret candidates were redacted; locations are recorded ' +
                'in the restricted policy index.'
            )
        }

        It 'records a failed collector without policy output on request failure' {
            Mock Invoke-ApimParallelArmRequest {
                $exception = [System.InvalidOperationException]::new(
                    'One or more parallel ARM requests failed.'
                )
                $exception.Data['FailureCount'] = 2
                throw $exception
            }

            {
                Invoke-ApimPolicyCollector -RunPath $script:run.Path `
                    -Environment $script:environment
            } | Should -Throw '*parallel ARM requests failed*'

            Test-Path -LiteralPath (
                Join-Path $script:run.Path 'policies/index.json'
            ) | Should -BeFalse
            $manifest = Get-RunManifest -RunPath $script:run.Path
            $collector = $manifest.collectors |
                Where-Object name -EQ 'Policies'
            $collector.status | Should -Be 'Failed'
            $collector.errors | Should -Be 2
        }

        It 'keeps only previously sanitized XML when a later policy is rejected' {
            Mock Invoke-ApimParallelArmRequest {
                @(
                    [pscustomobject]@{
                        index = 0
                        notFound = $false
                        payload = [pscustomobject]@{
                            properties = [pscustomobject]@{
                                value = '<policies><inbound><base /></inbound></policies>'
                            }
                        }
                    }
                    [pscustomobject]@{
                        index = 1
                        notFound = $false
                        payload = [pscustomobject]@{
                            properties = [pscustomobject]@{
                                value = '<policies><inbound><set-variable ' +
                                    'value="bad "synthetic-private"" /></inbound></policies>'
                            }
                        }
                    }
                )
            }

            $rejection = $null
            try {
                Invoke-ApimPolicyCollector -RunPath $script:run.Path `
                    -Environment $script:environment | Out-Null
            }
            catch {
                $rejection = $_
            }

            Get-ApimSmokeFailureCode -ErrorRecord $rejection |
                Should -Be 'POLICY_XML_REJECTED'
            Test-Path -LiteralPath (
                Join-Path $script:run.Path 'policies/global.xml'
            ) | Should -BeTrue
            Test-Path -LiteralPath (
                Join-Path $script:run.Path 'policies/product.internal.xml'
            ) | Should -BeFalse
            Test-Path -LiteralPath (
                Join-Path $script:run.Path 'policies/index.json'
            ) | Should -BeFalse
            $manifest = Get-RunManifest -RunPath $script:run.Path
            $collector = $manifest.collectors |
                Where-Object name -EQ Policies
            $collector.status | Should -Be 'Partial'
            $collector.errors | Should -Be 1
            (Get-Content -LiteralPath $script:run.LogPath -Raw) |
                Should -Not -Match 'synthetic-private'
        }
    }
}
