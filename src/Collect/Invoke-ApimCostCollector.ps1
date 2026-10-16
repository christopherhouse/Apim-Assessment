#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimCostQueryBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Window,

        [AllowNull()]
        [string] $MeterCategory
    )

    $group = if ($PSBoundParameters.ContainsKey('MeterCategory')) { 'MeterSubCategory' } else { 'MeterCategory' }
    $body = [ordered]@{
        type = 'ActualCost'; timeframe = 'Custom'
        timePeriod = [ordered]@{
            from = ([datetimeoffset] $Window.startUtc).UtcDateTime.ToString('O')
            to = ([datetimeoffset] $Window.endUtc).UtcDateTime.AddTicks(-1).ToString('O')
        }
        dataset = [ordered]@{
            granularity = 'Daily'
            aggregation = [ordered]@{ totalCost = [ordered]@{ name = 'PreTaxCost'; function = 'Sum' } }
            grouping = @(
                [ordered]@{ type = 'Dimension'; name = 'ResourceId' }
                [ordered]@{ type = 'Dimension'; name = $group }
            )
        }
    }
    if ($PSBoundParameters.ContainsKey('MeterCategory')) {
        $body.dataset.filter = [ordered]@{
            dimensions = [ordered]@{ name = 'MeterCategory'; operator = 'In'; values = @($MeterCategory) }
        }
    }
    return ConvertTo-Json -InputObject $body -Depth 20 -Compress -WarningAction Stop
}

function ConvertTo-ApimCostQueryRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Payload,

        [Parameter(Mandatory)]
        [string] $Scope,

        [Parameter(Mandatory)]
        [object] $Window,

        [AllowNull()]
        [string] $MeterCategory
    )

    $properties = Get-ApimDiagnosticProperty -InputObject $Payload -Name properties -Context 'Cost response'
    $next = Get-ApimDiagnosticProperty -InputObject $properties -Name nextLink -Context 'Cost response' -AllowMissing
    if (-not [string]::IsNullOrEmpty([string] $next)) {
        throw 'Cost response requires pagination; incomplete pages cannot bypass the ARM token URL guard.'
    }
    $columns = Get-ApimDiagnosticProperty -InputObject $properties -Name columns -Context 'Cost response'
    $rows = Get-ApimDiagnosticProperty -InputObject $properties -Name rows -Context 'Cost response'
    if ($null -eq $columns -or $null -eq $rows) { throw 'Cost response rows or columns are missing.' }
    $map = @{}
    $index = 0
    foreach ($column in @($columns)) {
        $name = Get-ApimDiagnosticProperty -InputObject $column -Name name -Context 'Cost column'
        if ($name -isnot [string] -or $map.ContainsKey($name)) { throw 'Cost columns are invalid or ambiguous.' }
        $map[$name] = $index++
    }
    $dimension = if ($PSBoundParameters.ContainsKey('MeterCategory')) { 'MeterSubCategory' } else { 'MeterCategory' }
    foreach ($name in @('ResourceId', 'Currency', 'UsageDate', $dimension)) {
        if (-not $map.ContainsKey($name)) { throw 'Cost response is missing a required column.' }
    }
    $costColumns = @('PreTaxCost', 'Cost', 'totalCost' | Where-Object { $map.ContainsKey($_) })
    if ($costColumns.Count -ne 1) {
        throw 'Cost response does not have one unambiguous cost column.'
    }
    $costColumn = $costColumns[0]
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($row in @($rows)) {
        if ($row -isnot [array] -or $row.Count -ne @($columns).Count) {
            throw 'Cost response row does not match its columns.'
        }
        $resource = $row[$map.ResourceId]
        $currency = $row[$map.Currency]
        $group = $row[$map[$dimension]]
        if ($resource -isnot [string] -or $currency -isnot [string] -or
            $currency -cnotmatch '^[A-Z]{3}$' -or $group -isnot [string] -or
            $group.Length -gt 256 -or $group -match '[\x00-\x1f\x7f]') {
            throw 'Cost dimensions are invalid.'
        }
        if ($resource -ne '' -and (-not $resource.StartsWith("$Scope/",
                    [StringComparison]::OrdinalIgnoreCase) -or
                $resource -notmatch '^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/[^/?#]+/.+$')) {
            throw 'Cost resource is outside its configured scope or is not a resource ID.'
        }
        $day = [datetime]::ParseExact([string] $row[$map.UsageDate], 'yyyyMMdd',
            [Globalization.CultureInfo]::InvariantCulture)
        if ($day -lt ([datetimeoffset] $Window.startUtc).UtcDateTime.Date -or
            $day -ge ([datetimeoffset] $Window.endUtc).UtcDateTime) {
            throw 'Cost usage date is outside its evidence window.'
        }
        $result = [pscustomobject][ordered]@{
            day = $day.ToString('yyyy-MM-dd')
            resourceId = $resource.ToLowerInvariant()
            meterCategory = $(if ($dimension -ceq 'MeterCategory') { $group } else { $MeterCategory })
            meterSubCategory = $(if ($dimension -ceq 'MeterSubCategory') { $group } else { $null })
            cost = ConvertTo-ApimTelemetryNumber -Value $row[$map[$costColumn]] -Minimum (-[double]::MaxValue)
            currency = $currency
        }
        $key = Get-ApimCostRowKey -Row $result -IncludeSubcategory
        if (-not $seen.Add($key)) { throw 'Cost response contains duplicate daily dimension keys.' }
        $result
    }
}

function Get-ApimCostRowKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Row,

        [switch] $IncludeSubcategory
    )

    $key = @($Row.day, $Row.resourceId.ToLowerInvariant(), $Row.meterCategory, $Row.currency)
    if ($IncludeSubcategory) { $key += $Row.meterSubCategory }
    return ConvertTo-Json -InputObject $key -Compress
}

function Invoke-ApimCostCollector {
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
        throw 'Cost collection requires compatible telemetry run settings.'
    }
    $window = Get-ApimEvidenceWindow -EndUtc $saved.Manifest.startedUtc -Kind Cost `
        -Length $saved.Manifest.windows.costMonths
    $targets = @($saved.Settings.telemetry.costScopes)
    if ($saved.Settings.telemetry.skipCost -or $targets.Count -eq 0) {
        $reason = if ($saved.Settings.telemetry.skipCost) { 'OptOut' } else { 'Unconfigured' }
        foreach ($scope in @(if ($targets.Count) { $targets } else { 'unconfigured' })) {
            Set-ApimEvidenceWindow -RunPath $RunPath -Kind Cost -Target $scope `
                -Window $window -Schema NotApplicable -Status Skipped -Reason $reason
        }
        Set-RunCollectorStatus -RunPath $RunPath -Name Cost -Status Skipped -Files @() `
            -DurationSec $timer.Elapsed.TotalSeconds
        return
    }
    $scopeRows = [Collections.Generic.List[object]]::new()
    $errorCount = 0
    $itemCount = 0
    foreach ($scope in $targets) {
        $details = [Collections.Generic.List[object]]::new()
        $status = 'Completed'
        try {
            $uri = "$scope/providers/Microsoft.CostManagement/query?api-version=2025-03-01"
            $base = Invoke-ApimArm -Method POST -Uri $uri `
                -Body (Get-ApimCostQueryBody -Window $window) -LogPath (Join-Path $RunPath 'logs/run.log')
            $totals = @(ConvertTo-ApimCostQueryRow -Payload $base -Scope $scope -Window $window)
            $categories = @($totals | ForEach-Object meterCategory | Sort-Object -Unique)
            if ($categories.Count -gt 128) { throw 'Cost meter-category expansion exceeds its safety bound.' }
            foreach ($category in $categories) {
                $payload = Invoke-ApimArm -Method POST -Uri $uri `
                    -Body (Get-ApimCostQueryBody -Window $window -MeterCategory $category) `
                    -LogPath (Join-Path $RunPath 'logs/run.log')
                foreach ($row in @(ConvertTo-ApimCostQueryRow -Payload $payload -Scope $scope `
                            -Window $window -MeterCategory $category)) {
                    $details.Add($row)
                }
            }
            $sums = [Collections.Generic.Dictionary[string, decimal]]::new([StringComparer]::Ordinal)
            foreach ($row in $details) {
                $key = Get-ApimCostRowKey -Row $row
                if (-not $sums.ContainsKey($key)) { $sums[$key] = 0 }
                $sums[$key] += [decimal] $row.cost
            }
            if ($sums.Count -ne $totals.Count) { throw 'Cost detail keys do not reconcile with category totals.' }
            foreach ($row in $totals) {
                $key = Get-ApimCostRowKey -Row $row
                if (-not $sums.ContainsKey($key) -or
                    [math]::Abs($sums[$key] - [decimal] $row.cost) -gt [decimal] 0.000001) {
                    throw 'Cost detail amounts do not reconcile with category totals.'
                }
            }
            $itemCount += $details.Count
        }
        catch {
            $details.Clear()
            $status = 'Failed'
            $errorCount++
            Add-RunWarning -RunPath $RunPath `
                -Message 'Cost scope evidence unavailable or incomplete; no amount or currency is assumed.'
        }
        $scopeRows.Add([pscustomobject][ordered]@{
            scope = $scope; status = $status
            rows = @($details | Sort-Object day, resourceId, meterCategory, meterSubCategory, currency)
        })
        $reason = if ($status -ceq 'Completed') { 'None' } else { 'Unavailable' }
        Set-ApimEvidenceWindow -RunPath $RunPath -Kind Cost -Target $scope -Window $window `
            -Schema NotApplicable -Status $status -Reason $reason
    }
    $null = Write-RunFile -RunPath $RunPath -RelativePath cost/daily.json `
        -InputObject ([ordered]@{ schemaVersion = '1.0'; scopes = @($scopeRows) })
    $status = if ($errorCount -gt 0) { 'Partial' } else { 'Completed' }
    Set-RunCollectorStatus -RunPath $RunPath -Name Cost -Status $status -Items $itemCount `
        -Errors $errorCount -Files @('cost/daily.json') -DurationSec $timer.Elapsed.TotalSeconds
}
