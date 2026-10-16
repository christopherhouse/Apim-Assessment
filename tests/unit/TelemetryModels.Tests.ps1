$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force
AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Source-bound offline telemetry models' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:telemetryModelRepository = $Repository
        BeforeAll {
            . (Join-Path $script:telemetryModelRepository 'tests/helpers/New-SyntheticCollectedRun.ps1')
            . (Join-Path $script:telemetryModelRepository 'tests/helpers/New-SyntheticTelemetryRun.ps1')
        }
        BeforeEach {
            $script:telemetryInput = New-SyntheticTelemetryRun -RepoRoot $script:telemetryModelRepository `
                -OutputRoot (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
            $script:telemetryPath = $script:telemetryInput.Run.Path
            Mock Invoke-ApimArm { throw 'Offline telemetry models must not contact Azure.' }
            Mock Get-ApimSpectralTool { return $null }
        }

        It 'builds monthly usage, hourly-sample percentiles and same-period normalized costs deterministically' {
            $result = Invoke-ApimAnalyze -RunFolder $script:telemetryPath
            $result.ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:telemetryPath
            $models.usage.rows.Count | Should -Be 4
            @($models.usage.rows | Where-Object modelStatus -CEQ Complete).Count | Should -Be 2
            $models.usage.topApis[0].calls | Should -Be 2000000
            $models.capacity.capacityAvg | Should -Be 11.5
            $models.capacity.capacityP95 | Should -Be 22
            $models.capacity.capacityMax | Should -Be 63
            $models.capacity.units | Should -Be 2
            $september = @($models.cost.normalized | Where-Object month -CEQ '2026-09-01')[0]
            $september.calls | Should -Be 1000000
            $september.costPerMillionCalls | Should -Be 20
            $september.changePercent | Should -Be 100
            $models.cost.logicApps[0].historicalPlanChanges | Should -BeNullOrEmpty
            $first = Get-Content -LiteralPath (Join-Path $script:telemetryPath model/cost.json) -Raw
            (Invoke-ApimAnalyze -RunFolder $script:telemetryPath).ExitCode | Should -Be 0
            Get-Content -LiteralPath (Join-Path $script:telemetryPath model/cost.json) -Raw | Should -BeExactly $first
            Should -Invoke Invoke-ApimArm -Exactly -Times 0
        }

        It 'rejects changed model values, saved settings and closed-source mutations' {
            (Invoke-ApimAnalyze -RunFolder $script:telemetryPath).ExitCode | Should -Be 0
            $cost = Read-ApimSmokeOutputJson -RunPath $script:telemetryPath -RelativePath model/cost.json
            $cost.normalized[0].costPerMillionCalls = 999
            $null = Write-RunFile -RunPath $script:telemetryPath -RelativePath model/cost.json -InputObject $cost
            { Get-ApimModelSet -RunPath $script:telemetryPath } | Should -Throw '*validated sources*'
            (Invoke-ApimAnalyze -RunFolder $script:telemetryPath).ExitCode | Should -Be 0
            $context = Get-ApimRunSetting -RunPath $script:telemetryPath
            $context.Settings.telemetry.unusedDays = 7
            $null = Write-RunFile -RunPath $script:telemetryPath -RelativePath restricted/run-settings.json `
                -InputObject $context.Settings
            { Get-ApimModelSet -RunPath $script:telemetryPath } | Should -Throw '*validated sources*'
            $payload = Read-ApimCostEvidence -RunPath $script:telemetryPath
            $payload.scopes[0].rows[0] | Add-Member -NotePropertyName rawPayload -NotePropertyValue 'SYNTHETIC_FORBIDDEN'
            $null = Write-RunFile -RunPath $script:telemetryPath -RelativePath cost/daily.json -InputObject $payload
            (Invoke-ApimAnalyze -RunFolder $script:telemetryPath).ExitCode | Should -Be 4
        }

        It 'keeps missing or zero call denominators null and never compares MTD as a complete month' {
            $payload = Read-ApimLogEvidence -RunPath $script:telemetryPath -Kind usageMonthly
            $payload.workspaces[0].rows[1].calls = 0
            $null = Write-RunFile -RunPath $script:telemetryPath -RelativePath logs/usageMonthly.json -InputObject $payload
            (Invoke-ApimAnalyze -RunFolder $script:telemetryPath).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:telemetryPath
            $september = @($models.cost.normalized | Where-Object month -CEQ '2026-09-01')[0]
            $september.calls | Should -Be 0
            $september.costPerMillionCalls | Should -BeNullOrEmpty
            $september.changePercent | Should -BeNullOrEmpty
            $october = @($models.cost.normalized | Where-Object month -CEQ '2026-10-01')[0]
            $october.completeMonth | Should -BeFalse
            $october.changePercent | Should -BeNullOrEmpty
        }

        It 'closes calendar months at UTC midnight rather than workstation-local midnight' {
            $context = Get-ApimRunSetting -RunPath $script:telemetryPath
            $source = Get-ApimTelemetrySource -RunPath $script:telemetryPath -Context $context
            $context.Manifest.startedUtc = '2026-10-01T00:00:00Z'
            $source.Cost.payloads['cost/daily.json'].scopes[0].rows = @(
                $source.Cost.payloads['cost/daily.json'].scopes[0].rows |
                    Where-Object day -LT '2026-10-01'
            )
            $usage = Get-ApimUsageModel -Context $context -Source $source -SourceSha256 ('a' * 64)
            $cost = Get-ApimCostModel -Context $context -Source $source -SourceSha256 ('a' * 64) -Usage $usage
            $september = @($cost.normalized | Where-Object month -CEQ '2026-09-01')[0]
            $september.completeMonth | Should -BeTrue
            $september.costPerMillionCalls | Should -Be 20
            $september.changePercent | Should -Be 100
        }

        It 'keeps legacy runs at ten required baseline contracts with no telemetry defaults' {
            $legacy = New-SyntheticCollectedRun -RepoRoot $script:telemetryModelRepository `
                -OutputRoot (Join-Path $TestDrive legacy)
            (Invoke-ApimAnalyze -RunFolder $legacy.Run.Path).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $legacy.Run.Path
            $models.Contains('usage') | Should -BeFalse
            $models.Contains('capacity') | Should -BeFalse
            $models.Contains('cost') | Should -BeFalse
            (Get-RunManifest -RunPath $legacy.Run.Path).schemaVersion | Should -Be '1.1'
        }

        It 'rejects a telemetry run with all optional model files removed' {
            (Invoke-ApimAnalyze -RunFolder $script:telemetryPath).ExitCode | Should -Be 0
            foreach ($name in @('usage', 'capacity', 'cost')) {
                Remove-Item -LiteralPath (Join-Path $script:telemetryPath "model/$name.json")
            }
            { Get-ApimModelSet -RunPath $script:telemetryPath } | Should -Throw '*telemetry models are incomplete*'
        }

        It 'deduplicates identical overlaps, rejects conflicting costs and withholds ambiguous workspace denominators' {
            $context = Get-ApimRunSetting -RunPath $script:telemetryPath
            $source = Get-ApimTelemetrySource -RunPath $script:telemetryPath -Context $context
            $hash = 'a' * 64
            $usage = Get-ApimUsageModel -Context $context -Source $source -SourceSha256 $hash
            $cost = Get-ApimCostModel -Context $context -Source $source -SourceSha256 $hash -Usage $usage
            $scopes = $context.Settings.telemetry.costScopes
            $context.Settings.telemetry.costScopes = @('/subscriptions/00000000-0000-0000-0000-000000000099')
            $uncovered = Get-ApimCostModel -Context $context -Source $source -SourceSha256 $hash -Usage $usage
            $uncovered.missingInputs | Should -Contain costCoverage
            @($uncovered.normalized | Where-Object { $null -ne $_.costPerMillionCalls }).Count | Should -Be 0
            $context.Settings.telemetry.costScopes = $scopes
            $source.Cost.payloads['cost/daily.json'].scopes += $source.Cost.payloads['cost/daily.json'].scopes[0]
            $deduplicated = Get-ApimCostModel -Context $context -Source $source -SourceSha256 $hash -Usage $usage
            $deduplicated.daily.Count | Should -Be $cost.daily.Count
            $deduplicated.monthly.cost | Should -Be $cost.monthly.cost
            $copy = ConvertFrom-Json (ConvertTo-Json $source.Cost.payloads['cost/daily.json'].scopes[0] -Depth 20)
            $copy.rows[0].cost = 999
            $source.Cost.payloads['cost/daily.json'].scopes += $copy
            { Get-ApimCostModel -Context $context -Source $source -SourceSha256 $hash -Usage $usage } |
                Should -Throw '*conflicting*'
            $workspace = ConvertFrom-Json (ConvertTo-Json $source.LogAnalytics.payloads['logs/usageMonthly.json'].workspaces[0] -Depth 20)
            $workspace.workspaceId = '00000000-0000-0000-0000-000000000099'
            $window = ConvertFrom-Json (ConvertTo-Json @($source.windows | Where-Object kind -CEQ Usage)[0] -Depth 10)
            $window.target = $workspace.workspaceId
            $source.windows += $window
            $source.LogAnalytics.payloads['logs/usageMonthly.json'].workspaces += $workspace
            $duplicateUsage = Get-ApimUsageModel -Context $context -Source $source -SourceSha256 $hash
            $duplicateUsage.topApis[0].calls | Should -Be 2000000
            $workspace.rows[0].calls = 123
            $ambiguous = Get-ApimUsageModel -Context $context -Source $source -SourceSha256 $hash
            $ambiguous.missingInputs | Should -Contain workspaceOverlap
            $ambiguous.rows.Count | Should -Be 0
        }

        It 'populates table-bound Excel charts and private HTML while admitting only closed COST conditions' {
            (Invoke-ApimAnalyze -RunFolder $script:telemetryPath).ExitCode | Should -Be 0
            $candidate = New-ApimAnalysisPackage -RunPath $script:telemetryPath -Config $script:telemetryInput.Config
            $candidatePath = Join-Path $script:telemetryPath "restricted/candidates/$($candidate.candidateId)/analysis-package.json"
            $json = Get-Content -LiteralPath $candidatePath -Raw
            $package = ConvertFrom-Json $json
            $package.schemaVersion | Should -Be '1.5'
            $package.facts.Where({ $_.code -ceq 'AssessmentCondition' }).value |
                Should -Contain NormalizedCostIncreasing
            $json | Should -Not -Match 'orders-v1|logic-synthetic|USD|1000000|capacityP95|resourceId|workspaceId'
            $validation = Test-ApimAnalysisPackage -CandidatePath $candidatePath
            $validation.status | Should -Be Passed
            $root = Split-Path $script:telemetryInput.Config.Output.Root -Parent
            $analysisRoot = Join-Path $root "analysis-$($candidate.candidateId)"
            $publication = Publish-ApimAnalysisPackage -RestrictedRoot $script:telemetryPath `
                -CandidateId $candidate.candidateId -AnalysisRoot $analysisRoot `
                -PrivateStagingRoot (Join-Path $root "stage-$($candidate.candidateId)") `
                -CopilotVisiblePath @($analysisRoot) -VisibleRootsComplete -Version version-000001
            $publication.status | Should -Be Promoted
            $conditions = @($package.facts | Where-Object {
                    $_.code -ceq 'AssessmentCondition' -and $_.value -ceq 'NormalizedCostIncreasing'
                })
            $conditions.Count | Should -Be 1
            $conditions[0].subjectAlias = @($package.entities | Where-Object kind -CEQ Api)[0].alias
            { Test-ApimAnalysisContract -Kind AnalysisPackage -Json (ConvertTo-Json $package -Depth 30) } |
                Should -Throw
            $package = ConvertFrom-Json $json
            $costFinding = @($package.findings | Where-Object ruleId -CEQ APIM-COST-002)[0]
            $costFinding.factRefs = @(@($package.facts | Where-Object {
                        $_.code -ceq 'AssessmentCondition' -and $_.value -ceq 'PremiumCapacityReview'
                    })[0].factId)
            { Test-ApimAnalysisContract -Kind AnalysisPackage -Json (ConvertTo-Json $package -Depth 30) } |
                Should -Throw
            $excelPath = Export-ApimActionPlan -RunPath $script:telemetryPath
            $workbook = Open-ExcelPackage -Path $excelPath
            try {
                $workbook.Workbook.Worksheets['Usage'].Tables['tblUsage'].Address.End.Row | Should -BeGreaterThan 4
                $workbook.Workbook.Worksheets['Usage'].Drawings.Count | Should -Be 1
                $workbook.Workbook.Worksheets['Cost'].Drawings.Count | Should -Be 1
                $workbook.Workbook.Worksheets['Usage'].Drawings[0].Series[0].Series | Should -Match 'tblUsageTrend'
                $workbook.Workbook.Worksheets['Cost'].Drawings[0].Series[0].Series | Should -Match 'tblCostTrend'
            }
            finally { $workbook.Dispose() }
            (Export-ApimExecutiveHtml -RunPath $script:telemetryPath -WorkbookPath $excelPath).status | Should -Be Completed
            Get-Content -LiteralPath ([IO.Path]::ChangeExtension($excelPath, '.html')) -Raw |
                Should -Match 'Cost per million|Normalized|cost per million'
            Should -Invoke Invoke-ApimArm -Exactly -Times 0
        }
    }
}
