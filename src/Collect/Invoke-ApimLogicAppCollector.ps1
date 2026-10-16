#Requires -Version 7.4

Set-StrictMode -Version Latest

function Test-ApimLogicAppResourceId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ResourceId,
        [Parameter(Mandatory)][string] $SubscriptionId,
        [Parameter(Mandatory)][ValidateSet('Consumption', 'Standard', 'Plan')][string] $Kind,
        [string] $ResourceGroup
    )

    $type = switch ($Kind) {
        Consumption { 'Microsoft\.Logic/workflows' }
        Standard { 'Microsoft\.Web/sites' }
        Plan { 'Microsoft\.Web/serverfarms' }
    }
    $group = if ($ResourceGroup) { [regex]::Escape($ResourceGroup) } else { '[^/?#]+' }
    if ($ResourceId -notmatch (
            '^/subscriptions/{0}/resourceGroups/{1}/providers/{2}/[^/?#]+$' -f
                [regex]::Escape($SubscriptionId), $group, $type)) {
        throw 'Logic Apps cost inventory contains an invalid or out-of-scope resource.'
    }
}

function Invoke-ApimLogicAppCollector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Environment
    )

    $saved = Get-ApimRunSetting -RunPath $RunPath
    if ($saved.Manifest.schemaVersion -cne '1.2' -or
        $Environment.SubscriptionId -ine $saved.Manifest.subscriptionId) {
        throw 'Logic Apps cost collection requires telemetry run settings.'
    }
    $targets = @($saved.Settings.telemetry.logicAppResourceGroups)
    if ($saved.Settings.telemetry.skipCost -or $targets.Count -eq 0) {
        Set-RunCollectorStatus -RunPath $RunPath -Name LogicApps -Status Skipped -Files @()
        return
    }
    $window = Get-ApimEvidenceWindow -EndUtc $saved.Manifest.startedUtc -Kind Metric `
        -Length $saved.Manifest.windows.metricDays
    $groups = @(
        foreach ($group in $targets) {
            $resources = [Collections.Generic.List[object]]::new()
            $status = 'Completed'
            try {
                $query = 'resources | where resourceGroup =~ ' +
                    (ConvertTo-Json -InputObject $group -Compress) +
                    ' | where type =~ "microsoft.logic/workflows" or ' +
                    '(type =~ "microsoft.web/sites" and kind has "workflowapp") ' +
                    '| project id, type=tolower(type), planId=tostring(properties.serverFarmId)'
                $inventory = @(Invoke-ApimResourceGraphQuery -Query $query `
                        -SubscriptionId $saved.Manifest.subscriptionId)
                $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                foreach ($item in $inventory) {
                    $id = Get-ApimDiagnosticProperty $item id 'Logic Apps inventory'
                    $type = Get-ApimDiagnosticProperty $item type 'Logic Apps inventory'
                    $kind = switch ($type) {
                        'microsoft.logic/workflows' { 'Consumption' }
                        'microsoft.web/sites' { 'Standard' }
                        default { throw 'Unsupported Logic Apps inventory type.' }
                    }
                    Test-ApimLogicAppResourceId -ResourceId $id -SubscriptionId $saved.Manifest.subscriptionId `
                        -ResourceGroup $group -Kind $kind
                    if (-not $seen.Add($id)) { throw 'Duplicate Logic Apps cost inventory resource.' }
                    $planId = $null; $sku = $null; $instances = $null
                    $metricTarget = $id
                    if ($kind -ceq 'Standard') {
                        $planId = Get-ApimDiagnosticProperty $item planId 'Logic Apps plan'
                        Test-ApimLogicAppResourceId -ResourceId $planId `
                            -SubscriptionId $saved.Manifest.subscriptionId -Kind Plan
                        $planQuery = 'resources | where type =~ "microsoft.web/serverfarms" | where id =~ ' +
                            (ConvertTo-Json -InputObject $planId -Compress) +
                            ' | project id, skuName=tostring(sku.name), instances=toint(sku.capacity)'
                        $plans = @(Invoke-ApimResourceGraphQuery -Query $planQuery `
                                -SubscriptionId $saved.Manifest.subscriptionId)
                        if ($plans.Count -ne 1 -or
                            (Get-ApimDiagnosticProperty $plans[0] id 'Logic Apps plan') -ine $planId) {
                            throw 'Logic Apps plan metadata is unavailable.'
                        }
                        $sku = Get-ApimDiagnosticProperty $plans[0] skuName 'Logic Apps plan'
                        if ($sku -isnot [string] -or $sku -notmatch '^[A-Za-z0-9_-]{1,128}$') {
                            throw 'Logic Apps plan SKU is invalid.'
                        }
                        $instances = ConvertTo-ApimTelemetryNumber -Integer -Value (
                            Get-ApimDiagnosticProperty $plans[0] instances 'Logic Apps plan'
                        )
                        $metricTarget = $planId
                    }
                    $metrics = @(
                        foreach ($definition in Get-ApimMetricDefinition -Kind "Logic$kind") {
                            try {
                                Invoke-ApimMetricSeries -ResourceId $metricTarget -Definition $definition `
                                    -Window $window -LogPath (Join-Path $RunPath 'logs/run.log')
                            }
                            catch {
                                $status = 'Partial'
                                Add-RunWarning -RunPath $RunPath -Message 'Logic Apps billable/capacity metrics unavailable; workflow review is out of scope.'
                                [pscustomobject]@{
                                    name = $definition.Name; unit = $definition.Unit; interval = $definition.Interval
                                    expectedPoints = $(if ($definition.Interval -ceq 'P1D') {
                                            $saved.Manifest.windows.metricDays
                                        } else { 24 * $saved.Manifest.windows.metricDays })
                                    status = 'Failed'; points = @()
                                }
                            }
                        }
                    )
                    if (@($metrics | Where-Object status -CNE Completed).Count) { $status = 'Partial' }
                    $resources.Add([pscustomobject][ordered]@{
                        resourceId = $id.ToLowerInvariant(); kind = $kind
                        planId = $planId; sku = $sku; instances = $instances; metrics = @($metrics | Sort-Object name)
                    })
                }
            }
            catch {
                $resources.Clear()
                $status = 'Failed'
                Add-RunWarning -RunPath $RunPath -Message 'Logic Apps cost-only inventory unavailable; no workflow definitions were requested.'
            }
            [pscustomobject]@{
                resourceGroup = $group; status = $status; resources = @($resources | Sort-Object resourceId)
            }
        }
    )
    $payload = [ordered]@{ schemaVersion = '1.0'; groups = @($groups) }
    $null = Write-RunFile -RunPath $RunPath -RelativePath cost/logicApps.json -InputObject $payload
    $count = @($groups | ForEach-Object { $_.resources }).Count
    $errors = @($groups | Where-Object status -CNE Completed).Count
    Set-RunCollectorStatus -RunPath $RunPath -Name LogicApps `
        -Status $(if ($errors) { 'Partial' } else { 'Completed' }) `
        -Items $count -Errors $errors -Files @('cost/logicApps.json')
}

function Read-ApimLogicAppEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $RunPath)

    $payload = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath cost/logicApps.json
    $schema = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) `
        'schemas/logic-app-evidence.schema.json'
    if (-not (Test-Json -Json (ConvertTo-Json $payload -Depth 40 -WarningAction Stop) `
                -SchemaFile $schema -ErrorAction Stop)) {
        throw 'Logic Apps saved evidence failed schema validation.'
    }
    return $payload
}

function Test-ApimLogicAppSavedOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][object] $Collector
    )

    $saved = Get-ApimRunSetting -RunPath $RunPath
    if ($saved.Manifest.schemaVersion -cne '1.2' -or $Collector.name -cne 'LogicApps') {
        throw 'Logic Apps evidence does not belong to a telemetry run.'
    }
    $targets = @($saved.Settings.telemetry.logicAppResourceGroups)
    if ($saved.Settings.telemetry.skipCost -or $targets.Count -eq 0) {
        if ($Collector.status -cne 'Skipped' -or $Collector.items -ne 0 -or
            $null -eq $Collector.PSObject.Properties['files'] -or $Collector.files.Count -ne 0) {
            throw 'Logic Apps saved opt-out is inconsistent.'
        }
        return 0
    }
    if ($Collector.status -cnotin @('Completed', 'Partial') -or
        $null -eq $Collector.PSObject.Properties['files'] -or
        $Collector.files.Count -ne 1 -or $Collector.files[0] -cne 'cost/logicApps.json') {
        throw 'Logic Apps saved file inventory is invalid.'
    }
    $payload = Read-ApimLogicAppEvidence -RunPath $RunPath
    if ($payload.groups.Count -ne $targets.Count) { throw 'Logic Apps groups are incomplete.' }
    $window = Get-ApimEvidenceWindow -EndUtc $saved.Manifest.startedUtc -Kind Metric `
        -Length $saved.Manifest.windows.metricDays
    $groups = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $count = 0
    foreach ($group in $payload.groups) {
        if ($group.resourceGroup -cnotin $targets -or -not $groups.Add($group.resourceGroup) -or
            ($group.status -ceq 'Failed' -and $group.resources.Count)) {
            throw 'Logic Apps group coverage is invalid.'
        }
        $complete = $true
        foreach ($resource in $group.resources) {
            Test-ApimLogicAppResourceId -ResourceId $resource.resourceId `
                -SubscriptionId $saved.Manifest.subscriptionId -ResourceGroup $group.resourceGroup -Kind $resource.kind
            if (-not $ids.Add($resource.resourceId)) { throw 'Logic Apps resource inventory is duplicated.' }
            if ($resource.kind -ceq 'Consumption') {
                if ($null -ne $resource.planId -or $null -ne $resource.sku -or $null -ne $resource.instances) {
                    throw 'Consumption evidence contains unsupported plan metadata.'
                }
            }
            else {
                Test-ApimLogicAppResourceId -ResourceId $resource.planId `
                    -SubscriptionId $saved.Manifest.subscriptionId -Kind Plan
                if ($null -eq $resource.sku -or $null -eq $resource.instances) {
                    throw 'Standard evidence is missing plan metadata.'
                }
            }
            $definitions = @(Get-ApimMetricDefinition -Kind "Logic$($resource.kind)")
            if ($resource.metrics.Count -ne $definitions.Count -or
                @($resource.metrics.name | Sort-Object -Unique).Count -ne $definitions.Count) {
                throw 'Logic Apps metric inventory is invalid.'
            }
            foreach ($metric in $resource.metrics) {
                $definition = @($definitions | Where-Object Name -CEQ $metric.name)
                $expected = if ($metric.interval -ceq 'P1D') { $saved.Manifest.windows.metricDays }
                    else { 24 * $saved.Manifest.windows.metricDays }
                if ($definition.Count -ne 1 -or $metric.unit -cne $definition[0].Unit -or
                    $metric.interval -cne $definition[0].Interval -or $metric.expectedPoints -ne $expected) {
                    throw 'Logic Apps metric definition is invalid.'
                }
                $stamps = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                $metricComplete = $metric.points.Count -eq $expected
                foreach ($point in $metric.points) {
                    $stamp = [datetimeoffset] $point.timestamp
                    if ($stamp -lt [datetimeoffset] $window.startUtc -or $stamp -ge [datetimeoffset] $window.endUtc -or
                        -not $stamps.Add($stamp.UtcDateTime.ToString('O'))) {
                        throw 'Logic Apps metric timestamps are invalid.'
                    }
                    foreach ($field in @('average', 'maximum', 'total')) {
                        if ($field -in $definition[0].Aggregations) {
                            if ($null -eq $point.$field) { $metricComplete = $false }
                        }
                        elseif ($null -ne $point.$field) { throw 'Logic Apps aggregation is not requested.' }
                    }
                }
                if (($metric.status -ceq 'Completed') -ne $metricComplete) {
                    throw 'Logic Apps metric status contradicts its points.'
                }
                if (-not $metricComplete) { $complete = $false }
            }
            $count++
        }
        if ($group.status -cne 'Failed' -and ($group.status -ceq 'Completed') -ne $complete) {
            throw 'Logic Apps group status contradicts its metrics.'
        }
    }
    if ($Collector.items -ne $count -or ($Collector.status -ceq 'Completed') -ne
        (@($payload.groups | Where-Object status -CNE Completed).Count -eq 0)) {
        throw 'Logic Apps collector totals are inconsistent.'
    }
    return $count
}
