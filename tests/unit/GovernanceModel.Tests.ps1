$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Explicit product governance evidence' {
    InModuleScope ApimAssessment {
        BeforeEach {
            $script:governanceProducts = [pscustomobject]@{ value = @(
                [pscustomobject]@{ name = 'partner'; properties = [pscustomobject]@{
                    description = 'SYNTHETIC_DESCRIPTION_CANARY'; approvalRequired = $false
                    owner = 'SYNTHETIC_OWNER_CANARY'
                } }
            ) }
        }

        It 'keeps absent intent unknown instead of inferring ownership or external classification' {
            $rows = Get-ApimProductGovernanceModel -ProductsPayload $script:governanceProducts
            $rows.Count | Should -Be 1
            $rows[0].hasDescription | Should -BeTrue
            $rows[0].hasOwner | Should -BeNullOrEmpty
            $rows[0].isExternal | Should -BeNullOrEmpty
            $rows[0].missingInputs | Should -Be @('externalIntent', 'ownerIntent')
            $rows[0].modelStatus | Should -Be Partial
            ConvertTo-Json $rows -Depth 10 | Should -Not -Match 'CANARY'
            Test-ApimModelJson -Name products -Json (ConvertTo-Json -InputObject $rows -Depth 10)
        }

        It 'retains explicit booleans and missing description without storing identity or description text' {
            $script:governanceProducts.value[0].properties.description = ' '
            $rows = Get-ApimProductGovernanceModel -ProductsPayload $script:governanceProducts `
                -ProductIntent @(@{ ProductId = 'partner'; HasOwner = $false; IsExternal = $true })
            $rows[0].hasDescription | Should -BeFalse
            $rows[0].hasOwner | Should -BeFalse
            $rows[0].isExternal | Should -BeTrue
            $rows[0].approvalRequired | Should -BeFalse
            $rows[0].modelStatus | Should -Be Complete
        }

        It 'keeps approval unknown for an external product rather than defaulting to disabled' {
            $script:governanceProducts.value[0].properties.approvalRequired = $null
            $rows = Get-ApimProductGovernanceModel -ProductsPayload $script:governanceProducts `
                -ProductIntent @(@{ ProductId = 'partner'; HasOwner = $true; IsExternal = $true })
            $rows[0].approvalRequired | Should -BeNullOrEmpty
            $rows[0].missingInputs | Should -Be @('approval')
        }

        It 'joins exact IDs and retains unresolved configured products' {
            $rows = Get-ApimProductGovernanceModel -ProductsPayload $script:governanceProducts `
                -ProductIntent @(@{ ProductId = 'PARTNER'; HasOwner = $false; IsExternal = $true })
            $rows.Count | Should -Be 2
            $configured = @($rows | Where-Object productId -CEQ PARTNER)[0]
            $configured.productFound | Should -BeFalse
            $configured.hasOwner | Should -BeNullOrEmpty
            $configured.missingInputs | Should -Be @('product')
            @($rows | Where-Object productId -CEQ partner)[0].hasOwner | Should -BeNullOrEmpty
        }

        It 'validates all optional models before writing any files' {
            $rows = Get-ApimProductGovernanceModel -ProductsPayload $script:governanceProducts
            $rows[0] | Add-Member NoteProperty ownerIdentity 'SYNTHETIC_CANARY'
            $path = Join-Path $TestDrive 'invalid-models'
            { Write-ApimModelSet -RunPath $path -Models @{ products = $rows } } | Should -Throw '*schema validation*'
            Test-Path $path | Should -BeFalse
        }
    }
}

Describe 'Effective diagnostic configuration evidence' {
    InModuleScope ApimAssessment {
        BeforeEach {
            $script:coverageApis = [pscustomobject]@{ value = @(
                [pscustomobject]@{ name = 'orders'; properties = @{ isCurrent = $true } }
            ) }
            $script:coverageDiagnostic = [pscustomobject]@{ name = 'applicationinsights'; properties = @{
                loggerId = '/loggers/insights'; sampling = @{ samplingType = 'fixed'; percentage = 100 }
            } }
            $script:coverageArguments = @{
                ApisPayload = $script:coverageApis
                LoggersPayload = [pscustomobject]@{ value = @([pscustomobject]@{ name = 'insights' }) }
                ServiceDiagnosticsPayload = [pscustomobject]@{ value = @($script:coverageDiagnostic) }
                DiagnosticsByApi = @{ orders = [pscustomobject]@{ value = @() } }
                Governance = @{ CriticalApiIds = @('orders') }
                ServiceResourcePath = '/subscriptions/synthetic/resourceGroups/synthetic/providers/Microsoft.ApiManagement/service/synthetic'
            }
        }

        It 'uses service diagnostics only after a known empty API configuration' {
            $row = (Get-ApimDiagnosticCoverageModel @script:coverageArguments)[0]
            $row.sourceScope | Should -Be Service
            $row.configured | Should -BeTrue
            $row.loggerResolved | Should -BeTrue
            $row.samplingPercentage | Should -Be 100
            $row.isCritical | Should -BeTrue
            $row.modelStatus | Should -Be Complete
            Test-ApimModelJson -Name diagnosticCoverage -Json (
                ConvertTo-Json -InputObject @($row) -Depth 10
            )
        }

        It 'attributes API overrides and exact sampling below and at 100 (<Percentage>)' -ForEach @(
            @{ Percentage = 0 }; @{ Percentage = 99.99 }; @{ Percentage = 100 }
        ) {
            $apiDiagnostic = [pscustomobject]@{ name = 'applicationinsights'; properties = @{
                loggerId = '/loggers/insights'; sampling = @{ samplingType = 'fixed'; percentage = $Percentage }
            } }
            $script:coverageArguments.DiagnosticsByApi.orders.value = @($apiDiagnostic)
            $row = (Get-ApimDiagnosticCoverageModel @script:coverageArguments)[0]
            $row.sourceScope | Should -Be Api
            $row.samplingPercentage | Should -Be $Percentage
        }

        It 'distinguishes absent configuration from missing API, service or logger evidence (<Kind>)' -ForEach @(
            @{ Kind = 'absent' }; @{ Kind = 'apiUnknown' }
            @{ Kind = 'serviceUnknown' }; @{ Kind = 'loggerUnknown' }; @{ Kind = 'loggerMismatch' }
        ) {
            switch ($Kind) {
                absent { $script:coverageArguments.ServiceDiagnosticsPayload.value = @() }
                apiUnknown { $script:coverageArguments.DiagnosticsByApi = @{} }
                serviceUnknown { $script:coverageArguments.ServiceDiagnosticsPayload = $null }
                loggerUnknown { $script:coverageArguments.LoggersPayload = $null }
                loggerMismatch {
                    $script:coverageDiagnostic.properties.loggerId =
                        '/subscriptions/other/resourceGroups/other/providers/Microsoft.ApiManagement/service/other/loggers/insights'
                }
            }
            $row = (Get-ApimDiagnosticCoverageModel @script:coverageArguments)[0]
            switch ($Kind) {
                absent {
                    $row.configured | Should -BeFalse
                    $row.sourceScope | Should -Be None
                    $row.modelStatus | Should -Be Complete
                }
                loggerUnknown {
                    $row.configured | Should -BeTrue
                    $row.loggerResolved | Should -BeNullOrEmpty
                    $row.missingInputs | Should -Contain logger
                }
                loggerMismatch { $row.loggerResolved | Should -BeFalse }
                default {
                    $row.configured | Should -BeNullOrEmpty
                    $row.sourceScope | Should -Be Unknown
                    $row.missingInputs | Should -Contain diagnostics
                }
            }
        }

        It 'preserves absent critical intent separately from explicit no-critical-API attestation' {
            $script:coverageArguments.Governance = $null
            $unknown = (Get-ApimDiagnosticCoverageModel @script:coverageArguments)[0]
            $unknown.isCritical | Should -BeNullOrEmpty
            $unknown.missingInputs | Should -Be @('criticalIntent')
            $script:coverageArguments.Governance = @{ CriticalApiIds = @() }
            $known = (Get-ApimDiagnosticCoverageModel @script:coverageArguments)[0]
            $known.isCritical | Should -BeFalse
            $known.modelStatus | Should -Be Complete
        }

        It 'does not invent sampling when the type or percentage is unavailable (<Kind>)' -ForEach @(
            @{ Kind = 'percentage' }; @{ Kind = 'type' }
        ) {
            if ($Kind -ceq 'percentage') { $script:coverageDiagnostic.properties.sampling.percentage = $null }
            else { $script:coverageDiagnostic.properties.sampling.samplingType = $null }
            $row = (Get-ApimDiagnosticCoverageModel @script:coverageArguments)[0]
            $row.samplingPercentage | Should -BeNullOrEmpty
            $row.missingInputs | Should -Contain sampling
        }

        It 'preserves a known low sample alongside an unrelated unknown diagnostic sample' {
            $script:coverageDiagnostic.properties.sampling.percentage = 50
            $script:coverageArguments.ServiceDiagnosticsPayload.value += [pscustomobject]@{
                name = 'eventhub'; properties = @{ loggerId = '/loggers/insights' }
            }
            $row = (Get-ApimDiagnosticCoverageModel @script:coverageArguments)[0]
            $row.samplingPercentage | Should -Be 50
            $row.modelStatus | Should -Be Partial
            $row.missingInputs | Should -Contain sampling
        }

        It 'retains unresolved critical IDs and never projects their intent onto a different API' {
            $script:coverageArguments.Governance = @{ CriticalApiIds = @('ORDERS') }
            $rows = Get-ApimDiagnosticCoverageModel @script:coverageArguments
            $rows.Count | Should -Be 2
            $unresolved = @($rows | Where-Object apiId -CEQ ORDERS)[0]
            $unresolved.apiFound | Should -BeFalse
            $unresolved.configured | Should -BeNullOrEmpty
            $unresolved.missingInputs | Should -Contain api
            @($rows | Where-Object apiId -CEQ orders)[0].isCritical | Should -BeFalse
        }
    }
}
