$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

BeforeAll {
    Import-Module ImportExcel -RequiredVersion 7.8.10 -Force 3>$null
}

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
    Remove-Module -Name ImportExcel -Force -ErrorAction SilentlyContinue
}

Describe 'Private action-plan workbook writer' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)

        $script:reportRepoRoot = $RepoRoot

        BeforeAll {
            function Get-ReportFixtureModel {
                $root = Join-Path $script:reportRepoRoot (
                    'tests/fixtures/synthetic-reference/model'
                )
                $models = [ordered]@{}
                foreach ($name in @(
                        'service', 'apis', 'operations', 'policyMatrix',
                        'subscriptions', 'namedValues', 'backends',
                        'certificates', 'network', 'exposure'
                    )) {
                    $fileName = if ($name -eq 'apis') {
                        'apis.exposure.json'
                    }
                    else {
                        "$name.json"
                    }
                    $models[$name] = Get-Content -LiteralPath (
                        Join-Path $root $fileName
                    ) -Raw | ConvertFrom-Json -Depth 100 -NoEnumerate
                }
                return $models
            }

            function Get-ReportFinding {
                param(
                    [string] $RuleId = 'APIM-SEC-003',
                    [string] $Title = 'Synthetic caller authentication check',
                    [string] $Pillar = 'Security',
                    [string] $Mcsb = 'IM-1',
                    [string] $Scope = 'api:orders-v1',
                    [double] $PriorityScore = 9,
                    [ValidateSet('Evaluated', 'NotEvaluated')]
                    [string] $Evaluation = 'Evaluated'
                )

                $notEvaluated = $Evaluation -eq 'NotEvaluated'
                return [pscustomobject][ordered]@{
                    findingKey = (
                        "$RuleId|apim-example-prod|$Scope"
                    )
                    ruleId = $RuleId
                    title = $Title
                    pillar = $Pillar
                    mcsb = $Mcsb
                    severity = if ($notEvaluated) { 'Info' } else { 'High' }
                    scope = $Scope
                    resource = 'apim-example-prod'
                    exposure = if ($notEvaluated) {
                        'Unknown'
                    }
                    else {
                        'DirectPublic'
                    }
                    usage = $null
                    priorityScore = $PriorityScore
                    evidence = if ($notEvaluated) {
                        @{ missingInputs = @('model/apis.json') }
                    }
                    else {
                        @{ callerAuth = 'None' }
                    }
                    evidenceText = 'Synthetic evidence'
                    recommendation = 'Use caller authentication.'
                    effort = 'M'
                    sourceFiles = @('model/apis.json')
                    status = 'Open'
                    evaluation = $Evaluation
                }
            }

            function Get-ReportFixtureRun {
                param(
                    [Parameter(Mandatory)]
                    [string] $Name
                )

                $config = Import-PowerShellDataFile (
                    Join-Path $script:reportRepoRoot 'config/sample.psd1'
                )
                $config.Output.Root = Join-Path $TestDrive $Name
                $run = New-ApimRun -Config $config -EnvironmentName Prod `
                    -TenantId '00000000-0000-0000-0000-000000000002' `
                    -Operator Synthetic -RunId 'synthetic-report' `
                    -StartedUtc ([datetimeoffset] '2026-10-13T12:00:00Z')
                $null = Write-ApimModelSet -RunPath $run.Path `
                    -Models (Get-ReportFixtureModel)
                $findings = @(
                    Get-ReportFinding -Scope 'api:orders-v1' -PriorityScore 9
                    Get-ReportFinding -Scope 'api:status-v1' -PriorityScore 6
                    Get-ReportFinding -RuleId 'APIM-GOV-001' `
                        -Title 'Synthetic product membership gap' `
                        -Pillar OperationalExcellence -Mcsb 'AM-1' `
                        -Scope 'missing-input' -PriorityScore 0.5 `
                        -Evaluation NotEvaluated
                )
                $null = Write-ApimFindingSet -RunPath $run.Path `
                    -Findings $findings
                return [pscustomobject]@{
                    RunPath = $run.Path
                    Findings = $findings
                }
            }

            function Get-ReportTableCell {
                [CmdletBinding()]
                param(
                    [Parameter(Mandatory)]
                    [object] $Table,

                    [Parameter(Mandatory)]
                    [int] $DataRow,

                    [Parameter(Mandatory)]
                    [int] $Column
                )

                $cell = $Table.WorkSheet.Cells[
                    ($Table.Address.Start.Row + $DataRow),
                    ($Table.Address.Start.Column + $Column - 1)
                ]
                $PSCmdlet.WriteObject($cell, $false)
            }
        }

        It 'renders validated run data into the current MVP workbook sheets' {
            $fixture = Get-ReportFixtureRun -Name 'complete'

            $path = Export-ApimActionPlan -RunPath $fixture.RunPath

            $path | Should -BeOfType [string]
            [System.IO.Path]::GetFileName($path) |
                Should -Be (
                    'Example APIM Assessment - Prod - 2026-10-13.xlsx'
                )
            Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
            $package = Open-ExcelPackage -Path $path
            try {
                @($package.Workbook.Worksheets.Name) |
                    Should -Contain 'Action Plan'
                $actionSheet = $package.Workbook.Worksheets['Action Plan']
                $actionSheet.Tables.Count | Should -Be 1
                $actions = $actionSheet.Tables['tblActions']
                $details = $package.Workbook.Worksheets[
                    'Finding Details'
                ].Tables['tblFindings']
                $apis = $package.Workbook.Worksheets[
                    'API Inventory'
                ].Tables['tblApis']
                $policy = $package.Workbook.Worksheets[
                    'Effective Policy Matrix'
                ].Tables['tblPolicy']
                $subscriptions = $package.Workbook.Worksheets[
                    'Subscriptions'
                ].Tables['tblSubs']
                $exposure = $package.Workbook.Worksheets[
                    'Exposure Map'
                ].Tables['tblExposure']

                $actions.Address.Rows | Should -Be 3
                $details.Address.Rows | Should -Be 4
                $apis.Address.Rows | Should -Be 3
                $policy.Address.Rows | Should -Be 3
                $subscriptions.Address.Rows | Should -Be 7
                $exposure.Address.Rows | Should -Be 3
                (Get-ReportTableCell -Table $actions -DataRow 1 `
                    -Column 1).Text |
                    Should -Be 'APIM-SEC-003'
                (Get-ReportTableCell -Table $actions -DataRow 1 `
                    -Column 6).Value | Should -Be 2
                (Get-ReportTableCell -Table $actions -DataRow 1 `
                    -Column 8).Value | Should -Be 9
                (Get-ReportTableCell -Table $details -DataRow 1 `
                    -Column 1).Text |
                    Should -Be $fixture.Findings[0].findingKey
                (Get-ReportTableCell -Table $apis -DataRow 1 `
                    -Column 1).Text | Should -Be 'orders-v1'
                (Get-ReportTableCell -Table $policy -DataRow 1 `
                    -Column 4).Text | Should -Be 'Fail'
                (Get-ReportTableCell -Table $subscriptions -DataRow 1 `
                    -Column 1).Text |
                    Should -Be 'api-client'
                (Get-ReportTableCell -Table $exposure -DataRow 1 `
                    -Column 1).Text |
                    Should -Match '^agw-synthetic-prod'

                $summary = $package.Workbook.Worksheets['Summary']
                $summary.Cells[4, 1].Text |
                    Should -Match 'NotEvaluated findings: 1'
                $summary.Cells[7, 2].Formula |
                    Should -Be (
                        'ROWS(tblFindings[Rule ID])-' +
                        'COUNTBLANK(tblFindings[Rule ID])'
                    )
                ($details.Address.Rows - 1) |
                    Should -Be $fixture.Findings.Count
                $summary.Drawings.Count | Should -Be 1

                $exposureSheet = $package.Workbook.Worksheets['Exposure Map']
                $exposureSheet.Cells[3, 25].Text | Should -Be 'Internal'
                $exposureSheet.Cells[5, 25].Text | Should -Be 'Restricted'
                $exposureSheet.Cells[10, 25].Text | Should -Be 'Complete'

                foreach ($entry in @(
                        @{ Sheet = 'Usage'; Table = 'tblUsage' }
                        @{ Sheet = 'Cost'; Table = 'tblCost' }
                        @{
                            Sheet = 'Environment Drift'
                            Table = 'tblDrift'
                        }
                        @{ Sheet = 'Run Info'; Table = 'tblRun' }
                        @{ Sheet = 'Method & Rules'; Table = 'tblRules' }
                        @{ Sheet = 'Method & Rules'; Table = 'tblWeights' }
                    )) {
                    $table = $package.Workbook.Worksheets[
                        $entry.Sheet
                    ].Tables[$entry.Table]
                    $table.Address.Rows | Should -Be 2
                    for ($column = 1;
                        $column -le $table.Address.Columns;
                        $column++) {
                        (Get-ReportTableCell -Table $table -DataRow 1 `
                            -Column $column).Value | Should -BeNullOrEmpty
                    }
                }
            }
            finally {
                Close-ExcelPackage -ExcelPackage $package -NoSave
            }
        }

        It 'appends a numeric suffix instead of overwriting a report' {
            $fixture = Get-ReportFixtureRun -Name 'suffix'

            $first = Export-ApimActionPlan -RunPath $fixture.RunPath
            $firstHash = (
                Get-FileHash -LiteralPath $first -Algorithm SHA256
            ).Hash
            $second = Export-ApimActionPlan -RunPath $fixture.RunPath

            [System.IO.Path]::GetFileName($second) |
                Should -Be (
                    'Example APIM Assessment - Prod - 2026-10-13-2.xlsx'
                )
            (Get-FileHash -LiteralPath $first -Algorithm SHA256).Hash |
                Should -Be $firstHash
        }

        It 'fails before output when findings are invalid' {
            $fixture = Get-ReportFixtureRun -Name 'invalid-findings'
            Set-Content -LiteralPath (
                Join-Path $fixture.RunPath 'findings.json'
            ) -Value '[{"unexpected":true}]'

            {
                Export-ApimActionPlan -RunPath $fixture.RunPath
            } | Should -Throw 'Findings failed schema validation.'
            @(Get-ChildItem -LiteralPath (
                    Join-Path $fixture.RunPath 'report'
                ) -File).Count | Should -Be 0
        }

        It 'fails before output when a registered model is missing' {
            $fixture = Get-ReportFixtureRun -Name 'missing-model'
            Remove-Item -LiteralPath (
                Join-Path $fixture.RunPath 'model/apis.json'
            )

            {
                Export-ApimActionPlan -RunPath $fixture.RunPath
            } | Should -Throw "Required model 'apis' was unavailable."
            @(Get-ChildItem -LiteralPath (
                    Join-Path $fixture.RunPath 'report'
                ) -File).Count | Should -Be 0
        }

        It 'rejects an incompatible template without leaving partial output' {
            $fixture = Get-ReportFixtureRun -Name 'bad-template'
            $template = Join-Path $TestDrive 'bad-template.xlsx'
            Copy-Item -LiteralPath $script:ApimReportTemplatePath `
                -Destination $template
            $package = Open-ExcelPackage -Path $template
            $package.Workbook.Worksheets.Delete('Action Plan')
            Close-ExcelPackage -ExcelPackage $package

            {
                Export-ApimActionPlan -RunPath $fixture.RunPath `
                    -TemplatePath $template
            } | Should -Throw (
                "Report template worksheet 'Action Plan' was unavailable."
            )
            @(Get-ChildItem -LiteralPath (
                    Join-Path $fixture.RunPath 'report'
                ) -File).Count | Should -Be 0
        }

        It 'rejects unsafe manifest filename components' {
            $fixture = Get-ReportFixtureRun -Name 'unsafe-name'
            $manifest = Get-RunManifest -RunPath $fixture.RunPath
            $manifest.customer = '../unsafe'
            $null = Save-RunManifest -RunPath $fixture.RunPath `
                -Manifest $manifest

            {
                Export-ApimActionPlan -RunPath $fixture.RunPath
            } | Should -Throw (
                'Report filename component contains unsupported characters.'
            )
        }

        It 'enforces the template row boundary' {
            {
                Assert-ApimReportRowCount -Count 9998 `
                    -TableName 'tblFindings'
            } | Should -Throw (
                "Report table 'tblFindings' exceeds the 9,997-row " +
                'template limit.'
            )
            {
                Assert-ApimReportRowCount -Count 9997 `
                    -TableName 'tblFindings'
            } | Should -Not -Throw
        }
    }
}
