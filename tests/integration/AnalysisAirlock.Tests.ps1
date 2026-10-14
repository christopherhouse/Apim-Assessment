$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Offline model-data airlock integration' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:airlockRepository = $Repository
        BeforeAll {
            . (Join-Path $script:airlockRepository 'tests/helpers/New-AnalysisTestRun.ps1')
            . (Join-Path $script:airlockRepository 'tests/fixtures/synthetic-reference/scaled/New-SyntheticReference.ps1')

            function Get-AirlockPublication {
                param([object] $Run, [string] $CandidateId, [string] $Root)
                return @{
                    RestrictedRoot = $Run.RunPath
                    CandidateId = $CandidateId
                    AnalysisRoot = Join-Path $Root 'analysis'
                    PrivateStagingRoot = Join-Path $Root 'private-stage'
                    CopilotVisiblePath = @((Join-Path $Root 'analysis'))
                    VisibleRootsComplete = $true
                    Version = 'version-000001'
                }
            }
        }

        It 'runs the scaled saved-input pipeline with <Scenario> and leaves source bytes unchanged' -ForEach @(
            @{ Scenario = 'unknown usage'; WithUsage = $false }
            @{ Scenario = 'explicit synthetic usage'; WithUsage = $true }
        ) {
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $models = New-SyntheticReferenceModelSet -WithUsage:$WithUsage
            $run = New-AnalysisTestRun -Root $root -Repository $script:airlockRepository -Models $models
            $sourceHashes = @{}
            foreach ($file in Get-ChildItem $run.RunPath -Recurse -File) {
                $sourceHashes[$file.FullName] = (Get-FileHash $file.FullName).Hash
            }
            $built = New-ApimAnalysisPackage -RunPath $run.RunPath -Config $run.Config
            $candidate = Join-Path $run.RunPath "restricted/candidates/$($built.candidateId)/analysis-package.json"
            $attestation = Test-ApimAnalysisPackage -CandidatePath $candidate
            $publication = Get-AirlockPublication -Run $run -CandidateId $built.candidateId -Root $root
            $result = Publish-ApimAnalysisPackage @publication
            $result.packageSha256 | Should -Be $attestation.packageSha256
            $published = Join-Path $publication.AnalysisRoot 'version-000001/analysis-package.json'
            $package = Get-Content $published -Raw | ConvertFrom-Json
            $package.entities.Where({ $_.kind -eq 'Api' }).Count | Should -Be 60
            if ($WithUsage) {
                $package.facts.Where({
                    $_.code -eq 'UsageBucket' -and $_.value -eq 'Zero'
                }).Count | Should -Be 11
            }
            else {
                $package.assumptions | Should -Contain TelemetryUnavailable
                $package.facts.Where({
                    $_.code -eq 'UsageBucket' -and $_.value -ne 'Unknown'
                }).Count | Should -Be 0
            }
            $package.facts.Where({
                $_.code -eq 'AssessmentCondition' -and $_.value -eq 'ProductMissing'
            }).Count | Should -Be 14
            $package.facts.Where({
                $_.code -eq 'AssessmentCondition' -and $_.value -eq 'PolicyCredentialDetected'
            }).Count | Should -Be 2
            foreach ($path in $sourceHashes.Keys) {
                (Get-FileHash $path).Hash | Should -Be $sourceHashes[$path]
            }
            $second = New-ApimAnalysisPackage -RunPath $run.RunPath -Config $run.Config
            $repeat = Join-Path $run.RunPath "restricted/candidates/$($second.candidateId)/analysis-package.json"
            (Get-FileHash $repeat).Hash | Should -Be (Get-FileHash $candidate).Hash
            @(Get-ChildItem (Split-Path $published -Parent) -File).Count | Should -Be 2
        }

        It 'excludes source canaries from candidates, maps, streams, attestations and publication: <Label>' -ForEach @(
            @{ Label = 'identifier'; Canary = '/subscriptions/11223344-5566-7788-9900-aabbccddeeff/resourceGroups/airlock-marker' }
            @{ Label = 'URL'; Canary = 'https://airlock-marker.invalid/NEVER_COPY_FRAGMENT' }
            @{ Label = 'IP'; Canary = '203.0.113.47/24' }
            @{ Label = 'UPN'; Canary = 'NEVER_COPY_FRAGMENT@airlock-marker.invalid' }
            @{ Label = 'policy'; Canary = '<policies><inbound>NEVER_COPY_FRAGMENT</inbound></policies>' }
            @{ Label = 'metrics'; Canary = 'calls90d=987654321;cost=12345.67;NEVER_COPY_FRAGMENT' }
            @{ Label = 'credential'; Canary = 'AccountKey=NEVER_COPY_FRAGMENT' }
            @{ Label = 'percent'; Canary = '%4e%45%56%45%52%5f%43%4f%50%59%5f%46%52%41%47%4d%45%4e%54' }
            @{ Label = 'base64'; Canary = 'TkVWRVJfQ09QWV9GUkFHTUVOVF9BSVJMT0NLX01BUktFUg==' }
            @{ Label = 'hex'; Canary = '4e455645525f434f50595f465241474d454e545f4149524c4f434b' }
            @{ Label = 'Unicode'; Canary = "NEVER_COPY_$([char]0x200b)FRAGMENT" }
            @{ Label = 'entropy'; Canary = 'Q7v9K2n4Z8p6R3x5W1c0D9f7H6j4L2m8N5s3T1u0V9y7B6a' }
        ) {
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $run = New-AnalysisTestRun -Root $root -Repository $script:airlockRepository
            $manifest = Get-RunManifest -RunPath $run.RunPath
            $manifest.customer = $Canary
            $manifest.operator = $Canary
            $null = Save-RunManifest -RunPath $run.RunPath -Manifest $manifest
            $models = Get-ApimModelSet -RunPath $run.RunPath
            foreach ($api in $models.apis) {
                $api.displayName = $Canary
                $api.backendHost = $Canary
                $api.tags = @($Canary)
                $api.ownerTag = $Canary
            }
            foreach ($operation in $models.operations) { $operation.fullPath = "/$Canary" }
            foreach ($subscription in $models.subscriptions) { $subscription.displayName = $Canary }
            $models.network.nsgName = $Canary
            $models.network.appGatewayTlsPolicyNames = @($Canary)
            $null = Write-ApimModelSet -RunPath $run.RunPath -Models $models
            $rules = @(Get-ApimRuleCatalog -CatalogPath (Join-Path $script:airlockRepository 'rules'))
            $findings = @(Invoke-ApimRuleEngine -Rules $rules -Models $models `
                    -Manifest $manifest -Config $run.Config)
            $null = Write-ApimFindingSet -RunPath $run.RunPath -Findings $findings
            $streams = @(New-ApimAnalysisPackage -RunPath $run.RunPath -Config $run.Config *>&1)
            $streams.Count | Should -Be 1
            $candidateId = $streams[0].candidateId
            $publication = Get-AirlockPublication -Run $run -CandidateId $candidateId -Root $root
            $streams += @(Publish-ApimAnalysisPackage @publication *>&1)
            $safeTexts = @($streams | ConvertTo-Json -Depth 32)
            $safeTexts += @(Get-ChildItem (Join-Path $run.RunPath "restricted/candidates/$candidateId") -File |
                    ForEach-Object { Get-Content $_.FullName -Raw })
            $safeTexts += @(Get-ChildItem $publication.AnalysisRoot -Recurse -File |
                    ForEach-Object { Get-Content $_.FullName -Raw })
            foreach ($text in $safeTexts) {
                $text.Contains($Canary) | Should -BeFalse
                $text | Should -Not -Match 'NEVER_COPY|airlock-marker|FRAGMENT'
            }
        }

        It 'rejects a newly introduced source field before producing output or staging' {
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $run = New-AnalysisTestRun -Root $root -Repository $script:airlockRepository
            $path = Join-Path $run.RunPath 'model/service.json'
            $source = Get-Content $path -Raw | ConvertFrom-Json -AsHashtable
            $source.customerPrompt = 'NEVER_COPY_FRAGMENT'
            [IO.File]::WriteAllText($path, (ConvertTo-Json $source -Depth 32))
            $messages = @()
            try { $messages = @(New-ApimAnalysisPackage -RunPath $run.RunPath -Config $run.Config *>&1) }
            catch { $messages += $_.Exception.Message }
            $messages | Should -Be @('ANALYSIS_BUILD_REJECTED')
            Test-Path (Join-Path $run.RunPath 'restricted/candidates') | Should -BeFalse
            Test-Path (Join-Path $root 'analysis') | Should -BeFalse
        }

        It 'rejects tampered builder output and leaves an earlier published version intact' {
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $run = New-AnalysisTestRun -Root $root -Repository $script:airlockRepository
            $built = New-ApimAnalysisPackage -RunPath $run.RunPath -Config $run.Config
            $publication = Get-AirlockPublication -Run $run -CandidateId $built.candidateId -Root $root
            $null = Publish-ApimAnalysisPackage @publication
            $published = Join-Path $publication.AnalysisRoot 'version-000001/analysis-package.json'
            $hash = (Get-FileHash $published).Hash
            $candidate = Join-Path $run.RunPath "restricted/candidates/$($built.candidateId)/analysis-package.json"
            $package = Get-Content $candidate -Raw | ConvertFrom-Json -AsHashtable
            $package.facts[0].value = 'https://airlock-marker.invalid/NEVER_COPY_FRAGMENT'
            [IO.File]::WriteAllText($candidate, (ConvertTo-ApimAnalysisJson $package))
            $publication.Version = 'version-000002'
            $messages = @()
            try { $messages = @(Publish-ApimAnalysisPackage @publication *>&1) }
            catch { $messages += $_.Exception.Message }
            $messages | Should -Be @('ANALYSIS_PROMOTION_REJECTED')
            (Get-FileHash $published).Hash | Should -Be $hash
            @(Get-ChildItem $publication.AnalysisRoot).Count | Should -Be 1
            @(Get-ChildItem $publication.PrivateStagingRoot -Force).Count | Should -Be 0
        }
    }
}
