$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Manifest-bound partial portal ingestion' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:portalSavedRepository = $Repository
        BeforeAll {
            . (Join-Path $script:portalSavedRepository 'tests/helpers/New-SyntheticCollectedRun.ps1')
        }
        BeforeEach {
            $script:portalSavedInput = New-SyntheticCollectedRun -RepoRoot $script:portalSavedRepository `
                -OutputRoot (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
            $script:portalSavedPath = $script:portalSavedInput.Run.Path
            Mock Invoke-ApimArm { throw 'Offline portal analysis attempted Azure access.' }
            Mock Invoke-ApimResourceGraphQuery { throw 'Offline portal analysis attempted graph access.' }
            Mock Get-ApimSpectralTool { return $null }
        }

        It 'retains a known positive from Partial files and ignores stale unlisted evidence' {
            $manifest = Get-RunManifest -RunPath $script:portalSavedPath
            $record = @($manifest.collectors | Where-Object name -CEQ Portal)[0]
            $record.status = 'Partial'; $record.errors = 2
            $record.files = @($record.files | Where-Object {
                    $_ -cnotin @('raw/portal/signup.json', 'raw/portal/revisions.json')
                })
            $record.items -= 2
            $null = Save-RunManifest -RunPath $script:portalSavedPath -Manifest $manifest
            $path = Join-Path $script:portalSavedPath 'raw/portal/config.json'
            $config = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
            $config.properties.enableBasicAuth = $true
            $null = Write-RunFile -RunPath $script:portalSavedPath `
                -RelativePath 'raw/portal/config.json' -InputObject $config
            $null = Write-RunFile -RunPath $script:portalSavedPath `
                -RelativePath 'raw/portal/signup.json' -InputObject @{ unexpected = 'STALE_SYNTHETIC' }

            (Invoke-ApimAnalyze -RunFolder $script:portalSavedPath).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:portalSavedPath
            $models.portal.basicAuthEnabled | Should -BeTrue
            $models.portal.signupEnabled | Should -BeNullOrEmpty
            $models.portal.published | Should -BeNullOrEmpty
            $models.portal.modelStatus | Should -Be Partial
            $finding = @(Get-ApimFindingSet -RunPath $script:portalSavedPath |
                    Where-Object ruleId -CEQ APIM-POR-002)
            $finding.Count | Should -Be 1
            $finding[0].evaluation | Should -Be Evaluated
            (Get-RunManifest -RunPath $script:portalSavedPath).collectors.Where({
                    $_.name -ceq 'Portal'
                }).status | Should -Be Partial
            Should -Invoke Invoke-ApimArm -Times 0 -Exactly
            Should -Invoke Invoke-ApimResourceGraphQuery -Times 0 -Exactly
        }

        It 'rejects malformed listed Partial <Kind> evidence rather than skipping its closed gate' -ForEach @(
            @{ Kind = 'Portal'; File = 'raw/portal/config.json' }
            @{ Kind = 'Identity'; File = 'raw/identityProviders.json' }
        ) {
            $manifest = Get-RunManifest -RunPath $script:portalSavedPath
            $record = @($manifest.collectors | Where-Object name -CEQ $Kind)[0]
            $record.status = 'Partial'; $record.errors = 1
            $null = Save-RunManifest -RunPath $script:portalSavedPath -Manifest $manifest
            $path = Join-Path $script:portalSavedPath $File
            $payload = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
            $payload.unexpected = 'SYNTHETIC_UNKNOWN_FIELD'
            $null = Write-RunFile -RunPath $script:portalSavedPath -RelativePath $File -InputObject $payload
            (Invoke-ApimAnalyze -RunFolder $script:portalSavedPath).ExitCode | Should -Be 4
            (Get-RunManifest -RunPath $script:portalSavedPath).stages.analyze | Should -Be Failed
            Test-Path -LiteralPath (Join-Path $script:portalSavedPath 'model/portal.json') | Should -BeFalse
        }

        It 'keeps the legacy ten-model saved-run path usable without portal recollection' {
            $manifest = Get-RunManifest -RunPath $script:portalSavedPath
            $manifest.collectors = @($manifest.collectors | Where-Object {
                    $_.name -cnotin @('Identity', 'Portal', 'OpenApi')
                })
            $null = Save-RunManifest -RunPath $script:portalSavedPath -Manifest $manifest
            (Invoke-ApimAnalyze -RunFolder $script:portalSavedPath).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:portalSavedPath
            $models.Count | Should -Be 10
            $models.Contains('portal') | Should -BeFalse
            $findings = @(Get-ApimFindingSet -RunPath $script:portalSavedPath |
                    Where-Object { $_.ruleId -cin @('APIM-POR-001', 'APIM-POR-002', 'APIM-POR-003', 'APIM-POR-005') })
            $findings.Count | Should -Be 4
            @($findings.evaluation | Select-Object -Unique) | Should -Be @('NotEvaluated')
            (Invoke-ApimReport -RunFolder $script:portalSavedPath).ExitCode | Should -Be 0
        }
    }
}
