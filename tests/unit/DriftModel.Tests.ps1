$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Optional saved environment drift' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)
        $script:driftRepo = $RepoRoot
        BeforeAll {
            . (Join-Path $script:driftRepo 'tests/helpers/New-SyntheticCollectedRun.ps1')
            function Get-DriftComparisonRun {
                param([string] $Root, [string] $Id, [string] $Environment = 'Prod')
                $run = New-SyntheticCollectedRun -RepoRoot $script:driftRepo `
                    -OutputRoot $Root -RunId $Id
                $manifest = Get-RunManifest -RunPath $run.Run.Path
                $manifest.environment = $Environment
                $manifest.apim.resourceId = $manifest.apim.resourceId -replace 'apim-synthetic-prod',
                    "apim-synthetic-$($Environment.ToLowerInvariant())"
                $null = Save-RunManifest -RunPath $run.Run.Path -Manifest $manifest
                return $run
            }
            function Write-SyntheticGitDrift {
                param([string] $RunPath)
                $current = Get-ApimDriftSnapshot -RunPath $RunPath
                $policies = @($current.policies | Where-Object exists | ForEach-Object {
                        [ordered]@{ scopeType = $_.scopeType; scope = $_.scope; sha256 = $_.sha256 }
                    })
                $policies[0].sha256 = 'a' * 64
                $null = Write-RunFile -RunPath $RunPath -RelativePath 'git/policyHashes.json' `
                    -InputObject ([ordered]@{ schemaVersion = '1.0'; commitSha = 'b' * 40
                        scopeTypes = @('Api', 'Fragment', 'Global', 'Operation', 'Product')
                        policies = $policies })
                Set-RunCollectorStatus -RunPath $RunPath -Name Git -Status Completed -Items $policies.Count
            }
        }
        BeforeEach {
            $script:driftRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $script:driftCurrent = Get-DriftComparisonRun -Root $script:driftRoot `
                -Id current -Environment Prod
            $script:driftOther = Get-DriftComparisonRun -Root $script:driftRoot `
                -Id other -Environment Dev
            Mock Invoke-ApimArm { throw 'Unexpected Azure call.' }
            Mock Invoke-ApimResourceGraphQuery { throw 'Unexpected graph call.' }
            Mock Get-ApimSpectralTool { return $null }
        }

        It 'keeps ordinary no-Git analysis and paired reports available with explicit gaps' {
            $path = $script:driftCurrent.Run.Path
            (Invoke-ApimAnalyze -RunFolder $path).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $path
            $models.Count | Should -Be 12
            $models.Contains('portal') | Should -BeTrue
            $models.Contains('drift') | Should -BeFalse
            $gaps = @(Get-ApimFindingSet -RunPath $path | Where-Object {
                    $_.ruleId -cin @('APIM-GOV-007', 'APIM-GOV-011')
                })
            $gaps.Count | Should -Be 2
            foreach ($gap in $gaps) {
                $gap.evaluation | Should -Be NotEvaluated
                $gap.severity | Should -Be Info
            }
            (Invoke-ApimReport -RunFolder $path).ExitCode | Should -Be 0
            Should -Invoke Invoke-ApimArm -Times 0 -Exactly
        }

        It 'compares equal snapshots without drift findings and replays without external paths' {
            $path = $script:driftCurrent.Run.Path
            (Invoke-ApimAnalyze -RunFolder $path -CompareRuns $script:driftOther.Run.Path).ExitCode |
                Should -Be 0
            $models = Get-ApimModelSet -RunPath $path
            $models.Count | Should -Be 13
            $models.Contains('portal') | Should -BeTrue
            @($models.drift | Where-Object changeType -CNE All).Count | Should -Be 0
            @(Get-ApimFindingSet -RunPath $path | Where-Object ruleId -CEQ 'APIM-GOV-011').Count |
                Should -Be 0
            $first = (Get-FileHash (Join-Path $path 'model/drift.json')).Hash
            Move-Item -LiteralPath $script:driftOther.Run.Path `
                -Destination (Join-Path $script:driftRoot 'moved-external-source')
            (Invoke-ApimAnalyze -RunFolder $path).ExitCode | Should -Be 0
            (Get-FileHash (Join-Path $path 'model/drift.json')).Hash | Should -Be $first
            (Invoke-ApimReport -RunFolder $path).ExitCode | Should -Be 0
        }

        It 'detects differences and production-only policies with stable rule evidence' {
            $inputs = [ordered]@{
                schemaVersion = '1.0'
                current = Get-ApimDriftSnapshot -RunPath $script:driftCurrent.Run.Path
                sources = @((Get-ApimDriftSnapshot -RunPath $script:driftOther.Run.Path))
            }
            $policy = @($inputs.sources[0].policies | Where-Object exists)[0]
            $policy.sha256 = 'a' * 64
            $rows = @(Get-ApimDriftModel -Inputs $inputs)
            @($rows | Where-Object changeType -CEQ Differs).Count | Should -Be 1
            $policy.exists = $false
            $policy.sha256 = $null
            $rows = @(Get-ApimDriftModel -Inputs $inputs)
            @($rows | Where-Object changeType -CEQ ProdOnly).Count | Should -Be 1
            $rules = @(Get-ApimRuleCatalog -CatalogPath $script:ApimReportRuleCatalogPath |
                    Where-Object Id -CEQ 'APIM-GOV-011')
            $context = Get-ApimRunSetting -RunPath $script:driftCurrent.Run.Path
            $findings = @(Invoke-ApimRuleEngine -Rules $rules -Models @{ drift = $rows } `
                    -Manifest $context.Manifest -Config $context.Config)
            $findings.Count | Should -Be 1
            $findings[0].scope | Should -Be service
            $findings[0].sourceFiles | Should -Be @('model/drift.json')
            $findings[0].evidence.differences.Count | Should -Be 1
            $first = ConvertTo-Json -InputObject $rows -Depth 100
            $inputs.current.policies = @($inputs.current.policies | Sort-Object scope -Descending)
            (ConvertTo-Json -InputObject @(Get-ApimDriftModel -Inputs $inputs) -Depth 100) |
                Should -Be $first
        }

        It 'retains incomplete evidence as Unknown and one NotEvaluated result' {
            Set-RunCollectorStatus -RunPath $script:driftOther.Run.Path -Name Policies -Status Partial
            $path = $script:driftCurrent.Run.Path
            (Invoke-ApimAnalyze -RunFolder $path -CompareRuns $script:driftOther.Run.Path).ExitCode |
                Should -Be 0
            $models = Get-ApimModelSet -RunPath $path
            $models.drift[0].changeType | Should -Be Unknown
            $models.drift[0].presentB | Should -BeNullOrEmpty
            $gaps = @(Get-ApimFindingSet -RunPath $path | Where-Object ruleId -CEQ 'APIM-GOV-011')
            $gaps.Count | Should -Be 1
            $gaps[0].evaluation | Should -Be NotEvaluated
        }

        It 'renders Git differences and validates only approved drift codes in model-safe replay' {
            $path = $script:driftCurrent.Run.Path
            Write-SyntheticGitDrift -RunPath $path
            $other = $script:driftOther.Run.Path
            $index = Read-ApimSmokeOutputJson -RunPath $other -RelativePath 'policies/index.json'
            $global = @($index.policies | Where-Object scopeType -CEQ Global)[0]
            $xml = '<policies><inbound><base /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
            $global.sha256 = Get-ApimPolicySha256 -Xml $xml
            $null = Write-RunFile -RunPath $other -RelativePath $global.file -InputObject $xml -Format Text
            $null = Write-RunFile -RunPath $other -RelativePath 'policies/index.json' -InputObject $index
            (Invoke-ApimAnalyze -RunFolder $path -CompareRuns $other).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $path
            @($models.drift | Where-Object changeType -CEQ Differs).Count | Should -Be 2
            $findings = @(Get-ApimFindingSet -RunPath $path |
                    Where-Object ruleId -CEQ 'APIM-GOV-007')
            $findings.Count | Should -Be 1
            $findings[0].evaluation | Should -Be Evaluated
            $context = Get-ApimRunSetting -RunPath $path
            $candidate = New-ApimAnalysisPackage -RunPath $path -Config $context.Config
            $file = Join-Path $path "restricted/candidates/$($candidate.candidateId)/analysis-package.json"
            $json = Get-Content -LiteralPath $file -Raw
            $safe = $json | ConvertFrom-Json
            $safe.schemaVersion | Should -Be '1.2'
            $safe.facts.value | Should -Contain SourcePolicyDrift
            $safe.facts.value | Should -Contain EnvironmentPolicyDrift
            $json | Should -Not -Match ('synthetic|global|git/policy|commitSha|' + ('a' * 64) + '|' + ('b' * 40))
            (Test-ApimAnalysisPackage -CandidatePath $file).status | Should -Be Passed
            $mutated = $json.Replace('SourcePolicyDrift', 'PrivateGitPath')
            { Test-ApimAnalysisContract -Kind AnalysisPackage -Json $mutated } | Should -Throw
            $mutated = $json -replace '"schemaVersion"\s*:\s*"1.2"', '"schemaVersion":"1.1"'
            { Test-ApimAnalysisContract -Kind AnalysisPackage -Json $mutated } | Should -Throw
            (Invoke-ApimReport -RunFolder $path).ExitCode | Should -Be 0
            $workbook = @(Get-ChildItem (Join-Path $path 'report') -Filter '*.xlsx')[0]
            Import-Module ImportExcel -RequiredVersion 7.8.10 3>$null
            $excel = Open-ExcelPackage -Path $workbook.FullName
            try {
                $table = $excel.Workbook.Worksheets['Environment Drift'].Tables['tblDrift']
                $table.Address.Rows | Should -Be ($models.drift.Count + 1)
                $sheet = $table.WorkSheet
                $sheet.Cells[($table.Address.Start.Row + 1), $table.Address.Start.Column].Text |
                    Should -Be Environment
                $sheet.Cells[($table.Address.Start.Row + 1), $table.Address.Start.Column].Formula |
                    Should -BeNullOrEmpty
            }
            finally { Close-ExcelPackage -ExcelPackage $excel -NoSave }
            @(Get-ChildItem (Join-Path $path 'report') -Filter '*.html').Count | Should -Be 1
        }

        It 'passes equal Git policies and preserves known differences with incomplete scope coverage' {
            $path = $script:driftCurrent.Run.Path
            $context = Get-ApimRunSetting -RunPath $path
            $current = Get-ApimDriftSnapshot -RunPath $path
            $source = [ordered]@{ kind = 'Git'; environment = 'Git'; runId = $null
                resourceId = $null; complete = $true; scopeTypes = $current.scopeTypes
                apiIds = @(); policies = $current.policies }
            $inputs = [ordered]@{ schemaVersion = '1.0'; current = $current; sources = @($source) }
            $rules = @(Get-ApimRuleCatalog -CatalogPath $script:ApimReportRuleCatalogPath |
                    Where-Object Id -CEQ 'APIM-GOV-007')
            $rows = @(Get-ApimDriftModel -Inputs $inputs)
            @(Invoke-ApimRuleEngine -Rules $rules -Models @{ drift = $rows } `
                    -Manifest $context.Manifest -Config $context.Config).Count | Should -Be 0
            $source.policies = @($current.policies | Where-Object scopeType -CNE Fragment |
                    ForEach-Object {
                        [ordered]@{ scopeType = $_.scopeType; scope = $_.scope
                            exists = $_.exists
                            sha256 = if ($_.exists) { 'a' * 64 } else { $null } }
                    })
            $source.scopeTypes = @('Api', 'Global', 'Operation', 'Product')
            $rows = @(Get-ApimDriftModel -Inputs $inputs)
            $findings = @(Invoke-ApimRuleEngine -Rules $rules -Models @{ drift = $rows } `
                    -Manifest $context.Manifest -Config $context.Config)
            $findings.Count | Should -Be 1
            $findings[0].evaluation | Should -Be Evaluated
            $findings[0].evidence.incompleteComparisons | Should -Be 1
        }

        It 'reports uncovered Git scopes as Unknown rather than differences or matches' {
            $current = Get-ApimDriftSnapshot -RunPath $script:driftCurrent.Run.Path
            $source = [ordered]@{ kind = 'Git'; environment = 'Git'; runId = $null
                resourceId = $null; complete = $true; scopeTypes = @('Global')
                apiIds = @(); policies = @() }
            $rows = @(Get-ApimDriftModel -Inputs (
                    [ordered]@{ schemaVersion = '1.0'; current = $current; sources = @($source) }
                ))
            $unknown = @($rows | Where-Object key -NotMatch '^Global[|]')
            $unknown.Count | Should -BeGreaterThan 0
            foreach ($row in $unknown) {
                $row.changeType | Should -Be Unknown
                $row.presentB | Should -BeNullOrEmpty
                $row.missingInputs | Should -Be @('sourceCoverage')
            }
        }

        It 'rejects duplicate, incompatible, same-environment and invalid requested inputs (<Kind>)' -TestCases @(
            @{ Kind = 'duplicate' }, @{ Kind = 'same' }, @{ Kind = 'environment' },
            @{ Kind = 'tenant' }, @{ Kind = 'missing' }, @{ Kind = 'empty' }
        ) {
            param($Kind)
            $other = $script:driftOther.Run.Path
            $inputs = @($other)
            switch ($Kind) {
                duplicate { $inputs = @($other, $other) }
                empty { $inputs = @() }
                same { $inputs = @($script:driftCurrent.Run.Path) }
                missing { $inputs = @((Join-Path $script:driftRoot 'not-a-run')) }
                environment {
                    $manifest = Get-RunManifest -RunPath $other
                    $manifest.environment = 'Prod'
                    $null = Save-RunManifest -RunPath $other -Manifest $manifest
                }
                tenant {
                    $manifest = Get-RunManifest -RunPath $other
                    $manifest.tenantId = '00000000-0000-0000-0000-000000000099'
                    $null = Save-RunManifest -RunPath $other -Manifest $manifest
                }
            }
            $result = Invoke-ApimAnalyze -RunFolder $script:driftCurrent.Run.Path -CompareRuns $inputs
            $result.ExitCode | Should -Be 4
            (ConvertTo-Json $result) | Should -Not -Match 'not-a-run|synthetic|tenantId'
        }

        It 'rejects changed binding, model, inputs or missing requested output (<Kind>)' -TestCases @(
            @{ Kind = 'binding' }, @{ Kind = 'model' }, @{ Kind = 'inputs' },
            @{ Kind = 'missing' }, @{ Kind = 'git' }, @{ Kind = 'bindingVersion' },
            @{ Kind = 'gitCount' }
        ) {
            param($Kind)
            $path = $script:driftCurrent.Run.Path
            if ($Kind -cin @('git', 'gitCount')) { Write-SyntheticGitDrift -RunPath $path }
            (Invoke-ApimAnalyze -RunFolder $path -CompareRuns $script:driftOther.Run.Path).ExitCode |
                Should -Be 0
            switch ($Kind) {
                binding {
                    $file = Join-Path $path 'restricted/drift-binding.json'
                    $json = Get-Content $file -Raw | ConvertFrom-Json
                    $json.inputsSha256 = 'a' * 64
                }
                bindingVersion {
                    $file = Join-Path $path 'restricted/drift-binding.json'
                    $json = Get-Content $file -Raw | ConvertFrom-Json
                    $json.schemaVersion = '9.0'
                }
                model {
                    $file = Join-Path $path 'model/drift.json'
                    $json = @(Get-Content $file -Raw | ConvertFrom-Json)
                    $json[0].changeType = 'Differs'
                }
                inputs {
                    $file = Join-Path $path 'restricted/drift-inputs.json'
                    $json = Get-Content $file -Raw | ConvertFrom-Json
                    $json.sources[0].environment = 'mutated-source'
                }
                git {
                    $file = Join-Path $path 'git/policyHashes.json'
                    $json = Get-Content $file -Raw | ConvertFrom-Json
                    $json.policies[0].sha256 = 'c' * 64
                }
                gitCount {
                    Set-RunCollectorStatus -RunPath $path -Name Git -Status Completed -Items 0
                }
                missing { Remove-Item -LiteralPath (Join-Path $path 'model/drift.json') }
            }
            if ($Kind -cnotin @('missing', 'gitCount')) {
                Set-Content $file (ConvertTo-Json -InputObject $json -Depth 100)
            }
            (Invoke-ApimReport -RunFolder $path).ExitCode | Should -Be 4
            @(Get-ChildItem (Join-Path $path 'report') -Filter '*.xlsx').Count | Should -Be 0
            if ($Kind -cin @('binding', 'bindingVersion', 'inputs')) {
                (Invoke-ApimAnalyze -RunFolder $path).ExitCode | Should -Be 4
            }
        }
    }
}
