$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Evidence-backed GOV catalog' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)
        $script:govRulesRepoRoot = $RepoRoot

        BeforeAll {
            $script:govRulesConfig = Import-PowerShellDataFile (
                Join-Path $script:govRulesRepoRoot 'config/sample.psd1'
            )
            $script:govRulesConfig.Output.Root = Join-Path $TestDrive 'restricted'
            $run = New-ApimRun -Config $script:govRulesConfig `
                -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000002' `
                -Operator Synthetic -RunId 'synthetic-gov-rules'
            $script:govRulesManifest = Get-RunManifest -RunPath $run.Path
            $script:govRules = @(
                Get-ApimRuleCatalog -CatalogPath (
                    Join-Path $script:govRulesRepoRoot 'rules'
                ) | Where-Object Id -Like 'APIM-GOV-*'
            )
            $script:govFixtureRoot = Join-Path $script:govRulesRepoRoot (
                'tests/fixtures/synthetic-reference/model'
            )

            function Get-SyntheticGovModelSet {
                return [ordered]@{
                    apis = Get-Content -LiteralPath (
                        Join-Path $script:govFixtureRoot 'apis.exposure.json'
                    ) -Raw | ConvertFrom-Json -Depth 100 -NoEnumerate
                    operations = Get-Content -LiteralPath (
                        Join-Path $script:govFixtureRoot 'operations.json'
                    ) -Raw | ConvertFrom-Json -Depth 100 -NoEnumerate
                }
            }

            function Get-SyntheticGovFinding {
                param(
                    [Parameter(Mandatory)]
                    [string] $RuleId,

                    [Parameter(Mandatory)]
                    [System.Collections.IDictionary] $Models
                )

                $rule = @($script:govRules | Where-Object Id -EQ $RuleId)
                return @(Invoke-ApimRuleEngine -Rules $rule -Models $Models `
                        -Manifest $script:govRulesManifest `
                        -Config $script:govRulesConfig)
            }
        }

        It 'loads the ten currently model-backed GOV rules with empty references' {
            @($script:govRules.Id | Sort-Object) | Should -Be @(
                'APIM-GOV-001',
                'APIM-GOV-002',
                'APIM-GOV-003',
                'APIM-GOV-005',
                'APIM-GOV-006',
                'APIM-GOV-007',
                'APIM-GOV-008',
                'APIM-GOV-009',
                'APIM-GOV-010',
                'APIM-GOV-011'
            )
            foreach ($rule in $script:govRules) {
                $rule.References.Count | Should -Be 0
                $rule.Enabled | Should -BeTrue
            }
        }

        It 'flags only APIs without product membership' {
            $models = Get-SyntheticGovModelSet
            @(Get-SyntheticGovFinding -RuleId 'APIM-GOV-001' `
                    -Models $models).Count | Should -Be 0

            $models.apis[0].products = @()
            $found = @(Get-SyntheticGovFinding -RuleId 'APIM-GOV-001' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].scope | Should -Be 'api:orders-v1'
            $found[0].evidence.products.Count | Should -Be 0
            $found[0].sourceFiles | Should -Contain 'raw/productApis/'
        }

        It 'flags APIs without owner or team tags' {
            $models = Get-SyntheticGovModelSet
            $found = @(Get-SyntheticGovFinding -RuleId 'APIM-GOV-002' `
                    -Models $models)
            $found.Count | Should -Be 2
            @($found.evidence.ownerTag | Select-Object -Unique) |
                Should -Be @($null)
            $found[0].sourceFiles | Should -Contain 'raw/apiTags/'

            $models.apis[0].ownerTag = 'owner:team-a'
            $models.apis[1].ownerTag = 'team:platform'
            @(Get-SyntheticGovFinding -RuleId 'APIM-GOV-002' `
                    -Models $models).Count | Should -Be 0
        }

        It 'flags only a proven product governance reason (<Reason>)' -ForEach @(
            @{ Reason = 'DescriptionMissing' }
            @{ Reason = 'OwnerMissing' }
            @{ Reason = 'ExternalApprovalDisabled' }
        ) {
            $models = Get-SyntheticGovModelSet
            $description = if ($Reason -ceq 'DescriptionMissing') { '' } else { 'Synthetic description.' }
            $models.products = Get-ApimProductGovernanceModel -ProductsPayload ([pscustomobject]@{
                value = @([pscustomobject]@{ name = 'orphan-product'; properties = @{
                    description = $description; approvalRequired = $Reason -cne 'ExternalApprovalDisabled'
                } })
            }) -ProductIntent @(@{
                ProductId = 'orphan-product'; HasOwner = $Reason -cne 'OwnerMissing'; IsExternal = $true
            })
            $found = @(Get-SyntheticGovFinding -RuleId APIM-GOV-003 -Models $models)
            $found.Count | Should -Be 1
            $found[0].scope | Should -Be 'product:orphan-product'
            $found[0].findingKey | Should -Be 'APIM-GOV-003|apim-example-prod|product:orphan-product'
            $found[0].severity | Should -Be Low
            $found[0].evaluation | Should -Be Evaluated
            $found[0].evidence.reasonCodes | Should -Be @($Reason)
            $found[0].evidence.sourceScope | Should -Be Product
            $found[0].sourceFiles | Should -Contain model/products.json
        }

        It 'does not flag a governed internal product for approval disabled' {
            $models = Get-SyntheticGovModelSet
            $models.products = Get-ApimProductGovernanceModel -ProductsPayload ([pscustomobject]@{
                value = @([pscustomobject]@{ name = 'internal'; properties = @{
                    description = 'Synthetic description.'; approvalRequired = $false
                } })
            }) -ProductIntent @(@{ ProductId = 'internal'; HasOwner = $true; IsExternal = $false })
            @(Get-SyntheticGovFinding -RuleId APIM-GOV-003 -Models $models).Count | Should -Be 0
        }

        It 'emits one unknown product assessment without discarding a known positive (<Positive>)' -ForEach @(
            @{ Positive = $false }; @{ Positive = $true }
        ) {
            $models = Get-SyntheticGovModelSet
            $description = if ($Positive) { '' } else { 'Synthetic description.' }
            $models.products = Get-ApimProductGovernanceModel -ProductsPayload ([pscustomobject]@{
                value = @([pscustomobject]@{ name = 'internal'; properties = @{ description = $description } })
            }) -ProductIntent @(@{ ProductId = 'unresolved'; HasOwner = $false; IsExternal = $true })
            $found = @(Get-SyntheticGovFinding -RuleId APIM-GOV-003 -Models $models)
            $found.Count | Should -Be 1
            if ($Positive) {
                $found[0].evaluation | Should -Be Evaluated
                $found[0].evidence.reasonCodes | Should -Be @('DescriptionMissing')
                $found[0].evidence.incompleteTargets | Should -Be 2
            }
            else {
                $found[0].evaluation | Should -Be NotEvaluated
                $found[0].severity | Should -Be Info
            }
        }

        It 'evaluates effective diagnostic coverage without invented sampling (<Kind>)' -ForEach @(
            @{ Kind = 'missing'; Expected = 'DiagnosticsAbsent' }
            @{ Kind = 'logger'; Expected = 'LoggerUnresolved' }
            @{ Kind = 'lowCritical'; Expected = 'CriticalSamplingBelowFull' }
            @{ Kind = 'fullCritical'; Expected = '' }
            @{ Kind = 'lowNoncritical'; Expected = '' }
            @{ Kind = 'unknownSampling'; Expected = 'NotEvaluated' }
            @{ Kind = 'unknownIntent'; Expected = 'NotEvaluated' }
            @{ Kind = 'unknownDiagnostics'; Expected = 'NotEvaluated' }
        ) {
            $models = Get-SyntheticGovModelSet
            $diagnostic = [pscustomobject]@{ name = 'insights'; properties = @{
                loggerId = '/loggers/insights'; sampling = @{ samplingType = 'fixed'; percentage = 100 }
            } }
            $coverageArguments = @{
                ApisPayload = [pscustomobject]@{ value = @(
                    [pscustomobject]@{ name = 'orders-v1'; properties = @{ isCurrent = $true } }
                    [pscustomobject]@{ name = 'status-v1'; properties = @{ isCurrent = $true } }
                ) }
                LoggersPayload = [pscustomobject]@{ value = @([pscustomobject]@{ name = 'insights' }) }
                ServiceDiagnosticsPayload = [pscustomobject]@{ value = @($diagnostic) }
                DiagnosticsByApi = @{
                    'orders-v1' = [pscustomobject]@{ value = @() }
                    'status-v1' = [pscustomobject]@{ value = @() }
                }
                Governance = @{ CriticalApiIds = @('orders-v1') }
                ServiceResourcePath = '/synthetic'
            }
            switch ($Kind) {
                missing { $coverageArguments.ServiceDiagnosticsPayload.value = @() }
                logger { $diagnostic.properties.loggerId = '/loggers/missing' }
                lowCritical { $diagnostic.properties.sampling.percentage = 99.99 }
                lowNoncritical {
                    $diagnostic.properties.sampling.percentage = 1
                    $coverageArguments.Governance.CriticalApiIds = @()
                }
                unknownSampling { $diagnostic.properties.sampling.percentage = $null }
                unknownIntent { $coverageArguments.Governance = $null }
                unknownDiagnostics { $coverageArguments.DiagnosticsByApi = @{} }
            }
            $models.diagnosticCoverage = Get-ApimDiagnosticCoverageModel @coverageArguments
            $found = @(Get-SyntheticGovFinding -RuleId APIM-GOV-009 -Models $models)
            if ($Expected -ceq '') { $found.Count | Should -Be 0 }
            elseif ($Expected -ceq 'NotEvaluated') {
                $found.Count | Should -Be 1
                $found[0].evaluation | Should -Be NotEvaluated
                $found[0].severity | Should -Be Info
            }
            else {
                $found.Count | Should -Be $(if ($Kind -ceq 'lowCritical') { 1 } else { 2 })
                $found[0].evaluation | Should -Be Evaluated
                $found[0].severity | Should -Be Medium
                $found[0].evidence.reasonCodes | Should -Be @($Expected)
                $found[0].sourceFiles | Should -Contain model/diagnosticCoverage.json
            }
        }

        It 'retains a known diagnostic gap while another API has unavailable evidence' {
            $models = Get-SyntheticGovModelSet
            $models.diagnosticCoverage = Get-ApimDiagnosticCoverageModel `
                -ApisPayload ([pscustomobject]@{ value = @(
                    [pscustomobject]@{ name = 'orders-v1'; properties = @{ isCurrent = $true } }
                    [pscustomobject]@{ name = 'status-v1'; properties = @{ isCurrent = $true } }
                ) }) -LoggersPayload ([pscustomobject]@{ value = @() }) `
                -ServiceDiagnosticsPayload ([pscustomobject]@{ value = @() }) `
                -DiagnosticsByApi @{ 'orders-v1' = [pscustomobject]@{ value = @() } } `
                -ServiceResourcePath /synthetic
            $found = @(Get-SyntheticGovFinding -RuleId APIM-GOV-009 -Models $models)
            $found.Count | Should -Be 1
            $found[0].evaluation | Should -Be Evaluated
            $found[0].scope | Should -Be api:orders-v1
            $found[0].evidence.incompleteTargets | Should -Be 2
            $found[0].evidence.missingInputs | Should -Contain criticalIntent
        }

        It 'flags APIs with non-current online revisions' {
            $models = Get-SyntheticGovModelSet
            $found = @(Get-SyntheticGovFinding -RuleId 'APIM-GOV-005' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].scope | Should -Be 'api:status-v1'
            $found[0].evidence.nonCurrentOnlineRevisions | Should -Be 1
            $found[0].sourceFiles | Should -Contain 'raw/apiRevisions/'

            $models.apis[1].nonCurrentOnlineRevisions = 0
            @(Get-SyntheticGovFinding -RuleId 'APIM-GOV-005' `
                    -Models $models).Count | Should -Be 0
        }

        It 'flags unversioned and single-version version-set APIs' {
            $models = Get-SyntheticGovModelSet
            $found = @(Get-SyntheticGovFinding -RuleId 'APIM-GOV-006' `
                    -Models $models)
            $found.Count | Should -Be 2
            @($found.evidence.distinctVersionCount | Select-Object -Unique) |
                Should -Be @(1)

            $models.apis[1].versionSet = 'orders'
            $models.apis[1].version = 'v2'
            @(Get-SyntheticGovFinding -RuleId 'APIM-GOV-006' `
                    -Models $models).Count | Should -Be 0

            $models.apis[0].versionSet = $null
            $unversioned = @(Get-SyntheticGovFinding `
                    -RuleId 'APIM-GOV-006' -Models $models)
            $unversioned.Count | Should -Be 2
            $unversionedFinding = $unversioned |
                Where-Object scope -EQ 'api:orders-v1'
            $unversionedFinding.evidence.versionSet | Should -BeNullOrEmpty
        }

        It 'emits one service finding for inconsistent path conventions' {
            $models = Get-SyntheticGovModelSet
            @(Get-SyntheticGovFinding -RuleId 'APIM-GOV-008' `
                    -Models $models).Count | Should -Be 0

            $models.apis[1].path = 'api/v1/status'
            $found = @(Get-SyntheticGovFinding -RuleId 'APIM-GOV-008' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].scope | Should -Be 'service'
            $found[0].evidence.conventions | Should -Be @(
                'ApiVersionPrefix',
                'NoVersionSegment'
            )
            $found[0].evidence.distribution.ApiVersionPrefix |
                Should -Be 1
            $found[0].evidence.distribution.NoVersionSegment |
                Should -Be 1
        }

        It 'flags effective operation paths that omit base inheritance' {
            $models = Get-SyntheticGovModelSet
            $found = @(Get-SyntheticGovFinding -RuleId 'APIM-GOV-010' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].scope | Should -Be 'operation:orders-v1/get-orders'
            $found[0].evidence.baseMissing | Should -BeTrue
            $found[0].sourceFiles | Should -Contain 'raw/policies/'

            foreach ($operation in $models.operations) {
                $operation.baseMissing = $false
            }
            @(Get-SyntheticGovFinding -RuleId 'APIM-GOV-010' `
                    -Models $models).Count | Should -Be 0
        }

        It 'marks incomplete version or policy facts NotEvaluated' `
            -TestCases @(
                @{
                    Id = 'APIM-GOV-006'
                    Missing = 'model/apis.json#version'
                    Setup = 'Version'
                }
                @{
                    Id = 'APIM-GOV-010'
                    Missing = 'model/operations.json#baseMissing'
                    Setup = 'Policy'
                }
            ) {
            param($Id, $Missing, $Setup)

            $models = Get-SyntheticGovModelSet
            if ($Setup -eq 'Version') {
                $models.apis[1].versionSet = 'orders'
                $models.apis[1].version = $null
            }
            else {
                foreach ($operation in $models.operations) {
                    $operation.baseMissing = $false
                }
                $models.operations[0].policyEvaluationStatus = 'Partial'
            }

            $found = @(Get-SyntheticGovFinding -RuleId $Id `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].evaluation | Should -Be 'NotEvaluated'
            $found[0].severity | Should -Be 'Info'
            $found[0].evidence.missingInputs | Should -Contain $Missing
        }

        It 'marks each GOV rule NotEvaluated once when its model is missing' {
            foreach ($id in @($script:govRules.Id)) {
                $found = @(Get-SyntheticGovFinding -RuleId $id `
                        -Models ([ordered]@{}))
                $found.Count | Should -Be 1
                $found[0].evaluation | Should -Be 'NotEvaluated'
                $found[0].severity | Should -Be 'Info'
                $found[0].scope | Should -Be 'missing-input'
                $found[0].evidence.missingInputs.Count |
                    Should -Be $(if ($id -ceq 'APIM-GOV-009') { 2 } else { 1 })
            }
        }

        It 'persists deterministic schema-valid GOV findings' {
            $models = Get-SyntheticGovModelSet
            $models.apis[0].products = @()
            $models.apis[1].path = 'api/v1/status'
            $findings = @(Invoke-ApimRuleEngine -Rules $script:govRules `
                    -Models $models -Manifest $script:govRulesManifest `
                    -Config $script:govRulesConfig)
            @($findings.ruleId) | Should -Contain 'APIM-GOV-001'
            @($findings.ruleId) | Should -Contain 'APIM-GOV-008'
            @($findings.ruleId) | Should -Contain 'APIM-GOV-010'
            $first = Write-ApimFindingSet -RunPath (
                Join-Path $TestDrive 'gov-first'
            ) -Findings $findings
            $second = Write-ApimFindingSet -RunPath (
                Join-Path $TestDrive 'gov-second'
            ) -Findings $findings
            $json = Get-Content -LiteralPath $first -Raw
            $json | Should -Be (Get-Content -LiteralPath $second -Raw)
            ($json | Test-Json -SchemaFile (
                    Join-Path $script:govRulesRepoRoot 'schemas/findings.schema.json'
                )) | Should -BeTrue
        }
    }
}
