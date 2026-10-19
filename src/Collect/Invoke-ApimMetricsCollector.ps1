#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimMetricDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Apim', 'AppGateway', 'LogicConsumption', 'LogicStandard')]
        [string] $Kind
    )

    $definitions = switch ($Kind) {
        Apim {
            @(
                @{ Name = 'Capacity'; Unit = 'Percent'; Aggregations = @('Average', 'Maximum'); Interval = 'PT1H' }
                @{ Name = 'Requests'; Unit = 'Count'; Aggregations = @('Total'); Interval = 'P1D' }
                @{ Name = 'Duration'; Unit = 'MilliSeconds'; Aggregations = @('Average'); Interval = 'PT1H' }
                @{ Name = 'BackendDuration'; Unit = 'MilliSeconds'; Aggregations = @('Average'); Interval = 'PT1H' }
            )
        }
        AppGateway {
            @(
                @{ Name = 'CapacityUnits'; Unit = 'Count'; Aggregations = @('Average'); Interval = 'PT1H' }
                @{ Name = 'Throughput'; Unit = 'BytesPerSecond'; Aggregations = @('Average'); Interval = 'PT1H' }
                @{ Name = 'UnhealthyHostCount'; Unit = 'Count'; Aggregations = @('Average'); Interval = 'PT1H' }
            )
        }
        LogicConsumption {
            @(
                @{ Name = 'BillableActionExecutions'; Unit = 'Count'; Aggregations = @('Total'); Interval = 'P1D' }
                @{ Name = 'BillableTriggerExecutions'; Unit = 'Count'; Aggregations = @('Total'); Interval = 'P1D' }
            )
        }
        LogicStandard {
            @(
                @{ Name = 'CpuPercentage'; Unit = 'Percent'; Aggregations = @('Average'); Interval = 'PT1H' }
            )
        }
    }
    return @($definitions | ForEach-Object { [pscustomobject] $_ })
}

function Invoke-ApimMetricSeries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ResourceId,

        [Parameter(Mandatory)]
        [object] $Definition,

        [Parameter(Mandatory)]
        [object] $Window,

        [Parameter(Mandatory)]
        [string] $LogPath
    )

    $range = [Uri]::EscapeDataString((
        '{0}/{1}' -f ([datetimeoffset] $Window.startUtc).UtcDateTime.ToString('O'),
        ([datetimeoffset] $Window.endUtc).UtcDateTime.ToString('O')
    ))
    $aggregation = [Uri]::EscapeDataString(($Definition.Aggregations -join ','))
    $uri = "$ResourceId/providers/Microsoft.Insights/metrics?api-version=2018-01-01" +
        "&metricnames=$($Definition.Name)&timespan=$range&interval=$($Definition.Interval)" +
        "&aggregation=$aggregation&AutoAdjustTimegrain=false"
    $payload = Invoke-ApimArm -Uri $uri -LogPath $LogPath
    $values = Get-ApimDiagnosticProperty -InputObject $payload -Name value -Context 'Metric response'
    if (@($values).Count -ne 1) { throw 'Metric response did not contain exactly one metric.' }
    $metric = @($values)[0]
    $name = Get-ApimDiagnosticProperty -InputObject $metric -Name name -Context 'Metric response'
    $actualName = Get-ApimDiagnosticProperty -InputObject $name -Name value -Context 'Metric name'
    $unit = Get-ApimDiagnosticProperty -InputObject $metric -Name unit -Context 'Metric response'
    if ($actualName -cne $Definition.Name -or $unit -cne $Definition.Unit) {
        throw 'Metric response name or unit does not match the requested metric.'
    }
    $series = Get-ApimDiagnosticProperty -InputObject $metric -Name timeseries -Context 'Metric response'
    if (@($series).Count -ne 1) {
        throw 'Missing or dimension-split metric series cannot be treated as a resource aggregate.'
    }
    $data = Get-ApimDiagnosticProperty -InputObject @($series)[0] -Name data -Context 'Metric series'
    $points = [Collections.Generic.List[object]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $partial = @($data).Count -eq 0
    foreach ($point in @($data)) {
        $stamp = Get-ApimDiagnosticProperty -InputObject $point -Name timeStamp -Context 'Metric point'
        $date = [datetimeoffset] $stamp
        if ($date -lt [datetimeoffset] $Window.startUtc -or $date -ge [datetimeoffset] $Window.endUtc) {
            throw 'Metric point is outside the requested evidence window.'
        }
        $timestamp = $date.UtcDateTime.ToString('O')
        if (-not $seen.Add($timestamp)) { throw 'Metric response contains duplicate timestamps.' }
        $row = [ordered]@{ timestamp = $timestamp; average = $null; maximum = $null; total = $null }
        foreach ($aggregationName in $Definition.Aggregations) {
            $field = $aggregationName.ToLowerInvariant()
            $number = Get-ApimDiagnosticProperty -InputObject $point -Name $field `
                -Context 'Metric point' -AllowMissing
            $row[$field] = ConvertTo-ApimTelemetryNumber -Value $number -Nullable
            if ($null -eq $row[$field]) { $partial = $true }
        }
        $points.Add([pscustomobject] $row)
    }
    $span = [datetimeoffset] $Window.endUtc - [datetimeoffset] $Window.startUtc
    $expected = [long] [math]::Ceiling($(if ($Definition.Interval -ceq 'P1D') {
                $span.TotalDays
            }
            else { $span.TotalHours }))
    if ($points.Count -ne $expected) { $partial = $true }
    return [pscustomobject][ordered]@{
        name = $Definition.Name; unit = $Definition.Unit; interval = $Definition.Interval
        expectedPoints = $expected
        status = $(if ($partial) { 'Partial' } else { 'Completed' })
        points = @($points | Sort-Object timestamp)
    }
}

function Invoke-ApimMetricsCollector {
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
        throw 'Metric collection requires telemetry run settings.'
    }
    $window = Get-ApimEvidenceWindow -EndUtc $saved.Manifest.startedUtc -Kind Metric `
        -Length $saved.Manifest.windows.metricDays
    $outputs = @{ Apim = [Collections.Generic.List[object]]::new(); AppGateway = [Collections.Generic.List[object]]::new() }
    $targets = @(
        [pscustomobject]@{ resourceId = $saved.Manifest.apim.resourceId; kind = 'Apim' }
        foreach ($gateway in $saved.Settings.appGateways) {
            [pscustomobject]@{
                resourceId = (
                    '/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Network/applicationGateways/{2}'
                ) -f $Environment.SubscriptionId,
                    (ConvertTo-ApimResourceSegment -Value $gateway.resourceGroup),
                    (ConvertTo-ApimResourceSegment -Value $gateway.name)
                kind = 'AppGateway'
            }
        }
    )
    $errorCount = 0
    $itemCount = 0
    foreach ($target in @($targets | Sort-Object resourceId)) {
        $metrics = [Collections.Generic.List[object]]::new()
        foreach ($definition in Get-ApimMetricDefinition -Kind $target.kind) {
            try {
                $metric = Invoke-ApimMetricSeries -ResourceId $target.resourceId `
                    -Definition $definition -Window $window -LogPath (Join-Path $RunPath 'logs/run.log')
                $itemCount += $metric.points.Count
                if ($metric.status -cne 'Completed') { $errorCount++ }
            }
            catch {
                $errorCount++
                $metric = [pscustomobject][ordered]@{
                    name = $definition.Name; unit = $definition.Unit; interval = $definition.Interval
                    expectedPoints = $(if ($definition.Interval -ceq 'P1D') {
                            $saved.Manifest.windows.metricDays
                        }
                        else { 24 * $saved.Manifest.windows.metricDays })
                    status = 'Failed'; points = @()
                }
                Add-RunWarning -RunPath $RunPath `
                    -Message "Metric $($definition.Name) unavailable; missing samples are not zero utilization."
            }
            $metrics.Add($metric)
        }
        $outputs[$target.kind].Add([pscustomobject][ordered]@{
            resourceId = $target.resourceId; metrics = @($metrics | Sort-Object name)
        })
        $status = if (@($metrics | Where-Object status -CEQ Failed).Count -eq $metrics.Count) {
            'Failed'
        }
        elseif (@($metrics | Where-Object status -CNE Completed).Count) { 'Partial' }
        else { 'Completed' }
        $reason = if ($status -ceq 'Completed') { 'None' } else { 'Unavailable' }
        Set-ApimEvidenceWindow -RunPath $RunPath -Kind Metric -Target $target.resourceId `
            -Window $window -Schema NotApplicable -Status $status -Reason $reason
    }
    $files = @('metrics/apim.json', 'metrics/appgw.json')
    foreach ($kind in @('Apim', 'AppGateway')) {
        $relative = if ($kind -ceq 'Apim') { $files[0] } else { $files[1] }
        $null = Write-RunFile -RunPath $RunPath -RelativePath $relative `
            -InputObject ([ordered]@{ schemaVersion = '1.0'; resources = @($outputs[$kind]) })
    }
    $status = if ($errorCount -gt 0) { 'Partial' } else { 'Completed' }
    Set-RunCollectorStatus -RunPath $RunPath -Name Metrics -Status $status -Items $itemCount `
        -Errors $errorCount -Files $files -DurationSec $timer.Elapsed.TotalSeconds
}
