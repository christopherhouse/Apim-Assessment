$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force
AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Evidence-qualified COST rules' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:costRuleRepository = $Repository
        BeforeAll {
            . (Join-Path $script:costRuleRepository 'tests/helpers/New-SyntheticTelemetryRun.ps1')
            $inputRun = New-SyntheticTelemetryRun -RepoRoot $script:costRuleRepository `
                -OutputRoot (Join-Path $TestDrive rules)
            Mock Get-ApimSpectralTool { return $null }
            (Invoke-ApimAnalyze -RunFolder $inputRun.Run.Path).ExitCode | Should -Be 0
            $script:costRuleBaseline = Get-ApimModelSet -RunPath $inputRun.Run.Path | ConvertTo-Json -Depth 40
            $script:costRuleManifest = Get-RunManifest -RunPath $inputRun.Run.Path
            $script:costRuleConfig = $inputRun.Config
            $script:costRules = @(Get-ApimRuleCatalog -CatalogPath (Join-Path $script:costRuleRepository rules) |
                    Where-Object Id -Like 'APIM-COST-*')
            function Get-SyntheticCostFinding {
                param([string] $Id)
                @(Invoke-ApimRuleEngine -Rules @($script:costRules | Where-Object Id -CEQ $Id) `
                    -Models $script:costRuleModels -Manifest $script:costRuleManifest -Config $script:costRuleConfig)
            }
        }
        BeforeEach {
            $script:costRuleModels = ConvertFrom-Json $script:costRuleBaseline -AsHashtable -Depth 40
            $script:costRuleManifest.environment = 'Prod'
        }

        It 'emits traceable deterministic findings for all five conditions and preserves HA qualifications' {
            $script:costRuleManifest.environment = 'Test'
            $found = @(Invoke-ApimRuleEngine -Rules $script:costRules -Models $script:costRuleModels `
                    -Manifest $script:costRuleManifest -Config $script:costRuleConfig)
            $found.Count | Should -Be 5
            @($found | Where-Object evaluation -CNE Evaluated).Count | Should -Be 0
            foreach ($row in $found) {
                $row.sourceFiles.Count | Should -BeGreaterThan 0
                $row.findingKey | Should -Match ('^' + [regex]::Escape($row.ruleId) + '\|')
            }
            ($found | Where-Object ruleId -CEQ APIM-COST-001).recommendation | Should -Match 'zone|HA'
            ($found | Where-Object ruleId -CEQ APIM-COST-004).evidence.signals[0].historicalPlanChanges |
                Should -BeNullOrEmpty
            $again = @(Invoke-ApimRuleEngine -Rules $script:costRules -Models $script:costRuleModels `
                    -Manifest $script:costRuleManifest -Config $script:costRuleConfig)
            (ConvertTo-Json $again -Depth 30) | Should -BeExactly (ConvertTo-Json $found -Depth 30)
        }

        It 'does not flag a non-Premium service, production environment, stable normalization or sub-threshold growth' {
            $script:costRuleModels.service.skuName = 'Standard'
            @(Get-SyntheticCostFinding APIM-COST-001).Count | Should -Be 0
            @(Get-SyntheticCostFinding APIM-COST-005).Count | Should -Be 0
            $script:costRuleModels.service.skuName = 'Premium'
            @(Get-SyntheticCostFinding APIM-COST-005).Count | Should -Be 0
            $script:costRuleModels.cost.normalized[1].changePercent = 0
            @(Get-SyntheticCostFinding APIM-COST-002).Count | Should -Be 0
            $script:costRuleModels.apis | ForEach-Object { $_.bodyLogging = $false }
            $script:costRuleModels.cost.ingestion[1].gb = 19.99
            @(Get-SyntheticCostFinding APIM-COST-003).Count | Should -Be 0
            $logicId = $script:costRuleModels.cost.logicApps[0].resourceId
            @($script:costRuleModels.cost.monthly | Where-Object {
                    $_.resourceId -ceq $logicId -and $_.month -ceq '2026-09-01'
                })[0].cost = 15
            @(Get-SyntheticCostFinding APIM-COST-004).Count | Should -Be 0
        }

        It 'keeps missing, cross-currency and incomplete evidence NotEvaluated rather than passing' {
            $script:costRuleModels.capacity.modelStatus = 'Partial'
            @(Get-SyntheticCostFinding APIM-COST-001)[0].evaluation | Should -Be NotEvaluated
            $script:costRuleModels.cost.normalized | ForEach-Object { $_.changePercent = $null }
            @(Get-SyntheticCostFinding APIM-COST-002)[0].evaluation | Should -Be NotEvaluated
            $script:costRuleModels.cost.ingestion = @()
            $script:costRuleModels.cost.missingInputs = @('ingestion')
            @(Get-SyntheticCostFinding APIM-COST-003)[0].evaluation | Should -Be NotEvaluated
            $logicId = $script:costRuleModels.cost.logicApps[0].resourceId
            @($script:costRuleModels.cost.monthly | Where-Object {
                    $_.resourceId -ceq $logicId -and $_.month -ceq '2026-09-01'
                })[0].currency = 'EUR'
            @(Get-SyntheticCostFinding APIM-COST-004)[0].evaluation | Should -Be NotEvaluated
            $script:costRuleModels.service.skuName = $null
            @(Get-SyntheticCostFinding APIM-COST-005)[0].evaluation | Should -Be NotEvaluated
            $script:costRuleModels.Remove('cost')
            @(Get-SyntheticCostFinding APIM-COST-004).Count | Should -Be 1
        }

        It 'does not attribute stable App Gateway ingestion to APIM body logging' {
            $script:costRuleModels.apis | ForEach-Object { $_.bodyLogging = $true }
            $script:costRuleModels.cost.ingestion | ForEach-Object {
                $_.dataType = 'AGWAccessLogs'
                $_.gb = 10.0
            }
            @(Get-SyntheticCostFinding APIM-COST-003).Count | Should -Be 0
            $script:costRuleModels.cost.ingestion | ForEach-Object {
                $_.dataType = 'ApiManagementGatewayLogs'
            }
            $finding = @(Get-SyntheticCostFinding APIM-COST-003)
            $finding.Count | Should -Be 1
            $finding[0].evidence.signals[0].bodyLogging | Should -BeTrue
            $finding[0].sourceFiles | Should -Contain 'model/cost.json'
        }
    }
}
