#Requires -Version 7.4

Set-StrictMode -Version Latest

$script:ApimActionsSchemaPath = Join-Path (
    Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
) 'schemas/actions.schema.json'

function Test-ApimActionPlanJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Json
    )

    if (-not (Test-Path -LiteralPath $script:ApimActionsSchemaPath `
            -PathType Leaf)) {
        throw 'Action-plan schema was unavailable.'
    }
    try {
        $valid = Test-Json -Json $Json `
            -SchemaFile $script:ApimActionsSchemaPath -ErrorAction Stop
    }
    catch {
        throw 'Action-plan items failed schema validation.'
    }
    if (-not $valid) {
        throw 'Action-plan items failed schema validation.'
    }
}

function Assert-ApimActionInvariant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Findings,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $PropertyName
    )

    if ($Findings.Count -eq 0) {
        throw 'Action-plan aggregation received an empty rule group.'
    }
    $expected = $Findings[0].$PropertyName
    if (@($Findings | Where-Object {
                $_.$PropertyName -cne $expected
            }).Count -gt 0) {
        throw "Action-plan findings have inconsistent '$PropertyName' values."
    }
    return $expected
}

function Get-ApimActionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Findings
    )

    try {
        $findingsJson = ConvertTo-Json -InputObject $Findings `
            -Depth 100 -ErrorAction Stop
    }
    catch {
        throw 'Findings could not be serialized for action-plan aggregation.'
    }
    Test-ApimFindingsJson -Json $findingsJson
    Assert-ApimFindingKey -Findings $Findings

    $groups = [System.Collections.Generic.SortedDictionary[
        string,
        System.Collections.Generic.List[object]
    ]]::new([System.StringComparer]::Ordinal)
    foreach ($finding in $Findings) {
        if (-not $groups.ContainsKey([string] $finding.ruleId)) {
            $groups.Add(
                [string] $finding.ruleId,
                [System.Collections.Generic.List[object]]::new()
            )
        }
        $groups[[string] $finding.ruleId].Add($finding)
    }

    $actions = [System.Collections.Generic.List[object]]::new()
    foreach ($ruleId in $groups.Keys) {
        [object[]] $ruleFindings = $groups[$ruleId].ToArray()
        $title = Assert-ApimActionInvariant -Findings $ruleFindings `
            -PropertyName title
        $pillar = Assert-ApimActionInvariant -Findings $ruleFindings `
            -PropertyName pillar
        $mcsb = Assert-ApimActionInvariant -Findings $ruleFindings `
            -PropertyName mcsb
        $severity = Assert-ApimActionInvariant -Findings $ruleFindings `
            -PropertyName severity
        $evaluation = Assert-ApimActionInvariant -Findings $ruleFindings `
            -PropertyName evaluation
        $effort = Assert-ApimActionInvariant -Findings $ruleFindings `
            -PropertyName effort

        [object[]] $orderedFindings = $ruleFindings.Clone()
        [System.Array]::Sort(
            $orderedFindings,
            [System.Collections.Generic.Comparer[object]]::Create(
                [System.Comparison[object]] {
                    param($left, $right)
                    $priority = $right.priorityScore.CompareTo(
                        $left.priorityScore
                    )
                    if ($priority -ne 0) {
                        return $priority
                    }
                    return [string]::CompareOrdinal(
                        $left.scope,
                        $right.scope
                    )
                }
            )
        )
        $evaluated = @($orderedFindings | Where-Object {
                $_.evaluation -eq 'Evaluated'
            })
        $recommendations = [System.Collections.Generic.SortedSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($finding in $orderedFindings) {
            $null = $recommendations.Add([string] $finding.recommendation)
        }

        $actions.Add([ordered]@{
                ruleId = $ruleId
                title = [string] $title
                pillar = [string] $pillar
                mcsb = [string] $mcsb
                severity = [string] $severity
                evaluation = [string] $evaluation
                affectedCount = $evaluated.Count
                findingCount = $orderedFindings.Count
                maxPriorityScore = [double] $orderedFindings[0].priorityScore
                topAffectedScopes = @(
                    $evaluated |
                        Select-Object -First 5 |
                        ForEach-Object { [string] $_.scope }
                )
                recommendation = @($recommendations) -join ' '
                effort = [string] $effort
                owner = $null
                status = 'Open'
                targetDate = $null
                notes = $null
            })
    }

    [object[]] $sortedActions = $actions.ToArray()
    [System.Array]::Sort(
        $sortedActions,
        [System.Collections.Generic.Comparer[object]]::Create(
            [System.Comparison[object]] {
                param($left, $right)
                $priority = $right.maxPriorityScore.CompareTo(
                    $left.maxPriorityScore
                )
                if ($priority -ne 0) {
                    return $priority
                }
                return [string]::CompareOrdinal(
                    $left.ruleId,
                    $right.ruleId
                )
            }
        )
    )
    try {
        $actionsJson = ConvertTo-Json -InputObject $sortedActions `
            -Depth 100 -ErrorAction Stop
    }
    catch {
        throw 'Action-plan items could not be serialized.'
    }
    Test-ApimActionPlanJson -Json $actionsJson
    return $sortedActions
}
