$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Private action-plan aggregation' {
    InModuleScope ApimAssessment {
        BeforeAll {
            function Get-SyntheticFinding {
                param(
                    [string] $RuleId = 'APIM-SEC-003',
                    [string] $Title = 'Synthetic caller authentication check',
                    [string] $Scope = 'api:orders-v1',
                    [string] $Resource = 'apim-example-prod',
                    [double] $PriorityScore = 4.5,
                    [string] $Recommendation = 'Use caller authentication.',
                    [ValidateSet('Evaluated', 'NotEvaluated')]
                    [string] $Evaluation = 'Evaluated'
                )

                $notEvaluated = $Evaluation -eq 'NotEvaluated'
                return [pscustomobject][ordered]@{
                    findingKey = "$RuleId|$Resource|$Scope"
                    ruleId = $RuleId
                    title = $Title
                    pillar = 'Security'
                    mcsb = 'IM-1'
                    severity = if ($notEvaluated) { 'Info' } else { 'High' }
                    scope = $Scope
                    resource = $Resource
                    exposure = if ($notEvaluated) {
                        'Unknown'
                    }
                    else {
                        'DirectPublic'
                    }
                    usage = $null
                    priorityScore = $PriorityScore
                    evidence = if ($notEvaluated) {
                        @{ missingInputs = @('model/apis.json') }
                    }
                    else {
                        @{ callerAuth = 'SubscriptionKeyOnly' }
                    }
                    evidenceText = 'Synthetic evidence'
                    recommendation = $Recommendation
                    effort = 'M'
                    sourceFiles = @('model/apis.json')
                    status = 'Open'
                    evaluation = $Evaluation
                }
            }
        }

        It 'aggregates affected counts, priority, recommendations, and top five scopes' {
            $findings = @(
                Get-SyntheticFinding -Scope 'api:zeta' -PriorityScore 3 `
                    -Recommendation 'Recommendation B.'
                Get-SyntheticFinding -Scope 'api:echo' -PriorityScore 8
                Get-SyntheticFinding -Scope 'api:delta' -PriorityScore 8
                Get-SyntheticFinding -Scope 'api:charlie' -PriorityScore 6
                Get-SyntheticFinding -Scope 'api:bravo' -PriorityScore 5
                Get-SyntheticFinding -Scope 'api:alpha' -PriorityScore 4 `
                    -Recommendation 'Recommendation A.'
            )

            $action = @(Get-ApimActionPlan -Findings $findings)[0]

            $action.ruleId | Should -Be 'APIM-SEC-003'
            $action.affectedCount | Should -Be 6
            $action.findingCount | Should -Be 6
            $action.maxPriorityScore | Should -Be 8
            @($action.topAffectedScopes) | Should -Be @(
                'api:delta',
                'api:echo',
                'api:charlie',
                'api:bravo',
                'api:alpha'
            )
            $action.recommendation | Should -Be (
                'Recommendation A. Recommendation B. ' +
                'Use caller authentication.'
            )
            $action.owner | Should -BeNullOrEmpty
            $action.status | Should -Be 'Open'
            $action.targetDate | Should -BeNullOrEmpty
            $action.notes | Should -BeNullOrEmpty
        }

        It 'keeps a NotEvaluated rule visible without counting a missing input as affected' {
            $finding = Get-SyntheticFinding -Scope 'missing-input' `
                -PriorityScore 0.5 -Evaluation NotEvaluated

            $action = @(Get-ApimActionPlan -Findings @($finding))[0]

            $action.evaluation | Should -Be 'NotEvaluated'
            $action.affectedCount | Should -Be 0
            $action.findingCount | Should -Be 1
            @($action.topAffectedScopes).Count | Should -Be 0
        }

        It 'sorts actions by descending priority then ordinal rule ID' {
            $findings = @(
                Get-SyntheticFinding -RuleId 'APIM-SEC-010' `
                    -Scope 'api:ten' -PriorityScore 5
                Get-SyntheticFinding -RuleId 'APIM-SEC-002' `
                    -Scope 'api:two' -PriorityScore 5
                Get-SyntheticFinding -RuleId 'APIM-SEC-020' `
                    -Scope 'api:twenty' -PriorityScore 8
            )

            $actions = @(Get-ApimActionPlan -Findings $findings)

            @($actions.ruleId) | Should -Be @(
                'APIM-SEC-020',
                'APIM-SEC-002',
                'APIM-SEC-010'
            )
        }

        It 'returns an empty action set for an empty finding set' {
            @(Get-ApimActionPlan -Findings @()).Count | Should -Be 0
        }

        It 'produces stable schema-valid output on repeated aggregation' {
            $findings = @(
                Get-SyntheticFinding -Scope 'api:bravo' -PriorityScore 5
                Get-SyntheticFinding -Scope 'api:alpha' -PriorityScore 7
            )

            $first = @(Get-ApimActionPlan -Findings $findings)
            $second = @(Get-ApimActionPlan -Findings @(
                    $findings[1],
                    $findings[0]
                ))
            $json = ConvertTo-Json -InputObject $first -Depth 100

            { Test-ApimActionPlanJson -Json $json } |
                Should -Not -Throw
            $json | Should -Be (
                ConvertTo-Json -InputObject $second -Depth 100
            )
        }

        It 'rejects invalid findings before aggregation' {
            $finding = Get-SyntheticFinding
            $finding.PSObject.Properties.Remove('resource')

            { Get-ApimActionPlan -Findings @($finding) } |
                Should -Throw 'Findings failed schema validation.'
        }

        It 'rejects duplicate finding keys before aggregation' {
            $finding = Get-SyntheticFinding

            { Get-ApimActionPlan -Findings @($finding, $finding) } |
                Should -Throw (
                    'Findings contain an invalid or duplicate finding key.'
                )
        }

        It 'rejects inconsistent metadata for one rule' {
            $findings = @(
                Get-SyntheticFinding -Scope 'api:first'
                Get-SyntheticFinding -Scope 'api:second' `
                    -Title 'Conflicting title'
            )

            { Get-ApimActionPlan -Findings $findings } |
                Should -Throw (
                    "Action-plan findings have inconsistent 'title' values."
                )
        }
    }
}
