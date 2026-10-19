#Requires -Version 7.4

Set-StrictMode -Version Latest

function Write-ApimTelemetryChart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Package,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Models
    )

    $usage = $Package.Workbook.Worksheets['Usage']
    $cost = $Package.Workbook.Worksheets['Cost']
    $usage.Cells[2, 1].Value = 'Monthly calls only. Partial boundary months are labeled; route/latency percentiles are not inferred from monthly counts.'
    $cost.Cells[2, 1].Value = 'Currencies remain separate. Combined normalization repeats APIM/App Gateway costs: do not add it to resource rows. MTD is not a full month.'
    if ($Models.Contains('usage') -and $Models.usage.rows.Count) {
        $usage.Cells[3, 16].Value = 'Period'
        $usage.Cells[3, 17].Value = 'Calls'
        $index = 4
        foreach ($group in @($Models.usage.rows | Group-Object period | Sort-Object Name)) {
            $usage.Cells[$index, 16].Value = $group.Name
            $known = @($group.Group | Where-Object { $null -ne $_.calls })
            $usage.Cells[$index, 17].Value = if ($known.Count) {
                [double] (($known | Measure-Object calls -Sum).Sum)
            } else { $null }
            $index++
        }
        $null = $usage.Tables.Add($usage.Cells[3, 16, ($index - 1), 17], 'tblUsageTrend')
        $chart = $usage.Drawings.AddChart('UsageTrend', [OfficeOpenXml.Drawing.Chart.eChartType]::Line)
        $chart.Title.Text = 'Observed monthly calls (boundary months may be partial)'
        $null = $chart.Series.Add('tblUsageTrend[Calls]', 'tblUsageTrend[Period]')
        $chart.SetPosition(2, 0, 19, 0); $chart.SetSize(800, 380)
    }
    if ($Models.Contains('capacity')) {
        $capacity = $Models.capacity
        $usage.Cells[1, 16].Value = 'Capacity P95: nearest-rank hourly average samples; units are current, not historical.'
        $usage.Cells[2, 16].Value = "P95=$($capacity.capacityP95); max=$($capacity.capacityMax); current units=$($capacity.units); samples=$($capacity.sampleCount)/$($capacity.expectedSamples)"
    }
    if (-not $Models.Contains('cost') -or $Models.cost.monthly.Count -eq 0) { return }
    $currencies = @($Models.cost.monthly.currency | Sort-Object -Unique)
    if ($currencies.Count -gt 16) { throw 'Cost charts exceed the supported 16 separate currency views.' }
    $currencyIndex = 0
    $first = 3
    foreach ($currency in $currencies) {
        $headers = @('Month', 'APIM', 'App Gateway', 'Logic Apps', 'Plans', 'Other')
        for ($column = 0; $column -lt $headers.Count; $column++) {
            $cost.Cells[$first, (13 + $column)].Value = $headers[$column]
        }
        $index = $first + 1
        foreach ($group in @($Models.cost.monthly | Where-Object currency -CEQ $currency |
                Group-Object month | Sort-Object Name)) {
            $cost.Cells[$index, 13].Value = $group.Name
            $amounts = @(0.0, 0.0, 0.0, 0.0, 0.0)
            foreach ($row in $group.Group) {
                $bucket = switch ($row.resourceType.ToLowerInvariant()) {
                    'microsoft.apimanagement/service' { 0 }
                    'microsoft.network/applicationgateways' { 1 }
                    'microsoft.logic/workflows' { 2 }
                    'microsoft.web/serverfarms' { 3 }
                    default { 4 }
                }
                $amounts[$bucket] += $row.cost
            }
            for ($column = 0; $column -lt 5; $column++) {
                $cost.Cells[$index, (14 + $column)].Value = $amounts[$column]
            }
            $index++
        }
        $name = "tblCostTrend$currencyIndex"
        $null = $cost.Tables.Add($cost.Cells[$first, 13, ($index - 1), 18], $name)
        $chart = $cost.Drawings.AddChart("CostTrend$currencyIndex", [OfficeOpenXml.Drawing.Chart.eChartType]::ColumnStacked)
        $chart.Title.Text = "Monthly resource cost / $currency (MTD may be partial)"
        foreach ($header in $headers | Select-Object -Skip 1) {
            $series = $chart.Series.Add("$name[$header]", "$name[Month]")
            $series.Header = $header
        }
        $chart.SetPosition(($first - 1), 0, 20, 0); $chart.SetSize(800, 380)
        $first = [math]::Max($index + 4, $first + 25)
        $currencyIndex++
    }
}
