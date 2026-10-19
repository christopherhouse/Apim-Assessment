#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimWorkspaceSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $WorkspaceId,

        [Parameter(Mandatory)]
        [string] $SubscriptionId,

        [Parameter(Mandatory)]
        [string] $LogPath
    )

    if ($WorkspaceId -notmatch '^[0-9a-fA-F-]{36}$') {
        throw 'Workspace ID is invalid.'
    }
    $query = 'resources | where type =~ "microsoft.operationalinsights/workspaces" ' +
        '| where tostring(properties.customerId) =~ ' +
        (ConvertTo-Json -InputObject $WorkspaceId -Compress) + ' | project id'
    $workspaceMatches = @(Invoke-ApimResourceGraphQuery -Query $query -SubscriptionId $SubscriptionId)
    if ($workspaceMatches.Count -ne 1) { throw 'Workspace metadata could not be resolved uniquely.' }
    $id = Get-ApimDiagnosticProperty -InputObject $workspaceMatches[0] -Name id -Context 'Workspace metadata'
    if ($id -isnot [string] -or $id -notmatch (
            '^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/' +
            'providers/Microsoft\.OperationalInsights/workspaces/[^/?#]+$')) {
        throw 'Workspace resource ID is invalid.'
    }
    $workspace = Invoke-ApimArm -Uri "$($id)?api-version=2023-09-01" -LogPath $LogPath
    $properties = Get-ApimDiagnosticProperty -InputObject $workspace `
        -Name properties -Context 'Workspace metadata'
    $actualId = Get-ApimDiagnosticProperty -InputObject $properties `
        -Name customerId -Context 'Workspace metadata'
    if ([string] $actualId -ine $WorkspaceId) {
        throw 'Workspace metadata does not match the configured workspace.'
    }
    $retention = ConvertTo-ApimTelemetryNumber -Integer -Minimum 1 -Value (
        Get-ApimDiagnosticProperty -InputObject $properties -Name retentionInDays `
            -Context 'Workspace metadata'
    )
    if ($retention -gt 3650) { throw 'Workspace retention is outside the supported range.' }
    $tables = Invoke-ApimArm -Uri "$id/tables?api-version=2023-09-01" -LogPath $LogPath
    $tableRetentions = @{}
    $tableValues = Get-ApimDiagnosticProperty -InputObject $tables `
        -Name value -Context 'Workspace tables'
    foreach ($table in @($tableValues)) {
        $name = Get-ApimDiagnosticProperty -InputObject $table -Name name -Context 'Workspace table'
        if ($name -cnotin @('ApiManagementGatewayLogs', 'AzureDiagnostics', 'Usage', 'AGWAccessLogs')) { continue }
        if ($tableRetentions.ContainsKey($name)) { throw 'Duplicate workspace table metadata.' }
        $settings = Get-ApimDiagnosticProperty -InputObject $table `
            -Name properties -Context 'Workspace table'
        $days = Get-ApimDiagnosticProperty -InputObject $settings -Name retentionInDays `
            -Context 'Workspace table' -AllowMissing
        if ($null -eq $days -or [string] $days -eq '-1') { $days = $retention }
        $days = ConvertTo-ApimTelemetryNumber -Integer -Minimum 1 -Value $days
        if ($days -gt 3650) { throw 'Table retention is outside the supported range.' }
        $tableRetentions[$name] = [int] $days
    }
    return [pscustomobject]@{
        workspaceId = $WorkspaceId.ToLowerInvariant()
        resourceId = $id
        retentionDays = [int] $retention
        tables = $tableRetentions
    }
}

function Invoke-ApimLogCollector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Environment
    )

    $timer = [Diagnostics.Stopwatch]::StartNew()
    $saved = Get-ApimRunSetting -RunPath $RunPath
    if ($saved.Manifest.schemaVersion -cne '1.2' -or
        $Environment.SubscriptionId -ine $saved.Manifest.subscriptionId) {
        throw 'Log collection requires telemetry run settings.'
    }
    $manifest = $saved.Manifest
    $settings = $saved.Settings
    $observedRoutes = $settings.schemaVersion -ceq '1.2'
    $targets = @($settings.telemetry.workspaceIds)
    $kinds = @('usageByApi', 'usageByRoute', 'usageMonthly', 'tls', 'noSubscriptionCalls')
    if (-not $settings.telemetry.skipCost) { $kinds += 'laIngestion' }
    $outputs = @{}
    foreach ($kind in $kinds) { $outputs[$kind] = [Collections.Generic.List[object]]::new() }
    $routeOutputs = [ordered]@{}
    if ($observedRoutes) {
        foreach ($kind in @('appgwByListener', 'appgwNonEdge', 'directNonAppGw', 'headersLogged')) {
            $routeOutputs[$kind] = [Collections.Generic.List[object]]::new()
        }
    }
    $metadataRows = [Collections.Generic.List[object]]::new()
    $errorCount = 0
    $itemCount = 0
    if ($settings.telemetry.skipLogs -or $targets.Count -eq 0) {
        $reason = if ($settings.telemetry.skipLogs) { 'OptOut' } else { 'Unconfigured' }
        foreach ($target in @(if ($targets.Count) { $targets } else { 'unconfigured' })) {
            foreach ($kind in @('Usage', 'Security', 'Ingestion') + @(
                    if ($observedRoutes) { 'AppGateway' }
                )) {
                $length = if ($kind -ceq 'Security') {
                    $manifest.windows.securityLogDays
                }
                else { $manifest.windows.usageDays }
                $window = Get-ApimEvidenceWindow -EndUtc $manifest.startedUtc `
                    -Kind $kind -Length $length
                Set-ApimEvidenceWindow -RunPath $RunPath -Kind $kind -Target $target `
                    -Window $window -Schema None -Status Skipped -Reason $reason
            }
        }
        Set-RunCollectorStatus -RunPath $RunPath -Name LogAnalytics -Status Skipped `
            -DurationSec $timer.Elapsed.TotalSeconds -Files @()
        return
    }

    foreach ($workspaceId in $targets) {
        $metadata = $null
        $selected = 'None'
        $mixed = $false
        $windows = @{}
        $statuses = @{ Usage = 'Failed'; Security = 'Failed'; Ingestion = 'Failed' }
        $reasons = @{ Usage = 'Unavailable'; Security = 'Unavailable'; Ingestion = 'Unavailable' }
        if ($settings.telemetry.skipCost) {
            $statuses.Ingestion = 'Skipped'
            $reasons.Ingestion = 'OptOut'
        }
        foreach ($kind in @('Usage', 'Security', 'Ingestion')) {
            $length = if ($kind -ceq 'Security') {
                $manifest.windows.securityLogDays
            }
            else { $manifest.windows.usageDays }
            $windows[$kind] = Get-ApimEvidenceWindow -EndUtc $manifest.startedUtc `
                -Kind $kind -Length $length
        }
        try {
            $metadata = Get-ApimWorkspaceSetting -WorkspaceId $workspaceId `
                -SubscriptionId $Environment.SubscriptionId -LogPath (Join-Path $RunPath 'logs/run.log')
            $schemas = [ordered]@{ ResourceSpecific = 'ApiManagementGatewayLogs'; Legacy = 'AzureDiagnostics' }
            $observed = @{}
            foreach ($schema in $schemas.Keys) {
                $table = $schemas[$schema]
                if (-not $metadata.tables.ContainsKey($table)) { continue }
                $candidate = Get-ApimEvidenceWindow -EndUtc $manifest.startedUtc -Kind Usage `
                    -Length $manifest.windows.usageDays -RetentionDays $metadata.tables[$table]
                $query = Get-ApimLogQuery -Name schema -Schema $schema `
                    -Window $candidate -ResourceId $manifest.apim.resourceId
                $rows = @(Invoke-ApimLogQuery -WorkspaceId $workspaceId -Query $query)
                if ($rows.Count -ne 1) { throw 'Schema detection did not return one count.' }
                $observed[$schema] = (ConvertTo-ApimLogAggregate -Row $rows[0] -Kind schema).calls
            }
            if ($observed.ContainsKey('ResourceSpecific') -and $observed.ResourceSpecific -gt 0) {
                $selected = 'ResourceSpecific'
                $mixed = $observed.ContainsKey('Legacy') -and $observed.Legacy -gt 0
            }
            elseif ($observed.ContainsKey('Legacy') -and $observed.Legacy -gt 0) {
                $selected = 'Legacy'
            }
            if ($selected -cne 'None') {
                $retention = $metadata.tables[$schemas[$selected]]
                foreach ($kind in @('Usage', 'Security')) {
                    $length = if ($kind -ceq 'Security') {
                        $manifest.windows.securityLogDays
                    }
                    else { $manifest.windows.usageDays }
                    $windows[$kind] = Get-ApimEvidenceWindow -EndUtc $manifest.startedUtc `
                        -Kind $kind -Length $length -RetentionDays $retention
                    $statuses[$kind] = if ($mixed) { 'Partial' } else { 'Completed' }
                    $reasons[$kind] = if ($mixed) { 'Conflicting' } else { 'None' }
                }
            }
        }
        catch {
            $errorCount++
            Add-RunWarning -RunPath $RunPath `
                -Message 'Log Analytics workspace/schema detection failed; inspect saved coverage locally.'
        }
        if ($null -ne $metadata) {
            $tableRows = @(
                foreach ($name in @($metadata.tables.Keys | Sort-Object)) {
                    [ordered]@{ name = $name; retentionDays = $metadata.tables[$name] }
                }
            )
            $metadataRows.Add([pscustomobject][ordered]@{
                workspaceId = $workspaceId; resourceId = $metadata.resourceId
                retentionDays = $metadata.retentionDays; tables = $tableRows
                schema = $selected; mixed = $mixed
            })
            if (-not $settings.telemetry.skipCost -and $metadata.tables.ContainsKey('Usage')) {
                $windows.Ingestion = Get-ApimEvidenceWindow -EndUtc $manifest.startedUtc `
                    -Kind Ingestion -Length $manifest.windows.usageDays `
                    -RetentionDays $metadata.tables.Usage
                $statuses.Ingestion = 'Completed'
                $reasons.Ingestion = 'None'
            }
        }
        foreach ($kind in $kinds) {
            $family = if ($kind -ceq 'laIngestion') { 'Ingestion' }
                elseif ($kind -ceq 'tls') { 'Security' } else { 'Usage' }
            $rows = @()
            $status = $statuses[$family]
            if ($status -cin @('Completed', 'Partial')) {
                try {
                    $schema = if ($kind -ceq 'laIngestion') { 'ResourceSpecific' } else { $selected }
                    $query = Get-ApimLogQuery -Name $kind -Schema $schema `
                        -Window $windows[$family] -ResourceId $manifest.apim.resourceId `
                        -AppGwCidrs $settings.appGwSubnetCidrs -InternalCidrs $settings.telemetry.internalCidrs
                    $raw = @(Invoke-ApimLogQuery -WorkspaceId $workspaceId -Query $query)
                    $rows = @(
                        foreach ($row in $raw) { ConvertTo-ApimLogAggregate -Row $row -Kind $kind }
                    )
                    Test-ApimLogAggregate -Rows $rows -Window $windows[$family]
                    $itemCount += $rows.Count
                }
                catch {
                    $rows = @()
                    $status = 'Failed'
                    $statuses[$family] = 'Partial'
                    $reasons[$family] = 'Unavailable'
                    $errorCount++
                    Add-RunWarning -RunPath $RunPath `
                        -Message "Log Analytics $kind query failed; incomplete evidence is not zero usage."
                }
            }
            $outputs[$kind].Add([pscustomobject][ordered]@{
                workspaceId = $workspaceId; status = $status
                rows = @($rows | Sort-Object apiId, operationId, productId, route, month, dataType, day, tlsVersion)
            })
        }
        foreach ($family in @('Usage', 'Security', 'Ingestion')) {
            $schema = if ($family -ceq 'Ingestion') { 'NotApplicable' }
                elseif ($mixed) { 'Mixed' } else { $selected }
            Set-ApimEvidenceWindow -RunPath $RunPath -Kind $family -Target $workspaceId `
                -Window $windows[$family] -Schema $schema -Status $statuses[$family] `
                -Reason $reasons[$family]
            if ($statuses[$family] -cnotin @('Completed', 'Skipped')) { $errorCount++ }
        }
        if ($observedRoutes) {
            $observations = Invoke-ApimObservedRouteWorkspace -RunPath $RunPath -Context $saved `
                -WorkspaceId $workspaceId -Metadata $metadata -ApimSchema $selected -ApimMixed $mixed `
                -UsageWindow $windows.Usage
            foreach ($kind in $routeOutputs.Keys) {
                $routeOutputs[$kind].Add($observations[$kind])
                $itemCount += $observations[$kind].rows.Count
                if ($observations[$kind].status -cnotin @('Completed', 'Skipped')) { $errorCount++ }
            }
        }
    }
    $files = [Collections.Generic.List[string]]::new()
    $files.Add('logs/workspaces.json')
    $null = Write-RunFile -RunPath $RunPath -RelativePath 'logs/workspaces.json' `
        -InputObject ([ordered]@{ schemaVersion = '1.0'; workspaces = @($metadataRows) })
    foreach ($kind in $kinds) {
        $relative = if ($kind -ceq 'laIngestion') { 'cost/laIngestion.json' } else { "logs/$kind.json" }
        $null = Write-RunFile -RunPath $RunPath -RelativePath $relative `
            -InputObject ([ordered]@{ schemaVersion = '1.0'; kind = $kind; workspaces = @($outputs[$kind]) })
        $files.Add($relative)
    }
    foreach ($kind in $routeOutputs.Keys) {
        $payload = [pscustomobject][ordered]@{
            schemaVersion = '1.0'; kind = $kind; workspaces = @($routeOutputs[$kind])
        }
        Test-ApimObservedRoutePayload -Payload $payload
        $relative = "logs/$kind.json"
        $null = Write-RunFile -RunPath $RunPath -RelativePath $relative -InputObject $payload
        $files.Add($relative)
    }
    $status = if ($errorCount -gt 0) { 'Partial' } else { 'Completed' }
    Set-RunCollectorStatus -RunPath $RunPath -Name LogAnalytics -Status $status `
        -Items $itemCount -Errors $errorCount -Files @($files | Sort-Object) `
        -DurationSec $timer.Elapsed.TotalSeconds
}
