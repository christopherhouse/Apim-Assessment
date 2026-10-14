$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Independent analysis package validation' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:validationRepository = $Repository
        BeforeEach {
            $script:validationPath = Join-Path $TestDrive 'candidate.json'
            $script:validationPackage = Get-Content -LiteralPath (
                Join-Path $script:validationRepository 'tests/fixtures/synthetic-reference/analysis-contracts/analysis-package.json'
            ) -Raw | ConvertFrom-Json -AsHashtable
        }

        It 'attests exact bytes, fixed check metadata and module-derived versions' {
            $json = ConvertTo-ApimAnalysisJson -Value $script:validationPackage
            [IO.File]::WriteAllText($script:validationPath, $json)
            $result = Test-ApimAnalysisPackage -CandidatePath $script:validationPath
            $result.packageSha256 | Should -Be (
                Get-FileHash $script:validationPath -Algorithm SHA256
            ).Hash.ToLowerInvariant()
            $result.builderVersion | Should -Be (Get-ApimAssessmentToolVersion)
            $result.validatorVersion | Should -Be (Get-ApimAssessmentToolVersion)
            $result.status | Should -Be Passed
            $attestationJson = ConvertTo-ApimAnalysisJson -Value $result
            { Test-ApimAnalysisAttestation -Json $attestationJson } | Should -Not -Throw
            $attestationJson | Should -Not -Match 'candidate.json|TestDrive|timestamp'
        }

        It 'rejects unapproved values without echoing any input or source path: <Label>' -ForEach @(
            @{ Label = 'GUID'; Value = '11223344-5566-7788-9900-aabbccddeeff' }
            @{ Label = 'ARM'; Value = '/subscriptions/11223344-5566-7788-9900-aabbccddeeff/resources/marker' }
            @{ Label = 'URL'; Value = 'https://marker-airlock.invalid/resource' }
            @{ Label = 'IP'; Value = '203.0.113.47/24' }
            @{ Label = 'UPN'; Value = 'canary@marker-airlock.invalid' }
            @{ Label = 'XML'; Value = '<policies><inbound /></policies>' }
            @{ Label = 'path'; Value = 'C:\private\marker-airlock' }
            @{ Label = 'credential'; Value = 'AccountKey=MARKER_CREDENTIAL_NEVER_COPY' }
            @{ Label = 'base64'; Value = 'aHR0cHM6Ly9tYXJrZXItYWlybG9jay5pbnZhbGlkL3NlY3JldA==' }
            @{ Label = 'percent'; Value = '%68%74%74%70%73%3a%2f%2fmarker-airlock.invalid' }
            @{ Label = 'double percent'; Value = '%2568%2574%2574%2570%2573' }
            @{ Label = 'hex'; Value = '68747470733a2f2f6d61726b65722d6169726c6f636b2e696e76616c6964' }
            @{ Label = 'Unicode'; Value = "Intern$([char]0x200b)al" }
            @{ Label = 'confusable'; Value = "$([char]0xff29)nternal" }
            @{ Label = 'escaped'; Value = '\u0068\u0074\u0074\u0070' }
            @{ Label = 'entity'; Value = '&#104;&#116;&#116;&#112;' }
            @{ Label = 'exact usage'; Value = 987654321 }
            @{ Label = 'fractional usage'; Value = 123.456 }
        ) {
            $script:validationPackage.facts[0].value = $Value
            [IO.File]::WriteAllText($script:validationPath, (
                    ConvertTo-ApimAnalysisJson -Value $script:validationPackage
                ))
            $output = @()
            try { $output = @(Test-ApimAnalysisPackage -CandidatePath $script:validationPath *>&1) }
            catch { $output += $_.Exception.Message }
            $output | Should -Be @('ANALYSIS_VALIDATION_REJECTED')
            { Assert-ApimAnalysisScan -Package $script:validationPackage } |
                Should -Throw '*ANALYSIS_SCAN_REJECTED*'
        }

        It 'rejects unexpected keys, invalid references, unsupported versions and failed scanners' {
            foreach ($mutation in @('key', 'reference', 'version', 'scanner')) {
                $candidate = $script:validationPackage | ConvertTo-Json -Depth 32 |
                    ConvertFrom-Json -AsHashtable
                switch ($mutation) {
                    key { $candidate.infrastructure = 'MARKER_NEVER_COPY' }
                    reference { $candidate.findings[0].factRefs = @('fact-999999') }
                    version { $candidate.schemaVersion = '9.9' }
                    scanner { Mock Assert-ApimAnalysisScan { throw 'MARKER_NEVER_COPY' } }
                }
                [IO.File]::WriteAllText($script:validationPath, (ConvertTo-ApimAnalysisJson $candidate))
                { Test-ApimAnalysisPackage -CandidatePath $script:validationPath } |
                    Should -Throw '*ANALYSIS_VALIDATION_REJECTED*'
            }
        }

        It 'rejects malformed, duplicate, deep, oversized and invalid UTF8 input' {
            foreach ($json in @(
                    '{"schemaVersion":"1.0","schemaVersion":"1.1"}',
                    '{"schemaVersion":',
                    ('[' * 34 + '0' + ']' * 34),
                    (' ' * (16MB + 1))
                )) {
                [IO.File]::WriteAllText($script:validationPath, $json)
                { Test-ApimAnalysisPackage -CandidatePath $script:validationPath } |
                    Should -Throw '*ANALYSIS_VALIDATION_REJECTED*'
            }
            [IO.File]::WriteAllBytes($script:validationPath, [byte[]]@(0xff, 0xfe, 0xff))
            { Test-ApimAnalysisPackage -CandidatePath $script:validationPath } |
                Should -Throw '*ANALYSIS_VALIDATION_REJECTED*'
        }
    }
}
