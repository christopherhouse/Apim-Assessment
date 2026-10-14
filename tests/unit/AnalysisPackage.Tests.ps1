$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Allowlist analysis package construction' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:builderRepository = $Repository
        BeforeAll {
            . (Join-Path $script:builderRepository 'tests/helpers/New-AnalysisTestRun.ps1')
        }
        BeforeEach {
            $script:builderRun = New-AnalysisTestRun -Root (
                Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            ) -Repository $script:builderRepository
        }

        It 'constructs only aliases, typed facts and qualified deterministic findings' {
            $result = New-ApimAnalysisPackage -RunPath $script:builderRun.RunPath `
                -Config $script:builderRun.Config
            $folder = Join-Path $script:builderRun.RunPath "restricted/candidates/$($result.candidateId)"
            $json = Get-Content (Join-Path $folder 'analysis-package.json') -Raw
            Test-ApimAnalysisContract -Kind AnalysisPackage -Json $json | Should -BeTrue
            $package = $json | ConvertFrom-Json
            $package.schemaVersion | Should -Be '1.1'
            $package.entities.Count | Should -BeGreaterThan 10
            $package.dataGaps | Should -Contain UsageUnavailable
            $package.dataGaps | Should -Contain CostUnavailable
            $package.assumptions | Should -Contain TelemetryUnavailable
            $package.facts.Where({ $_.code -eq 'UsageBucket' }).value |
                Select-Object -Unique | Should -Be 'Unknown'
            $package.facts.Where({ $_.code -eq 'AssessmentCondition' }).value |
                Should -Contain PolicyCredentialDetected
            $json | Should -Not -Match 'synthetic|orders-v1|status-v1|apim-example|evidenceText|priorityScore|apiId|gateway'
            $map = Get-Content (Join-Path $folder 'alias-map.json') -Raw | ConvertFrom-Json
            $map.aliases.scope | Should -Contain 'api:orders-v1'
            $map.aliases[0].PSObject.Properties.Name | Should -Be @('alias', 'scope')
            $package.findings.Where({ $_.evaluation -eq 'NotEvaluated' }).ForEach({
                $_.severity | Should -Be Info
                $_.priorityBucket | Should -Be Unknown
                $_.dataGaps.Count | Should -BeGreaterThan 0
            })
        }

        It 'is byte-identical on rerun and under shuffled model and finding order' {
            $first = New-ApimAnalysisPackage -RunPath $script:builderRun.RunPath `
                -Config $script:builderRun.Config
            $models = Get-ApimModelSet -RunPath $script:builderRun.RunPath
            foreach ($key in $models.Keys) {
                if ($models[$key] -is [array]) {
                    [array]::Reverse($models[$key])
                }
            }
            $null = Write-ApimModelSet -RunPath $script:builderRun.RunPath -Models $models
            $findings = @(Get-ApimFindingSet -RunPath $script:builderRun.RunPath)
            [array]::Reverse($findings)
            $null = Write-ApimFindingSet -RunPath $script:builderRun.RunPath -Findings $findings
            $second = New-ApimAnalysisPackage -RunPath $script:builderRun.RunPath `
                -Config $script:builderRun.Config
            foreach ($file in @('analysis-package.json', 'alias-map.json')) {
                $a = Join-Path $script:builderRun.RunPath "restricted/candidates/$($first.candidateId)/$file"
                $b = Join-Path $script:builderRun.RunPath "restricted/candidates/$($second.candidateId)/$file"
                (Get-FileHash $a).Hash | Should -Be (Get-FileHash $b).Hash
            }
        }

        It 'does not copy unrestricted source text from otherwise valid fields' {
            $canary = 'https://marker-airlock.invalid/credential?sig=NEVER_COPY_THIS_MARKER'
            $path = Join-Path $script:builderRun.RunPath 'model/apis.json'
            $apis = Get-Content $path -Raw | ConvertFrom-Json -NoEnumerate
            $apis[0].displayName = $canary
            $null = Write-ApimModelSet -RunPath $script:builderRun.RunPath -Models @{ apis = $apis }
            $result = New-ApimAnalysisPackage -RunPath $script:builderRun.RunPath `
                -Config $script:builderRun.Config
            Get-ChildItem (Join-Path $script:builderRun.RunPath "restricted/candidates/$($result.candidateId)") |
                ForEach-Object { Get-Content $_.FullName -Raw | Should -Not -Match 'NEVER_COPY|marker-airlock' }
        }

        It 'rejects unsupported, changed, or malformed inputs with fixed errors: <Mutation>' -ForEach @(
            @{ Mutation = 'missing model' }
            @{ Mutation = 'unknown source field' }
            @{ Mutation = 'stale severity' }
            @{ Mutation = 'bad thresholds' }
            @{ Mutation = 'changed scoring' }
            @{ Mutation = 'tainted identity' }
        ) {
            switch ($Mutation) {
                'missing model' { Remove-Item (Join-Path $script:builderRun.RunPath 'model/apis.json') }
                'unknown source field' {
                    $path = Join-Path $script:builderRun.RunPath 'model/apis.json'
                    $rows = Get-Content $path -Raw | ConvertFrom-Json -AsHashtable
                    $rows[0].unexpected = 'NEVER_COPY_MUTATION'
                    [IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $rows -Depth 32))
                }
                'stale severity' {
                    $path = Join-Path $script:builderRun.RunPath 'findings.json'
                    $rows = Get-Content $path -Raw | ConvertFrom-Json -AsHashtable
                    $rows[0].severity = 'Info'
                    [IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $rows -Depth 32))
                }
                'bad thresholds' { $script:builderRun.Config.AnalysisPackage.UsageBuckets = @(0, 1) }
                'changed scoring' { $script:builderRun.Config.Scoring.Severity.High = 4 }
                'tainted identity' {
                    $path = Join-Path $script:builderRun.RunPath 'model/namedValues.json'
                    $rows = Get-Content $path -Raw | ConvertFrom-Json -AsHashtable
                    $rows[0].namedValueId = 'password=NEVER_COPY_MUTATION'
                    [IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $rows -Depth 32))
                }
            }
            { New-ApimAnalysisPackage -RunPath $script:builderRun.RunPath `
                    -Config $script:builderRun.Config } | Should -Throw '*ANALYSIS_BUILD_REJECTED*'
            Test-Path (Join-Path $script:builderRun.RunPath 'restricted/candidates') | Should -BeFalse
        }

        It 'uses all configured usage bands and exact threshold boundaries without releasing counts' {
            $thresholds = @(0, 1, 1000, 10000, 100000, 1000000)
            foreach ($case in @(
                    @($null, 'Unknown'), @(0, 'Zero'), @(1, 'Low'),
                    @(999, 'Low'), @(1000, 'Medium'), @(10000, 'High'),
                    @(100000, 'VeryHigh'), @(1000000, 'Extreme')
                )) {
                Get-ApimAnalysisUsageBand -Calls $case[0] -Thresholds $thresholds |
                    Should -Be $case[1]
            }
            Get-ApimAnalysisUsageBand -Calls 1 -Thresholds @(0, 10, 20, 30, 40, 50) |
                Should -Be VeryLow
        }

        It 'does not write candidates for WhatIf' {
            New-ApimAnalysisPackage -RunPath $script:builderRun.RunPath `
                -Config $script:builderRun.Config -WhatIf | Should -BeNullOrEmpty
            Test-Path (Join-Path $script:builderRun.RunPath 'restricted/candidates') | Should -BeFalse
        }
    }
}
