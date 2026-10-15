$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Offline governance report and model-safe delivery' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:governanceDeliveryRepository = $Repository
        BeforeAll {
            . (Join-Path $script:governanceDeliveryRepository 'tests/helpers/New-SyntheticCollectedRun.ps1')
            Mock Invoke-ApimArm { throw 'Governance delivery must remain offline.' }
            Mock Get-ApimSpectralTool { return $null }
            $script:governanceDeliveryRoot = Join-Path $TestDrive 'delivery'
            $inputRun = New-SyntheticCollectedRun -RepoRoot $script:governanceDeliveryRepository `
                -OutputRoot (Join-Path $script:governanceDeliveryRoot 'restricted')
            $script:governanceDeliveryPath = $inputRun.Run.Path
            $script:governanceDeliveryConfig = $inputRun.Config
            $inputRun.Config.Governance = @{
                Products = @(
                    @{ ProductId = 'internal'; HasOwner = $true; IsExternal = $false }
                    @{ ProductId = 'partner'; HasOwner = $true; IsExternal = $true }
                    @{ ProductId = 'orphan'; HasOwner = $false; IsExternal = $false }
                )
                CriticalApiIds = @('orders-v1')
            }
            $products = Read-ApimSmokeOutputJson -RunPath $script:governanceDeliveryPath `
                -RelativePath raw/products.json -Collection
            $products.value += [pscustomobject]@{ name = 'orphan'; properties = @{
                    description = 'SYNTHETIC_RESTRICTED_PRODUCT_DESCRIPTION'
                    approvalRequired = $true; state = 'published'; subscriptionRequired = $true
                } }
            $null = Write-RunFile -RunPath $script:governanceDeliveryPath `
                -RelativePath raw/products.json -InputObject $products
            foreach ($kind in @('productApis', 'productGroups')) {
                $null = Write-RunFile -RunPath $script:governanceDeliveryPath `
                    -RelativePath "raw/$kind/orphan.json" -InputObject @{ value = @() }
            }
            Set-RunCollectorStatus -RunPath $script:governanceDeliveryPath `
                -Name Products -Status Completed -Items 3
            $policies = Read-ApimSmokeOutputJson -RunPath $script:governanceDeliveryPath `
                -RelativePath policies/index.json
            $policies.policies += [pscustomobject]@{
                scopeType = 'Product'; scope = 'orphan'; file = 'policies/product.orphan.xml'
                exists = $false; sha256 = $null; hardcodedSecretLocations = @()
            }
            $null = Write-RunFile -RunPath $script:governanceDeliveryPath `
                -RelativePath policies/index.json -InputObject $policies
            Set-RunCollectorStatus -RunPath $script:governanceDeliveryPath `
                -Name Policies -Status Completed -Items 9
            $diagnostics = Read-ApimSmokeOutputJson -RunPath $script:governanceDeliveryPath `
                -RelativePath raw/apiDiagnostics/orders-v1.json -Collection
            $diagnostics.value[0].properties.sampling.percentage = 23.5
            $null = Write-RunFile -RunPath $script:governanceDeliveryPath `
                -RelativePath raw/apiDiagnostics/orders-v1.json -InputObject $diagnostics
            $users = Get-ApimEmptyUserSummary
            $users.total = 17; $users.byState.active = 17; $users.byProvider.aad = 17
            $null = Write-RunFile -RunPath $script:governanceDeliveryPath `
                -RelativePath raw/users.summary.json -InputObject $users
            Set-RunCollectorStatus -RunPath $script:governanceDeliveryPath `
                -Name Organization -Status Completed -Items 17 -Files @((Get-ApimOrganizationEndpoint).File)
            Save-ApimRunSetting -RunPath $script:governanceDeliveryPath -Config $inputRun.Config `
                -Environment $inputRun.Config.Environments[0]
            (Invoke-ApimAnalyze -RunFolder $script:governanceDeliveryPath).ExitCode | Should -Be 0
            $candidate = New-ApimAnalysisPackage -RunPath $script:governanceDeliveryPath `
                -Config $inputRun.Config
            $script:governanceCandidateId = $candidate.candidateId
            $script:governanceCandidatePath = Join-Path $script:governanceDeliveryPath (
                "restricted/candidates/$($candidate.candidateId)/analysis-package.json"
            )
            $script:governancePackageJson = Get-Content $script:governanceCandidatePath -Raw
        }
        BeforeEach {
            $script:governancePackage = ConvertFrom-Json $script:governancePackageJson -AsHashtable
        }

        It 'exports only the two fixed conditions with unique aliases including unreferenced products' {
            $script:governancePackage.schemaVersion | Should -Be '1.4'
            $findings = @($script:governancePackage.findings | Where-Object {
                    $_.ruleId -cin @('APIM-GOV-003', 'APIM-GOV-009') -and $_.evaluation -ceq 'Evaluated'
                })
            $findings.Count | Should -Be 2
            $facts = @($script:governancePackage.facts | Where-Object factId -In $findings.factRefs)
            @($facts.value | Sort-Object) | Should -Be @('ApiDiagnosticsWeak', 'ProductGovernanceWeak')
            $entities = @($script:governancePackage.entities | Where-Object kind -CEQ Product)
            $entities.Count | Should -Be 3
            @($entities.alias | Select-Object -Unique).Count | Should -Be 3
            $productFinding = @($findings | Where-Object ruleId -CEQ 'APIM-GOV-003')[0]
            $entities.alias | Should -Contain $productFinding.subjectAlias
            $script:governancePackageJson | Should -Not -MatchExactly (
                'orphan|orders-v1|"internal"|"partner"|SYNTHETIC_RESTRICTED|23\.5|"17"|' +
                '"(?:total|byState|byProvider|hasOwner|isExternal|criticalApiIds|samplingPercentage|reasonCodes)"'
            )
            Should -Invoke Invoke-ApimArm -Exactly -Times 0
        }

        It 'preserves old package admission while rejecting new conditions in version <Version>' -ForEach @(
            @{ Version = '1.0' }; @{ Version = '1.1' }; @{ Version = '1.2' }; @{ Version = '1.3' }
        ) {
            $legacy = Get-Content (Join-Path $script:governanceDeliveryRepository `
                    'tests/fixtures/synthetic-reference/analysis-contracts/analysis-package.json') -Raw |
                ConvertFrom-Json -AsHashtable
            $legacy.schemaVersion = $Version
            Test-ApimAnalysisContract -Kind AnalysisPackage `
                -Json (ConvertTo-Json $legacy -Depth 32) | Should -BeTrue
            $script:governancePackage.schemaVersion = $Version
            { Test-ApimAnalysisContract -Kind AnalysisPackage `
                    -Json (ConvertTo-Json $script:governancePackage -Depth 32) } | Should -Throw
        }

        It 'rejects schema-valid governance binding tampering: <Case>' -ForEach @(
            @{ Case = 'wrong kind' }; @{ Case = 'wrong subject' }; @{ Case = 'wrong condition' }
        ) {
            $finding = @($script:governancePackage.findings | Where-Object {
                    $_.ruleId -ceq 'APIM-GOV-003' -and $_.evaluation -ceq 'Evaluated'
                })[0]
            $fact = @($script:governancePackage.facts | Where-Object factId -In $finding.factRefs)[0]
            switch ($Case) {
                'wrong kind' {
                    $entity = @($script:governancePackage.entities |
                            Where-Object alias -CEQ $finding.subjectAlias)[0]
                    $entity.kind = 'Service'
                }
                'wrong subject' {
                    $fact.subjectAlias = @($script:governancePackage.entities |
                            Where-Object kind -CEQ Product |
                            Where-Object alias -CNE $finding.subjectAlias)[0].alias
                }
                'wrong condition' { $fact.value = 'OwnerTagMissing' }
            }
            { Test-ApimAnalysisContract -Kind AnalysisPackage `
                    -Json (ConvertTo-Json $script:governancePackage -Depth 32) } | Should -Throw
        }

        It 'independently validates, promotes and admits the digest-bound package through the broker' {
            $attestation = Test-ApimAnalysisPackage -CandidatePath $script:governanceCandidatePath
            $attestation.packageSchemaVersion | Should -Be '1.4'
            $publicationArguments = @{
                RestrictedRoot = $script:governanceDeliveryPath
                CandidateId = $script:governanceCandidateId
                AnalysisRoot = Join-Path $script:governanceDeliveryRoot 'analysis'
                PrivateStagingRoot = Join-Path $script:governanceDeliveryRoot 'private-stage'
                CopilotVisiblePath = @((Join-Path $script:governanceDeliveryRoot 'analysis'))
                VisibleRootsComplete = $true; Version = 'version-000001'
            }
            $publication = Publish-ApimAnalysisPackage @publicationArguments
            $publication.status | Should -Be Promoted
            $context = @{ operator = @{
                    restrictedRoot = $publicationArguments.RestrictedRoot
                    analysisRoot = $publicationArguments.AnalysisRoot
                    privateStagingRoot = $publicationArguments.PrivateStagingRoot
                    visibleRoots = $publicationArguments.CopilotVisiblePath
                } }
            Get-ApimBrokerPublication -Context $context -Run @{ publication = $publication } |
                Should -BeExactly $script:governancePackageJson
            $publication.packageSha256 = '0' * 64
            { Get-ApimBrokerPublication -Context $context -Run @{ publication = $publication } } |
                Should -Throw 'BROKER_PACKAGE_REJECTED'
        }

        It 'independently rejects unknown condition text and user-count fields without the schema gate' {
            $fact = @($script:governancePackage.facts |
                    Where-Object value -CEQ ProductGovernanceWeak)[0]
            $fact.value = 'UNAPPROVED_PRODUCT_DESCRIPTION'
            { Assert-ApimAnalysisScan -Package $script:governancePackage } |
                Should -Throw 'ANALYSIS_SCAN_REJECTED'
            $fact.value = 'ProductGovernanceWeak'
            $script:governancePackage.userCount = 17
            { Assert-ApimAnalysisScan -Package $script:governancePackage } |
                Should -Throw 'ANALYSIS_SCAN_REJECTED'
        }

        It 'entails governance and diagnostics specialist claims without cross-condition substitution' {
            foreach ($case in @(
                    @{ Rule = 'APIM-GOV-003'; Claim = 'GovernanceGap'; Recommendation = 'EstablishOwnership'
                        Analyst = 'ArchitectureExposure'; Category = 'Governance'; Id = 'architecture' }
                    @{ Rule = 'APIM-GOV-009'; Claim = 'InsufficientDiagnostics'; Recommendation = 'EnableDiagnostics'
                        Analyst = 'Security'; Category = 'Security'; Id = 'security' }
                )) {
                $finding = @($script:governancePackage.findings | Where-Object {
                        $_.ruleId -ceq $case.Rule -and $_.evaluation -ceq 'Evaluated'
                    })[0]
                $fact = @($script:governancePackage.facts | Where-Object factId -In $finding.factRefs)[0]
                $observation = @{ schemaVersion = '1.0'; analyst = $case.Analyst; observations = @(
                        @{ observationId = "observation-$($case.Id)-001"; category = $case.Category
                            confidence = 'Low'; findingRefs = @($finding.findingId); factRefs = @($fact.factId)
                            rationaleCode = $case.Claim; recommendationCode = $case.Recommendation }
                    ) }
                Test-ApimAgentClaim -Kind ExpertObservations -Json (ConvertTo-Json $observation -Depth 10) `
                    -PackageJson $script:governancePackageJson | Should -BeTrue
                $otherClaim = if ($case.Rule -ceq 'APIM-GOV-003') { 'InsufficientDiagnostics' } else { 'GovernanceGap' }
                Test-ApimClaimFact -Claim $otherClaim -Fact $fact | Should -BeFalse
            }
        }

        It 'renders both findings and catalog rows and replays tracking and package generation offline' {
            (Invoke-ApimReport -RunFolder $script:governanceDeliveryPath).ExitCode | Should -Be 0
            $reports = Get-ApimRenderedPath -RunPath $script:governanceDeliveryPath
            $workbook = Open-ExcelPackage -Path $reports.workbook
            try {
                $detailRow = $workbook.Workbook.Worksheets['Finding Details'].Tables['tblFindings'].Address.Start.Row
                $ruleRow = $workbook.Workbook.Worksheets['Method & Rules'].Tables['tblRules'].Address.Start.Row
            }
            finally { $workbook.Dispose() }
            $details = @(Import-Excel -Path $reports.workbook -WorksheetName 'Finding Details' -StartRow $detailRow)
            $rules = @(Import-Excel -Path $reports.workbook -WorksheetName 'Method & Rules' -StartRow $ruleRow)
            $html = Get-Content $reports.html -Raw
            foreach ($id in @('APIM-GOV-003', 'APIM-GOV-009')) {
                $details.'Rule ID' | Should -Contain $id
                $rules.'Rule ID' | Should -Contain $id
            }
            $evaluatedCount = @(Get-ApimFindingSet -RunPath $script:governanceDeliveryPath |
                    Where-Object evaluation -CEQ Evaluated).Count
            $html | Should -Match "<strong>$evaluatedCount</strong>Evaluated findings"
            $html | Should -Match 'APIM-GOV-009'
            $before = Get-Content (Join-Path $script:governanceDeliveryPath findings.json) -Raw
            $workbook = Open-ExcelPackage -Path $reports.workbook
            try {
                $sheet = $workbook.Workbook.Worksheets['Finding Details']
                $table = $sheet.Tables['tblFindings']
                $column = [array]::IndexOf(@($table.Columns.Name), 'Status') + $table.Address.Start.Column
                $index = [array]::IndexOf(@($details.'Rule ID'), 'APIM-GOV-003')
                $sheet.Cells[($detailRow + $index + 1), $column].Value = 'Accepted risk'
                $workbook.Save()
            }
            finally { $workbook.Dispose() }
            (Invoke-ApimReport -RunFolder $script:governanceDeliveryPath `
                    -PreviousReport $reports.workbook).ExitCode | Should -Be 0
            $next = Get-ApimRenderedPath -RunPath $script:governanceDeliveryPath
            $carried = @(Import-Excel -Path $next.workbook -WorksheetName 'Finding Details' -StartRow $detailRow)
            @($carried | Where-Object 'Rule ID' -CEQ 'APIM-GOV-003')[0].Status | Should -Be 'Accepted risk'
            (Invoke-ApimAnalyze -RunFolder $script:governanceDeliveryPath).ExitCode | Should -Be 0
            Get-Content (Join-Path $script:governanceDeliveryPath findings.json) -Raw |
                Should -BeExactly $before
            $candidate = New-ApimAnalysisPackage -RunPath $script:governanceDeliveryPath `
                -Config $script:governanceDeliveryConfig
            Get-Content (Join-Path $script:governanceDeliveryPath (
                    "restricted/candidates/$($candidate.candidateId)/analysis-package.json"
                )) -Raw | Should -BeExactly $script:governancePackageJson
        }

        It 'compares saved governance findings without guessing across changed intent settings' {
            $baseline = New-SyntheticCollectedRun -RepoRoot $script:governanceDeliveryRepository `
                -OutputRoot (Join-Path $TestDrive 'comparison-baseline') -RunId baseline
            (Invoke-ApimAnalyze -RunFolder $baseline.Run.Path).ExitCode | Should -Be 0
            (Compare-ApimRun -Baseline $baseline.Run.Path -Current $script:governanceDeliveryPath).ExitCode |
                Should -Be 0
            $comparison = Get-ApimSavedComparison -RunPath $script:governanceDeliveryPath
            $comparison.gaps.ruleId | Should -Contain APIM-GOV-003
            $comparison.gaps.ruleId | Should -Contain APIM-GOV-009
        }
    }
}
