#Requires -Version 7.4
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Path = (
        Join-Path (Split-Path $PSScriptRoot -Parent) (
            'template/ApimActionPlan.xlsx'
        )
    ),

    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$previousWarningPreference = $WarningPreference
try {
    $WarningPreference = 'SilentlyContinue'
    Import-Module ImportExcel -RequiredVersion 7.8.10 -Force `
        -ErrorAction Stop 3>$null
}
finally {
    $WarningPreference = $previousWarningPreference
}

$navy = [System.Drawing.ColorTranslator]::FromHtml('#1F3864')
$white = [System.Drawing.Color]::White
$lightBlue = [System.Drawing.ColorTranslator]::FromHtml('#D9EAF7')
$paleYellow = [System.Drawing.ColorTranslator]::FromHtml('#FFF2CC')
$darkGray = [System.Drawing.ColorTranslator]::FromHtml('#595959')
$maxDataRow = 10000

function Get-ApimTemplateDefinition {
    [CmdletBinding()]
    param()

    return @(
        [ordered]@{
            Worksheet = 'Action Plan'
            TableName = 'tblActions'
            Title = 'APIM Assessment Action Plan'
            Subtitle = 'Prioritized actions with owner-managed tracking fields'
            Headers = @(
                'Rule ID', 'Title', 'Pillar', 'Severity', 'Evaluation',
                'Affected Count', 'Finding Count', 'Priority',
                'Top Affected Scopes', 'Recommendation', 'Effort', 'Owner',
                'Status', 'Target Date', 'Notes'
            )
        }
        [ordered]@{
            Worksheet = 'Finding Details'
            TableName = 'tblFindings'
            Title = 'Finding Details'
            Subtitle = 'One row per deterministic rule and target finding'
            Headers = @(
                'Finding Key', 'Rule ID', 'Title', 'Pillar', 'MCSB', 'Severity',
                'Scope', 'Resource', 'Exposure', 'Usage', 'Priority', 'Evidence',
                'Evidence Text', 'Recommendation', 'Effort', 'Source Files',
                'Evaluation', 'Owner', 'Status', 'Target Date', 'Notes'
            )
        }
        [ordered]@{
            Worksheet = 'API Inventory'
            TableName = 'tblApis'
            Title = 'API Inventory'
            Subtitle = 'Normalized API catalog, policy, exposure, and usage facts'
            Headers = @(
                'API ID', 'Display Name', 'Path', 'API Type', 'Protocols',
                'Backend Host', 'Products', 'Owner Tag', 'Tags', 'Version Set',
                'Version', 'Revision Count', 'Non-current Online Revisions',
                'Operation Count', 'Subscription Required', 'Caller Auth',
                'Throttling', 'IP Filter', 'Unsafe CORS', 'Backend Auth',
                'Hard-coded Secret', 'Base Missing', 'Mock or Trace',
                'Backend TLS Validation', 'Body Logging',
                'Sensitive Headers Logged', 'Reachability', 'Exposure',
                'Calls 90d', 'Calls via App Gateway', 'Calls Internal',
                'Last Call', 'P95 ms', 'Backend P95 ms', '5xx Percent',
                'OpenAPI Score', 'In Git', 'Finding IDs', 'Model Status',
                'Missing Inputs'
            )
        }
        [ordered]@{
            Worksheet = 'Effective Policy Matrix'
            TableName = 'tblPolicy'
            Title = 'Effective Policy Matrix'
            Subtitle = 'Effective policy control coverage by API'
            Headers = @(
                'API ID', 'Evaluation Status', 'Caller Auth', 'Rate Limit',
                'IP Filter', 'CORS Safe', 'Backend Auth',
                'No Hard-coded Secret', 'Base Present', 'No Mock or Trace',
                'Model Status', 'Missing Inputs'
            )
        }
        [ordered]@{
            Worksheet = 'Subscriptions'
            TableName = 'tblSubs'
            Title = 'Subscriptions'
            Subtitle = 'Secret-free subscription scope, owner type, and usage'
            Headers = @(
                'Subscription ID', 'Display Name', 'Scope Type', 'Scope Target',
                'State', 'Owner Type', 'Created Date', 'Expiration Date',
                'Allow Tracing', 'Calls 90d', 'Last Used', 'Built-in Master',
                'Flags', 'Model Status', 'Missing Inputs'
            )
        }
        [ordered]@{
            Worksheet = 'Exposure Map'
            TableName = 'tblExposure'
            Title = 'Exposure Map'
            Subtitle = 'Published route and reachability classification'
            Headers = @(
                'Route Key', 'Gateway', 'Listener', 'Listener Host',
                'Backend Host', 'Frontend Type', 'Rule Type', 'Pattern',
                'WAF State', 'WAF Mode', 'Edge', 'API ID', 'Reachability',
                'Restriction', 'Exposure', 'Calls via App Gateway',
                'Calls Internal', 'Confidence', 'Base Missing Bypass',
                'Restricted Operations', 'Model Status', 'Missing Inputs'
            )
        }
        [ordered]@{
            Worksheet = 'Usage'
            TableName = 'tblUsage'
            Title = 'Usage'
            Subtitle = 'API request volume, latency, and error telemetry'
            Headers = @(
                'Period', 'API ID', 'Calls', 'Calls via App Gateway',
                'Calls Internal', 'Last Call', 'P50 ms', 'P95 ms',
                'Backend P95 ms', '4xx Percent', '5xx Percent', 'Model Status',
                'Missing Inputs'
            )
        }
        [ordered]@{
            Worksheet = 'Cost'
            TableName = 'tblCost'
            Title = 'Cost'
            Subtitle = 'Monthly service cost and normalized usage indicators'
            Headers = @(
                'Month', 'Scope', 'Service', 'Cost', 'Currency', 'Calls',
                'Cost per Million Calls', 'Change Percent', 'Model Status',
                'Missing Inputs'
            )
        }
        [ordered]@{
            Worksheet = 'Environment Drift'
            TableName = 'tblDrift'
            Title = 'Environment Drift'
            Subtitle = 'Normalized differences between assessed environments'
            Headers = @(
                'Category', 'Key', 'Change Type', 'Environment A',
                'Environment B', 'Previous Value', 'Current Value', 'Severity',
                'Notes'
            )
        }
        [ordered]@{
            Worksheet = 'Run Info'
            TableName = 'tblRun'
            Title = 'Run Information'
            Subtitle = 'Manifest stages, collectors, windows, and tool versions'
            Headers = @(
                'Section', 'Name', 'Status', 'Items', 'Errors', 'Duration Sec',
                'Started UTC', 'Completed UTC', 'Window', 'Value'
            )
        }
    )
}

function Add-ApimTemplateTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [OfficeOpenXml.ExcelWorksheet] $Worksheet,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TableName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Headers,

        [int] $StartColumn = 1
    )

    $startRow = 3
    $endColumn = $StartColumn + $Headers.Count - 1
    for ($index = 0; $index -lt $Headers.Count; $index++) {
        $column = $StartColumn + $index
        $Worksheet.Cells[$startRow, $column].Value = $Headers[$index]
        $Worksheet.Cells[($startRow + 1), $column].Value = $null
        $width = switch -Regex ($Headers[$index]) {
            'Recommendation|Evidence|Notes|Affected Scopes|Missing Inputs' {
                34
                break
            }
            'Display Name|Title|Previous Value|Current Value' {
                26
                break
            }
            'Key|Resource|Host|Files|Operations|Finding IDs' {
                24
                break
            }
            'Date|Call|Month|Period' {
                18
                break
            }
            default {
                16
            }
        }
        $Worksheet.Column($column).Width = $width
    }

    $range = $Worksheet.Cells[
        $startRow,
        $StartColumn,
        ($startRow + 1),
        $endColumn
    ]
    $table = $Worksheet.Tables.Add($range, $TableName)
    $table.TableStyle = [OfficeOpenXml.Table.TableStyles]::Medium2
    $table.ShowFilter = $true
    $table.ShowRowStripes = $true
    return $table
}

function Add-ApimConditionalText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [OfficeOpenXml.ExcelWorksheet] $Worksheet,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Address,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $BackgroundColor,

        [string] $ForegroundColor = 'Black'
    )

    Add-ConditionalFormatting -Worksheet $Worksheet -Address $Address `
        -RuleType ContainsText -ConditionValue $Value `
        -BackgroundColor $BackgroundColor -ForegroundColor $ForegroundColor `
        | Out-Null
}

function Format-ApimTemplateWorksheet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [OfficeOpenXml.ExcelWorksheet] $Worksheet,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Title,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Subtitle,

        [Parameter(Mandatory)]
        [ValidateRange(1, 200)]
        [int] $LastColumn
    )

    $Worksheet.Cells[1, 1, 1, $LastColumn].Merge = $true
    $Worksheet.Cells[1, 1].Value = $Title
    $Worksheet.Cells[1, 1, 1, $LastColumn].Style.Fill.PatternType = 'Solid'
    $Worksheet.Cells[1, 1, 1, $LastColumn].Style.Fill.BackgroundColor.SetColor(
        $navy
    )
    $Worksheet.Cells[1, 1, 1, $LastColumn].Style.Font.Color.SetColor($white)
    $Worksheet.Cells[1, 1, 1, $LastColumn].Style.Font.Bold = $true
    $Worksheet.Cells[1, 1, 1, $LastColumn].Style.Font.Size = 16
    $Worksheet.Cells[1, 1, 1, $LastColumn].Style.VerticalAlignment = 'Center'
    $Worksheet.Row(1).Height = 26

    $Worksheet.Cells[2, 1, 2, $LastColumn].Merge = $true
    $Worksheet.Cells[2, 1].Value = $Subtitle
    $Worksheet.Cells[2, 1, 2, $LastColumn].Style.Fill.PatternType = 'Solid'
    $Worksheet.Cells[2, 1, 2, $LastColumn].Style.Fill.BackgroundColor.SetColor(
        $lightBlue
    )
    $Worksheet.Cells[2, 1, 2, $LastColumn].Style.Font.Color.SetColor($darkGray)
    $Worksheet.Cells[2, 1, 2, $LastColumn].Style.Font.Italic = $true
    $Worksheet.Row(2).Height = 20
    $Worksheet.View.FreezePanes(4, 1)
    $Worksheet.View.ShowGridLines = $false
}

$fullPath = [System.IO.Path]::GetFullPath($Path)
if ((Test-Path -LiteralPath $fullPath) -and -not $Force) {
    throw "Workbook template already exists at '$fullPath'. Use -Force to replace it."
}
if (-not $PSCmdlet.ShouldProcess($fullPath, 'Generate APIM action-plan template')) {
    return
}

$directory = Split-Path $fullPath -Parent
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$temporaryPath = Join-Path $directory (
    ".ApimActionPlan.$([guid]::NewGuid().ToString('N')).tmp.xlsx"
)
$package = $null
try {
    $package = Open-ExcelPackage -Path $temporaryPath -Create
    $package.Workbook.Properties.Title = 'APIM Assessment Action Plan'
    $package.Workbook.Properties.Subject = (
        'Customer-neutral deterministic assessment workbook template'
    )
    $package.Workbook.Properties.Author = (
        'APIM Assessment Toolkit contributors'
    )
    $package.Workbook.Properties.Comments = (
        'Generated by scripts/New-ApimActionPlanTemplate.ps1'
    )

    $summary = $package.Workbook.Worksheets.Add('Summary')
    $summary.View.ShowGridLines = $false
    $summary.Cells[1, 1, 1, 10].Merge = $true
    $summary.Cells[1, 1].Value = 'APIM Assessment Summary'
    $summary.Cells[1, 1, 1, 10].Style.Fill.PatternType = 'Solid'
    $summary.Cells[1, 1, 1, 10].Style.Fill.BackgroundColor.SetColor($navy)
    $summary.Cells[1, 1, 1, 10].Style.Font.Color.SetColor($white)
    $summary.Cells[1, 1, 1, 10].Style.Font.Bold = $true
    $summary.Cells[1, 1, 1, 10].Style.Font.Size = 18
    $summary.Row(1).Height = 30
    $summary.Cells[2, 1, 2, 10].Merge = $true
    $summary.Cells[2, 1].Value = (
        'Deterministic findings, priorities, assumptions, and data gaps'
    )
    $summary.Cells[2, 1, 2, 10].Style.Fill.PatternType = 'Solid'
    $summary.Cells[2, 1, 2, 10].Style.Fill.BackgroundColor.SetColor($lightBlue)
    $summary.Cells[4, 1, 5, 10].Merge = $true
    $summary.Cells[4, 1].Value = (
        'ASSUMPTIONS AND DATA GAPS - populated from the run manifest during ' +
        'report rendering. NotEvaluated findings remain visible.'
    )
    $summary.Cells[4, 1, 5, 10].Style.Fill.PatternType = 'Solid'
    $summary.Cells[4, 1, 5, 10].Style.Fill.BackgroundColor.SetColor($paleYellow)
    $summary.Cells[4, 1, 5, 10].Style.Font.Bold = $true
    $summary.Cells[4, 1, 5, 10].Style.WrapText = $true

    $summary.Cells[7, 1].Value = 'Total Findings'
    $summary.Cells[7, 2].Formula = (
        'ROWS(tblFindings[Rule ID])-COUNTBLANK(tblFindings[Rule ID])'
    )
    $summary.Cells[8, 1].Value = 'High Severity'
    $summary.Cells[8, 2].Formula = (
        'COUNTIFS(tblFindings[Severity],"High")'
    )
    $summary.Cells[9, 1].Value = 'Not Evaluated'
    $summary.Cells[9, 2].Formula = (
        'COUNTIFS(tblFindings[Evaluation],"NotEvaluated")'
    )
    $summary.Cells[10, 1].Value = 'Published APIs'
    $summary.Cells[10, 2].Formula = (
        'ROWS(tblApis[API ID])-COUNTBLANK(tblApis[API ID])'
    )
    $summary.Cells[7, 1, 10, 1].Style.Font.Bold = $true
    $summary.Cells[7, 1, 10, 2].Style.Border.BorderAround(
        [OfficeOpenXml.Style.ExcelBorderStyle]::Thin
    )

    $summary.Cells[12, 1].Value = 'Pillar'
    $severities = @('High', 'Medium', 'Low', 'Info')
    for ($index = 0; $index -lt $severities.Count; $index++) {
        $summary.Cells[12, ($index + 2)].Value = $severities[$index]
    }
    $pillars = @(
        'Security',
        'Reliability',
        'OperationalExcellence',
        'CostOptimization',
        'PerformanceEfficiency'
    )
    for ($rowIndex = 0; $rowIndex -lt $pillars.Count; $rowIndex++) {
        $row = 13 + $rowIndex
        $summary.Cells[$row, 1].Value = $pillars[$rowIndex]
        for ($column = 2; $column -le 5; $column++) {
            $summary.Cells[$row, $column].Formula = (
                'COUNTIFS(tblFindings[Pillar],$A' + $row +
                ',tblFindings[Severity],' +
                $summary.Cells[12, $column].Address.Replace('12', '$12') + ')'
            )
        }
    }
    $summary.Cells[12, 1, 12, 5].Style.Fill.PatternType = 'Solid'
    $summary.Cells[12, 1, 12, 5].Style.Fill.BackgroundColor.SetColor($navy)
    $summary.Cells[12, 1, 12, 5].Style.Font.Color.SetColor($white)
    $summary.Cells[12, 1, 12, 5].Style.Font.Bold = $true

    $summary.Cells[7, 7].Value = 'Top 5 Action Items'
    $summary.Cells[7, 7, 7, 10].Merge = $true
    $summary.Cells[7, 7, 7, 10].Style.Fill.PatternType = 'Solid'
    $summary.Cells[7, 7, 7, 10].Style.Fill.BackgroundColor.SetColor($navy)
    $summary.Cells[7, 7, 7, 10].Style.Font.Color.SetColor($white)
    $summary.Cells[7, 7, 7, 10].Style.Font.Bold = $true
    for ($rank = 1; $rank -le 5; $rank++) {
        $row = 7 + $rank
        $summary.Cells[$row, 7].Value = $rank
        $summary.Cells[$row, 8].Formula = (
            "IFERROR(INDEX(tblActions[Title],$rank),`"`")"
        )
        $summary.Cells[$row, 9].Formula = (
            "IFERROR(INDEX(tblActions[Priority],$rank),`"`")"
        )
    }
    $summary.Cells[7, 1, 17, 10].Style.VerticalAlignment = 'Center'
    $summary.Column(1).Width = 28
    $summary.Column(2).Width = 14
    $summary.Column(7).Width = 8
    $summary.Column(8).Width = 34
    $summary.Column(9).Width = 14
    $summary.Column(10).Width = 18
    $summary.View.FreezePanes(7, 1)

    $chart = $summary.Drawings.AddChart(
        'chtFindingsByPillar',
        [OfficeOpenXml.Drawing.Chart.eChartType]::ColumnClustered
    )
    $chart.Title.Text = 'Findings by Pillar and Severity'
    for ($column = 2; $column -le 5; $column++) {
        $series = $chart.Series.Add(
            $summary.Cells[13, $column, 17, $column],
            $summary.Cells[13, 1, 17, 1]
        )
        $series.Header = [string] $summary.Cells[12, $column].Value
    }
    $chart.SetPosition(18, 0, 0, 0)
    $chart.SetSize(720, 320)

    foreach ($definition in Get-ApimTemplateDefinition) {
        $worksheet = $package.Workbook.Worksheets.Add(
            [string] $definition.Worksheet
        )
        $null = Add-ApimTemplateTable -Worksheet $worksheet `
            -TableName $definition.TableName -Headers $definition.Headers
        Format-ApimTemplateWorksheet -Worksheet $worksheet `
            -Title $definition.Title -Subtitle $definition.Subtitle `
            -LastColumn $definition.Headers.Count
    }

    $method = $package.Workbook.Worksheets.Add('Method & Rules')
    $ruleHeaders = @(
        'Rule ID', 'Title', 'Pillar', 'MCSB', 'Severity', 'Scope', 'Requires',
        'Recommendation', 'Effort', 'Enabled'
    )
    $weightHeaders = @('Dimension', 'Value', 'Weight')
    $null = Add-ApimTemplateTable -Worksheet $method -TableName 'tblRules' `
        -Headers $ruleHeaders
    $weightColumn = $ruleHeaders.Count + 3
    $null = Add-ApimTemplateTable -Worksheet $method -TableName 'tblWeights' `
        -Headers $weightHeaders -StartColumn $weightColumn
    Format-ApimTemplateWorksheet -Worksheet $method -Title 'Method & Rules' `
        -Subtitle 'Implemented catalog and editable priority weights' `
        -LastColumn ($weightColumn + $weightHeaders.Count - 1)

    $actionSheet = $package.Workbook.Worksheets['Action Plan']
    $findingSheet = $package.Workbook.Worksheets['Finding Details']
    foreach ($entry in @(
            @{ Sheet = $actionSheet; Column = 'D' }
            @{ Sheet = $findingSheet; Column = 'F' }
        )) {
        Add-ApimConditionalText -Worksheet $entry.Sheet `
            -Address "$($entry.Column)4:$($entry.Column)$maxDataRow" `
            -Value High -BackgroundColor '#F4CCCC' -ForegroundColor '#9C0006'
        Add-ApimConditionalText -Worksheet $entry.Sheet `
            -Address "$($entry.Column)4:$($entry.Column)$maxDataRow" `
            -Value Medium -BackgroundColor '#FCE5CD' `
            -ForegroundColor '#9C5700'
        Add-ApimConditionalText -Worksheet $entry.Sheet `
            -Address "$($entry.Column)4:$($entry.Column)$maxDataRow" `
            -Value Low -BackgroundColor '#FFF2CC' -ForegroundColor '#7F6000'
        Add-ApimConditionalText -Worksheet $entry.Sheet `
            -Address "$($entry.Column)4:$($entry.Column)$maxDataRow" `
            -Value Info -BackgroundColor '#D9EAF7' -ForegroundColor '#1F4E78'
    }

    $policySheet = $package.Workbook.Worksheets['Effective Policy Matrix']
    foreach ($column in 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J') {
        Add-ApimConditionalText -Worksheet $policySheet `
            -Address "${column}4:${column}$maxDataRow" -Value Fail `
            -BackgroundColor '#F4CCCC' -ForegroundColor '#9C0006'
        Add-ApimConditionalText -Worksheet $policySheet `
            -Address "${column}4:${column}$maxDataRow" -Value Pass `
            -BackgroundColor '#D9EAD3' -ForegroundColor '#274E13'
        Add-ApimConditionalText -Worksheet $policySheet `
            -Address "${column}4:${column}$maxDataRow" -Value NA `
            -BackgroundColor '#E7E6E6' -ForegroundColor '#595959'
    }

    foreach ($entry in @(
            @{ Sheet = $package.Workbook.Worksheets['API Inventory']; Column = 'AB' }
            @{ Sheet = $package.Workbook.Worksheets['Exposure Map']; Column = 'O' }
        )) {
        foreach ($rule in @(
                @{ Value = 'DirectPublic'; Back = '#F4CCCC'; Fore = '#9C0006' }
                @{ Value = 'External'; Back = '#FCE5CD'; Fore = '#9C5700' }
                @{ Value = 'Restricted'; Back = '#FFF2CC'; Fore = '#7F6000' }
                @{ Value = 'Internal'; Back = '#D9EAD3'; Fore = '#274E13' }
                @{ Value = 'Unknown'; Back = '#E7E6E6'; Fore = '#595959' }
            )) {
            Add-ApimConditionalText -Worksheet $entry.Sheet `
                -Address "$($entry.Column)4:$($entry.Column)$maxDataRow" `
                -Value $rule.Value -BackgroundColor $rule.Back `
                -ForegroundColor $rule.Fore
        }
    }

    $statusValidation = $actionSheet.DataValidations.AddListValidation(
        "M4:M$maxDataRow"
    )
    foreach ($status in @(
            'Open',
            'In progress',
            'Done',
            'Accepted risk',
            'Not applicable'
        )) {
        $statusValidation.Formula.Values.Add($status)
    }
    $statusValidation.ShowErrorMessage = $true
    $statusValidation.ErrorTitle = 'Invalid status'
    $statusValidation.Error = 'Select a status from the list.'
    $actionSheet.Cells["N4:N$maxDataRow"].Style.Numberformat.Format = (
        'yyyy-mm-dd'
    )
    $findingSheet.Cells["T4:T$maxDataRow"].Style.Numberformat.Format = (
        'yyyy-mm-dd'
    )

    Close-ExcelPackage -ExcelPackage $package
    $package = $null
    Move-Item -LiteralPath $temporaryPath -Destination $fullPath -Force
}
catch {
    if ($null -ne $package) {
        $package.Dispose()
    }
    if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
    throw
}
