$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Saved OpenAPI quality and offline replay' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:savedQualityRepository = $Repository

        BeforeAll {
            . (Join-Path $script:savedQualityRepository 'tests/helpers/New-SyntheticCollectedRun.ps1')
        }
        BeforeEach {
            $script:savedQualityRun = New-SyntheticCollectedRun `
                -RepoRoot $script:savedQualityRepository `
                -OutputRoot (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
            $script:savedQualityPath = $script:savedQualityRun.Run.Path
            Mock Get-ApimSpectralTool { return $null }
            Mock Invoke-ApimSpectral { throw 'Unexpected linter execution during unavailable-tool fallback.' }
            Mock Invoke-ApimArm { throw 'Offline quality attempted Azure access.' }
            Mock Invoke-ApimResourceGraphQuery { throw 'Offline quality attempted Resource Graph access.' }
        }

        It 'saves explicit unavailable-tool rows, preserves scores as null and reports without a linter' {
            $null = Write-RunFile -RunPath $script:savedQualityPath `
                -RelativePath 'raw/openapi/unlisted.json' -InputObject @{ unexpected = 'STALE_SYNTHETIC' }
            (Invoke-ApimAnalyze -RunFolder $script:savedQualityPath).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:savedQualityPath
            $models.openApiQuality.Count | Should -Be $models.apis.Count
            @($models.openApiQuality.status | Select-Object -Unique) | Should -Be @('ToolUnavailable')
            foreach ($row in $models.openApiQuality) {
                $row.score | Should -BeNullOrEmpty
                $row.sourceSha256 | Should -Match '^[a-f0-9]{64}$'
                $row.operationCount | Should -Be 1
                $row.descriptionCoverage | Should -BeIn @(0, 100)
            }
            @($models.apis | Where-Object { $null -ne $_.openApiScore }).Count | Should -Be 0
            (Invoke-ApimReport -RunFolder $script:savedQualityPath).ExitCode | Should -Be 0
            Should -Invoke Invoke-ApimSpectral -Times 0 -Exactly
            Should -Invoke Invoke-ApimArm -Times 0 -Exactly
            Should -Invoke Invoke-ApimResourceGraphQuery -Times 0 -Exactly
        }

        It 'replays quality independently of API inventory and quality row order' {
            (Invoke-ApimAnalyze -RunFolder $script:savedQualityPath).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:savedQualityPath
            [array]::Reverse($models.apis)
            [array]::Reverse($models.operations)
            [array]::Reverse($models.openApiQuality)
            $null = Write-ApimModelSet -RunPath $script:savedQualityPath -Models $models
            $replayed = Get-ApimModelSet -RunPath $script:savedQualityPath
            $replayed.openApiQuality.Count | Should -Be $models.apis.Count
            Should -Invoke Invoke-ApimSpectral -Times 0 -Exactly
        }

        It 'does not reuse unlisted failed-collector exports as successful evidence' {
            Set-RunCollectorStatus -RunPath $script:savedQualityPath -Name OpenApi `
                -Status Failed -Errors 1
            $null = Write-RunFile -RunPath $script:savedQualityPath `
                -RelativePath 'raw/openapi/index.json' -InputObject @{ unexpected = 'STALE_SYNTHETIC' }
            (Invoke-ApimAnalyze -RunFolder $script:savedQualityPath).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:savedQualityPath
            @($models.openApiQuality.status | Select-Object -Unique) | Should -Be @('ExportUnavailable')
            foreach ($row in $models.openApiQuality) {
                $row.sourceSha256 | Should -BeNullOrEmpty
                $row.score | Should -BeNullOrEmpty
            }
        }

        It 'binds custom penalties while leaving legacy settings unchanged when absent' {
            $saved = Get-ApimRunSetting -RunPath $script:savedQualityPath
            $saved.Settings.Contains('openApiQuality') | Should -BeFalse
            $config = $script:savedQualityRun.Config
            $config.OpenApiQuality = @{ ErrorPenalty = 12; WarningPenalty = 0 }
            Save-ApimRunSetting -RunPath $script:savedQualityPath -Config $config `
                -Environment $config.Environments[0]
            (Invoke-ApimAnalyze -RunFolder $script:savedQualityPath).ExitCode | Should -Be 0
            $saved = Get-ApimRunSetting -RunPath $script:savedQualityPath
            $saved.Config.OpenApiQuality.ErrorPenalty | Should -Be 12
            $saved.Config.OpenApiQuality.WarningPenalty | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:savedQualityPath
            @($models.openApiQuality.errorPenalty | Select-Object -Unique) | Should -Be @(12)
            @($models.openApiQuality.warningPenalty | Select-Object -Unique) | Should -Be @(0)
        }

        It 'replays bound scored quality through POR-004, paired reports and only the existing package condition' {
            $index = Read-ApimSmokeOutputJson -RunPath $script:savedQualityPath `
                -RelativePath 'raw/openapi/index.json'
            $entry = $index.entries[0]
            $definition = Read-ApimSmokeOutputJson -RunPath $script:savedQualityPath -RelativePath $entry.file
            $definition | Add-Member -Force -NotePropertyName servers -NotePropertyValue @(
                @{ url = 'https://SYNTHETIC_OPENAPI_SOURCE_CANARY.example.invalid' }
            )
            $sourcePath = Write-RunFile -RunPath $script:savedQualityPath `
                -RelativePath $entry.file -InputObject $definition
            $entry.sha256 = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
            $null = Write-RunFile -RunPath $script:savedQualityPath `
                -RelativePath 'raw/openapi/index.json' -InputObject $index
            (Invoke-ApimAnalyze -RunFolder $script:savedQualityPath).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:savedQualityPath
            $row = $models.openApiQuality[0]
            $row.status = 'Scored'; $row.errorCount = 4; $row.warningCount = 1
            $row.score = 58; $row.toolVersion = '6.17.0'
            $row.modelStatus = 'Complete'; $row.missingInputs = @()
            $script:scoredQualityRows = $models.openApiQuality
            Mock Get-ApimOpenApiQuality {
                param($Api)
                $script:scoredQualityRows | Where-Object apiId -CEQ $Api.apiId
            }
            (Invoke-ApimAnalyze -RunFolder $script:savedQualityPath).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:savedQualityPath
            @($models.apis | Where-Object apiId -CEQ $row.apiId)[0].openApiScore | Should -Be 58
            $findings = @(Get-ApimFindingSet -RunPath $script:savedQualityPath)
            $finding = @($findings | Where-Object {
                    $_.ruleId -ceq 'APIM-POR-004' -and $_.scope -ceq "api:$($row.apiId)"
                })[0]
            $finding.evidence.openApiScore | Should -Be 58
            $finding.evidence.method | Should -Be SpectralAndOperationDescriptionCoverage
            $finding.evidence.qualityStatus | Should -Be Scored
            $finding.sourceFiles | Should -Contain 'model/openApiQuality.json'
            $finding.evidenceText | Should -Match 'validated Spectral'
            (Invoke-ApimReport -RunFolder $script:savedQualityPath).ExitCode | Should -Be 0
            $candidate = New-ApimAnalysisPackage -RunPath $script:savedQualityPath `
                -Config $script:savedQualityRun.Config
            $candidatePath = Join-Path $script:savedQualityPath (
                "restricted/candidates/$($candidate.candidateId)/analysis-package.json"
            )
            $json = Get-Content -LiteralPath $candidatePath -Raw
            (Test-ApimAnalysisPackage -CandidatePath $candidatePath).packageSchemaVersion | Should -Be '1.3'
            $package = ConvertFrom-Json $json
            $package.facts.value | Should -Contain ApiDocumentationWeak
            $json | Should -Not -Match 'SYNTHETIC_OPENAPI_SOURCE_CANARY|openApiQuality|sourceSha256|rulesetSha256|toolVersion|descriptionCoverage|errorCount|warningCount'
            Should -Invoke Get-ApimOpenApiQuality -Times $models.apis.Count -Exactly
            Should -Invoke Invoke-ApimSpectral -Times 0 -Exactly
        }

        It 'rejects rebound quality with invalid <Field> rather than trusting only its digest' -ForEach @(
            @{ Field = 'descriptionCoverage'; Value = 37; ExpectedError = '*semantics rejected*' }
            @{ Field = 'sourceSha256'; Value = ('a' * 64); ExpectedError = '*source or settings rejected*' }
            @{ Field = 'rulesetSha256'; Value = ('b' * 64); ExpectedError = '*source or settings rejected*' }
            @{ Field = 'errorPenalty'; Value = 12; ExpectedError = '*source or settings rejected*' }
            @{ Field = 'apiCoverage'; Value = $null; ExpectedError = '*semantics rejected*' }
        ) {
            (Invoke-ApimAnalyze -RunFolder $script:savedQualityPath).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:savedQualityPath
            if ($Field -ceq 'apiCoverage') {
                $models.openApiQuality = @($models.openApiQuality[0])
            }
            else { $models.openApiQuality[0].$Field = $Value }
            $context = Get-ApimRunSetting -RunPath $script:savedQualityPath
            $exports = Get-ApimSavedOpenApiExport -RunPath $script:savedQualityPath -Context $context
            Save-ApimOpenApiQualityBinding -RunPath $script:savedQualityPath `
                -Quality $models.openApiQuality -Context $context -Exports $exports
            $null = Write-ApimModelSet -RunPath $script:savedQualityPath -Models $models
            { Get-ApimModelSet -RunPath $script:savedQualityPath } | Should -Throw $ExpectedError
        }

        It 'rejects malformed listed Partial export indexes instead of skipping the gate' {
            $manifest = Get-RunManifest -RunPath $script:savedQualityPath
            $record = @($manifest.collectors | Where-Object name -CEQ OpenApi)[0]
            $record.status = 'Partial'; $record.errors = 1
            $null = Save-RunManifest -RunPath $script:savedQualityPath -Manifest $manifest
            $index = Read-ApimSmokeOutputJson -RunPath $script:savedQualityPath `
                -RelativePath 'raw/openapi/index.json'
            $index | Add-Member -NotePropertyName unexpected -NotePropertyValue SYNTHETIC_UNKNOWN_FIELD
            $null = Write-RunFile -RunPath $script:savedQualityPath `
                -RelativePath 'raw/openapi/index.json' -InputObject $index
            (Invoke-ApimAnalyze -RunFolder $script:savedQualityPath).ExitCode | Should -Be 4
            Test-Path -LiteralPath (Join-Path $script:savedQualityPath 'model/openApiQuality.json') |
                Should -BeFalse
        }

        It 'uses a validated successful Partial export without admitting the failed API stale file' {
            $index = Read-ApimSmokeOutputJson -RunPath $script:savedQualityPath `
                -RelativePath 'raw/openapi/index.json'
            $failed = $index.entries[1]
            $staleFile = $failed.file
            $failed.status = 'Failed'; $failed.reasonCode = 'ExportFailed'
            $failed.file = $null; $failed.sha256 = $null
            $null = Write-RunFile -RunPath $script:savedQualityPath `
                -RelativePath 'raw/openapi/index.json' -InputObject $index
            $null = Write-RunFile -RunPath $script:savedQualityPath `
                -RelativePath $staleFile -InputObject @{ unexpected = 'STALE_FAILED_EXPORT' }
            $manifest = Get-RunManifest -RunPath $script:savedQualityPath
            $record = @($manifest.collectors | Where-Object name -CEQ OpenApi)[0]
            $record.status = 'Partial'; $record.errors = 1; $record.items = 1
            $record.files = @($record.files | Where-Object { $_ -cne $staleFile })
            $null = Save-RunManifest -RunPath $script:savedQualityPath -Manifest $manifest
            (Invoke-ApimAnalyze -RunFolder $script:savedQualityPath).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:savedQualityPath
            @($models.openApiQuality.status | Sort-Object) |
                Should -Be @('ExportUnavailable', 'ToolUnavailable')
            @($models.openApiQuality | Where-Object { $null -ne $_.sourceSha256 }).Count | Should -Be 1
            @($models.apis | Where-Object { $null -ne $_.openApiScore }).Count | Should -Be 0
            (Invoke-ApimReport -RunFolder $script:savedQualityPath).ExitCode | Should -Be 0
            Should -Invoke Invoke-ApimSpectral -Times 0 -Exactly
        }

        It 'rejects changed saved <Artifact> before replay' -ForEach @(
            @{ Artifact = 'source' }
            @{ Artifact = 'quality' }
            @{ Artifact = 'settings' }
            @{ Artifact = 'binding' }
            @{ Artifact = 'ruleset' }
            @{ Artifact = 'duplicate-binding' }
            @{ Artifact = 'duplicate-quality' }
        ) {
            (Invoke-ApimAnalyze -RunFolder $script:savedQualityPath).ExitCode | Should -Be 0
            switch ($Artifact) {
                source {
                    $index = Read-ApimSmokeOutputJson -RunPath $script:savedQualityPath `
                        -RelativePath 'raw/openapi/index.json'
                    $path = Resolve-RunFilePath -RunPath $script:savedQualityPath `
                        -RelativePath $index.entries[0].file
                    [IO.File]::AppendAllText($path, ' ')
                }
                quality {
                    $rows = Get-Content -LiteralPath (
                        Join-Path $script:savedQualityPath 'model/openApiQuality.json'
                    ) -Raw | ConvertFrom-Json -NoEnumerate
                    $rows[0].toolVersion = '0.0.0'
                    $null = Write-RunFile -RunPath $script:savedQualityPath `
                        -RelativePath 'model/openApiQuality.json' -InputObject $rows
                }
                settings {
                    $config = $script:savedQualityRun.Config
                    $config.OpenApiQuality = @{ ErrorPenalty = 12; WarningPenalty = 0 }
                    Save-ApimRunSetting -RunPath $script:savedQualityPath -Config $config `
                        -Environment $config.Environments[0]
                }
                binding {
                    $null = Write-RunFile -RunPath $script:savedQualityPath `
                        -RelativePath 'restricted/openapi-binding.json' -InputObject @{ schemaVersion = '1.0' }
                }
                ruleset {
                    Mock Get-FileHash { [pscustomobject]@{ Hash = 'a' * 64 } } -ParameterFilter {
                        [IO.Path]::GetFileName($LiteralPath) -ceq 'apim-style.yaml'
                    }
                }
                duplicate-binding {
                    $path = Join-Path $script:savedQualityPath 'restricted/openapi-binding.json'
                    $json = Get-Content -LiteralPath $path -Raw
                    $json = $json -replace '"schemaVersion"\s*:', '"schemaVersion":"1.0","schemaVersion":'
                    $null = Write-RunFile -RunPath $script:savedQualityPath `
                        -RelativePath 'restricted/openapi-binding.json' -InputObject $json -Format Text
                }
                duplicate-quality {
                    $path = Join-Path $script:savedQualityPath 'model/openApiQuality.json'
                    $json = Get-Content -LiteralPath $path -Raw
                    $json = $json -replace '"schemaVersion"\s*:', '"schemaVersion":"1.0","schemaVersion":'
                    $null = Write-RunFile -RunPath $script:savedQualityPath `
                        -RelativePath 'model/openApiQuality.json' -InputObject $json -Format Text
                }
            }
            { Get-ApimModelSet -RunPath $script:savedQualityPath } | Should -Throw
            (Invoke-ApimReport -RunFolder $script:savedQualityPath).ExitCode | Should -Be 4
            Should -Invoke Invoke-ApimSpectral -Times 0 -Exactly
        }

        It 'retains the legacy path and clears obsolete quality binding on explicit reanalysis' {
            (Invoke-ApimAnalyze -RunFolder $script:savedQualityPath).ExitCode | Should -Be 0
            $manifest = Get-RunManifest -RunPath $script:savedQualityPath
            $manifest.collectors = @($manifest.collectors | Where-Object name -CNE OpenApi)
            $null = Save-RunManifest -RunPath $script:savedQualityPath -Manifest $manifest
            (Invoke-ApimAnalyze -RunFolder $script:savedQualityPath).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:savedQualityPath
            $models.Contains('openApiQuality') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $script:savedQualityPath 'restricted/openapi-binding.json') |
                Should -BeFalse
            (Invoke-ApimReport -RunFolder $script:savedQualityPath).ExitCode | Should -Be 0
        }
    }
}
