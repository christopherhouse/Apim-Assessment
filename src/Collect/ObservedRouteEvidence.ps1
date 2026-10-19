#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimObservedGatewayId {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Context)

    return @(
        foreach ($gateway in $Context.Settings.appGateways) {
            ('/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Network/applicationGateways/{2}' -f
                $Context.Manifest.subscriptionId, $gateway.resourceGroup, $gateway.name).ToLowerInvariant()
        }
    )
}

function ConvertTo-ApimObservedRouteAggregate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Row,
        [Parameter(Mandatory)]
        [ValidateSet('appgwByListener', 'appgwNonEdge', 'directNonAppGw', 'headersLogged')]
        [string] $Kind
    )

    if ($Kind -ceq 'directNonAppGw') {
        return ConvertTo-ApimLogAggregate -Row $Row -Kind noSubscriptionCalls
    }
    $result = [ordered]@{}
    if ($Kind -cin @('appgwByListener', 'appgwNonEdge')) {
        foreach ($field in @('gatewayId', 'listener', 'rule', 'host') + @(
                if ($Kind -ceq 'appgwNonEdge') { 'clientClass' }
            )) {
            $value = Get-ApimDiagnosticProperty -InputObject $Row -Name $field -Context 'Route aggregate'
            if ($value -isnot [string] -or $value -match '[\x00-\x1f\x7f]' -or
                ($field -cne 'gatewayId' -and $value.Length -gt 256)) {
                throw 'Route aggregate identifier is invalid.'
            }
            $result[$field] = if ($field -ceq 'gatewayId') { $value.ToLowerInvariant() } else { $value }
        }
    }
    $fields = if ($Kind -ceq 'headersLogged') {
        @('calls', 'headersObserved', 'xForwardedForCalls', 'cfConnectingIpCalls')
    } else { @('calls', 'clientCount') }
    foreach ($field in $fields) {
        $result[$field] = ConvertTo-ApimTelemetryNumber -Integer -Value (
            Get-ApimDiagnosticProperty -InputObject $Row -Name $field -Context 'Route aggregate'
        )
    }
    if ($Kind -ceq 'headersLogged' -and
        ($result.headersObserved -gt $result.calls -or
            $result.xForwardedForCalls -gt $result.headersObserved -or
            $result.cfConnectingIpCalls -gt $result.headersObserved)) {
        throw 'Header-presence counts exceed their observed requests.'
    }
    return [pscustomobject] $result
}

function Test-ApimObservedRoutePayload {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Payload)

    $schema = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) (
        'schemas/observed-route-evidence.schema.json'
    )
    if (-not (Test-Json -Json (ConvertTo-Json -InputObject $Payload -Depth 40 -WarningAction Stop) `
                -SchemaFile $schema -ErrorAction Stop)) {
        throw 'Observed-route evidence failed schema validation.'
    }
    foreach ($workspace in $Payload.workspaces) {
        $keys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($row in $workspace.rows) {
            $projected = ConvertTo-ApimObservedRouteAggregate -Row $row -Kind $Payload.kind
            $identity = [ordered]@{}
            foreach ($field in @('gatewayId', 'listener', 'rule', 'host', 'clientClass', 'apiId')) {
                if ($null -ne $projected.PSObject.Properties[$field]) { $identity[$field] = $projected.$field }
            }
            if (-not $keys.Add((ConvertTo-Json -InputObject $identity -Compress))) {
                throw 'Observed-route aggregates contain duplicate keys.'
            }
        }
        if ($Payload.kind -ceq 'headersLogged' -and
            $workspace.status -cin @('Completed', 'Partial') -and $workspace.rows.Count -ne 1) {
            throw 'Header-presence query did not return one aggregate.'
        }
    }
}

function Invoke-ApimObservedRouteWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][object] $Context,
        [Parameter(Mandatory)][string] $WorkspaceId,
        [AllowNull()][object] $Metadata,
        [Parameter(Mandatory)][string] $ApimSchema,
        [Parameter(Mandatory)][bool] $ApimMixed,
        [Parameter(Mandatory)][object] $UsageWindow
    )

    $gatewayIds = @(Get-ApimObservedGatewayId -Context $Context)
    $window = Get-ApimEvidenceWindow -EndUtc $Context.Manifest.startedUtc -Kind AppGateway `
        -Length $Context.Manifest.windows.usageDays
    $selected = 'None'; $mixed = $false
    $status = if ($gatewayIds.Count) { 'Failed' } else { 'Skipped' }
    $reason = if ($gatewayIds.Count) { 'Unavailable' } else { 'Unconfigured' }
    $schemas = [ordered]@{ ResourceSpecific = 'AGWAccessLogs'; Legacy = 'AzureDiagnostics' }
    if ($gatewayIds.Count -and $null -ne $Metadata) {
        try {
            $observed = @{}
            foreach ($schema in $schemas.Keys) {
                $table = $schemas[$schema]
                if (-not $Metadata.tables.ContainsKey($table)) { continue }
                $candidate = Get-ApimEvidenceWindow -EndUtc $Context.Manifest.startedUtc -Kind AppGateway `
                    -Length $Context.Manifest.windows.usageDays -RetentionDays $Metadata.tables[$table]
                $query = Get-ApimLogQuery -Name appgwSchema -Schema $schema -Window $candidate `
                    -ResourceId $Context.Manifest.apim.resourceId -GatewayResourceIds $gatewayIds
                $counts = @(Invoke-ApimLogQuery -WorkspaceId $WorkspaceId -Query $query)
                if ($counts.Count -ne 1) { throw 'Gateway schema detection did not return one count.' }
                $observed[$schema] = (ConvertTo-ApimLogAggregate -Row $counts[0] -Kind schema).calls
            }
            if ($observed.ContainsKey('ResourceSpecific') -and $observed.ResourceSpecific -gt 0) {
                $selected = 'ResourceSpecific'
                $mixed = $observed.ContainsKey('Legacy') -and $observed.Legacy -gt 0
            }
            elseif ($observed.ContainsKey('Legacy') -and $observed.Legacy -gt 0) { $selected = 'Legacy' }
            if ($selected -cne 'None') {
                $window = Get-ApimEvidenceWindow -EndUtc $Context.Manifest.startedUtc -Kind AppGateway `
                    -Length $Context.Manifest.windows.usageDays -RetentionDays $Metadata.tables[$schemas[$selected]]
                $status = if ($mixed) { 'Partial' } else { 'Completed' }
                $reason = if ($mixed) { 'Conflicting' } else { 'None' }
            }
        }
        catch {
            Add-RunWarning -RunPath $RunPath -Message 'App Gateway log schema detection failed; route evidence is unavailable.'
        }
    }
    $outputs = [ordered]@{}
    foreach ($kind in @('appgwByListener', 'appgwNonEdge', 'directNonAppGw', 'headersLogged')) {
        $gatewayQuery = $kind -cin @('appgwByListener', 'appgwNonEdge')
        $querySchema = if ($gatewayQuery) { $selected } else { $ApimSchema }
        $queryMixed = if ($gatewayQuery) { $mixed } else { $ApimMixed }
        $queryWindow = if ($gatewayQuery) { $window } else { $UsageWindow }
        $queryStatus = if ($gatewayQuery) { $status }
            elseif ($querySchema -ceq 'None') { 'Failed' }
            elseif ($queryMixed) { 'Partial' } else { 'Completed' }
        $queryReason = if ($gatewayQuery) { $reason }
            elseif ($querySchema -ceq 'None') { 'Unavailable' }
            elseif ($queryMixed) { 'Conflicting' } else { 'None' }
        if (($kind -ceq 'appgwNonEdge' -and $Context.Settings.telemetry.trustedEdgeRanges.Count -eq 0) -or
            ($kind -ceq 'directNonAppGw' -and $Context.Settings.appGwSubnetCidrs.Count -eq 0)) {
            $queryStatus = 'Skipped'; $queryReason = 'Unconfigured'
        }
        $rows = @()
        if ($queryStatus -cin @('Completed', 'Partial')) {
            try {
                $query = Get-ApimLogQuery -Name $kind -Schema $querySchema -Window $queryWindow `
                    -ResourceId $Context.Manifest.apim.resourceId -GatewayResourceIds $gatewayIds `
                    -AppGwCidrs $Context.Settings.appGwSubnetCidrs `
                    -InternalCidrs $Context.Settings.telemetry.internalCidrs `
                    -TrustedEdgeRanges $Context.Settings.telemetry.trustedEdgeRanges
                $rows = @(
                    foreach ($row in @(Invoke-ApimLogQuery -WorkspaceId $WorkspaceId -Query $query)) {
                        ConvertTo-ApimObservedRouteAggregate -Row $row -Kind $kind
                    }
                )
                $probe = [pscustomobject]@{
                    schemaVersion = '1.0'; kind = $kind
                    workspaces = @([pscustomobject]@{
                        workspaceId = $WorkspaceId; schema = $querySchema; status = $queryStatus; reason = $queryReason
                        requestedStartUtc = $queryWindow.requestedStartUtc; startUtc = $queryWindow.startUtc
                        endUtc = $queryWindow.endUtc; retentionDays = $queryWindow.retentionDays
                        isCapped = $queryWindow.isCapped; rows = $rows
                    })
                }
                Test-ApimObservedRoutePayload -Payload $probe
                if ($gatewayQuery -and @($rows | Where-Object gatewayId -CNotIn $gatewayIds).Count) {
                    throw 'Gateway aggregate is outside configured targets.'
                }
            }
            catch {
                $rows = @(); $queryStatus = 'Failed'; $queryReason = 'Unavailable'
                if ($gatewayQuery) { $status = 'Partial'; $reason = 'Unavailable' }
                Add-RunWarning -RunPath $RunPath -Message "Observed-route $kind query failed; evidence is unavailable."
            }
        }
        $outputs[$kind] = [pscustomobject][ordered]@{
            workspaceId = $WorkspaceId
            schema = if ($queryMixed) { 'Mixed' } else { $querySchema }
            status = $queryStatus; reason = $queryReason
            requestedStartUtc = $queryWindow.requestedStartUtc; startUtc = $queryWindow.startUtc
            endUtc = $queryWindow.endUtc; retentionDays = $queryWindow.retentionDays; isCapped = $queryWindow.isCapped
            rows = @($rows | Sort-Object gatewayId, listener, rule, host, clientClass, apiId -CaseSensitive)
        }
    }
    Set-ApimEvidenceWindow -RunPath $RunPath -Kind AppGateway -Target $WorkspaceId -Window $window `
        -Schema $(if ($mixed) { 'Mixed' } else { $selected }) -Status $status -Reason $reason
    return $outputs
}

function Read-ApimObservedRouteEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)]
        [ValidateSet('appgwByListener', 'appgwNonEdge', 'directNonAppGw', 'headersLogged')]
        [string] $Kind
    )

    $payload = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath "logs/$Kind.json"
    Test-ApimObservedRoutePayload -Payload $payload
    if ($payload.kind -cne $Kind) { throw 'Saved observed-route evidence has the wrong query kind.' }
    return $payload
}

function Test-ApimObservedRouteSavedOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][object] $Context,
        [Parameter(Mandatory)][AllowNull()][object] $Metadata
    )

    $settings = $Context.Settings
    $targets = @($settings.telemetry.workspaceIds)
    $coverage = @($Context.Manifest.evidenceWindows | Where-Object kind -CEQ AppGateway)
    $expectedTargets = @(if ($targets.Count) { $targets } else { 'unconfigured' })
    if ($coverage.Count -ne $expectedTargets.Count -or
        @($coverage | Where-Object target -CNotIn $expectedTargets).Count) {
        throw 'Saved App Gateway coverage does not match configured workspaces.'
    }
    if ($settings.telemetry.skipLogs -or $targets.Count -eq 0) {
        $reason = if ($settings.telemetry.skipLogs) { 'OptOut' } else { 'Unconfigured' }
        if (@($coverage | Where-Object { $_.status -cne 'Skipped' -or $_.reason -cne $reason }).Count) {
            throw 'Saved observed-route opt-out is inconsistent.'
        }
        return [pscustomobject]@{ Items = 0; Complete = $true }
    }
    $gatewayIds = @(Get-ApimObservedGatewayId -Context $Context)
    $count = 0; $complete = $true
    foreach ($kind in @('appgwByListener', 'appgwNonEdge', 'directNonAppGw', 'headersLogged')) {
        $payload = Read-ApimObservedRouteEvidence -RunPath $RunPath -Kind $kind
        if ($payload.workspaces.Count -ne $targets.Count -or
            @($payload.workspaces.workspaceId | Sort-Object -Unique -CaseSensitive).Count -ne $targets.Count) {
            throw 'Saved observed-route workspace inventory is invalid.'
        }
        foreach ($workspace in $payload.workspaces) {
            if ($workspace.workspaceId -cnotin $targets) { throw 'Saved observed-route target is invalid.' }
            $family = if ($kind -cin @('appgwByListener', 'appgwNonEdge')) { 'AppGateway' } else { 'Usage' }
            $entry = @($Context.Manifest.evidenceWindows | Where-Object {
                    $_.kind -ceq $family -and $_.target -ceq $workspace.workspaceId
                })
            if ($entry.Count -ne 1) { throw 'Saved observed-route coverage is missing.' }
            foreach ($field in @('requestedStartUtc', 'startUtc', 'endUtc')) {
                if ([datetimeoffset] $workspace.$field -ne [datetimeoffset] $entry[0].$field) {
                    throw 'Saved observed-route window is inconsistent.'
                }
            }
            if ($workspace.schema -cne $entry[0].schema -or
                $workspace.retentionDays -ne $entry[0].retentionDays -or $workspace.isCapped -ne $entry[0].isCapped) {
                throw 'Saved observed-route schema and retention are inconsistent.'
            }
            $unconfigured = ($family -ceq 'AppGateway' -and $gatewayIds.Count -eq 0) -or
                ($kind -ceq 'appgwNonEdge' -and $settings.telemetry.trustedEdgeRanges.Count -eq 0) -or
                ($kind -ceq 'directNonAppGw' -and $settings.appGwSubnetCidrs.Count -eq 0)
            if ($unconfigured -ne ($workspace.status -ceq 'Skipped') -or
                ($unconfigured -and $workspace.reason -cne 'Unconfigured') -or
                ($family -ceq 'AppGateway' -and $entry[0].status -ceq 'Completed' -and
                    -not $unconfigured -and $workspace.status -cne 'Completed') -or
                ($entry[0].status -ceq 'Failed' -and -not $unconfigured -and $workspace.status -cne 'Failed')) {
                throw 'Saved observed-route query status contradicts its coverage or configuration.'
            }
            if ($workspace.status -cin @('Completed', 'Partial')) {
                $table = if ($family -ceq 'AppGateway' -and $workspace.schema -cne 'Legacy') { 'AGWAccessLogs' }
                    elseif ($workspace.schema -ceq 'Legacy') { 'AzureDiagnostics' } else { 'ApiManagementGatewayLogs' }
                $workspaceMetadata = @($Metadata.workspaces | Where-Object workspaceId -CEQ $workspace.workspaceId)
                $tableMetadata = @(if ($workspaceMetadata.Count -eq 1) {
                        $workspaceMetadata[0].tables | Where-Object name -CEQ $table
                    })
                if ($tableMetadata.Count -ne 1 -or $tableMetadata[0].retentionDays -ne $workspace.retentionDays) {
                    throw 'Saved observed-route retention has no matching table metadata.'
                }
            }
            if ($family -ceq 'AppGateway' -and @($workspace.rows |
                    Where-Object gatewayId -CNotIn $gatewayIds).Count) {
                throw 'Saved observed-route gateway is outside configured targets.'
            }
            if ($workspace.status -cnotin @('Completed', 'Skipped')) { $complete = $false }
            $count += $workspace.rows.Count
        }
    }
    return [pscustomobject]@{ Items = $count; Complete = $complete }
}
