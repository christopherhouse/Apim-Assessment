#Requires -Version 7.4

Set-StrictMode -Version Latest

function Read-ApimCostEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunPath
    )

    $payload = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath cost/daily.json
    $schema = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'schemas/cost-evidence.schema.json'
    if (-not (Test-Json -Json (ConvertTo-Json $payload -Depth 40 -WarningAction Stop) `
                -SchemaFile $schema -ErrorAction Stop)) {
        throw 'Saved cost evidence failed schema validation.'
    }
    return $payload
}

function Test-ApimCostSavedOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [object] $Collector
    )

    $saved = Get-ApimRunSetting -RunPath $RunPath
    if ($saved.Manifest.schemaVersion -cne '1.2' -or $Collector.name -cne 'Cost') {
        throw 'Cost evidence does not belong to a telemetry run.'
    }
    $targets = @($saved.Settings.telemetry.costScopes)
    $expectedTargets = @(if ($targets.Count) { $targets } else { 'unconfigured' })
    $coverage = @($saved.Manifest.evidenceWindows | Where-Object kind -CEQ Cost)
    if ($coverage.Count -ne $expectedTargets.Count -or
        @($coverage | Where-Object target -CNotIn $expectedTargets).Count) {
        throw 'Cost evidence windows do not match configured scopes.'
    }
    if ($saved.Settings.telemetry.skipCost -or $targets.Count -eq 0) {
        $reason = if ($saved.Settings.telemetry.skipCost) { 'OptOut' } else { 'Unconfigured' }
        if ($Collector.status -cne 'Skipped' -or $Collector.items -ne 0 -or
            $null -eq $Collector.PSObject.Properties['files'] -or $Collector.files.Count -ne 0 -or
            @($coverage | Where-Object { $_.status -cne 'Skipped' -or $_.reason -cne $reason }).Count) {
            throw 'Skipped cost evidence is inconsistent with configured exclusions.'
        }
        return 0
    }
    if ($Collector.status -cnotin @('Completed', 'Partial') -or
        $null -eq $Collector.PSObject.Properties['files'] -or
        $Collector.files.Count -ne 1 -or $Collector.files[0] -cne 'cost/daily.json') {
        throw 'Cost collector saved file inventory is invalid.'
    }
    $payload = Read-ApimCostEvidence -RunPath $RunPath
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if ($payload.scopes.Count -ne $targets.Count) { throw 'Saved cost scope inventory is incomplete.' }
    $count = 0
    $complete = $true
    foreach ($scope in $payload.scopes) {
        if ($scope.scope -cnotin $targets -or -not $seen.Add($scope.scope)) {
            throw 'Saved cost scope inventory is invalid.'
        }
        $entry = @($coverage | Where-Object target -CEQ $scope.scope)[0]
        if ($scope.status -cne $entry.status) { throw 'Cost scope status contradicts saved coverage.' }
        if ($scope.status -cne 'Completed') { $complete = $false }
        $keys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($row in $scope.rows) {
            if (-not $keys.Add((Get-ApimCostRowKey -Row $row -IncludeSubcategory))) {
                throw 'Saved cost evidence contains duplicate dimension keys.'
            }
            $day = [datetime]::ParseExact($row.day, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
            if ($day -lt ([datetimeoffset] $entry.startUtc).UtcDateTime.Date -or
                $day -ge ([datetimeoffset] $entry.endUtc).UtcDateTime -or
                ($row.resourceId -ne '' -and -not $row.resourceId.StartsWith("$($scope.scope)/",
                        [StringComparison]::OrdinalIgnoreCase))) {
                throw 'Saved cost row is outside its scope or evidence window.'
            }
        }
        $count += $scope.rows.Count
    }
    if (($Collector.status -ceq 'Completed') -ne $complete -or $Collector.items -ne $count) {
        throw 'Cost collector totals or completion status are inconsistent.'
    }
    return $count
}
