$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Immutable atomic analysis publication' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:promotionRepository = $Repository
        BeforeAll {
            . (Join-Path $script:promotionRepository 'tests/helpers/New-AnalysisTestRun.ps1')
            $script:originalAnalysisValidator = (Get-Command Test-ApimAnalysisPackage).ScriptBlock
        }
        BeforeEach {
            $script:promotionRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $script:promotionRun = New-AnalysisTestRun -Root $script:promotionRoot `
                -Repository $script:promotionRepository
            $candidate = New-ApimAnalysisPackage -RunPath $script:promotionRun.RunPath `
                -Config $script:promotionRun.Config
            $script:publication = @{
                RestrictedRoot = $script:promotionRun.RunPath
                CandidateId = $candidate.candidateId
                AnalysisRoot = Join-Path $script:promotionRoot 'analysis'
                PrivateStagingRoot = Join-Path $script:promotionRoot 'private-stage'
                CopilotVisiblePath = @(
                    (Join-Path $script:promotionRoot 'analysis'),
                    (Join-Path $script:promotionRoot 'visible')
                )
                VisibleRootsComplete = $true
                Version = 'version-000001'
            }
            $script:publicationCandidate = Join-Path $script:promotionRun.RunPath (
                "restricted/candidates/$($candidate.candidateId)/analysis-package.json"
            )
        }

        It 'publishes only the validated package and hash-bound attestation together' {
            $sourceHash = (Get-FileHash $script:publicationCandidate).Hash
            $result = Publish-ApimAnalysisPackage @script:publication
            $result.status | Should -Be Promoted
            $result.PSObject.Properties.Name | Should -Be @('status', 'version', 'packageSha256')
            $version = Join-Path $script:publication.AnalysisRoot 'version-000001'
            @(Get-ChildItem $version -Force).Name |
                Should -Be @('analysis-package.json', 'validation-attestation.json')
            $attestation = Get-Content (Join-Path $version 'validation-attestation.json') -Raw |
                ConvertFrom-Json
            $attestation.packageSha256 | Should -Be $sourceHash.ToLowerInvariant()
            (Get-FileHash (Join-Path $version 'analysis-package.json')).Hash |
                Should -Be $sourceHash
            (Get-FileHash $script:publicationCandidate).Hash | Should -Be $sourceHash
            @(Get-ChildItem $script:publication.PrivateStagingRoot -Force).Count | Should -Be 0
        }

        It 'never overwrites an existing version and preserves a previous good publication on failure' {
            $null = Publish-ApimAnalysisPackage @script:publication
            $path = Join-Path $script:publication.AnalysisRoot 'version-000001/analysis-package.json'
            $hash = (Get-FileHash $path).Hash
            { Publish-ApimAnalysisPackage @script:publication } |
                Should -Throw '*ANALYSIS_PROMOTION_REJECTED*'
            $script:publication.Version = 'version-000002'
            [IO.File]::WriteAllText($script:publicationCandidate, '{"canary":"NEVER_PUBLISH"}')
            { Publish-ApimAnalysisPackage @script:publication } |
                Should -Throw '*ANALYSIS_PROMOTION_REJECTED*'
            (Get-FileHash $path).Hash | Should -Be $hash
            @(Get-ChildItem $script:publication.AnalysisRoot).Count | Should -Be 1
            @(Get-ChildItem $script:publication.PrivateStagingRoot -Force).Count | Should -Be 0
        }

        It 'rejects unsafe or unproven root arrangements: <Case>' -ForEach @(
            @{ Case = 'missing visible context' }
            @{ Case = 'incomplete visible context' }
            @{ Case = 'restricted visible' }
            @{ Case = 'staging visible' }
            @{ Case = 'analysis nested' }
            @{ Case = 'restricted nested' }
            @{ Case = 'staging overlap' }
            @{ Case = 'traversal' }
            @{ Case = 'trailing dot alias' }
            @{ Case = 'trailing space alias' }
            @{ Case = 'relative' }
            @{ Case = 'bad candidate' }
            @{ Case = 'bad version' }
            @{ Case = 'extra candidate artifact' }
            @{ Case = 'staging is file' }
            @{ Case = 'unrecognized analysis content' }
        ) {
            switch ($Case) {
                'missing visible context' { $script:publication.CopilotVisiblePath = @() }
                'incomplete visible context' { $script:publication.VisibleRootsComplete = $false }
                'restricted visible' { $script:publication.CopilotVisiblePath = @($script:promotionRoot) }
                'staging visible' { $script:publication.CopilotVisiblePath = @($script:publication.PrivateStagingRoot) }
                'analysis nested' {
                    $script:publication.AnalysisRoot = Join-Path $script:publication.RestrictedRoot 'analysis'
                }
                'restricted nested' { $script:publication.AnalysisRoot = $script:promotionRoot }
                'staging overlap' { $script:publication.PrivateStagingRoot = $script:publication.AnalysisRoot }
                'traversal' { $script:publication.AnalysisRoot += '/unused/../analysis' }
                'trailing dot alias' { $script:publication.AnalysisRoot += '.' }
                'trailing space alias' { $script:publication.AnalysisRoot += ' ' }
                'relative' { $script:publication.AnalysisRoot = 'relative-analysis' }
                'bad candidate' { $script:publication.CandidateId = '../NEVER_PUBLISH' }
                'bad version' { $script:publication.Version = '../NEVER_PUBLISH' }
                'extra candidate artifact' {
                    [IO.File]::WriteAllText(
                        (Join-Path (Split-Path $script:publicationCandidate -Parent) 'extra.json'), 'NEVER_PUBLISH'
                    )
                }
                'staging is file' {
                    [IO.File]::WriteAllText($script:publication.PrivateStagingRoot, 'NEVER_PUBLISH')
                }
                'unrecognized analysis content' {
                    $null = [IO.Directory]::CreateDirectory($script:publication.AnalysisRoot)
                    [IO.File]::WriteAllText(
                        (Join-Path $script:publication.AnalysisRoot 'restricted-source.txt'), 'NEVER_PUBLISH'
                    )
                }
            }
            $output = @()
            try { $output = @(Publish-ApimAnalysisPackage @script:publication *>&1) }
            catch { $output += $_.Exception.Message }
            $output | Should -Be @('ANALYSIS_PROMOTION_REJECTED')
            Test-Path (Join-Path $script:publication.AnalysisRoot $script:publication.Version) |
                Should -BeFalse
        }

        It 'rejects validator, digest, attestation and snapshot failures: <Case>' -ForEach @(
            @{ Case = 'validator throws' }
            @{ Case = 'wrong digest' }
            @{ Case = 'attestation throws' }
            @{ Case = 'source mutation' }
            @{ Case = 'snapshot mutation' }
        ) {
            switch ($Case) {
                'validator throws' { Mock Test-ApimAnalysisPackage { throw 'NEVER_PUBLISH' } }
                'wrong digest' {
                    Mock Test-ApimAnalysisPackage {
                        param($CandidatePath)
                        $attestation = & $script:originalAnalysisValidator -CandidatePath $CandidatePath
                        $attestation.packageSha256 = '0' * 64
                        return $attestation
                    }
                }
                'attestation throws' { Mock Test-ApimAnalysisAttestation { throw 'NEVER_PUBLISH' } }
                'source mutation' {
                    Mock Test-ApimAnalysisPackage {
                        param($CandidatePath)
                        $result = & $script:originalAnalysisValidator -CandidatePath $CandidatePath
                        [IO.File]::AppendAllText($script:publicationCandidate, ' ')
                        return $result
                    }
                }
                'snapshot mutation' {
                    Mock Test-ApimAnalysisPackage {
                        param($CandidatePath)
                        $result = & $script:originalAnalysisValidator -CandidatePath $CandidatePath
                        [IO.File]::AppendAllText($CandidatePath, ' ')
                        return $result
                    }
                }
            }
            { Publish-ApimAnalysisPackage @script:publication } |
                Should -Throw '*ANALYSIS_PROMOTION_REJECTED*'
            @(Get-ChildItem $script:publication.AnalysisRoot -Force).Count | Should -Be 0
            @(Get-ChildItem $script:publication.PrivateStagingRoot -Force).Count | Should -Be 0
        }

        It 'rejects linked staging ancestors' {
            $target = Join-Path $script:promotionRoot 'link-target'
            $null = New-Item -ItemType Directory -Path $target
            $link = Join-Path $script:promotionRoot 'link-stage'
            $type = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
            $null = New-Item -ItemType $type -Path $link -Target $target -ErrorAction Stop
            try {
                $script:publication.PrivateStagingRoot = Join-Path $link 'child'
                { Publish-ApimAnalysisPackage @script:publication } |
                    Should -Throw '*ANALYSIS_PROMOTION_REJECTED*'
                Test-Path $script:publication.AnalysisRoot | Should -BeFalse
            }
            finally { Remove-Item -LiteralPath $link -Force }
        }

        It 'rejects a link back to restricted inputs already present in the analysis zone' {
            $null = [IO.Directory]::CreateDirectory($script:publication.AnalysisRoot)
            $link = Join-Path $script:publication.AnalysisRoot 'version-999999'
            $type = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
            $null = New-Item -ItemType $type -Path $link -Target $script:publication.RestrictedRoot
            try {
                { Publish-ApimAnalysisPackage @script:publication } |
                    Should -Throw '*ANALYSIS_PROMOTION_REJECTED*'
                Test-Path (Join-Path $script:publication.AnalysisRoot 'version-000001') | Should -BeFalse
            }
            finally { Remove-Item -LiteralPath $link -Force }
        }

        It 'rejects a modified previously published package without rewriting it' {
            $null = Publish-ApimAnalysisPackage @script:publication
            $path = Join-Path $script:publication.AnalysisRoot 'version-000001/analysis-package.json'
            [IO.File]::AppendAllText($path, ' ')
            $hash = (Get-FileHash $path).Hash
            $script:publication.Version = 'version-000002'
            { Publish-ApimAnalysisPackage @script:publication } |
                Should -Throw '*ANALYSIS_PROMOTION_REJECTED*'
            (Get-FileHash $path).Hash | Should -Be $hash
        }

        It 'fails closed on attestation persistence failure' {
            $script:originalAnalysisReader = (Get-Command Read-ApimAnalysisSnapshot).ScriptBlock
            Mock Read-ApimAnalysisSnapshot {
                param($Path)
                if ($Path.EndsWith('validation-attestation.json')) { throw 'NEVER_PUBLISH' }
                return ,(& $script:originalAnalysisReader -Path $Path)
            }
            { Publish-ApimAnalysisPackage @script:publication } |
                Should -Throw '*ANALYSIS_PROMOTION_REJECTED*'
            @(Get-ChildItem $script:publication.AnalysisRoot -Force).Count | Should -Be 0
            @(Get-ChildItem $script:publication.PrivateStagingRoot -Force).Count | Should -Be 0
        }

        It 'rejects a late destination collision rather than copying or overwriting' {
            Mock Test-ApimAnalysisPackage {
                param($CandidatePath)
                $result = & $script:originalAnalysisValidator -CandidatePath $CandidatePath
                $destination = Join-Path $script:publication.AnalysisRoot $script:publication.Version
                $null = [IO.Directory]::CreateDirectory($destination)
                [IO.File]::WriteAllText((Join-Path $destination 'owner-marker.txt'), 'KEEP_EXISTING')
                return $result
            }
            { Publish-ApimAnalysisPackage @script:publication } |
                Should -Throw '*ANALYSIS_PROMOTION_REJECTED*'
            $marker = Join-Path $script:publication.AnalysisRoot 'version-000001/owner-marker.txt'
            Get-Content $marker -Raw | Should -Be KEEP_EXISTING
            Test-Path (Join-Path (Split-Path $marker -Parent) 'analysis-package.json') | Should -BeFalse
            @(Get-ChildItem $script:publication.PrivateStagingRoot -Force).Count | Should -Be 0
        }

        It 'does not create staging or analysis output for WhatIf' {
            Publish-ApimAnalysisPackage @script:publication -WhatIf | Should -BeNullOrEmpty
            Test-Path $script:publication.AnalysisRoot | Should -BeFalse
            Test-Path $script:publication.PrivateStagingRoot | Should -BeFalse
        }
    }
}
