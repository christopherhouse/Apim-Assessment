$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force
AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Evidence-compatible specialist and executive proposals' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:claimRepository = $Repository
        BeforeAll {
            function ConvertTo-ClaimJson {
                param([object] $Value)
                ConvertTo-Json -InputObject $Value -Depth 32 -Compress
            }
        }
        BeforeEach {
            $script:claimPackage = Get-Content -Raw -LiteralPath (
                Join-Path $script:claimRepository 'tests/fixtures/synthetic-reference/analysis-contracts/analysis-package.json'
            ) | ConvertFrom-Json -AsHashtable
            $script:claimExpert = @{
                schemaVersion = '1.0'; analyst = 'ArchitectureExposure'
                observations = @(@{ observationId = 'observation-architecture-001'; category = 'Exposure'
                        confidence = 'High'; findingRefs = @('finding-000001'); factRefs = @('fact-000002')
                        rationaleCode = 'HostWidePublication'; recommendationCode = 'ConfirmExposure' })
            }
            $script:claimSummary = @{
                schemaVersion = '1.0'; posture = 'ActionRequired'; confidence = 'Medium'
                priorities = @(@{ itemId = 'priority-001'; code = 'ReduceExposure'; confidence = 'High'
                        findingRefs = @('finding-000001'); factRefs = @(); observationRefs = @('observation-architecture-001') })
                themes = @(); decisions = @(); roadmap = @()
                assumptions = $script:claimPackage.assumptions; dataGaps = $script:claimPackage.dataGaps
            }
        }

        It 'accepts entailed claims and reconciles a confidence-qualified summary' {
            $package = ConvertTo-ClaimJson $script:claimPackage
            $expert = ConvertTo-ClaimJson $script:claimExpert
            Test-ApimAgentClaim -Kind ExpertObservations -Json $expert -PackageJson $package | Should -BeTrue
            Test-ApimAgentClaim -Kind ExecutiveSummary -Json (ConvertTo-ClaimJson $script:claimSummary) `
                -PackageJson $package -ObservationJson @($expert) | Should -BeTrue
        }

        It 'rejects cited but unsupported, contradictory, or overconfident specialist evidence: <Case>' -ForEach @(
            @{ Case = 'unrelated fact'; Change = { $script:claimExpert.observations[0].factRefs = @('fact-000001') } }
            @{ Case = 'contradictory route'; Change = { $script:claimPackage.facts[1].value = 'PathBased' } }
            @{ Case = 'different finding'; Change = { $script:claimExpert.observations[0].findingRefs = @('finding-000002') } }
            @{ Case = 'weak evidence'; Change = { $script:claimPackage.facts[1].confidence = 'Low' } }
            @{ Case = 'unsupported recommendation'; Change = { $script:claimExpert.observations[0].recommendationCode = 'RemoveHardcodedSecrets' } }
            @{ Case = 'incorrect category'; Change = { $script:claimExpert.observations[0].category = 'Governance' } }
        ) {
            & $Change
            { Test-ApimAgentClaim -Kind ExpertObservations -Json (ConvertTo-ClaimJson $script:claimExpert) `
                    -PackageJson (ConvertTo-ClaimJson $script:claimPackage) } | Should -Throw 'AGENT_*_REJECTED'
        }

        It 'retains NotEvaluated as low-confidence missing evidence, never a risk assertion' {
            $item = $script:claimExpert.observations[0]
            $item.factRefs = @(); $item.findingRefs = @('finding-000003')
            $item.rationaleCode = 'MissingEvidence'; $item.recommendationCode = 'ResolveDataGaps'
            $item.confidence = 'Low'
            Test-ApimAgentClaim -Kind ExpertObservations -Json (ConvertTo-ClaimJson $script:claimExpert) `
                -PackageJson (ConvertTo-ClaimJson $script:claimPackage) | Should -BeTrue
            $item.confidence = 'High'
            { Test-ApimAgentClaim -Kind ExpertObservations -Json (ConvertTo-ClaimJson $script:claimExpert) `
                    -PackageJson (ConvertTo-ClaimJson $script:claimPackage) } | Should -Throw 'AGENT_*_REJECTED'
        }

        It 'does not misrepresent unsafe diagnostic capture as insufficient diagnostics' {
            $script:claimPackage.schemaVersion = '1.1'
            $script:claimPackage.facts[1].code = 'AssessmentCondition'
            $script:claimPackage.facts[1].value = 'SensitiveDiagnosticCapture'
            $script:claimExpert.observations[0].rationaleCode = 'InsufficientDiagnostics'
            $script:claimExpert.observations[0].recommendationCode = 'EnableDiagnostics'
            $script:claimExpert.observations[0].category = 'Security'
            $script:claimExpert.analyst = 'Security'
            $script:claimExpert.observations[0].observationId = 'observation-security-001'
            { Test-ApimAgentClaim -Kind ExpertObservations -Json (ConvertTo-ClaimJson $script:claimExpert) `
                    -PackageJson (ConvertTo-ClaimJson $script:claimPackage) } | Should -Throw 'AGENT_EVIDENCE_REJECTED'
        }

        It 'admits versioned cost-review claims without enabling unrelated executive claims: <Condition>' -ForEach @(
            @{ Condition = 'PremiumCapacityReview'; Rule = 'APIM-COST-001' }
            @{ Condition = 'NormalizedCostIncreasing'; Rule = 'APIM-COST-002' }
            @{ Condition = 'DiagnosticIngestionGrowth'; Rule = 'APIM-COST-003' }
            @{ Condition = 'LogicAppCostIncreasing'; Rule = 'APIM-COST-004' }
            @{ Condition = 'NonProductionPremium'; Rule = 'APIM-COST-005' }
        ) {
            $script:claimPackage.schemaVersion = '1.5'
            $script:claimPackage.facts = @(@{
                    factId = 'fact-000001'; subjectAlias = 'service-001'
                    code = 'AssessmentCondition'; value = $Condition; confidence = 'Medium'
                })
            $script:claimPackage.findings = @(@{
                    findingId = 'finding-000001'; ruleId = $Rule; subjectAlias = 'service-001'
                    severity = 'Info'; evaluation = 'Evaluated'; priorityBucket = 'Low'
                    factRefs = @('fact-000001'); dataGaps = @()
                })
            $script:claimSummary.posture = 'ImprovementRecommended'
            $item = $script:claimSummary.priorities[0]
            $item.code = 'ReviewCost'; $item.confidence = 'Medium'; $item.observationRefs = @()
            Test-ApimAgentClaim -Kind ExecutiveSummary -Json (ConvertTo-ClaimJson $script:claimSummary) `
                -PackageJson (ConvertTo-ClaimJson $script:claimPackage) | Should -BeTrue
            $item.code = 'ReduceExposure'
            { Test-ApimAgentClaim -Kind ExecutiveSummary -Json (ConvertTo-ClaimJson $script:claimSummary) `
                    -PackageJson (ConvertTo-ClaimJson $script:claimPackage) } | Should -Throw 'AGENT_EVIDENCE_REJECTED'
            $script:claimPackage.schemaVersion = '1.4'
            { Test-ApimAnalysisContract -Kind AnalysisPackage -Json (ConvertTo-ClaimJson $script:claimPackage) } |
                Should -Throw
        }

        It 'rejects executive distortion: <Case>' -ForEach @(
            @{ Case = 'downgraded posture'; Change = { $script:claimSummary.posture = 'ImprovementRecommended' } }
            @{ Case = 'confidence escalation'; Change = { $script:claimSummary.confidence = 'High' } }
            @{ Case = 'unrelated executive code'; Change = { $script:claimSummary.priorities[0].code = 'ProtectSecrets' } }
            @{ Case = 'omitted high priority'; Change = { $script:claimSummary.priorities = @() } }
            @{ Case = 'lost assumption'; Change = { $script:claimSummary.assumptions = @() } }
            @{ Case = 'invented gap'; Change = { $script:claimSummary.dataGaps += 'NetworkIncomplete' } }
        ) {
            & $Change
            { Test-ApimAgentClaim -Kind ExecutiveSummary -Json (ConvertTo-ClaimJson $script:claimSummary) `
                    -PackageJson (ConvertTo-ClaimJson $script:claimPackage) `
                    -ObservationJson @((ConvertTo-ClaimJson $script:claimExpert)) } | Should -Throw
        }
    }
}
