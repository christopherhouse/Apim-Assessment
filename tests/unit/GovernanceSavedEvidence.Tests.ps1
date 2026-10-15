$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Offline governance evidence integrity' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:governanceSavedRepository = $Repository
        BeforeAll {
            . (Join-Path $script:governanceSavedRepository 'tests/helpers/New-SyntheticCollectedRun.ps1')
        }
        BeforeEach {
            $script:governanceSavedInput = New-SyntheticCollectedRun -RepoRoot $script:governanceSavedRepository `
                -OutputRoot (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
            $script:governanceSavedPath = $script:governanceSavedInput.Run.Path
            Mock Invoke-ApimArm { throw 'Offline governance must not call Azure.' }
            Mock Get-ApimSpectralTool { return $null }
        }

        It 'builds optional evidence offline, preserves absent intent and remains byte-stable' {
            (Invoke-ApimAnalyze -RunFolder $script:governanceSavedPath).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:governanceSavedPath
            $models.products.Count | Should -Be 2
            $models.diagnosticCoverage.Count | Should -Be 2
            $models.products[0].hasOwner | Should -BeNullOrEmpty
            $models.diagnosticCoverage[0].isCritical | Should -BeNullOrEmpty
            $before = Get-Content (Join-Path $script:governanceSavedPath findings.json) -Raw
            (Invoke-ApimAnalyze -RunFolder $script:governanceSavedPath).ExitCode | Should -Be 0
            Get-Content (Join-Path $script:governanceSavedPath findings.json) -Raw | Should -BeExactly $before
            Should -Invoke Invoke-ApimArm -Exactly -Times 0
        }

        It 'keeps unrelated Organization endpoint failures independent from governance evidence' {
            $manifest = Get-RunManifest $script:governanceSavedPath
            $record = @($manifest.collectors | Where-Object name -CEQ Organization)[0]
            $record.status = 'Failed'; $record.items = 0; $record.errors = 7; $record.files = @()
            $null = Save-RunManifest -RunPath $script:governanceSavedPath -Manifest $manifest
            (Invoke-ApimAnalyze -RunFolder $script:governanceSavedPath).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:governanceSavedPath
            $models.products.Count | Should -Be 2
            @($models.diagnosticCoverage | Where-Object configured -EQ $true).Count | Should -Be 2
        }

        It 'does not trust unvalidated stale diagnostic files from a Partial collector' {
            $manifest = Get-RunManifest $script:governanceSavedPath
            $record = @($manifest.collectors | Where-Object name -CEQ Diagnostics)[0]
            $record.status = 'Partial'; $record.errors = 1
            $null = Save-RunManifest -RunPath $script:governanceSavedPath -Manifest $manifest
            $models = Get-ApimSavedGovernanceModel -RunPath $script:governanceSavedPath `
                -Context (Get-ApimRunSetting $script:governanceSavedPath)
            @($models.diagnosticCoverage | Where-Object { $null -ne $_.configured }).Count | Should -Be 0
            @($models.diagnosticCoverage | Where-Object { 'diagnostics' -cin $_.missingInputs }).Count | Should -Be 2
        }

        It 'rejects schema-valid <Kind> tampering and stale source evidence' -ForEach @(
            @{ Kind = 'model' }; @{ Kind = 'source' }; @{ Kind = 'settings' }
        ) {
            (Invoke-ApimAnalyze -RunFolder $script:governanceSavedPath).ExitCode | Should -Be 0
            $file = switch ($Kind) {
                model { 'model/products.json' }
                source { 'raw/products.json' }
                settings { 'restricted/run-settings.json' }
            }
            $payload = Get-Content (Join-Path $script:governanceSavedPath $file) -Raw |
                ConvertFrom-Json -AsHashtable -NoEnumerate
            switch ($Kind) {
                model { $payload[0].hasDescription = -not $payload[0].hasDescription }
                source { $payload.value[0].properties.description = '' }
                settings { $payload.governance = @{ criticalApiIds = @() } }
            }
            $null = Write-RunFile -RunPath $script:governanceSavedPath -RelativePath $file -InputObject $payload
            { Get-ApimModelSet -RunPath $script:governanceSavedPath } |
                Should -Throw '*governance evidence*'
        }

        It 'loads and reports legacy model sets with no new optional files' {
            (Invoke-ApimAnalyze -RunFolder $script:governanceSavedPath).ExitCode | Should -Be 0
            foreach ($file in @('products', 'diagnosticCoverage')) {
                Remove-Item -LiteralPath (Join-Path $script:governanceSavedPath "model/$file.json")
            }
            $models = Get-ApimModelSet -RunPath $script:governanceSavedPath
            $models.Contains('products') | Should -BeFalse
            $models.Contains('diagnosticCoverage') | Should -BeFalse
            $context = Get-ApimRunSetting -RunPath $script:governanceSavedPath
            $findings = @(Invoke-ApimRuleEngine -Rules @(
                    Get-ApimRuleCatalog -CatalogPath $script:ApimReportRuleCatalogPath
                ) -Models $models -Manifest $context.Manifest -Config $context.Config)
            $null = Write-ApimFindingSet -RunPath $script:governanceSavedPath -Findings $findings
            (Invoke-ApimReport -RunFolder $script:governanceSavedPath).ExitCode | Should -Be 0
        }
    }
}
