#Requires -Version 7.4

Set-StrictMode -Version Latest

function Read-ApimMetricEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [ValidateSet('Apim', 'AppGateway')]
        [string] $Kind
    )

    $relative = if ($Kind -ceq 'Apim') { 'metrics/apim.json' } else { 'metrics/appgw.json' }
    $payload = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath $relative
    $schema = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'schemas/metric-evidence.schema.json'
    if (-not (Test-Json -Json (ConvertTo-Json $payload -Depth 40 -WarningAction Stop) `
                -SchemaFile $schema -ErrorAction Stop)) {
        throw 'Saved metric evidence failed schema validation.'
    }
    return $payload
}

function Test-ApimMetricSavedOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [object] $Collector
    )

    $saved = Get-ApimRunSetting -RunPath $RunPath
    $files = @('metrics/apim.json', 'metrics/appgw.json')
    if ($saved.Manifest.schemaVersion -cne '1.2' -or $Collector.name -cne 'Metrics' -or
        $Collector.status -cnotin @('Completed', 'Partial') -or
        $null -eq $Collector.PSObject.Properties['files'] -or $Collector.files.Count -ne 2 -or
        @($Collector.files | Sort-Object -Unique).Count -ne 2 -or
        @($Collector.files | Where-Object { $_ -cnotin $files }).Count) {
        throw 'Metric collector saved inventory is invalid.'
    }
    $window = Get-ApimEvidenceWindow -EndUtc $saved.Manifest.startedUtc -Kind Metric `
        -Length $saved.Manifest.windows.metricDays
    $count = 0
    $allComplete = $true
    foreach ($kind in @('Apim', 'AppGateway')) {
        $payload = Read-ApimMetricEvidence -RunPath $RunPath -Kind $kind
        $targets = @(
            if ($kind -ceq 'Apim') { $saved.Manifest.apim.resourceId } else {
                foreach ($gateway in $saved.Settings.appGateways) {
                    '/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Network/applicationGateways/{2}' -f
                        $saved.Manifest.subscriptionId,
                        (ConvertTo-ApimResourceSegment -Value $gateway.resourceGroup),
                        (ConvertTo-ApimResourceSegment -Value $gateway.name)
                }
            }
        )
        if ($payload.resources.Count -ne @($targets).Count) { throw 'Metric resource inventory is incomplete.' }
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $definitions = @(Get-ApimMetricDefinition -Kind $kind)
        foreach ($resource in $payload.resources) {
            if ($resource.resourceId -notin $targets -or -not $seen.Add($resource.resourceId) -or
                $resource.metrics.Count -ne $definitions.Count -or
                @($resource.metrics.name | Sort-Object -Unique).Count -ne $definitions.Count) {
                throw 'Metric resource or metric inventory is invalid.'
            }
            foreach ($metric in $resource.metrics) {
                $definition = @($definitions | Where-Object Name -CEQ $metric.name)
                $expected = if ($metric.interval -ceq 'P1D') { $saved.Manifest.windows.metricDays }
                    else { 24 * $saved.Manifest.windows.metricDays }
                if ($definition.Count -ne 1 -or $metric.unit -cne $definition[0].Unit -or
                    $metric.interval -cne $definition[0].Interval -or $metric.expectedPoints -ne $expected) {
                    throw 'Metric definition or expected coverage does not match saved settings.'
                }
                $stamps = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                $complete = $metric.points.Count -eq $expected
                foreach ($point in $metric.points) {
                    $stamp = [datetimeoffset] $point.timestamp
                    if ($stamp -lt [datetimeoffset] $window.startUtc -or $stamp -ge [datetimeoffset] $window.endUtc -or
                        -not $stamps.Add($stamp.UtcDateTime.ToString('O'))) {
                        throw 'Metric point timestamp is duplicated or outside its saved window.'
                    }
                    foreach ($field in @('average', 'maximum', 'total')) {
                        if ($field -in $definition[0].Aggregations) {
                            if ($null -eq $point.$field) { $complete = $false }
                        }
                        elseif ($null -ne $point.$field) {
                            throw 'Metric point contains an unrequested aggregation.'
                        }
                    }
                }
                if (($metric.status -ceq 'Completed') -ne $complete) {
                    throw 'Metric status contradicts its sample coverage.'
                }
                if (-not $complete) { $allComplete = $false }
                $count += $metric.points.Count
            }
            $coverage = @($saved.Manifest.evidenceWindows | Where-Object {
                    $_.kind -ceq 'Metric' -and $_.target -ieq $resource.resourceId
                })
            $status = if (@($resource.metrics | Where-Object status -CEQ Failed).Count -eq $definitions.Count) {
                'Failed'
            }
            elseif (@($resource.metrics | Where-Object status -CNE Completed).Count) { 'Partial' }
            else { 'Completed' }
            if ($coverage.Count -ne 1 -or $coverage[0].status -cne $status) {
                throw 'Metric coverage does not match its saved samples.'
            }
        }
    }
    if (($Collector.status -ceq 'Completed') -ne $allComplete -or $Collector.items -ne $count) {
        throw 'Metric collector totals or completion status are inconsistent.'
    }
    return $count
}
