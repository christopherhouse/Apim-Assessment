BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:templatePath = Join-Path $repoRoot 'template/ApimActionPlan.xlsx'
    $script:generatorPath = Join-Path (
        $repoRoot
    ) 'scripts/New-ApimActionPlanTemplate.ps1'
    $previousWarningPreference = $WarningPreference
    try {
        $WarningPreference = 'SilentlyContinue'
        Import-Module ImportExcel -RequiredVersion 7.8.10 -Force 3>$null
    }
    finally {
        $WarningPreference = $previousWarningPreference
    }
    $script:templatePackage = Open-ExcelPackage -Path $script:templatePath
    $script:expectedSheets = @(
        'Summary',
        'Action Plan',
        'Finding Details',
        'API Inventory',
        'Effective Policy Matrix',
        'Subscriptions',
        'Exposure Map',
        'Usage',
        'Cost',
        'Environment Drift',
        'Run Info',
        'Method & Rules'
    )
    $script:expectedTables = [ordered]@{
        'Action Plan' = @('tblActions')
        'Finding Details' = @('tblFindings')
        'API Inventory' = @('tblApis')
        'Effective Policy Matrix' = @('tblPolicy')
        'Subscriptions' = @('tblSubs')
        'Exposure Map' = @('tblExposure')
        'Usage' = @('tblUsage')
        'Cost' = @('tblCost')
        'Environment Drift' = @('tblDrift')
        'Run Info' = @('tblRun')
        'Method & Rules' = @('tblRules', 'tblWeights')
    }
}

AfterAll {
    if ($null -ne $script:templatePackage) {
        Close-ExcelPackage -ExcelPackage $script:templatePackage -NoSave
    }
    Remove-Module ImportExcel -Force -ErrorAction SilentlyContinue
}

Describe 'APIM action-plan workbook template' {
    It 'opens with the fixed sheet and named-table contract' {
        Test-Path -LiteralPath $script:templatePath -PathType Leaf |
            Should -BeTrue
        @($script:templatePackage.Workbook.Worksheets.Name) |
            Should -Be $script:expectedSheets

        foreach ($sheetName in $script:expectedTables.Keys) {
            $worksheet = $script:templatePackage.Workbook.Worksheets[
                $sheetName
            ]
            @($worksheet.Tables.Name) |
                Should -Be $script:expectedTables[$sheetName]
        }
    }

    It 'uses empty table rows with stable headers at row three' {
        $actions = $script:templatePackage.Workbook.Worksheets[
            'Action Plan'
        ].Tables['tblActions']
        @($actions.Columns.Name) | Should -Be @(
            'Rule ID',
            'Title',
            'Pillar',
            'Severity',
            'Evaluation',
            'Affected Count',
            'Finding Count',
            'Priority',
            'Top Affected Scopes',
            'Recommendation',
            'Effort',
            'Owner',
            'Status',
            'Target Date',
            'Notes'
        )

        foreach ($sheetName in $script:expectedTables.Keys) {
            $worksheet = $script:templatePackage.Workbook.Worksheets[
                $sheetName
            ]
            foreach ($tableName in $script:expectedTables[$sheetName]) {
                $table = $worksheet.Tables[$tableName]
                $table.Address.Start.Row | Should -Be 3
                $table.Address.Rows | Should -Be 2
                @($table.DataRange.Value | Where-Object {
                        $null -ne $_ -and [string] $_ -ne ''
                    }).Count | Should -Be 0
                $table.ShowFilter | Should -BeTrue
                $table.ShowRowStripes | Should -BeTrue
            }
        }
    }

    It 'keeps title styling, frozen headers, and report formatting' {
        foreach ($sheetName in $script:expectedTables.Keys) {
            $worksheet = $script:templatePackage.Workbook.Worksheets[
                $sheetName
            ]
            $worksheet.Cells[1, 1].Style.Fill.BackgroundColor.Rgb |
                Should -Be 'FF1F3864'
            $worksheet.Cells[1, 1].Style.Font.Color.Rgb |
                Should -Be 'FFFFFFFF'
            $worksheet.Cells[1, 1].Style.Font.Bold | Should -BeTrue

            $namespace = [System.Xml.XmlNamespaceManager]::new(
                $worksheet.WorksheetXml.NameTable
            )
            $namespace.AddNamespace(
                'd',
                'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
            )
            $pane = $worksheet.WorksheetXml.SelectSingleNode(
                '//d:sheetView/d:pane[@state="frozen"]',
                $namespace
            )
            $pane | Should -Not -BeNullOrEmpty
            $pane.GetAttribute('topLeftCell') | Should -Be 'A4'
        }

        $script:templatePackage.Workbook.Worksheets[
            'Action Plan'
        ].ConditionalFormatting.Count | Should -BeGreaterThan 0
        $script:templatePackage.Workbook.Worksheets[
            'Effective Policy Matrix'
        ].ConditionalFormatting.Count | Should -BeGreaterThan 0
        $script:templatePackage.Workbook.Worksheets[
            'Exposure Map'
        ].ConditionalFormatting.Count | Should -BeGreaterThan 0
    }

    It 'contains Summary formulas, assumptions, a chart, and top actions' {
        $summary = $script:templatePackage.Workbook.Worksheets['Summary']

        $summary.Cells[4, 1].Text |
            Should -Match '^ASSUMPTIONS AND DATA GAPS'
        $summary.Cells[7, 2].Formula |
            Should -Be (
                'ROWS(tblFindings[Rule ID])-' +
                'COUNTBLANK(tblFindings[Rule ID])'
            )
        $summary.Cells[8, 2].Formula |
            Should -Be 'COUNTIFS(tblFindings[Severity],"High")'
        $summary.Cells[13, 2].Formula |
            Should -Be (
                'COUNTIFS(tblFindings[Pillar],$A13,' +
                'tblFindings[Severity],B$12)'
            )
        $summary.Cells[8, 8].Formula |
                Should -Be 'IFERROR(INDEX(tblActions[Title],1),"")'
            $summary.Cells[8, 9].Formula |
                Should -Be 'IFERROR(INDEX(tblActions[Priority],1),"")'
        $summary.Drawings.Count | Should -Be 1
        $summary.Drawings[0].Name | Should -Be 'chtFindingsByPillar'
    }

    It 'provides the exact action tracking status dropdown' {
        $worksheet = $script:templatePackage.Workbook.Worksheets[
            'Action Plan'
        ]
        $worksheet.DataValidations.Count | Should -Be 1
        $validation = $worksheet.DataValidations[0]
        $validation.Address.Address | Should -Be 'M4:M10000'
        @($validation.Formula.Values) | Should -Be @(
            'Open',
            'In progress',
            'Done',
            'Accepted risk',
            'Not applicable'
        )
    }

    It 'regenerates a structurally equivalent workbook' {
        $generated = Join-Path $TestDrive 'ApimActionPlan.xlsx'

        & $script:generatorPath -Path $generated
        $package = Open-ExcelPackage -Path $generated
        try {
            @($package.Workbook.Worksheets.Name) |
                Should -Be $script:expectedSheets
            foreach ($sheetName in $script:expectedTables.Keys) {
                @($package.Workbook.Worksheets[$sheetName].Tables.Name) |
                    Should -Be $script:expectedTables[$sheetName]
            }
            $package.Workbook.Worksheets['Summary'].Drawings.Count |
                Should -Be 1
        }
        finally {
            Close-ExcelPackage -ExcelPackage $package -NoSave
        }
    }

    It 'refuses to overwrite a workbook unless Force is explicit' {
        $generated = Join-Path $TestDrive 'existing.xlsx'

        & $script:generatorPath -Path $generated
        {
            & $script:generatorPath -Path $generated
        } | Should -Throw '*already exists*'
        {
            & $script:generatorPath -Path $generated -Force
        } | Should -Not -Throw
    }
}
