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

        It 'loads the eight currently model-backed GOV rules with empty references' {
            @($script:govRules.Id | Sort-Object) | Should -Be @(
                'APIM-GOV-001',
                'APIM-GOV-002',
                'APIM-GOV-005',
                'APIM-GOV-006',
                'APIM-GOV-007',
                'APIM-GOV-008',
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
                $found[0].evidence.missingInputs.Count | Should -Be 1
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
