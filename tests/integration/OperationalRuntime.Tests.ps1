$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Offline collected evidence to deterministic workbook' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)
        $script:runtimeRepoRoot = $RepoRoot

        BeforeAll {
            . (Join-Path $script:runtimeRepoRoot 'tests/helpers/New-SyntheticCollectedRun.ps1')
        }
        BeforeEach {
            $script:runtimeInput = New-SyntheticCollectedRun `
                -RepoRoot $script:runtimeRepoRoot -OutputRoot (
                    Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
                )
            $script:runtimePath = $script:runtimeInput.Run.Path
            Mock Invoke-ApimArm { throw 'Offline analysis attempted Azure access.' }
            Mock Invoke-ApimResourceGraphQuery { throw 'Offline analysis attempted graph access.' }
        }

        It 'builds eleven models including portal and repeatable findings from raw evidence and renders Excel' {
            $analysis = Invoke-ApimAnalyze -RunFolder $script:runtimePath
            $analysis.ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:runtimePath
            $models.Count | Should -Be 11
            $models.portal.basicAuthEnabled | Should -BeFalse
            $models.portal.basicAuthEvidence | Should -Be Direct
            $models.portal.published | Should -BeTrue
            $models.portal.nonEntraProviderEnabled | Should -BeFalse
            $models.apis.Count | Should -Be 2
            $models.operations.Count | Should -Be 2
            $models.exposure.Count | Should -Be 2
            $models.subscriptions.Count | Should -Be 6
            $models.namedValues.Count | Should -Be 3
            $models.apis.calls90d | Should -Be @($null, $null)
            $models.exposure.callsViaAppGw | Should -Be @($null, $null)
            $firstHash = (Get-FileHash -LiteralPath (
                    Join-Path $script:runtimePath 'findings.json'
                )).Hash
            $findings = @(Get-ApimFindingSet -RunPath $script:runtimePath)
            $findings.Count | Should -BeGreaterThan 0
            @($findings | Where-Object ruleId -EQ 'APIM-NET-004').Count |
                Should -Be 2
            (Invoke-ApimAnalyze -RunFolder $script:runtimePath).ExitCode | Should -Be 0
            (Get-FileHash -LiteralPath (
                    Join-Path $script:runtimePath 'findings.json'
                )).Hash | Should -Be $firstHash

            $report = Invoke-ApimReport -RunFolder $script:runtimePath
            $report.ExitCode | Should -Be 0
            $files = @(Get-ChildItem -LiteralPath (
                    Join-Path $script:runtimePath 'report'
                ) -Filter '*.xlsx')
            $files.Count | Should -Be 1
            $workbook = Open-ExcelPackage -Path $files[0].FullName
            try {
                $workbook.Workbook.Worksheets['API Inventory'].Tables['tblApis'].Address.Rows |
                    Should -Be 3
                $workbook.Workbook.Worksheets['Finding Details'].Tables['tblFindings'].Address.Rows |
                    Should -Be ($findings.Count + 1)
            }
            finally { $workbook.Dispose() }
            Should -Invoke Invoke-ApimArm -Times 0 -Exactly
            Should -Invoke Invoke-ApimResourceGraphQuery -Times 0 -Exactly
        }

        It 'replays changed portal raw evidence through POR findings and paired reports without altering raw files' {
            $raw = Read-ApimSmokeOutputJson -RunPath $script:runtimePath -RelativePath raw/portal/config.json
            $raw.properties.enableBasicAuth = $true
            $null = Write-RunFile -RunPath $script:runtimePath -RelativePath raw/portal/config.json -InputObject $raw
            $before = @(Get-ChildItem (Join-Path $script:runtimePath raw) -Recurse -File |
                Sort-Object FullName | Get-FileHash | Select-Object -ExpandProperty Hash)
            (Invoke-ApimAnalyze -RunFolder $script:runtimePath).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:runtimePath
            $models.portal.basicAuthEnabled | Should -BeTrue
            $models.portal.basicAuthEvidence | Should -Be Direct
            $finding = @(Get-ApimFindingSet -RunPath $script:runtimePath |
                Where-Object ruleId -CEQ APIM-POR-002)
            $finding.Count | Should -Be 1
            $finding[0].evaluation | Should -Be Evaluated
            $finding[0].scope | Should -Be portal
            (Invoke-ApimReport -RunFolder $script:runtimePath).ExitCode | Should -Be 0
            @(Get-ChildItem (Join-Path $script:runtimePath report) -Filter '*.xlsx').Count | Should -Be 1
            @(Get-ChildItem (Join-Path $script:runtimePath report) -Filter '*.html').Count | Should -Be 1
            $after = @(Get-ChildItem (Join-Path $script:runtimePath raw) -Recurse -File |
                Sort-Object FullName | Get-FileHash | Select-Object -ExpandProperty Hash)
            $after | Should -Be $before
            Should -Invoke Invoke-ApimArm -Times 0 -Exactly
            Should -Invoke Invoke-ApimResourceGraphQuery -Times 0 -Exactly
        }

        It 'uses only validated listed Partial portal files instead of stale complete portal evidence' {
            Set-RunCollectorStatus -RunPath $script:runtimePath -Name Portal -Status Partial `
                -Items 1 -Errors 4 -Files @('raw/portal/config.json')
            Set-RunStageStatus -RunPath $script:runtimePath -Stage collect -Status Partial
            $record = (Get-RunManifest -RunPath $script:runtimePath).collectors |
                Where-Object name -CEQ Portal
            Test-ApimCollectorOutput -RunPath $script:runtimePath `
                -Environment $script:runtimeInput.Config.Environments[0] -Collector $record
            (Invoke-ApimAnalyze -RunFolder $script:runtimePath).ExitCode | Should -Be 0
            $portal = (Get-ApimModelSet -RunPath $script:runtimePath).portal
            $portal.basicAuthEnabled | Should -BeFalse
            $portal.basicAuthEvidence | Should -Be Direct
            $portal.published | Should -BeNullOrEmpty
            $portal.signupEnabled | Should -BeNullOrEmpty
            $portal.modelStatus | Should -Be Partial
            $portal.missingInputs | Should -Contain published
            Should -Invoke Invoke-ApimArm -Times 0 -Exactly
        }

        It 'does not read stale failed-collector files or publish an incomplete model set' {
            Set-RunCollectorStatus -RunPath $script:runtimePath `
                -Name SecurityAssets -Status Failed -Errors 1
            $result = Invoke-ApimAnalyze -RunFolder $script:runtimePath
            $result.ExitCode | Should -Be 4
            (Get-RunManifest -RunPath $script:runtimePath).stages.analyze |
                Should -Be Failed
            Test-Path -LiteralPath (Join-Path $script:runtimePath 'model/backends.json') |
                Should -BeFalse
            $findings = @(Get-ApimFindingSet -RunPath $script:runtimePath)
            $missing = @($findings | Where-Object ruleId -EQ 'APIM-SEC-010')
            $missing.Count | Should -Be 1
            $missing[0].evaluation | Should -Be NotEvaluated
            $missing[0].severity | Should -Be Info
            (Invoke-ApimReport -RunFolder $script:runtimePath).ExitCode | Should -Be 4
            @(Get-ChildItem -LiteralPath (Join-Path $script:runtimePath 'report')).Count |
                Should -Be 0
        }

        It 'retains diagnostic data gaps rather than treating failed diagnostics as clean' {
            Set-RunCollectorStatus -RunPath $script:runtimePath `
                -Name Diagnostics -Status Partial -Errors 1
            $result = Invoke-ApimAnalyze -RunFolder $script:runtimePath
            $result.ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:runtimePath
            foreach ($api in $models.apis) {
                $api.bodyLogging | Should -BeNullOrEmpty
                $api.missingInputs | Should -Contain diagnostics
            }
            $missing = @(Get-ApimFindingSet -RunPath $script:runtimePath |
                    Where-Object ruleId -EQ 'APIM-SEC-014')
            $missing.Count | Should -Be 1
            $missing[0].evaluation | Should -Be NotEvaluated
        }

        It 'rejects modified deterministic evidence before writing reports' {
            (Invoke-ApimAnalyze -RunFolder $script:runtimePath).ExitCode | Should -Be 0
            $findings = @(Get-ApimFindingSet -RunPath $script:runtimePath)
            $findings[0].evidenceText = 'Modified synthetic claim.'
            $null = Write-ApimFindingSet -RunPath $script:runtimePath -Findings $findings
            (Invoke-ApimReport -RunFolder $script:runtimePath).ExitCode | Should -Be 4
            @(Get-ChildItem -LiteralPath (Join-Path $script:runtimePath 'report')).Count |
                Should -Be 0
        }

        It 'rejects malformed raw input and unknown saved settings' `
            -TestCases @(@{ Kind = 'raw' }, @{ Kind = 'settings' }) {
            param($Kind)
            if ($Kind -eq 'raw') {
                Set-Content -LiteralPath (Join-Path $script:runtimePath 'raw/apis.json') `
                    -Value '{"value":"invalid"}'
            }
            else {
                $settingsPath = Join-Path $script:runtimePath 'restricted/run-settings.json'
                $settings = Get-Content -LiteralPath $settingsPath -Raw |
                    ConvertFrom-Json -AsHashtable
                $settings['unknown'] = 'synthetic-canary'
                Set-Content -LiteralPath $settingsPath `
                    -Value (ConvertTo-Json -InputObject $settings -Depth 100)
            }
            $result = Invoke-ApimAnalyze -RunFolder $script:runtimePath
            $result.ExitCode | Should -Be 4
            (ConvertTo-Json -InputObject $result) | Should -Not -Match 'canary|invalid|raw/'
        }
    }
}
