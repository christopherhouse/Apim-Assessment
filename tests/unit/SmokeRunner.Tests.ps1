$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Cumulative collection smoke runner' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)

        $script:smokeRepoRoot = $RepoRoot

        It 'rejects missing or mismatched Azure contexts without leaking IDs' `
            -TestCases @(
                @{ Kind = 'missing' }
                @{ Kind = 'mismatch' }
                @{ Kind = 'no-tenant' }
            ) {
            param($Kind)

            $context = [pscustomobject]@{
                Subscription = [pscustomobject]@{
                    Id = '00000000-0000-0000-0000-000000000001'
                }
                Tenant = [pscustomobject]@{
                    Id = '00000000-0000-0000-0000-000000000010'
                }
            }
            if ($Kind -eq 'missing') {
                $context = $null
            }
            elseif ($Kind -eq 'no-tenant') {
                $context.Tenant.Id = ''
            }
            $targetId = if ($Kind -eq 'mismatch') {
                '00000000-0000-0000-0000-000000000002'
            }
            else {
                '00000000-0000-0000-0000-000000000001'
            }
            {
                Test-ApimSmokeContext -Context $context -SubscriptionId $targetId
            } | Should -Throw 'Active Azure context does not match the selected test subscription.'
        }

        It 'accepts only an explicitly matching context' {
            $context = [pscustomobject]@{
                Subscription = [pscustomobject]@{
                    Id = '00000000-0000-0000-0000-000000000001'
                }
                Tenant = [pscustomobject]@{
                    Id = '00000000-0000-0000-0000-000000000010'
                }
            }
            Test-ApimSmokeContext -Context $context -SubscriptionId (
                '00000000-0000-0000-0000-000000000001'
            ) | Should -Be '00000000-0000-0000-0000-000000000010'
        }

        BeforeEach {
            $script:smokeConfig = Import-PowerShellDataFile (
                Join-Path $script:smokeRepoRoot 'config/sample.psd1'
            )
            $script:smokeConfig.Output.Root = Join-Path $TestDrive (
                [guid]::NewGuid().ToString('N')
            )
            $script:smokeOrder = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-ApimServiceCollector {
                $script:smokeOrder.Add('Service')
                Set-RunCollectorStatus -RunPath $RunPath -Name Service `
                    -Status Completed -Items 1
                'synthetic-private-service-path'
            }
            Mock Invoke-ApimApiCatalogCollector {
                $script:smokeOrder.Add('Apis')
                Set-RunCollectorStatus -RunPath $RunPath -Name Apis `
                    -Status Completed -Items 2
                'synthetic-private-apis-path'
            }
            Mock Invoke-ApimProductCollector {
                $script:smokeOrder.Add('Products')
                Set-RunCollectorStatus -RunPath $RunPath -Name Products `
                    -Status Completed -Items 2
                'synthetic-private-products-path'
            }
            Mock Invoke-ApimSubscriptionCollector {
                $script:smokeOrder.Add('Subscriptions')
                Set-RunCollectorStatus -RunPath $RunPath -Name Subscriptions `
                    -Status Completed -Items 4
                'synthetic-private-subscriptions-path'
            }
            Mock Invoke-ApimPolicyCollector {
                $script:smokeOrder.Add('Policies')
                Set-RunCollectorStatus -RunPath $RunPath -Name Policies `
                    -Status Completed -Items 3
                'synthetic-private-policies-path'
            }
            Mock Invoke-ApimNetworkCollector {
                $script:smokeOrder.Add('Network')
                Set-RunCollectorStatus -RunPath $RunPath -Name Network `
                    -Status Completed -Items 1
                'synthetic-private-network-path'
            }
        }

        It 'runs all existing checks in dependency order and completes the manifest' {
            $result = Invoke-ApimSmoke -Config $script:smokeConfig `
                -EnvironmentName Prod -TenantId (
                    '00000000-0000-0000-0000-000000000010'
                ) -ThrottleLimit 2

            $names = @('Service', 'Apis', 'Products', 'Subscriptions',
                'Policies', 'Network')
            @($script:smokeOrder) | Should -Be $names
            @($result.Checks.Name) | Should -Be $names
            @($result.Checks.Status | Sort-Object -Unique) |
                Should -Be @('Completed')
            $result.Status | Should -Be 'Completed'
            $serialized = ConvertTo-Json -InputObject $result -Depth 10
            $serialized | Should -Not -Match 'synthetic-private'
            $serialized | Should -Not -Match '00000000-0000'
            $serialized | Should -Not -Match [regex]::Escape($TestDrive)
            Should -Invoke Invoke-ApimApiCatalogCollector -Exactly -Times 1 `
                -ParameterFilter { $ThrottleLimit -eq 2 }
            Should -Invoke Invoke-ApimProductCollector -Exactly -Times 1 `
                -ParameterFilter { $ThrottleLimit -eq 2 }
            Should -Invoke Invoke-ApimPolicyCollector -Exactly -Times 1 `
                -ParameterFilter { $ThrottleLimit -eq 2 }

            $runFolder = @(Get-ChildItem -LiteralPath (
                    $script:smokeConfig.Output.Root
                ) -Directory)
            $runFolder.Count | Should -Be 1
            $manifest = Get-RunManifest -RunPath $runFolder[0].FullName
            $manifest.stages.collect | Should -Be 'Completed'
            $manifest.stages.analyze | Should -Be 'NotStarted'
            $manifest.stages.report | Should -Be 'NotStarted'
            $manifest.completedUtc | Should -Not -BeNullOrEmpty
            @($manifest.collectors.status | Sort-Object -Unique) |
                Should -Be @('Completed')
        }

        It 'skips policy after API failure while continuing independent checks' {
            Mock Invoke-ApimApiCatalogCollector {
                $script:smokeOrder.Add('Apis')
                throw 'synthetic-private-canary'
            }

            $result = Invoke-ApimSmoke -Config $script:smokeConfig `
                -EnvironmentName Prod -TenantId (
                    '00000000-0000-0000-0000-000000000010'
                )

            @($script:smokeOrder) | Should -Be @(
                'Service', 'Apis', 'Products', 'Subscriptions', 'Network'
            )
            $result.Status | Should -Be 'Partial'
            ($result.Checks | Where-Object Name -EQ Apis).Status |
                Should -Be 'Failed'
            ($result.Checks | Where-Object Name -EQ Apis).FailureCode |
                Should -Be 'UNKNOWN_FAILURE'
            ($result.Checks | Where-Object Name -EQ Policies).Status |
                Should -Be 'Skipped'
            ($result.Checks | Where-Object Name -EQ Policies).FailureCode |
                Should -BeNullOrEmpty
            ($result.Checks | Where-Object Name -EQ Network).Status |
                Should -Be 'Completed'
            (ConvertTo-Json -InputObject $result -Depth 10) |
                Should -Not -Match 'synthetic-private-canary'
            Should -Invoke Invoke-ApimPolicyCollector -Exactly -Times 0

            $runFolder = @(Get-ChildItem -LiteralPath (
                    $script:smokeConfig.Output.Root
                ) -Directory)
            $manifest = Get-RunManifest -RunPath $runFolder[0].FullName
            $manifest.stages.collect | Should -Be 'Partial'
            $manifest.completedUtc | Should -Not -BeNullOrEmpty
            $manifest.warnings -join ';' |
                Should -Not -Match 'synthetic-private-canary'
        }

        It 'skips all dependent checks if the service request fails' {
            Mock Invoke-ApimServiceCollector {
                $script:smokeOrder.Add('Service')
                throw 'synthetic-private-service-error'
            }

            $result = Invoke-ApimSmoke -Config $script:smokeConfig `
                -EnvironmentName Prod -TenantId (
                    '00000000-0000-0000-0000-000000000010'
                )

            @($script:smokeOrder) | Should -Be @('Service')
            $result.Status | Should -Be 'Partial'
            @($result.Checks.Status | Where-Object { $_ -eq 'Skipped' }).Count |
                Should -Be 5
            ($result.Checks | Where-Object Name -EQ Service).FailureCode |
                Should -Be 'UNKNOWN_FAILURE'
            Should -Invoke Invoke-ApimNetworkCollector -Exactly -Times 0
        }

        It 'reports only a bounded HTTP code for an ARM failure' -TestCases @(
            @{ HttpStatus = 403 }
            @{ HttpStatus = 404 }
            @{ HttpStatus = 503 }
        ) {
            param($HttpStatus)

            Mock Invoke-ApimServiceCollector {
                throw (Get-ApimArmFailure -StatusCode $HttpStatus -Attempts 1)
            }

            $result = Invoke-ApimSmoke -Config $script:smokeConfig `
                -EnvironmentName Prod -TenantId (
                    '00000000-0000-0000-0000-000000000010'
                )

            $service = $result.Checks | Where-Object Name -EQ Service
            $service.Status | Should -Be 'Failed'
            $service.FailureCode | Should -Be "ARM_HTTP_$HttpStatus"
            @($result.Checks | Where-Object Status -EQ Skipped).Count |
                Should -Be 5
            (ConvertTo-Json -InputObject $result -Depth 10) |
                Should -Not -Match '00000000-0000'
        }

        It 'distinguishes an ARM transport failure without a response' {
            Mock Invoke-ApimServiceCollector {
                throw (Get-ApimArmFailure -StatusCode $null -Attempts 1)
            }

            $result = Invoke-ApimSmoke -Config $script:smokeConfig `
                -EnvironmentName Prod -TenantId (
                    '00000000-0000-0000-0000-000000000010'
                )

            ($result.Checks | Where-Object Name -EQ Service).FailureCode |
                Should -Be 'ARM_NO_RESPONSE'
        }

        It 'exposes only allowlisted transport categories' -TestCases @(
            @{ Kind = 'AUTH'; Code = 'ARM_AUTH_ERROR' }
            @{ Kind = 'COMMAND'; Code = 'ARM_COMMAND_ERROR' }
            @{ Kind = 'NETWORK'; Code = 'ARM_NETWORK_ERROR' }
            @{ Kind = 'TIMEOUT'; Code = 'ARM_TIMEOUT' }
        ) {
            param($Kind, $Code)

            $script:smokeTransportKind = $Kind
            Mock Invoke-ApimServiceCollector {
                throw (Get-ApimArmFailure -StatusCode $null -Attempts 1 `
                    -TransportKind $script:smokeTransportKind)
            }

            $result = Invoke-ApimSmoke -Config $script:smokeConfig `
                -EnvironmentName Prod -TenantId (
                    '00000000-0000-0000-0000-000000000010'
                )

            ($result.Checks | Where-Object Name -EQ Service).FailureCode |
                Should -Be $Code
            @($result.Checks | Where-Object Status -EQ Skipped).Count |
                Should -Be 5
        }

        It 'distinguishes local I/O failures without printing a private path' {
            Mock Invoke-ApimServiceCollector {
                throw [System.IO.IOException]::new(
                    'synthetic-private-output-path'
                )
            }

            $result = Invoke-ApimSmoke -Config $script:smokeConfig `
                -EnvironmentName Prod -TenantId (
                    '00000000-0000-0000-0000-000000000010'
                )

            ($result.Checks | Where-Object Name -EQ Service).FailureCode |
                Should -Be 'LOCAL_IO_ERROR'
            (ConvertTo-Json -InputObject $result -Depth 10) |
                Should -Not -Match 'synthetic-private-output-path'
        }

        It 'does not trust unmarked or invalid HTTP statuses' {
            $unmarked = [System.Exception]::new('synthetic-private-error')
            $unmarked.Data['StatusCode'] = 403
            $invalid = Get-ApimArmFailure -StatusCode 700 -Attempts 1
            $unmarkedRecord = [System.Management.Automation.ErrorRecord]::new(
                $unmarked, 'Synthetic',
                [System.Management.Automation.ErrorCategory]::NotSpecified, $null
            )
            $invalidRecord = [System.Management.Automation.ErrorRecord]::new(
                $invalid, 'Synthetic',
                [System.Management.Automation.ErrorCategory]::NotSpecified, $null
            )
            Get-ApimSmokeFailureCode -ErrorRecord $unmarkedRecord |
                Should -Be 'UNKNOWN_FAILURE'
            Get-ApimSmokeFailureCode -ErrorRecord $invalidRecord |
                Should -Be 'ARM_NO_RESPONSE'
            $invalid.Data['TransportKind'] = 'synthetic-private-value'
            Get-ApimSmokeFailureCode -ErrorRecord $invalidRecord |
                Should -Be 'ARM_NO_RESPONSE'
        }

        It 'retains a collector Partial state and skips its dependents' {
            Mock Invoke-ApimApiCatalogCollector {
                $script:smokeOrder.Add('Apis')
                Set-RunCollectorStatus -RunPath $RunPath -Name Apis `
                    -Status Partial -Errors 1
                throw 'synthetic-private-child-failure'
            }

            $result = Invoke-ApimSmoke -Config $script:smokeConfig `
                -EnvironmentName Prod -TenantId (
                    '00000000-0000-0000-0000-000000000010'
                )

            $result.Status | Should -Be 'Partial'
            ($result.Checks | Where-Object Name -EQ Apis).Status |
                Should -Be 'Partial'
            ($result.Checks | Where-Object Name -EQ Policies).Status |
                Should -Be 'Skipped'
            ($result.Checks | Where-Object Name -EQ Network).Status |
                Should -Be 'Completed'
            (ConvertTo-Json -InputObject $result -Depth 10) |
                Should -Not -Match 'synthetic-private-child-failure'
        }

        It 'fails before creating a run when a registered check is unavailable' {
            Mock Get-Command { $null } -ParameterFilter {
                $Name -eq 'Invoke-ApimPolicyCollector'
            }

            {
                Invoke-ApimSmoke -Config $script:smokeConfig `
                    -EnvironmentName Prod -TenantId (
                        '00000000-0000-0000-0000-000000000010'
                    )
            } | Should -Throw 'A registered smoke check is unavailable.'
            Test-Path -LiteralPath $script:smokeConfig.Output.Root |
                Should -BeFalse
        }

        It 'fails rather than reporting a missing collector completion as success' {
            Mock Invoke-ApimSubscriptionCollector {
                $script:smokeOrder.Add('Subscriptions')
                'synthetic-private-incomplete'
            }

            $result = Invoke-ApimSmoke -Config $script:smokeConfig `
                -EnvironmentName Prod -TenantId (
                    '00000000-0000-0000-0000-000000000010'
                )

            $result.Status | Should -Be 'Partial'
            ($result.Checks | Where-Object Name -EQ Subscriptions).Status |
                Should -Be 'Failed'
        }
    }
}

Describe 'Maintainer-only smoke command preflight' {
    BeforeAll {
        $script:smokeScript = Join-Path $repoRoot 'scripts/Invoke-ApimSmoke.ps1'
    }

    It 'requires explicit test-environment acknowledgement before loading Azure' {
        $output = & pwsh -NoProfile -File $script:smokeScript `
            -Config (Join-Path $repoRoot 'config/sample.psd1') `
            -Environment Prod 2>&1

        $LASTEXITCODE | Should -Be 1
        ($output -join ' ') |
            Should -Be 'SMOKE_CONFIG_ERROR: acknowledge a Microsoft-owned test environment.'
    }

    It 'rejects repository-local configuration with a fixed safe error' {
        $output = & pwsh -NoProfile -File $script:smokeScript `
            -Config (Join-Path $repoRoot 'config/sample.psd1') `
            -Environment Prod -MicrosoftOwnedTestEnvironment 2>&1

        $LASTEXITCODE | Should -Be 1
        ($output -join ' ') |
            Should -Be 'SMOKE_CONFIG_ERROR: check the private configuration and output locations.'
    }

    It 'rejects repository-local output even with external synthetic configuration' {
        $source = Get-Content -LiteralPath (
            Join-Path $repoRoot 'config/sample.psd1'
        ) -Raw
        $configFile = Join-Path $TestDrive 'synthetic-smoke.psd1'
        $content = $source.Replace(
            '<absolute-external-restricted-path>',
            $repoRoot.Replace('\', '/')
        ).Replace(
            '<absolute-external-analysis-path>',
            (Join-Path $TestDrive 'model-safe').Replace('\', '/')
        )
        Set-Content -LiteralPath $configFile -Value $content

        $output = & pwsh -NoProfile -File $script:smokeScript `
            -Config $configFile -Environment Prod `
            -MicrosoftOwnedTestEnvironment 2>&1

        $LASTEXITCODE | Should -Be 1
        ($output -join ' ') |
            Should -Be 'SMOKE_CONFIG_ERROR: check the private configuration and output locations.'
        $output -join ' ' | Should -Not -Match [regex]::Escape($repoRoot)
    }

    It 'rejects a repository-local analysis root even though it is unused' {
        $source = Get-Content -LiteralPath (
            Join-Path $repoRoot 'config/sample.psd1'
        ) -Raw
        $configFile = Join-Path $TestDrive 'synthetic-analysis-root.psd1'
        $content = $source.Replace(
            '<absolute-external-restricted-path>',
            (Join-Path $TestDrive 'restricted').Replace('\', '/')
        ).Replace(
            '<absolute-external-analysis-path>',
            (Join-Path $repoRoot 'model-safe').Replace('\', '/')
        )
        Set-Content -LiteralPath $configFile -Value $content

        $output = & pwsh -NoProfile -File $script:smokeScript `
            -Config $configFile -Environment Prod `
            -MicrosoftOwnedTestEnvironment 2>&1

        $LASTEXITCODE | Should -Be 1
        ($output -join ' ') |
            Should -Be 'SMOKE_CONFIG_ERROR: check the private configuration and output locations.'
        $output -join ' ' | Should -Not -Match [regex]::Escape($repoRoot)
    }
}
