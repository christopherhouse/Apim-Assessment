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
            Mock Invoke-ApimSecurityAssetCollector {
                $script:smokeOrder.Add('SecurityAssets')
                Set-RunCollectorStatus -RunPath $RunPath -Name SecurityAssets `
                    -Status Completed -Items 7
                'synthetic-private-security-assets-path'
            }
            Mock Invoke-ApimDiagnosticsCollector {
                $script:smokeOrder.Add('Diagnostics')
                Set-RunCollectorStatus -RunPath $RunPath -Name Diagnostics `
                    -Status Completed -Items 5
                'synthetic-private-diagnostics-path'
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

            $names = @(
                'Service', 'Apis', 'Products', 'Subscriptions',
                'SecurityAssets', 'Diagnostics', 'Policies', 'Network'
            )
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
            Should -Invoke Invoke-ApimDiagnosticsCollector -Exactly -Times 1 `
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

        It 'streams only bounded check transitions in order' {
            $script:smokeEvents = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-ApimApiCatalogCollector {
                $script:smokeOrder.Add('Apis')
                throw 'synthetic-private-canary'
            }

            $result = Invoke-ApimSmoke -Config $script:smokeConfig `
                -EnvironmentName Prod -TenantId (
                    '00000000-0000-0000-0000-000000000010'
                ) -OnProgress {
                    param($update)
                    $script:smokeEvents.Add($update)
                }

            $result.Status | Should -Be 'Partial'
            @($script:smokeEvents.Phase) | Should -Be @(
                'Running', 'Finished', 'Running', 'Finished',
                'Running', 'Finished', 'Running', 'Finished',
                'Running', 'Finished', 'Finished', 'Finished',
                'Running', 'Finished'
            )
            @($script:smokeEvents.Name) | Should -Be @(
                'Service', 'Service', 'Apis', 'Apis', 'Products', 'Products',
                'Subscriptions', 'Subscriptions', 'SecurityAssets',
                'SecurityAssets', 'Diagnostics', 'Policies', 'Network',
                'Network'
            )
            $script:smokeEvents[2].Index | Should -Be 2
            $script:smokeEvents[2].Total | Should -Be 8
            $script:smokeEvents[3].Status | Should -Be 'Failed'
            $script:smokeEvents[3].FailureCode | Should -Be 'UNKNOWN_FAILURE'
            $script:smokeEvents[10].Status | Should -Be 'Skipped'
            $script:smokeEvents[10].FailureCode | Should -BeNullOrEmpty
            $script:smokeEvents[11].Status | Should -Be 'Skipped'
            $script:smokeEvents[11].FailureCode | Should -BeNullOrEmpty
            (ConvertTo-Json -InputObject @($script:smokeEvents) -Depth 5) |
                Should -Not -Match 'synthetic-private|00000000-0000'
        }

        It 'formats streamed failures without revealing collector messages' {
            . (Join-Path $script:smokeRepoRoot `
                    'scripts/Format-ApimSmokeConsoleLine.ps1')
            $formatter = ${function:Format-ApimSmokeConsoleLine}
            $lines = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-ApimApiCatalogCollector {
                throw 'synthetic-private-canary'
            }
            $callback = {
                param($update)
                $parameters = @{
                    State = if ($update.Phase -eq 'Running') {
                        'Running'
                    }
                    else {
                        $update.Status
                    }
                    Name = $update.Name
                    Index = $update.Index
                    Total = $update.Total
                }
                if ($update.FailureCode) {
                    $parameters.FailureCode = $update.FailureCode
                }
                $lines.Add((& $formatter @parameters))
            }.GetNewClosure()

            Invoke-ApimSmoke -Config $script:smokeConfig `
                -EnvironmentName Prod -TenantId (
                    '00000000-0000-0000-0000-000000000010'
                ) -OnProgress $callback | Out-Null

            $lines.Count | Should -Be 14
            $lines[3] | Should -Match 'Apis - Failed \(UNKNOWN_FAILURE\)'
            $lines[10] | Should -Match 'Diagnostics - Skipped'
            $lines[11] | Should -Match 'Policies - Skipped'
            ($lines -join ' ') | Should -Not -Match 'synthetic-private'
        }

        It 'skips API-dependent checks while continuing independent checks' {
            Mock Invoke-ApimApiCatalogCollector {
                $script:smokeOrder.Add('Apis')
                throw 'synthetic-private-canary'
            }

            $result = Invoke-ApimSmoke -Config $script:smokeConfig `
                -EnvironmentName Prod -TenantId (
                    '00000000-0000-0000-0000-000000000010'
                )

            @($script:smokeOrder) | Should -Be @(
                'Service', 'Apis', 'Products', 'Subscriptions',
                'SecurityAssets', 'Network'
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
            ($result.Checks | Where-Object Name -EQ Diagnostics).Status |
                Should -Be 'Skipped'
            (ConvertTo-Json -InputObject $result -Depth 10) |
                Should -Not -Match 'synthetic-private-canary'
            Should -Invoke Invoke-ApimPolicyCollector -Exactly -Times 0
            Should -Invoke Invoke-ApimDiagnosticsCollector -Exactly -Times 0

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
                Should -Be 7
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
                Should -Be 7
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
                Should -Be 7
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

        It 'classifies only marked XML parser rejections without exposing source' {
            . (Join-Path $script:smokeRepoRoot `
                    'scripts/Format-ApimSmokeConsoleLine.ps1')
            $invalidXml = '<policies><inbound><set-header ' +
                'name="bad "synthetic-private"" /></inbound></policies>'
            $errorRecord = $null
            try {
                Protect-ApimPolicyXml -Xml $invalidXml | Out-Null
            }
            catch {
                $errorRecord = $_
            }

            Get-ApimSmokeFailureCode -ErrorRecord $errorRecord |
                Should -Be 'POLICY_XML_REJECTED'
            $unmarked = [System.InvalidOperationException]::new(
                'synthetic-private'
            )
            $unmarkedRecord = [System.Management.Automation.ErrorRecord]::new(
                $unmarked, 'Synthetic',
                [System.Management.Automation.ErrorCategory]::NotSpecified,
                $null
            )
            Get-ApimSmokeFailureCode -ErrorRecord $unmarkedRecord |
                Should -Be 'UNKNOWN_FAILURE'
            Format-ApimSmokeConsoleLine -State Partial -Name Policies `
                -Index 6 -Total 7 -FailureCode POLICY_XML_REJECTED |
                Should -Not -Match 'synthetic-private'
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
            ($result.Checks | Where-Object Name -EQ Diagnostics).Status |
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

Describe 'Saved collection smoke output validation' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)

        $script:smokeOutputRepoRoot = $RepoRoot
        BeforeEach {
            $config = Import-PowerShellDataFile (
                Join-Path $script:smokeOutputRepoRoot 'config/sample.psd1'
            )
            $config.Output.Root = Join-Path $TestDrive (
                [guid]::NewGuid().ToString('N')
            )
            $script:outputEnvironment = $config.Environments[0]
            $script:outputEnvironment.AppGateways = @()
            $script:outputRun = New-ApimRun -Config $config `
                -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000010' `
                -Operator LocalMaintainer -RunId 'synthetic-smoke'
            $script:outputNames = @(
                'Service', 'Apis', 'Products', 'Subscriptions',
                'SecurityAssets', 'Diagnostics', 'Policies', 'Network'
            )
            $script:outputItems = @(1, 1, 1, 1, 1, 1, 1, 7)
            $script:outputResult = [pscustomobject]@{
                RunId = $script:outputRun.RunId
                Status = 'Completed'
                Checks = @(
                    foreach ($name in $script:outputNames) {
                        [pscustomobject]@{
                            Name = $name
                            Status = 'Completed'
                        }
                    }
                )
            }
            foreach ($relativePath in @(
                    'raw/service.json', 'raw/apis.json',
                    'raw/apiRevisions/synthetic-api.json',
                    'raw/operations/synthetic-api.json',
                    'raw/apiTags/synthetic-api.json',
                    'raw/products.json',
                    'raw/productApis/synthetic-product.json',
                    'raw/productGroups/synthetic-product.json',
                    'raw/subscriptions.json', 'raw/namedValues.json',
                    'raw/backends.json', 'raw/certificates.json',
                    'raw/loggers.json', 'raw/diagnostics.json',
                    'raw/apiDiagnostics/synthetic-api.json'
                )) {
                $value = switch ($relativePath) {
                    'raw/service.json' {
                        [pscustomobject]@{ name = 'synthetic-service' }
                    }
                    'raw/apis.json' {
                        [pscustomobject]@{
                            value = @([pscustomobject]@{ name = 'synthetic-api' })
                        }
                    }
                    'raw/products.json' {
                        [pscustomobject]@{
                            value = @([pscustomobject]@{ name = 'synthetic-product' })
                        }
                    }
                    { $_ -in @(
                            'raw/subscriptions.json', 'raw/namedValues.json',
                            'raw/diagnostics.json'
                        ) } {
                        [pscustomobject]@{
                            value = @([pscustomobject]@{ name = 'synthetic-item' })
                        }
                    }
                    default { [pscustomobject]@{ value = @() } }
                }
                Write-RunFile -RunPath $script:outputRun.Path `
                    -RelativePath $relativePath -InputObject $value |
                    Out-Null
            }
            $script:policyXml = '<policies><inbound><base /></inbound></policies>'
            Write-RunFile -RunPath $script:outputRun.Path `
                -RelativePath 'policies/global.xml' `
                -InputObject $script:policyXml -Format Text | Out-Null
            Write-RunFile -RunPath $script:outputRun.Path `
                -RelativePath 'policies/index.json' -InputObject (
                    [pscustomobject]@{
                        schemaVersion = '1.0'
                        policies = @([pscustomobject]@{
                                file = 'policies/global.xml'
                                exists = $true
                                sha256 = Get-ApimPolicySha256 -Xml $script:policyXml
                            })
                    }
                ) | Out-Null
            foreach ($file in @(
                    'apimSubnet', 'nsgs', 'privateEndpoints',
                    'privateDnsZones', 'routeTables', 'publicIps', 'frontDoors'
                )) {
                Write-RunFile -RunPath $script:outputRun.Path `
                    -RelativePath "raw/network/$file.json" `
                    -InputObject ([pscustomobject]@{ value = @() }) |
                    Out-Null
            }
            for ($index = 0; $index -lt $script:outputNames.Count; $index++) {
                Set-RunCollectorStatus -RunPath $script:outputRun.Path `
                    -Name $script:outputNames[$index] -Status Completed `
                    -Items $script:outputItems[$index]
            }
            Set-RunStageStatus -RunPath $script:outputRun.Path `
                -Stage collect -Status Completed
            Complete-ApimRun -RunPath $script:outputRun.Path
        }

        It 'verifies the completed synthetic manifest, inventories and files' {
            {
                Test-ApimSmokeOutput -RunPath $script:outputRun.Path `
                    -Result $script:outputResult `
                    -Environment $script:outputEnvironment
            } | Should -Not -Throw
        }

        It 'rejects a missing API child file despite a completed collector' {
            Remove-Item -LiteralPath (
                Join-Path $script:outputRun.Path `
                    'raw/apiDiagnostics/synthetic-api.json'
            )
            {
                Test-ApimSmokeOutput -RunPath $script:outputRun.Path `
                    -Result $script:outputResult `
                    -Environment $script:outputEnvironment
            } | Should -Throw 'Smoke output is missing a required file.'
        }

        It 'rejects malformed JSON and mismatched collector counts' {
            Set-Content -LiteralPath (
                Join-Path $script:outputRun.Path 'raw/namedValues.json'
            ) -Value '{synthetic-invalid'
            {
                Test-ApimSmokeOutput -RunPath $script:outputRun.Path `
                    -Result $script:outputResult `
                    -Environment $script:outputEnvironment
            } | Should -Throw 'Smoke output contains invalid JSON.'

            Write-RunFile -RunPath $script:outputRun.Path `
                -RelativePath 'raw/namedValues.json' `
                -InputObject ([pscustomobject]@{ value = @() }) | Out-Null
            {
                Test-ApimSmokeOutput -RunPath $script:outputRun.Path `
                    -Result $script:outputResult `
                    -Environment $script:outputEnvironment
            } | Should -Throw 'Smoke collector item count does not match saved output.'
        }

        It 'rejects policy XML changed after its index hash was saved' {
            Write-RunFile -RunPath $script:outputRun.Path `
                -RelativePath 'policies/global.xml' `
                -InputObject '<policies><outbound /></policies>' `
                -Format Text | Out-Null
            {
                Test-ApimSmokeOutput -RunPath $script:outputRun.Path `
                    -Result $script:outputResult `
                    -Environment $script:outputEnvironment
            } | Should -Throw 'Smoke policy hash does not match the index.'
        }

        It 'rejects a manifest whose collector status disagrees with the run' {
            Set-RunCollectorStatus -RunPath $script:outputRun.Path `
                -Name Network -Status Partial -Errors 1
            {
                Test-ApimSmokeOutput -RunPath $script:outputRun.Path `
                    -Result $script:outputResult `
                    -Environment $script:outputEnvironment
            } | Should -Throw 'Smoke manifest collector status does not match the run.'
        }

        It 'does not substitute an older run for the just-created run ID' {
            $script:outputResult.RunId = 'another-synthetic-run'
            {
                Test-ApimSmokeOutput -RunPath $script:outputRun.Path `
                    -Result $script:outputResult `
                    -Environment $script:outputEnvironment
            } | Should -Throw 'Smoke manifest does not match the completed run.'
        }

        It 'validates completed files in a partial run without claiming success' {
            Set-RunCollectorStatus -RunPath $script:outputRun.Path `
                -Name Network -Status Failed -Errors 1
            Set-RunStageStatus -RunPath $script:outputRun.Path `
                -Stage collect -Status Partial
            $script:outputResult.Status = 'Partial'
            $script:outputResult.Checks[-1].Status = 'Failed'
            {
                Test-ApimSmokeOutput -RunPath $script:outputRun.Path `
                    -Result $script:outputResult `
                    -Environment $script:outputEnvironment
            } | Should -Not -Throw
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
        $output[-1] |
            Should -Be 'SMOKE_CONFIG_ERROR: acknowledge a Microsoft-owned test environment.'
    }

    It 'accepts the default private-config argument without weakening acknowledgement' {
        $output = & pwsh -NoProfile -File $script:smokeScript `
            -Environment Test 2>&1

        $LASTEXITCODE | Should -Be 1
        $output[-1] |
            Should -Be 'SMOKE_CONFIG_ERROR: acknowledge a Microsoft-owned test environment.'
    }

    It 'rejects repository-local configuration with a fixed safe error' {
        $output = & pwsh -NoProfile -File $script:smokeScript `
            -Config (Join-Path $repoRoot 'config/sample.psd1') `
            -Environment Prod -MicrosoftOwnedTestEnvironment 2>&1

        $LASTEXITCODE | Should -Be 1
        $output[-1] |
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
        $output[-1] |
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
        $output[-1] |
            Should -Be 'SMOKE_CONFIG_ERROR: check the private configuration and output locations.'
        $output -join ' ' | Should -Not -Match [regex]::Escape($repoRoot)
    }
}

Describe 'Smoke progress presentation' {
    BeforeAll {
        . (Join-Path $repoRoot 'scripts/Format-ApimSmokeConsoleLine.ps1')
    }

    It 'formats accessible progress and bounded help without terminal control codes' {
        Format-ApimSmokeConsoleLine -State Running -Name Service `
            -Index 1 -Total 6 | Should -Be (
            '[RUN] [#---------] 1/6 Service - collecting...'
        )
        Format-ApimSmokeConsoleLine -State Failed -Name Subscriptions `
            -Index 4 -Total 6 -FailureCode UNKNOWN_FAILURE |
            Should -Be (
                '[FAIL] [######----] 4/6 Subscriptions - Failed ' +
                '(UNKNOWN_FAILURE) - Inspect the restricted run locally.'
            )
        Format-ApimSmokeConsoleLine -State Skipped -Name Policies `
            -Index 5 -Total 6 | Should -Match 'prerequisite not complete'
        Format-ApimSmokeConsoleLine -State Summary `
            -SummaryStatus Partial |
            Should -Be '[SMOKE] Collection smoke: Partial'
    }

    It 'uses terminal color only when requested and rejects unsafe error codes' {
        $colored = Format-ApimSmokeConsoleLine -State Completed `
            -Name Service -Index 1 -Total 6 -Color
        $colored | Should -Match '^\x1b\['
        $colored | Should -Match '01/06.*Service\s+DONE'
        $colored | Should -Match ([regex]::Escape(
                [char]::ConvertFromUtf32(0x2705)
            ))
        $colored | Should -Not -Match '\[#'
        $header = Format-ApimSmokeConsoleLine -State Header -Color
        $header | Should -Match 'APIM / COLLECTION SMOKE'
        $summary = Format-ApimSmokeConsoleLine -State Summary `
            -SummaryStatus Partial -CompletedCount 5 -Total 6 -Color
        $summary | Should -Match '5/6 checks complete.*PARTIAL'
        $policy = Format-ApimSmokeConsoleLine -State Partial `
            -Name Policies -Index 5 -Total 6 `
            -FailureCode POLICY_XML_REJECTED -Color
        $policy | Should -Match 'POLICY_XML_REJECTED'
        $policy | Should -Not -Match 'synthetic-private'
        {
            Format-ApimSmokeConsoleLine -State Failed -Name Service `
                -Index 1 -Total 6 -FailureCode 'synthetic-private-canary'
        } | Should -Throw
    }

    It 'emits real emoji under a legacy code page and restores the encoding' {
        $probe = Join-Path $TestDrive 'synthetic-console-probe.ps1'
        @'
param($FormatterPath)
. $FormatterPath
[Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(437)
$line = Format-ApimSmokeConsoleLine -State Completed -Name Service `
    -Index 1 -Total 6 -Color
Write-ApimSmokeConsoleLine -Line $line -Color
[Console]::Out.WriteLine("encoding:$([Console]::OutputEncoding.CodePage)")
'@ | Set-Content -LiteralPath $probe -Encoding ascii

        $output = @(& pwsh -NoProfile -File $probe (
                Join-Path $repoRoot 'scripts/Format-ApimSmokeConsoleLine.ps1'
            ))
        $LASTEXITCODE | Should -Be 0
        $output.Count | Should -Be 2
        $output[0] | Should -Match ([regex]::Escape(
                [char]::ConvertFromUtf32(0x2705)
            ))
        $output[0] | Should -Match '01/06.*DONE'
        $output[1] | Should -Be 'encoding:437'
    }

    It 'replaces a rich running row but preserves plain streamed lines' {
        $probe = Join-Path $TestDrive 'synthetic-scorecard-probe.ps1'
        @'
param($FormatterPath)
. $FormatterPath
$running = Format-ApimSmokeConsoleLine -State Running -Name Service `
    -Index 1 -Total 6 -Color
$done = Format-ApimSmokeConsoleLine -State Completed -Name Service `
    -Index 1 -Total 6 -Color
Write-ApimSmokeConsoleLine -Line $running -Color -Transient
Write-ApimSmokeConsoleLine -Line $done -Color -ReplaceTransient
'@ | Set-Content -LiteralPath $probe -Encoding ascii

        $output = @(& pwsh -NoProfile -File $probe (
                Join-Path $repoRoot 'scripts/Format-ApimSmokeConsoleLine.ps1'
            ))
        $LASTEXITCODE | Should -Be 0
        $output.Count | Should -Be 2
        $output[0] | Should -Match '01/06.*WORKING'
        $output[1] | Should -Match '\x1b\[2K.*01/06.*DONE'

        $plain = Format-ApimSmokeConsoleLine -State Completed `
            -Name Service -Index 1 -Total 6
        $plain | Should -Not -Match '\x1b'
        $plain | Should -Be '[OK] [#---------] 1/6 Service - Completed'
    }
}
