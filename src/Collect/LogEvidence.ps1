#Requires -Version 7.4

Set-StrictMode -Version Latest

function Read-ApimLogEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [ValidateSet('workspaces', 'usageByApi', 'usageByRoute', 'usageMonthly',
            'tls', 'noSubscriptionCalls', 'laIngestion')]
        [string] $Kind
    )

    $relative = if ($Kind -ceq 'laIngestion') { 'cost/laIngestion.json' } else { "logs/$Kind.json" }
    $payload = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath $relative
    $schemaName = if ($Kind -ceq 'workspaces') { 'log-workspaces' } else { 'log-aggregate' }
    $schema = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) (
        "schemas/$schemaName.schema.json"
    )
    $json = ConvertTo-Json -InputObject $payload -Depth 40 -WarningAction Stop
    if (-not (Test-Json -Json $json -SchemaFile $schema -ErrorAction Stop)) {
        throw 'Saved log evidence failed schema validation.'
    }
    if ($Kind -cne 'workspaces' -and $payload.kind -cne $Kind) {
        throw 'Saved log evidence has the wrong query kind.'
    }
    return $payload
}

function Test-ApimLogSavedOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [object] $Collector
    )

    $saved = Get-ApimRunSetting -RunPath $RunPath
    if ($saved.Manifest.schemaVersion -cne '1.2' -or $Collector.name -cne 'LogAnalytics') {
        throw 'Log evidence does not belong to a telemetry run.'
    }
    $targets = @($saved.Settings.telemetry.workspaceIds)
    $families = @('Usage', 'Security', 'Ingestion')
    $coverage = @($saved.Manifest.evidenceWindows | Where-Object kind -CIn $families)
    $expectedTargets = @(if ($targets.Count) { $targets } else { 'unconfigured' })
    if ($coverage.Count -ne 3 * $expectedTargets.Count -or
        @($coverage | Where-Object target -CNotIn $expectedTargets).Count) {
        throw 'Saved log coverage does not match configured targets.'
    }
    if ($saved.Settings.telemetry.skipLogs -or $targets.Count -eq 0) {
        $reason = if ($saved.Settings.telemetry.skipLogs) { 'OptOut' } else { 'Unconfigured' }
        if ($Collector.status -cne 'Skipped' -or $Collector.items -ne 0 -or
            $null -eq $Collector.PSObject.Properties['files'] -or $Collector.files.Count -ne 0 -or
            @($coverage | Where-Object { $_.status -cne 'Skipped' -or $_.reason -cne $reason }).Count) {
            throw 'Skipped log evidence is inconsistent with the configured opt-out.'
        }
        return 0
    }
    $kinds = @('usageByApi', 'usageByRoute', 'usageMonthly', 'tls', 'noSubscriptionCalls')
    if ($saved.Settings.telemetry.skipCost) {
        if (@($coverage | Where-Object {
                    $_.kind -ceq 'Ingestion' -and
                    ($_.status -cne 'Skipped' -or $_.reason -cne 'OptOut')
                }).Count) {
            throw 'Ingestion evidence does not respect the configured cost opt-out.'
        }
    }
    else { $kinds += 'laIngestion' }
    $expectedFiles = @('logs/workspaces.json') + @(
        foreach ($kind in $kinds) {
            if ($kind -ceq 'laIngestion') { 'cost/laIngestion.json' } else { "logs/$kind.json" }
        }
    )
    if ($Collector.status -cnotin @('Completed', 'Partial') -or
        $null -eq $Collector.PSObject.Properties['files'] -or
        $Collector.files.Count -ne $expectedFiles.Count -or
        @($Collector.files | Sort-Object -Unique).Count -ne $expectedFiles.Count -or
        @($Collector.files | Where-Object { $_ -cnotin $expectedFiles }).Count) {
        throw 'Saved log file inventory is invalid.'
    }
    $metadata = Read-ApimLogEvidence -RunPath $RunPath -Kind workspaces
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($workspace in $metadata.workspaces) {
        if ($workspace.workspaceId -cnotin $targets -or -not $seen.Add($workspace.workspaceId) -or
            @($workspace.tables | ForEach-Object name | Sort-Object -Unique).Count -ne $workspace.tables.Count) {
            throw 'Saved workspace metadata is inconsistent.'
        }
        foreach ($family in $families) {
            $entry = @($coverage | Where-Object {
                    $_.kind -ceq $family -and $_.target -ceq $workspace.workspaceId
                })[0]
            if ($entry.status -cnotin @('Completed', 'Partial')) { continue }
            $table = if ($family -ceq 'Ingestion') { 'Usage' }
                elseif ($workspace.schema -ceq 'ResourceSpecific') { 'ApiManagementGatewayLogs' }
                elseif ($workspace.schema -ceq 'Legacy') { 'AzureDiagnostics' } else { '' }
            $tableMetadata = @($workspace.tables | Where-Object name -CEQ $table)
            $schema = if ($family -ceq 'Ingestion') { 'NotApplicable' }
                elseif ($workspace.mixed) { 'Mixed' } else { $workspace.schema }
            if ($tableMetadata.Count -ne 1 -or $entry.retentionDays -ne $tableMetadata[0].retentionDays -or
                $entry.schema -cne $schema) {
                throw 'Saved log windows do not match workspace schema and retention.'
            }
        }
    }
    foreach ($entry in $coverage) {
        if ($entry.status -cin @('Completed', 'Partial') -and -not $seen.Contains($entry.target)) {
            throw 'Saved log coverage is missing its workspace metadata.'
        }
    }
    $count = 0
    $complete = $metadata.workspaces.Count -eq $targets.Count -and
        @($coverage | Where-Object { $_.status -cnotin @('Completed', 'Skipped') }).Count -eq 0
    foreach ($kind in $kinds) {
        $payload = Read-ApimLogEvidence -RunPath $RunPath -Kind $kind
        $seen.Clear()
        if ($payload.workspaces.Count -ne $targets.Count) { throw 'Saved log workspace inventory is incomplete.' }
        $family = if ($kind -ceq 'laIngestion') { 'Ingestion' }
            elseif ($kind -ceq 'tls') { 'Security' } else { 'Usage' }
        foreach ($workspace in $payload.workspaces) {
            if ($workspace.workspaceId -cnotin $targets -or -not $seen.Add($workspace.workspaceId)) {
                throw 'Saved log workspace inventory is invalid.'
            }
            $entry = @($coverage | Where-Object {
                    $_.kind -ceq $family -and $_.target -ceq $workspace.workspaceId
                })[0]
            if (($entry.status -ceq 'Completed' -and $workspace.status -cne 'Completed') -or
                ($entry.status -ceq 'Failed' -and $workspace.status -cne 'Failed')) {
                throw 'Saved log query status contradicts its coverage.'
            }
            if ($workspace.status -cne 'Completed') { $complete = $false }
            $projected = @(
                foreach ($row in $workspace.rows) { ConvertTo-ApimLogAggregate -Row $row -Kind $kind }
            )
            Test-ApimLogAggregate -Rows $projected -Window $entry
            $count += $projected.Count
        }
    }
    if (($Collector.status -ceq 'Completed') -ne $complete -or $Collector.items -ne $count) {
        throw 'Saved log collector totals or completion status are inconsistent.'
    }
    return $count
}
