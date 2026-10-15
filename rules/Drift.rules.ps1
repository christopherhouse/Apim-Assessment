#Requires -Version 7.4

Set-StrictMode -Version Latest

foreach ($definition in @(
        @{ Id = 'APIM-GOV-007'; Category = 'Git'; Severity = 'Medium'
            Title = 'Production policies differ from source control'
            Recommendation = 'Review source and deployed policy differences through the approved deployment process; redacted hashes do not compare secret literal values.' }
        @{ Id = 'APIM-GOV-011'; Category = 'Environment'; Severity = 'Low'
            Title = 'Policies or API presence differ across environments'
            Recommendation = 'Review environment differences and document intentional deviations before aligning deployments through the approved process.' }
    )) {
    $category = $definition.Category
    @{
        Id = $definition.Id
        Title = $definition.Title
        Pillar = 'OperationalExcellence'
        Mcsb = 'n/a'
        Severity = $definition.Severity
        Scope = 'Service'
        Requires = @('model/drift.json')
        Applies = {
            param($x, $ctx)
            $null = $x
            $category -cne 'Git' -or $ctx.Manifest.environment -ieq 'Prod'
        }.GetNewClosure()
        DataGaps = {
            param($ctx)
            $rows = @($ctx.Models.drift | Where-Object category -CEQ $category)
            if (@($rows | Where-Object changeType -CNotIn @('All', 'Unknown')).Count -eq 0 -and
                ($rows.Count -eq 0 -or @($rows | Where-Object changeType -CEQ 'Unknown').Count -gt 0)) {
                if ($category -ceq 'Git') { 'model/drift.json#git' }
                else { 'model/drift.json#environments' }
            }
        }.GetNewClosure()
        Test = {
            param($x, $ctx)
            $null = $x
            @($ctx.Models.drift | Where-Object {
                    $_.category -ceq $category -and $_.changeType -cnotin @('All', 'Unknown')
                }).Count -gt 0
        }.GetNewClosure()
        Evidence = {
            param($x, $ctx)
            $null = $x
            [ordered]@{
                differences = @($ctx.Models.drift | Where-Object {
                        $_.category -ceq $category -and $_.changeType -cnotin @('All', 'Unknown')
                    })
                incompleteComparisons = @($ctx.Models.drift | Where-Object {
                        $_.category -ceq $category -and $_.changeType -ceq 'Unknown'
                    }).Count
            }
        }.GetNewClosure()
        EvidenceText = {
            param($x, $ctx)
            $null = $x
            $null = $ctx
            'Validated saved inventories contain differences; policy hashes compare protected normalized XML, not secret literals.'
        }
        Recommendation = $definition.Recommendation
        Effort = 'M'
        References = @()
        SourceFiles = @('model/drift.json')
        Enabled = $true
    }
}
