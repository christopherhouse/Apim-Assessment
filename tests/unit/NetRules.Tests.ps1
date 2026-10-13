$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Evidence-backed NET catalog' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)
        $script:netRulesRepoRoot = $RepoRoot

        BeforeAll {
            $script:netRulesConfig = Import-PowerShellDataFile (
                Join-Path $script:netRulesRepoRoot 'config/sample.psd1'
            )
            $script:netRulesConfig.Output.Root = Join-Path $TestDrive 'restricted'
            $run = New-ApimRun -Config $script:netRulesConfig `
                -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000002' `
                -Operator Synthetic -RunId 'synthetic-net-rules'
            $script:netRulesManifest = Get-RunManifest -RunPath $run.Path
            $script:netRules = @(
                Get-ApimRuleCatalog -CatalogPath (
                    Join-Path $script:netRulesRepoRoot 'rules'
                ) | Where-Object Id -Like 'APIM-NET-*'
            )
            $script:netFixtureRoot = Join-Path $script:netRulesRepoRoot (
                'tests/fixtures/synthetic-reference/model'
            )

            function Get-SyntheticNetModelSet {
                return [ordered]@{
                    network = Get-Content -LiteralPath (
                        Join-Path $script:netFixtureRoot 'network.json'
                    ) -Raw | ConvertFrom-Json -Depth 100
                    exposure = Get-Content -LiteralPath (
                        Join-Path $script:netFixtureRoot 'exposure.json'
                    ) -Raw | ConvertFrom-Json -Depth 100 -NoEnumerate
                }
            }

            function Get-SyntheticNetFinding {
                param(
                    [Parameter(Mandatory)]
                    [string] $RuleId,

                    [Parameter(Mandatory)]
                    [System.Collections.IDictionary] $Models
                )

                $rule = @($script:netRules | Where-Object Id -EQ $RuleId)
                return @(Invoke-ApimRuleEngine -Rules $rule -Models $Models `
                        -Manifest $script:netRulesManifest `
                        -Config $script:netRulesConfig)
            }
        }

        It 'loads exactly the seven evidence-backed rules with empty references' {
            @($script:netRules.Id) | Should -Be @(
                'APIM-NET-001', 'APIM-NET-002', 'APIM-NET-004',
                'APIM-NET-006', 'APIM-NET-007', 'APIM-NET-008',
                'APIM-NET-009'
            )
            foreach ($rule in $script:netRules) {
                $rule.References.Count | Should -Be 0
                $rule.Enabled | Should -BeTrue
            }
        }

        It 'flags attested edge-only ingress without origin authentication' {
            $models = Get-SyntheticNetModelSet
            $models.network.edgeOriginAssessment = [pscustomobject]@{
                edgeRangesOnly = $true
                originAuthentication = 'Absent'
                source = 'OperatorAttestation'
            }
            $found = @(Get-SyntheticNetFinding -RuleId 'APIM-NET-001' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].evaluation | Should -Be 'Evaluated'
            $found[0].evidence.originAuthentication | Should -Be 'Absent'
            $found[0].evidence.source | Should -Be 'OperatorAttestation'
            $found[0].sourceFiles | Should -Contain 'model/network.json'

            $models.network.edgeOriginAssessment.originAuthentication = 'Present'
            @(Get-SyntheticNetFinding -RuleId 'APIM-NET-001' `
                    -Models $models).Count | Should -Be 0
            $models.network.edgeOriginAssessment.edgeRangesOnly = $false
            $models.network.edgeOriginAssessment.originAuthentication = 'Absent'
            @(Get-SyntheticNetFinding -RuleId 'APIM-NET-001' `
                    -Models $models).Count | Should -Be 0
        }

        It 'does not infer absent origin authentication from missing evidence' {
            $models = Get-SyntheticNetModelSet
            $found = @(Get-SyntheticNetFinding -RuleId 'APIM-NET-001' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].evaluation | Should -Be 'NotEvaluated'
            $found[0].evidence.missingInputs |
                Should -Contain 'model/network.json#edgeOriginAssessment'

            $models.network.edgeOriginAssessment = [pscustomobject]@{
                edgeRangesOnly = $true
                originAuthentication = 'Unknown'
                source = 'OperatorAttestation'
            }
            @(Get-SyntheticNetFinding -RuleId 'APIM-NET-001' `
                    -Models $models)[0].evaluation | Should -Be 'NotEvaluated'
        }

        It 'flags only owner-attested unnecessary public auxiliary routes' {
            $models = Get-SyntheticNetModelSet
            $models.network.auxiliaryRoutes = @(
                [pscustomobject]@{
                    routeKey = 'aux-portal'
                    endpointType = 'Portal'
                    publicListener = $true
                    ownerNeed = 'NotNeeded'
                    source = 'OperatorAttestation'
                }
                [pscustomobject]@{
                    routeKey = 'aux-management'
                    endpointType = 'Management'
                    publicListener = $false
                    ownerNeed = 'NotNeeded'
                    source = 'OperatorAttestation'
                }
            )
            $found = @(Get-SyntheticNetFinding -RuleId 'APIM-NET-009' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].scope | Should -Be 'route:aux-portal'
            $found[0].evidence.endpointType | Should -Be 'Portal'
            $found[0].evidence.source | Should -Be 'OperatorAttestation'
            $found[0].sourceFiles | Should -Contain 'model/network.json'
            $again = @(Get-SyntheticNetFinding -RuleId 'APIM-NET-009' `
                    -Models (Get-SyntheticNetModelSet))
            $again[0].evaluation | Should -Be 'NotEvaluated'

            $models.network.auxiliaryRoutes[0].ownerNeed = 'Needed'
            @(Get-SyntheticNetFinding -RuleId 'APIM-NET-009' `
                    -Models $models).Count | Should -Be 0
        }

        It 'retains a known unnecessary route when another need is unknown' {
            $models = Get-SyntheticNetModelSet
            $models.network.auxiliaryRoutes = @(
                [pscustomobject]@{
                    routeKey = 'aux-portal'
                    endpointType = 'Portal'
                    publicListener = $true
                    ownerNeed = 'NotNeeded'
                    source = 'OperatorAttestation'
                }
                [pscustomobject]@{
                    routeKey = 'aux-management'
                    endpointType = 'Management'
                    publicListener = $true
                    ownerNeed = 'Unknown'
                    source = 'OperatorAttestation'
                }
            )
            $found = @(Get-SyntheticNetFinding -RuleId 'APIM-NET-009' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].scope | Should -Be 'route:aux-portal'
            $found[0].evidence.otherPublicRoutesWithUnknownNeed |
                Should -Be 1
        }

        It 'holds NET-009 when publication or owner need remains unknown' {
            $models = Get-SyntheticNetModelSet
            $found = @(Get-SyntheticNetFinding -RuleId 'APIM-NET-009' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].evaluation | Should -Be 'NotEvaluated'
            $found[0].evidence.missingInputs |
                Should -Contain 'model/network.json#auxiliaryRoutes'

            $models.network.auxiliaryRoutes = @(
                [pscustomobject]@{
                    routeKey = 'aux-portal'
                    endpointType = 'Portal'
                    publicListener = $true
                    ownerNeed = 'Unknown'
                    source = 'OperatorAttestation'
                }
            )
            @(Get-SyntheticNetFinding -RuleId 'APIM-NET-009' `
                    -Models $models)[0].evaluation | Should -Be 'NotEvaluated'
            $models.network.auxiliaryRoutes = @()
            @(Get-SyntheticNetFinding -RuleId 'APIM-NET-009' `
                    -Models $models).Count | Should -Be 0
        }

        It 'rejects a route rule targeting an undeclared model field' {
            $invalid = @($script:netRules |
                Where-Object Id -EQ 'APIM-NET-009')[0].Clone()
            $invalid.TargetField = 'secret'
            { Assert-ApimRule -Rule $invalid } | Should -Throw
        }

        It 'flags the synthetic host-wide public Basic route even before telemetry exists' {
            $models = Get-SyntheticNetModelSet
            $findings = @(Get-SyntheticNetFinding `
                    -RuleId 'APIM-NET-004' -Models $models)
            $findings.Count | Should -Be 2
            $findings[0].scope | Should -Match '^route:'
            $findings[0].evidence.pattern | Should -Be '/*'
            $findings[0].evidence.configuredApiCount | Should -Be 2
            $findings[0].evidence.reachableApiCount | Should -Be 2
            $findings[0].evidence.externalUnintendedApiCount |
                Should -BeNullOrEmpty
            $findings[0].usage | Should -BeNullOrEmpty
            $findings[0].sourceFiles | Should -Contain 'model/exposure.json'

            $again = @(Get-SyntheticNetFinding -RuleId 'APIM-NET-004' `
                    -Models (Get-SyntheticNetModelSet))
            (ConvertTo-Json -InputObject $findings -Depth 100) |
                Should -Be (ConvertTo-Json -InputObject $again -Depth 100)
        }

        It 'does not flag a path-based, private, or non-host-wide route' {
            $models = Get-SyntheticNetModelSet
            $models.exposure[0].pattern = '/orders/*'
            $models.exposure[1].frontendType = 'Private'
            @(Get-SyntheticNetFinding -RuleId 'APIM-NET-004' `
                    -Models $models).Count | Should -Be 0
        }

        It 'counts a policy-blocked route as configured but not reachable' {
            $models = Get-SyntheticNetModelSet
            $models.exposure[1].reachability = 'NotRoutable'
            $models.exposure[1].exposure = 'Internal'
            $findings = @(Get-SyntheticNetFinding -RuleId 'APIM-NET-004' `
                    -Models $models)
            $findings.Count | Should -Be 1
            $findings[0].evidence.configuredApiCount | Should -Be 2
            $findings[0].evidence.reachableApiCount | Should -Be 1
        }

        It 'counts ExternalUnintended only when all matching route classifications are known' {
            $models = Get-SyntheticNetModelSet
            foreach ($route in $models.exposure) {
                $route.exposure = 'ExternalUnintended'
                $route.missingInputs = @()
                $route.modelStatus = 'Complete'
            }
            $findings = @(Get-SyntheticNetFinding -RuleId 'APIM-NET-004' `
                    -Models $models)
            $findings[0].evidence.externalUnintendedApiCount | Should -Be 2
        }

        It 'flags <Id> with positive evidence and does not flag the known safe case' `
            -TestCases @(
                @{ Id = 'APIM-NET-002'; Field = 'wafState'; Value = 'Disabled'; Safe = 'Enabled' }
                @{ Id = 'APIM-NET-006'; Field = 'directPublic'; Value = $true; Safe = $false }
                @{ Id = 'APIM-NET-007'; Field = 'nsgEvaluation'; Value = 'Broad'; Safe = 'Restricted' }
                @{ Id = 'APIM-NET-008'; Field = 'appGatewayTlsPolicy'; Value = 'Weak'; Safe = 'Strong' }
            ) {
            param($Id, $Field, $Value, $Safe)

            $models = Get-SyntheticNetModelSet
            $models.network.$Field = $Value
            if ($Id -eq 'APIM-NET-002') {
                $models.network.wafMode = 'Detection'
            }
            if ($Id -eq 'APIM-NET-006') {
                $models.network.directPublicReasons = @('PublicNetworkAccess')
            }
            $found = @(Get-SyntheticNetFinding -RuleId $Id -Models $models)
            $found.Count | Should -Be 1
            $found[0].evaluation | Should -Be 'Evaluated'
            $found[0].evidence.Count | Should -BeGreaterThan 0
            $found[0].sourceFiles.Count | Should -BeGreaterThan 0

            $models.network.$Field = $Safe
            if ($Id -eq 'APIM-NET-002') {
                $models.network.wafMode = 'Prevention'
            }
            if ($Id -eq 'APIM-NET-006') {
                $models.network.directPublicReasons = @()
            }
            @(Get-SyntheticNetFinding -RuleId $Id -Models $models).Count |
                Should -Be 0
        }

        It 'marks each rule NotEvaluated once if its required model is unavailable' `
            -TestCases @(
                @{ Id = 'APIM-NET-001' }
                @{ Id = 'APIM-NET-002' }
                @{ Id = 'APIM-NET-004' }
                @{ Id = 'APIM-NET-006' }
                @{ Id = 'APIM-NET-007' }
                @{ Id = 'APIM-NET-008' }
                @{ Id = 'APIM-NET-009' }
            ) {
            param($Id)

            $finding = @(Get-SyntheticNetFinding `
                    -RuleId $Id -Models ([ordered]@{}))
            $finding.Count | Should -Be 1
            $finding[0].evaluation | Should -Be 'NotEvaluated'
            $finding[0].severity | Should -Be 'Info'
            $finding[0].evidence.missingInputs.Count | Should -Be 1
        }

        It 'returns no gateway-only findings when the gateway inventory is empty' {
            $models = Get-SyntheticNetModelSet
            $models.network.appGateways = @()
            $models.network.wafState = 'Unknown'
            $models.network.wafMode = 'Unknown'
            $models.network.appGatewayTlsPolicy = 'Unknown'
            foreach ($id in @('APIM-NET-002', 'APIM-NET-008')) {
                @(Get-SyntheticNetFinding -RuleId $id -Models $models).Count |
                    Should -Be 0
            }
        }

        It 'distinguishes a missing gateway inventory from a known empty one' {
            $models = Get-SyntheticNetModelSet
            $models.network.appGateways = $null
            foreach ($id in @('APIM-NET-002', 'APIM-NET-008')) {
                $finding = @(Get-SyntheticNetFinding -RuleId $id `
                        -Models $models)
                $finding.Count | Should -Be 1
                $finding[0].evaluation | Should -Be 'NotEvaluated'
                $finding[0].evidence.missingInputs |
                    Should -Contain 'model/network.json#appGateways'
            }
        }

        It 'reports unknown facts as one NotEvaluated finding instead of a pass' `
            -TestCases @(
                @{ Id = 'APIM-NET-002'; Field = 'wafState'; Value = 'Unknown'; Missing = 'wafState' }
                @{ Id = 'APIM-NET-006'; Field = 'directPublic'; Value = $null; Missing = 'directPublic' }
                @{ Id = 'APIM-NET-007'; Field = 'nsgEvaluation'; Value = 'Unknown'; Missing = 'nsgEvaluation' }
                @{ Id = 'APIM-NET-008'; Field = 'appGatewayTlsPolicy'; Value = 'Unknown'; Missing = 'appGatewayTlsPolicy' }
            ) {
            param($Id, $Field, $Value, $Missing)

            $models = Get-SyntheticNetModelSet
            $models.network.$Field = $Value
            if ($Id -eq 'APIM-NET-002') {
                $models.network.wafMode = 'Prevention'
            }
            $finding = @(Get-SyntheticNetFinding -RuleId $Id `
                    -Models $models)
            $finding.Count | Should -Be 1
            $finding[0].evaluation | Should -Be 'NotEvaluated'
            $finding[0].evidence.missingInputs |
                Should -Contain "model/network.json#$Missing"
        }

        It 'does not turn a positive WAF state into an unknown when mode is unavailable' {
            $models = Get-SyntheticNetModelSet
            $models.network.wafMode = 'Unknown'
            $found = @(Get-SyntheticNetFinding -RuleId 'APIM-NET-002' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].evaluation | Should -Be 'Evaluated'
            $found[0].evidence.wafState | Should -Be 'Disabled'
        }

        It 'flags WAF Detection mode even when the policy is enabled' {
            $models = Get-SyntheticNetModelSet
            $models.network.wafState = 'Enabled'
            $models.network.wafMode = 'Detection'
            $finding = @(Get-SyntheticNetFinding -RuleId 'APIM-NET-002' `
                    -Models $models)
            $finding.Count | Should -Be 1
            $finding[0].evaluation | Should -Be 'Evaluated'
            $finding[0].evidence.wafMode | Should -Be 'Detection'
        }

        It 'does not treat an absent NSG evaluation as a narrow allow' {
            $models = Get-SyntheticNetModelSet
            $models.network.nsgEvaluation = 'Missing'
            $models.network.nsgName = $null
            $finding = @(Get-SyntheticNetFinding -RuleId 'APIM-NET-007' `
                    -Models $models)
            $finding.Count | Should -Be 1
            $finding[0].evaluation | Should -Be 'NotEvaluated'
            $finding[0].evidence.missingInputs |
                Should -Contain 'model/network.json#nsgEvaluation'
        }

        It 'does not evaluate NET-004 when all potential host-wide routes are uncertain' {
            $models = Get-SyntheticNetModelSet
            foreach ($route in $models.exposure) {
                $route.reachability = 'Unknown'
            }
            $finding = @(Get-SyntheticNetFinding -RuleId 'APIM-NET-004' `
                    -Models $models)
            $finding.Count | Should -Be 1
            $finding[0].evaluation | Should -Be 'NotEvaluated'
            $finding[0].evidence.missingInputs |
                Should -Be @('model/exposure.json#reachability')
        }

        It 'evaluates the complete catalog without persisting or promoting models' {
            $models = Get-SyntheticNetModelSet
            $findings = @(Invoke-ApimRuleEngine -Rules $script:netRules `
                    -Models $models -Manifest $script:netRulesManifest `
                    -Config $script:netRulesConfig)
            @($findings.ruleId) | Should -Contain 'APIM-NET-002'
            @($findings.ruleId) | Should -Contain 'APIM-NET-004'
            $path = Write-ApimFindingSet -RunPath (
                Join-Path $TestDrive 'net-findings'
            ) -Findings $findings
            (Get-Content -LiteralPath $path -Raw | Test-Json -SchemaFile (
                    Join-Path $script:netRulesRepoRoot 'schemas/findings.schema.json'
                )) | Should -BeTrue
        }

        It 'persists deterministic schema-valid findings for both attested checks' {
            $models = Get-SyntheticNetModelSet
            $models.network.edgeOriginAssessment = [pscustomobject]@{
                edgeRangesOnly = $true
                originAuthentication = 'Absent'
                source = 'OperatorAttestation'
            }
            $models.network.auxiliaryRoutes = @(
                [pscustomobject]@{
                    routeKey = 'aux-portal'
                    endpointType = 'Portal'
                    publicListener = $true
                    ownerNeed = 'NotNeeded'
                    source = 'OperatorAttestation'
                }
            )
            $findings = @(Invoke-ApimRuleEngine -Rules $script:netRules `
                    -Models $models -Manifest $script:netRulesManifest `
                    -Config $script:netRulesConfig)
            @($findings.ruleId) | Should -Contain 'APIM-NET-001'
            @($findings.ruleId) | Should -Contain 'APIM-NET-009'
            $first = Write-ApimFindingSet -RunPath (
                Join-Path $TestDrive 'attested-first'
            ) -Findings $findings
            $second = Write-ApimFindingSet -RunPath (
                Join-Path $TestDrive 'attested-second'
            ) -Findings $findings
            $json = Get-Content -LiteralPath $first -Raw
            $json | Should -Be (Get-Content -LiteralPath $second -Raw)
            ($json | Test-Json -SchemaFile (
                    Join-Path $script:netRulesRepoRoot 'schemas/findings.schema.json'
                )) | Should -BeTrue
        }
    }
}
