#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimTelemetrySource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][object] $Context
    )

    $windows = @(
        foreach ($entry in $Context.Manifest.evidenceWindows) {
            $window = [ordered]@{}
            foreach ($property in $entry.PSObject.Properties) {
                $window[$property.Name] = if ($property.Name -cin @('requestedStartUtc', 'startUtc', 'endUtc')) {
                    ([datetimeoffset] $property.Value).ToUniversalTime().ToString('O')
                } else { $property.Value }
            }
            [pscustomobject] $window
        }
    )
    $source = [ordered]@{
        settings = $Context.Settings
        windows = @($windows | Sort-Object kind, target -CaseSensitive)
    }
    foreach ($name in @('LogAnalytics', 'Metrics', 'Cost', 'LogicApps')) {
        $records = @($Context.Manifest.collectors | Where-Object name -CEQ $name)
        if ($records.Count -gt 1) { throw 'Telemetry collector inventory is duplicated.' }
        $source[$name] = $null
        if ($records.Count -eq 0) { continue }
        $record = $records[0]
        $payloads = [ordered]@{}
        if ($record.status -cin @('Completed', 'Partial', 'Skipped')) {
            Test-ApimCollectorOutput -RunPath $RunPath -Environment $Context.Environment -Collector $record
            foreach ($file in @($record.files | Sort-Object -CaseSensitive)) {
                $payloads[$file] = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath $file
            }
        }
        $source[$name] = [pscustomobject]@{
            status = $record.status; items = $record.items; payloads = $payloads
        }
    }
    return $source
}

function Get-ApimTelemetryMonth {
    [CmdletBinding()]
    param([Parameter(Mandatory)][datetimeoffset] $Date)

    $utc = $Date.ToUniversalTime()
    return [datetimeoffset]::new($utc.Year, $utc.Month, 1, 0, 0, 0, [timespan]::Zero)
}

function Get-ApimUsageModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Context,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Source,
        [Parameter(Mandatory)][string] $SourceSha256
    )

    $end = ([datetimeoffset] $Context.Manifest.startedUtc).ToUniversalTime()
    $gaps = [Collections.Generic.List[string]]::new()
    $rows = @(); $top = @(); $start = $null
    $record = $Source.LogAnalytics
    $payload = if ($null -ne $record -and $record.payloads.Contains('logs/usageMonthly.json')) {
        $record.payloads['logs/usageMonthly.json']
    } else { $null }
    $coverage = @($Source.windows | Where-Object kind -CEQ Usage)
    $usable = $null -ne $payload -and $coverage.Count -gt 0 -and
        @($coverage | Where-Object status -CNE Completed).Count -eq 0 -and
        @($payload.workspaces | Where-Object status -CNE Completed).Count -eq 0
    if ($usable) {
        $first = $coverage[0]
        $start = $first.startUtc
        $canonical = $null
        foreach ($workspace in $payload.workspaces) {
            $entry = @($coverage | Where-Object target -CEQ $workspace.workspaceId)[0]
            $digest = Get-ApimConfigDigest -Config @{
                rows = @($workspace.rows | Sort-Object apiId, month -CaseSensitive)
                startUtc = ([datetimeoffset] $entry.startUtc).ToUniversalTime().ToString('O')
                endUtc = ([datetimeoffset] $entry.endUtc).ToUniversalTime().ToString('O')
            }
            if ($null -eq $canonical) { $canonical = $digest }
            elseif ($canonical -cne $digest) { $usable = $false; $gaps.Add('workspaceOverlap') }
        }
    }
    if ($usable) {
        if (@($coverage | Where-Object isCapped).Count) { $gaps.Add('usageCoverage') }
        $selected = $payload.workspaces[0]
        $apiIds = @($selected.rows | ForEach-Object apiId | Sort-Object -Unique -CaseSensitive)
        $rows = @(
            foreach ($apiId in $apiIds) {
                for ($month = Get-ApimTelemetryMonth -Date ([datetimeoffset] $start);
                    $month -lt $end; $month = $month.AddMonths(1)) {
                    $monthRows = @($selected.rows | Where-Object {
                            $_.apiId -ceq $apiId -and $_.month -ceq $month.ToString('yyyy-MM-dd')
                        })
                    $full = $month -ge [datetimeoffset] $start -and $month.AddMonths(1) -le $end
                    $calls = if ($monthRows.Count) { [long] $monthRows[0].calls } elseif ($full) { 0L } else { $null }
                    [pscustomobject][ordered]@{
                        period = $month.ToString('yyyy-MM-dd'); apiId = $apiId; calls = $calls
                        modelStatus = if ($full) { 'Complete' } else { 'Partial' }
                        missingInputs = @(if (-not $full) { 'partialMonth' })
                    }
                }
            }
        )
        $top = @(
            foreach ($api in @($selected.rows | Group-Object apiId -CaseSensitive)) {
                [pscustomobject]@{
                    apiId = $api.Name; calls = [long] (($api.Group | Measure-Object calls -Sum).Sum)
                }
            }
        )
        $top = @($top | Sort-Object @{ Expression = 'calls'; Descending = $true }, apiId -CaseSensitive |
                Select-Object -First 10)
    }
    else { $start = $null; $gaps.Add('usage') }
    return [pscustomobject][ordered]@{
        schemaVersion = '1.0'; sourceSha256 = $SourceSha256; startUtc = $start; endUtc = $end.ToString('O')
        modelStatus = if ($gaps.Count) { 'Partial' } else { 'Complete' }
        missingInputs = @($gaps | Sort-Object -Unique -CaseSensitive)
        rows = @($rows | Sort-Object period, apiId -CaseSensitive); topApis = $top
    }
}

function Get-ApimCapacityStatistic {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Points)

    $averages = @($Points | Where-Object { $null -ne $_.average } |
            ForEach-Object { [double] $_.average } | Sort-Object)
    $maximums = @($Points | Where-Object { $null -ne $_.maximum } | ForEach-Object { [double] $_.maximum })
    return [pscustomobject]@{
        capacityAvg = if ($averages.Count) { ($averages | Measure-Object -Average).Average } else { $null }
        capacityMax = if ($maximums.Count) { ($maximums | Measure-Object -Maximum).Maximum } else { $null }
        capacityP95 = if ($averages.Count) { $averages[[int] [math]::Ceiling(0.95 * $averages.Count) - 1] } else { $null }
        sampleCount = $averages.Count
    }
}

function Get-ApimCapacityModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Context,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Source,
        [Parameter(Mandatory)][string] $SourceSha256,
        [AllowNull()][object] $Service
    )

    $gaps = [Collections.Generic.List[string]]::new()
    $metric = $null
    if ($null -ne $Source.Metrics -and $Source.Metrics.payloads.Contains('metrics/apim.json')) {
        $metric = @($Source.Metrics.payloads['metrics/apim.json'].resources[0].metrics |
                Where-Object name -CEQ Capacity)[0]
    }
    if ($null -eq $metric) { $gaps.Add('capacity') }
    elseif ($metric.status -cne 'Completed') { $gaps.Add('capacityCoverage') }
    $units = if ($null -ne $Service) { $Service.skuCapacity } else { $null }
    if ($null -eq $units) { $gaps.Add('units') }
    $points = @(if ($null -ne $metric) { $metric.points })
    $summary = Get-ApimCapacityStatistic -Points $points
    $days = @(
        foreach ($group in @($points | Group-Object {
                    ([datetimeoffset] $_.timestamp).UtcDateTime.ToString('yyyy-MM-dd')
                })) {
            $stats = Get-ApimCapacityStatistic -Points @($group.Group)
            [pscustomobject][ordered]@{
                day = $group.Name; capacityAvg = $stats.capacityAvg
                capacityMax = $stats.capacityMax; capacityP95 = $stats.capacityP95; sampleCount = $stats.sampleCount
            }
        }
    )
    return [pscustomobject][ordered]@{
        schemaVersion = '1.0'; sourceSha256 = $SourceSha256
        modelStatus = if ($gaps.Count) { 'Partial' } else { 'Complete' }
        missingInputs = @($gaps | Sort-Object -CaseSensitive)
        percentileMethod = 'NearestRankHourlyAverage'; units = $units
        capacityAvg = $summary.capacityAvg; capacityMax = $summary.capacityMax
        capacityP95 = $summary.capacityP95; sampleCount = $summary.sampleCount
        expectedSamples = 24 * $Context.Manifest.windows.metricDays
        rows = @($days | Sort-Object day -CaseSensitive)
    }
}

function Get-ApimCostModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Context,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Source,
        [Parameter(Mandatory)][string] $SourceSha256,
        [Parameter(Mandatory)][object] $Usage
    )

    $gaps = [Collections.Generic.List[string]]::new()
    $end = ([datetimeoffset] $Context.Manifest.startedUtc).ToUniversalTime()
    $daily = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $costComplete = $null -ne $Source.Cost -and $Source.Cost.status -ceq 'Completed'
    $targetIds = @($Context.Manifest.apim.resourceId) + @(
        foreach ($gateway in $Context.Settings.appGateways) {
            '/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Network/applicationGateways/{2}' -f
                $Context.Manifest.subscriptionId, $gateway.resourceGroup, $gateway.name
        }
    )
    foreach ($target in $targetIds) {
        if (@($Context.Settings.telemetry.costScopes | Where-Object {
                    $target.StartsWith("$_/", [StringComparison]::OrdinalIgnoreCase)
                }).Count -eq 0) {
            $costComplete = $false
        }
    }
    if ($null -ne $Source.Cost -and $Source.Cost.payloads.Contains('cost/daily.json')) {
        foreach ($scope in $Source.Cost.payloads['cost/daily.json'].scopes) {
            foreach ($row in $scope.rows) {
                $key = Get-ApimCostRowKey -Row $row -IncludeSubcategory
                if ($daily.ContainsKey($key)) {
                    if ($daily[$key].cost -ne $row.cost) { throw 'Overlapping cost scopes contain conflicting amounts.' }
                }
                else { $daily.Add($key, $row) }
            }
        }
    }
    else { $gaps.Add('cost') }
    if (-not $costComplete) { $gaps.Add('costCoverage') }
    if ($Usage.modelStatus -cne 'Complete') { $gaps.Add('usage') }
    $monthly = @(
        foreach ($group in @($daily.Values | Group-Object {
                    '{0}|{1}|{2}|{3}' -f $_.day.Substring(0, 7), $_.resourceId, $_.meterCategory, $_.currency
                } -CaseSensitive)) {
            $row = $group.Group[0]
            $month = "$($row.day.Substring(0, 7))-01"
            $type = [regex]::Match($row.resourceId, '(?i)/providers/([^/]+/[^/]+)/').Groups[1].Value
            [pscustomobject][ordered]@{
                month = $month; resourceId = $row.resourceId; resourceType = $type
                meterCategory = $row.meterCategory; cost = [double] (($group.Group | Measure-Object cost -Sum).Sum)
                currency = $row.currency
                completeMonth = $costComplete -and ([datetimeoffset] "${month}T00:00:00Z").AddMonths(1) -le $end
            }
        }
    )
    if ($costComplete) {
        $costStart = Get-ApimEvidenceWindow -EndUtc $end -Kind Cost -Length $Context.Manifest.windows.costMonths
        $zeros = @(
            foreach ($group in @($monthly | Group-Object {
                        "$($_.resourceId)|$($_.meterCategory)"
                    } -CaseSensitive)) {
                if (@($group.Group.currency | Sort-Object -Unique).Count -ne 1) { continue }
                $example = $group.Group[0]
                for ($month = [datetimeoffset] $costStart.startUtc; $month -lt $end; $month = $month.AddMonths(1)) {
                    $period = $month.ToString('yyyy-MM-dd')
                    if (@($group.Group | Where-Object month -CEQ $period).Count) { continue }
                    [pscustomobject][ordered]@{
                        month = $period; resourceId = $example.resourceId; resourceType = $example.resourceType
                        meterCategory = $example.meterCategory; cost = 0.0; currency = $example.currency
                        completeMonth = $month.AddMonths(1) -le $end
                    }
                }
            }
        )
        $monthly += $zeros
    }
    $normalized = @(
        foreach ($group in @($monthly | Where-Object resourceId -In $targetIds |
                Group-Object { "$($_.month)|$($_.currency)" } -CaseSensitive)) {
            $row = $group.Group[0]
            $start = [datetimeoffset] "$($row.month)T00:00:00Z"
            $periodEnd = if ($start.AddMonths(1) -lt $end) { $start.AddMonths(1) } else { $end }
            $calls = $null
            if ($null -ne $Usage.startUtc -and $Usage.modelStatus -ceq 'Complete' -and
                [datetimeoffset] $Usage.startUtc -le $start -and [datetimeoffset] $Usage.endUtc -ge $periodEnd) {
                $matching = @($Usage.rows | Where-Object period -CEQ $row.month)
                $calls = if ($matching.Count) { [long] (($matching | Measure-Object calls -Sum).Sum) } else { 0L }
            }
            $amount = [double] (($group.Group | Measure-Object cost -Sum).Sum)
            [pscustomobject][ordered]@{
                month = $row.month; cost = $amount; currency = $row.currency; calls = $calls
                costPerMillionCalls = if ($costComplete -and $null -ne $calls -and $calls -gt 0) {
                    $amount * 1000000.0 / $calls
                } else { $null }
                changePercent = $null; completeMonth = $row.completeMonth
            }
        }
    )
    $normalized = @($normalized | Sort-Object month, currency -CaseSensitive)
    foreach ($row in $normalized) {
        $priorMonth = ([datetimeoffset] "$($row.month)T00:00:00Z").AddMonths(-1).ToString('yyyy-MM-dd')
        $prior = @($normalized | Where-Object { $_.month -ceq $priorMonth -and $_.currency -ceq $row.currency })
        if ($row.completeMonth -and $null -ne $row.costPerMillionCalls -and $prior.Count -eq 1 -and
            $prior[0].completeMonth -and $null -ne $prior[0].costPerMillionCalls -and
            $prior[0].costPerMillionCalls -gt 0) {
            $row.changePercent = 100.0 * ($row.costPerMillionCalls / $prior[0].costPerMillionCalls - 1)
        }
    }
    $ingestion = @()
    if ($null -ne $Source.LogAnalytics -and $Source.LogAnalytics.payloads.Contains('cost/laIngestion.json')) {
        $payload = $Source.LogAnalytics.payloads['cost/laIngestion.json']
        $ingestion = @(
            foreach ($workspace in $payload.workspaces) {
                $entry = @($Source.windows | Where-Object {
                        $_.kind -ceq 'Ingestion' -and $_.target -ceq $workspace.workspaceId
                    })[0]
                foreach ($group in @($workspace.rows | Where-Object dataType -CIn @(
                            'ApiManagementGatewayLogs', 'AzureDiagnostics', 'AGWAccessLogs'
                        ) | Group-Object dataType -CaseSensitive)) {
                    for ($month = Get-ApimTelemetryMonth -Date ([datetimeoffset] $entry.startUtc);
                        $month -lt [datetimeoffset] $entry.endUtc; $month = $month.AddMonths(1)) {
                        $monthRows = @($group.Group | Where-Object {
                                $_.day.StartsWith($month.ToString('yyyy-MM'), [StringComparison]::Ordinal)
                            })
                        $full = $entry.status -ceq 'Completed' -and $workspace.status -ceq 'Completed' -and
                            $month -ge [datetimeoffset] $entry.startUtc -and $month.AddMonths(1) -le [datetimeoffset] $entry.endUtc
                        if (-not $monthRows.Count -and -not $full) { continue }
                        [pscustomobject][ordered]@{
                            workspaceId = $workspace.workspaceId; month = $month.ToString('yyyy-MM-dd')
                            dataType = $group.Name
                            gb = if ($monthRows.Count) { [double] (($monthRows | Measure-Object gb -Sum).Sum) } else { 0.0 }
                            completeMonth = $full
                        }
                    }
                }
                $firstFull = Get-ApimTelemetryMonth -Date ([datetimeoffset] $entry.startUtc)
                if ($firstFull -lt [datetimeoffset] $entry.startUtc) { $firstFull = $firstFull.AddMonths(1) }
                if ($firstFull.AddMonths(2) -gt [datetimeoffset] $entry.endUtc) { $gaps.Add('ingestion') }
            }
        )
        if (@($Source.windows | Where-Object {
                    $_.kind -ceq 'Ingestion' -and $_.status -cne 'Completed'
                }).Count) { $gaps.Add('ingestion') }
    }
    else { $gaps.Add('ingestion') }
    $logic = @()
    if ($null -ne $Source.LogicApps -and $Source.LogicApps.payloads.Contains('cost/logicApps.json')) {
        $payload = $Source.LogicApps.payloads['cost/logicApps.json']
        $logic = @(
            foreach ($resource in @($payload.groups | ForEach-Object { $_.resources })) {
                [pscustomobject][ordered]@{
                    resourceId = $resource.resourceId; kind = $resource.kind; planId = $resource.planId
                    sku = $resource.sku; instances = $resource.instances
                    metricsComplete = @($resource.metrics | Where-Object status -CNE Completed).Count -eq 0
                    historicalPlanChanges = $null
                }
            }
        )
        if ($Source.LogicApps.status -cne 'Completed') { $gaps.Add('logicApps') }
    }
    else { $gaps.Add('logicApps') }
    return [pscustomobject][ordered]@{
        schemaVersion = '1.0'; sourceSha256 = $SourceSha256
        modelStatus = if ($gaps.Count) { 'Partial' } else { 'Complete' }
        missingInputs = @($gaps | Sort-Object -Unique -CaseSensitive)
        daily = @(
            foreach ($row in @($daily.Values | Sort-Object day, resourceId, meterCategory, meterSubCategory, currency -CaseSensitive)) {
                [pscustomobject][ordered]@{
                    day = $row.day; resourceId = $row.resourceId
                    resourceType = [regex]::Match($row.resourceId, '(?i)/providers/([^/]+/[^/]+)/').Groups[1].Value
                    meterCategory = $row.meterCategory; meterSubCategory = $row.meterSubCategory
                    cost = $row.cost; currency = $row.currency
                }
            }
        )
        monthly = @($monthly | Sort-Object month, resourceId, meterCategory, currency -CaseSensitive)
        normalized = $normalized
        ingestion = @($ingestion | Sort-Object workspaceId, month, dataType -CaseSensitive)
        logicApps = @($logic | Sort-Object resourceId -CaseSensitive)
    }
}

function Get-ApimSavedTelemetryModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][object] $Context,
        [AllowNull()][object] $Service
    )

    if ($Context.Manifest.schemaVersion -cne '1.2') { return [ordered]@{} }
    $source = Get-ApimTelemetrySource -RunPath $RunPath -Context $Context
    $hash = Get-ApimConfigDigest -Config @{
        source = $source
        currentUnits = if ($null -ne $Service) { $Service.skuCapacity } else { $null }
    }
    $usage = Get-ApimUsageModel -Context $Context -Source $source -SourceSha256 $hash
    return [ordered]@{
        usage = $usage
        capacity = Get-ApimCapacityModel -Context $Context -Source $source -SourceSha256 $hash -Service $Service
        cost = Get-ApimCostModel -Context $Context -Source $source -SourceSha256 $hash -Usage $usage
    }
}

function Test-ApimSavedTelemetryModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Models
    )

    $names = @('usage', 'capacity', 'cost' | Where-Object { $Models.Contains($_) })
    $context = Get-ApimRunSetting -RunPath $RunPath
    if ($context.Manifest.schemaVersion -cne '1.2') {
        if ($names.Count) { throw 'Telemetry models cannot be attached to a legacy run.' }
        return
    }
    if ($names.Count -ne 3) { throw 'Saved telemetry models are incomplete.' }
    $expected = Get-ApimSavedTelemetryModel -RunPath $RunPath -Context $context -Service $Models.service
    foreach ($name in $names) {
        $projection = ConvertFrom-Json -InputObject (
            ConvertTo-Json -InputObject $expected[$name] -Depth 30 -WarningAction Stop
        ) -Depth 30 -NoEnumerate -ErrorAction Stop
        if (-not (Test-ApimAuthSavedProjection -Payload $Models[$name] -Projection $projection)) {
            throw 'Saved telemetry model does not match its validated sources and settings.'
        }
    }
}
