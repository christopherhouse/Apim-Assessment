$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Restricted report lifecycle' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)
        $script:lifecycleRepo = $RepoRoot

        BeforeAll {
            . (Join-Path $script:lifecycleRepo 'tests/helpers/New-SyntheticCollectedRun.ps1')
            $script:lifecycleTemplate = Join-Path $TestDrive 'lifecycle-template.xlsx'
            & (Join-Path $script:lifecycleRepo 'scripts/New-ApimActionPlanTemplate.ps1') `
                -Path $script:lifecycleTemplate
            $script:originalTemplate = $script:ApimReportTemplatePath
            $script:ApimReportTemplatePath = $script:lifecycleTemplate
            Import-ApimReportDependency

            function Get-LifecycleCell {
                param($Package, $Sheet, $Table, $Header, [int] $Row = 1)
                $tableObject = $Package.Workbook.Worksheets[$Sheet].Tables[$Table]
                $column = [array]::IndexOf(@($tableObject.Columns.Name), $Header) + $tableObject.Address.Start.Column
                return ,$Package.Workbook.Worksheets[$Sheet].Cells[($tableObject.Address.Start.Row + $Row), $column]
            }
        }
        AfterAll { $script:ApimReportTemplatePath = $script:originalTemplate }
        BeforeEach {
            $inputRun = New-SyntheticCollectedRun -RepoRoot $script:lifecycleRepo `
                -OutputRoot (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
            $script:lifecycleRun = $inputRun.Run.Path
            $script:lifecycleConfig = $inputRun.Config
            (Invoke-ApimAnalyze -RunFolder $script:lifecycleRun).ExitCode | Should -Be 0
            $script:lifecycleSnapshot = Get-ApimComparisonSnapshot -RunPath $script:lifecycleRun
            Mock Invoke-ApimArm { throw 'Unexpected live call.' }
            Mock Invoke-ApimResourceGraphQuery { throw 'Unexpected live query.' }
        }

        It 'carries tracking at both grains without mutating findings or the prior workbook' {
            $prior = Export-ApimActionPlan -RunPath $script:lifecycleRun
            $package = Open-ExcelPackage -Path $prior
            foreach ($definition in @(
                    @{ Sheet = 'Action Plan'; Table = 'tblActions' }
                    @{ Sheet = 'Finding Details'; Table = 'tblFindings' }
                )) {
                (Get-LifecycleCell $package $definition.Sheet $definition.Table Owner).Value = '=literal text'
                (Get-LifecycleCell $package $definition.Sheet $definition.Table Status).Value = 'Accepted risk'
                (Get-LifecycleCell $package $definition.Sheet $definition.Table 'Target Date').Value = [datetime]'2027-01-02'
                (Get-LifecycleCell $package $definition.Sheet $definition.Table Notes).Value = 'Synthetic tracking'
            }
            Close-ExcelPackage $package
            $priorHash = (Get-FileHash $prior).Hash
            $findingsPath = Join-Path $script:lifecycleRun 'findings.json'
            $findingsHash = (Get-FileHash $findingsPath).Hash
            $next = Export-ApimActionPlan -RunPath $script:lifecycleRun -PreviousReport $prior
            $package = Open-ExcelPackage -Path $next
            try {
                foreach ($definition in @(
                        @{ Sheet = 'Action Plan'; Table = 'tblActions' }
                        @{ Sheet = 'Finding Details'; Table = 'tblFindings' }
                    )) {
                    (Get-LifecycleCell $package $definition.Sheet $definition.Table Owner).Value | Should -Be '=literal text'
                    (Get-LifecycleCell $package $definition.Sheet $definition.Table Owner).Formula | Should -BeNullOrEmpty
                    (Get-LifecycleCell $package $definition.Sheet $definition.Table Status).Value | Should -Be 'Accepted risk'
                    (Get-LifecycleCell $package $definition.Sheet $definition.Table 'Target Date').Value | Should -Be '2027-01-02'
                    (Get-LifecycleCell $package $definition.Sheet $definition.Table Notes).Value | Should -Be 'Synthetic tracking'
                }
            }
            finally { $package.Dispose() }
            (Get-FileHash $prior).Hash | Should -Be $priorHash
            (Get-FileHash $findingsPath).Hash | Should -Be $findingsHash
            (Invoke-ApimReport -RunFolder $script:lifecycleRun -PreviousReport $next).ExitCode | Should -Be 0
            (Get-FileHash $findingsPath).Hash | Should -Be $findingsHash
        }

        It 'rejects invalid imported workbook data before publishing a new file (<Kind>)' -TestCases @(
            @{ Kind = 'status' }, @{ Kind = 'formula' }, @{ Kind = 'date' },
            @{ Kind = 'duplicate' }, @{ Kind = 'header' }, @{ Kind = 'scope' }, @{ Kind = 'missingKey' }
        ) {
            param($Kind)
            $prior = Export-ApimActionPlan -RunPath $script:lifecycleRun
            $package = Open-ExcelPackage -Path $prior
            switch ($Kind) {
                status { (Get-LifecycleCell $package 'Action Plan' tblActions Status).Value = 'Invalid' }
                formula { (Get-LifecycleCell $package 'Action Plan' tblActions Notes).Formula = '1+1' }
                date { (Get-LifecycleCell $package 'Action Plan' tblActions 'Target Date').Value = 'not-a-date' }
                duplicate {
                    (Get-LifecycleCell $package 'Action Plan' tblActions 'Rule ID' 2).Value =
                        (Get-LifecycleCell $package 'Action Plan' tblActions 'Rule ID').Value
                }
                header { $package.Workbook.Worksheets['Action Plan'].Tables['tblActions'].Columns[11].Name = 'Unexpected' }
                scope {
                    $table = $package.Workbook.Worksheets['Run Info'].Tables['tblRun']
                    for ($row = $table.Address.Start.Row + 1; $row -le $table.Address.End.Row; $row++) {
                        if ((Read-ApimTrackingCell $table $row Name) -ceq 'Environment') {
                            $index = [array]::IndexOf(@($table.Columns.Name), 'Value') + $table.Address.Start.Column
                            $table.WorkSheet.Cells[$row, $index].Value = 'Test'
                        }
                    }
                }
                missingKey { (Get-LifecycleCell $package 'Action Plan' tblActions 'Rule ID').Value = $null }
            }
            Close-ExcelPackage $package
            $count = @(Get-ChildItem (Join-Path $script:lifecycleRun 'report') -Filter '*.xlsx').Count
            { Export-ApimActionPlan -RunPath $script:lifecycleRun -PreviousReport $prior } | Should -Throw
            @(Get-ChildItem (Join-Path $script:lifecycleRun 'report') -Filter '*.xlsx').Count | Should -Be $count
        }

        It 'classifies comparable snapshots, severity changes and evidence gaps deterministically' {
            $before = $script:lifecycleSnapshot
            $after = ConvertFrom-Json (ConvertTo-Json $before -Depth 100) -AsHashtable -Depth 100
            $evaluated = @($before.findings | Where-Object evaluation -CEQ Evaluated)
            $persistent = $evaluated[0].findingKey
            $removed = $evaluated[1].findingKey
            $after.findings = @($after.findings | Where-Object findingKey -CNE $removed)
            $copy = ConvertFrom-Json (ConvertTo-Json $evaluated[1] -Depth 100) -AsHashtable
            $copy.scope = 'synthetic-new'; $copy.findingKey = "$($copy.ruleId)|$($copy.resource)|synthetic-new"
            $after.findings += $copy
            foreach ($finding in $after.findings) {
                if ($finding.findingKey -ceq $persistent) { $finding.severity = 'Low' }
            }
            foreach ($models in @($before.models, $after.models)) {
                foreach ($name in $models.Keys) {
                    foreach ($model in @($models[$name])) { $model.modelStatus = 'Complete' }
                }
            }
            $diff = Get-ApimRunComparison -Baseline $before -Current $after
            @($diff.changes | Where-Object change -CEQ New).Count | Should -Be 1
            @($diff.changes | Where-Object change -CEQ Resolved).Count | Should -Be 1
            ($diff.changes | Where-Object findingKey -CEQ $persistent).severityChanged | Should -BeTrue
            ($diff.kpis | Where-Object metric -CEQ MonthlyCost).delta | Should -BeNullOrEmpty
            ($diff.kpis | Where-Object metric -CEQ UnusedApis).reason | Should -Be UsageUnavailable
            @($diff.gaps | Where-Object change -CNE NotReassessed).Count | Should -Be 0
            $first = ConvertTo-Json $diff -Depth 100
            $after.findings = @($after.findings | Sort-Object findingKey -Descending)
            (ConvertTo-Json (Get-ApimRunComparison $before $after) -Depth 100) | Should -Be $first
            $after.settingsDigest = 'changed'
            $diff = Get-ApimRunComparison $before $after
            @($diff.changes | Where-Object change -CEQ Resolved).Count | Should -Be 0
            ($diff.gaps | Where-Object findingKey -CEQ $removed).reason | Should -Be SettingsChanged
        }

        It 'does not resolve disappearing findings when required models or assessment coverage are incomplete' {
            $before = $script:lifecycleSnapshot
            $after = ConvertFrom-Json (ConvertTo-Json $before -Depth 100) -AsHashtable -Depth 100
            $target = @($before.findings | Where-Object { $_.ruleId -ceq 'APIM-GOV-002' -and $_.evaluation -ceq 'Evaluated' })[0]
            $after.findings = @($after.findings | Where-Object findingKey -CNE $target.findingKey)
            $after.models.apis[0].modelStatus = 'Partial'
            $diff = Get-ApimRunComparison $before $after
            ($diff.gaps | Where-Object findingKey -CEQ $target.findingKey).reason | Should -Be EvidenceIncomplete
            $before.replayMatches = $false
            $diff = Get-ApimRunComparison $before $after
            ($diff.gaps | Where-Object findingKey -CEQ $target.findingKey).reason | Should -Be HistoricalReplayMismatch
        }

        It 'persists a bound offline comparison and paired reports without changing the baseline' {
            $other = New-SyntheticCollectedRun -RepoRoot $script:lifecycleRepo `
                -OutputRoot (Join-Path $TestDrive 'comparison-current')
            (Invoke-ApimAnalyze -RunFolder $other.Run.Path).ExitCode | Should -Be 0
            $hash = (Get-FileHash (Join-Path $script:lifecycleRun 'findings.json')).Hash
            (Compare-ApimRun -Baseline $script:lifecycleRun -Current $other.Run.Path).ExitCode | Should -Be 0
            $diff = Get-ApimSavedComparison -RunPath $other.Run.Path
            @($diff.changes | Where-Object change -CNE Persisting).Count | Should -Be 0
            $jsonPath = Join-Path $other.Run.Path 'diff.json'
            $first = (Get-FileHash $jsonPath).Hash
            (Compare-ApimRun -Baseline $script:lifecycleRun -Current $other.Run.Path).ExitCode | Should -Be 0
            (Get-FileHash $jsonPath).Hash | Should -Be $first
            $paths = Get-ApimRenderedPath -RunPath $other.Run.Path
            Test-Path $paths.html | Should -BeTrue
            $package = Open-ExcelPackage -Path $paths.workbook
            try {
                $package.Workbook.Worksheets['Run Comparison'].Tables['tblComparison'].Address.Rows |
                    Should -Be ($diff.changes.Count + 1)
            }
            finally { $package.Dispose() }
            (Get-FileHash (Join-Path $script:lifecycleRun 'findings.json')).Hash | Should -Be $hash
            (Compare-ApimRun -Baseline $other.Run.Path -Current $other.Run.Path).ExitCode | Should -Be 4
            (Compare-ApimRun -Baseline $other.Run.Path -Current (
                    Join-Path $other.Run.Path 'nested-run'
                )).ExitCode | Should -Be 4
            $diff.kpis[0].delta = 999
            $null = Write-RunFile -RunPath $other.Run.Path -RelativePath diff.json -InputObject $diff -Depth 100
            { Get-ApimSavedComparison -RunPath $other.Run.Path } | Should -Throw
            (Invoke-ApimReport -RunFolder $other.Run.Path).ExitCode | Should -Be 4
            Should -Invoke Invoke-ApimArm -Times 0 -Exactly
        }

        It 'rejects unknown contract fields and incompatible scope without exposing inputs' {
            $diff = Get-ApimRunComparison $script:lifecycleSnapshot $script:lifecycleSnapshot
            $diff.unknown = 'synthetic-canary'
            { Test-ApimLifecycleJson -Json (ConvertTo-Json $diff -Depth 100) -Contract comparison } | Should -Throw
            $other = ConvertFrom-Json (ConvertTo-Json $script:lifecycleSnapshot -Depth 100) -AsHashtable -Depth 100
            $other.manifest.environment = 'Test'
            { Get-ApimRunComparison $script:lifecycleSnapshot $other } | Should -Throw
            $result = Compare-ApimRun -Baseline 'synthetic-secret-canary' -Current $script:lifecycleRun
            $result.ExitCode | Should -Be 4
            (ConvertTo-Json $result) | Should -Not -Match 'canary'
        }

        It 'retains unmatched tracking separately and resolves it only against the matching compared snapshot' {
            $prior = Export-ApimActionPlan -RunPath $script:lifecycleRun
            $current = $script:lifecycleSnapshot
            $target = @($current.findings | Where-Object evaluation -CEQ Evaluated)[0]
            $findings = @($current.findings | Where-Object findingKey -CNE $target.findingKey)
            $actions = @(Get-ApimActionPlan -Findings $findings)
            $arguments = @{
                RunPath = $script:lifecycleRun; Manifest = $current.manifest; Models = $current.models
                Actions = $actions; Findings = $findings; PreviousReport = $prior
            }
            $tracking = Merge-ApimPriorTracking @arguments
            @($tracking.notReassessed | Where-Object key -CEQ $target.findingKey).Count | Should -Be 1
            $tracking.resolved.Count | Should -Be 0
            foreach ($name in $current.models.Keys) {
                foreach ($model in @($current.models[$name])) { $model.modelStatus = 'Complete' }
            }
            $arguments.Comparison = @{
                baseline = @{ sha256 = $current.identity.sha256 }
                changes = @(@{ findingKey = $target.findingKey; ruleId = $target.ruleId; change = 'Resolved' })
                gaps = @()
            }
            $tracking = Merge-ApimPriorTracking @arguments
            @($tracking.resolved | Where-Object key -CEQ $target.findingKey).Count | Should -Be 1
            $arguments.Comparison.baseline.sha256 = '0' * 64
            (Merge-ApimPriorTracking @arguments).resolved.Count | Should -Be 0
        }

        It 'preserves intentional blanks and all approved tracking states independently from machine finding status' {
            $prior = Export-ApimActionPlan -RunPath $script:lifecycleRun
            $package = Open-ExcelPackage -Path $prior
            $states = @('Open', 'In progress', 'Done', 'Accepted risk', 'Not applicable', $null)
            for ($index = 0; $index -lt $states.Count; $index++) {
                (Get-LifecycleCell $package 'Finding Details' tblFindings Status ($index + 1)).Value = $states[$index]
            }
            Close-ExcelPackage $package
            $imported = Read-ApimPriorTracking -Path $prior -Manifest $script:lifecycleSnapshot.manifest
            $rows = @($imported.records | Where-Object kind -CEQ Finding)
            for ($index = 0; $index -lt $states.Count; $index++) { $rows[$index].status | Should -Be $states[$index] }
            @($script:lifecycleSnapshot.findings | Where-Object status -CNE Open).Count | Should -Be 0
        }

        It 'handles empty snapshots and null reachability without inventing zero usage or cost' {
            $before = $script:lifecycleSnapshot
            $after = ConvertFrom-Json (ConvertTo-Json $before -Depth 100) -AsHashtable -Depth 100
            $before.findings = @(); $after.findings = @()
            $after.models.apis[0].reachability = $null
            $diff = Get-ApimRunComparison $before $after
            $diff.changes.Count | Should -Be 0
            $diff.gaps.Count | Should -Be 0
            ($diff.kpis | Where-Object metric -CEQ ReachableApis).delta | Should -BeNullOrEmpty
            ($diff.kpis | Where-Object metric -CEQ ReachableApis).reason | Should -Be EvidenceIncomplete
            $after.models.apis[0].reachability = 'Reachable'
            $after.models.apis += $after.models.apis[0]
            (Get-ApimComparisonKpi -Snapshot $after -Metric ReachableApis) | Should -Be 2
        }

        It 'binds snapshots independently of inventory order and rejects stale current inputs' {
            $before = $script:lifecycleSnapshot
            $models = $before.models
            foreach ($name in $models.Keys) {
                if ($models[$name] -is [array]) { [array]::Reverse($models[$name]) }
            }
            $null = Write-ApimModelSet -RunPath $script:lifecycleRun -Models $models
            $after = Get-ApimComparisonSnapshot -RunPath $script:lifecycleRun
            $after.identity.sha256 | Should -Be $before.identity.sha256
            $diff = Get-ApimRunComparison $before $after
            $null = Write-RunFile -RunPath $script:lifecycleRun -RelativePath diff.json -InputObject $diff -Depth 100
            $null = Write-RunFile -RunPath $script:lifecycleRun -RelativePath 'restricted/comparison-binding.json' `
                -InputObject @{ schemaVersion = '1.0'; diffSha256 = Get-ApimLifecycleDigest $diff }
            $null = Get-ApimSavedComparison -RunPath $script:lifecycleRun
            $models.service.minApiVersion = '2025-01-01'
            $null = Write-ApimModelSet -RunPath $script:lifecycleRun -Models $models
            { Get-ApimSavedComparison -RunPath $script:lifecycleRun } | Should -Throw
        }

        It 'does not add workbook tracking or comparison to the model-safe package' {
            $first = New-ApimAnalysisPackage -RunPath $script:lifecycleRun -Config $script:lifecycleConfig
            $first.status | Should -Be Built
            $prior = Export-ApimActionPlan -RunPath $script:lifecycleRun
            $package = Open-ExcelPackage -Path $prior
            (Get-LifecycleCell $package 'Action Plan' tblActions Notes).Value = 'NEVER_COPY_TRACKING'
            Close-ExcelPackage $package
            $null = Export-ApimActionPlan -RunPath $script:lifecycleRun -PreviousReport $prior
            $second = New-ApimAnalysisPackage -RunPath $script:lifecycleRun -Config $script:lifecycleConfig
            $second.status | Should -Be Built
            $a = Join-Path $script:lifecycleRun "restricted/candidates/$($first.candidateId)/analysis-package.json"
            $b = Join-Path $script:lifecycleRun "restricted/candidates/$($second.candidateId)/analysis-package.json"
            (Get-FileHash $a).Hash | Should -Be (Get-FileHash $b).Hash
            (Get-Content $b -Raw) | Should -Not -Match 'NEVER_COPY_TRACKING'
        }
    }
}
