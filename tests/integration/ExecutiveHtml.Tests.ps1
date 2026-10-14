$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force
AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Local self-contained executive HTML' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:htmlRepository = $Repository
        BeforeAll {
            . (Join-Path $script:htmlRepository 'tests/helpers/New-SyntheticCollectedRun.ps1')
        }
        BeforeEach {
            $script:htmlInput = New-SyntheticCollectedRun -RepoRoot $script:htmlRepository `
                -OutputRoot (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
            $script:htmlRun = $script:htmlInput.Run.Path
            (Invoke-ApimAnalyze -RunFolder $script:htmlRun).ExitCode | Should -Be 0
        }

        It 'produces byte-identical offline HTML with all required sections, local counts and accessibility hooks' {
            $null = Export-ApimExecutiveHtml -RunPath $script:htmlRun
            $path = @(Get-ChildItem -LiteralPath (Join-Path $script:htmlRun 'report') -Filter '*.html')[0].FullName
            $bytes = [IO.File]::ReadAllBytes($path)
            $html = [Text.Encoding]::UTF8.GetString($bytes)
            $null = Export-ApimExecutiveHtml -RunPath $script:htmlRun
            [IO.File]::ReadAllBytes($path) | Should -Be $bytes
            foreach ($section in @('posture', 'architecture', 'risks', 'actions', 'gaps', 'roadmap')) {
                $html | Should -Match "id=`"$section`""
            }
            $html | Should -Match 'API exposure counts|Not evaluated|Cloudflare|assumed'
            $html | Should -Match 'role="img"|aria-labelledby|scope="col"|Skip to assessment'
            $html | Should -Match '@media print|prefers-reduced-motion|connect-src ''none'''
            $html | Should -Match '--cp-bg: #f7f4ef|scoutTheme|Segoe UI'
            $html | Should -Not -Match '<script[^>]+src=|<link[^>]+href=|<img[^>]+src=|fetch\s*\(|XMLHttpRequest|https?://'
            $html | Should -Not -Match '\{\{[A-Z]+\}\}'
        }

        It 'escapes local text and rejects unsupported filename characters before persistence' {
            ConvertTo-ApimHtmlText '</script><img src=x onerror=alert(1)>' |
                Should -Be '&lt;/script&gt;&lt;img src=x onerror=alert(1)&gt;'
            $manifest = Get-RunManifest -RunPath $script:htmlRun
            $manifest.customer = "Synthetic & 'local label'"
            $null = Save-RunManifest -RunPath $script:htmlRun -Manifest $manifest
            $null = Export-ApimExecutiveHtml -RunPath $script:htmlRun
            $path = @(Get-ChildItem -LiteralPath (Join-Path $script:htmlRun 'report') -Filter '*.html')[0].FullName
            Get-Content -LiteralPath $path -Raw | Should -Match 'Synthetic &amp; &#39;local label&#39;'
            $manifest.customer = '<script>unsafe</script>'
            $null = Save-RunManifest -RunPath $script:htmlRun -Manifest $manifest
            { Export-ApimExecutiveHtml -RunPath $script:htmlRun } | Should -Throw '*filename*'
            @(Get-ChildItem -LiteralPath (Join-Path $script:htmlRun 'report') -Filter '*.html').Count | Should -Be 1
        }

        It 'rejects stale packages and altered identity maps before assisted rendering' {
            $candidate = New-ApimAnalysisPackage -RunPath $script:htmlRun -Config $script:htmlInput.Config
            $root = Join-Path $script:htmlRun "restricted/candidates/$($candidate.candidateId)"
            $context = @{ packageJson = Get-Content -LiteralPath (Join-Path $root 'analysis-package.json') -Raw
                candidateId = $candidate.candidateId; observations = @(); executives = @() }
            $null = Export-ApimExecutiveHtml -RunPath $script:htmlRun -AgentOutputContext $context
            [IO.File]::AppendAllText((Join-Path $root 'alias-map.json'), ' ')
            { Export-ApimExecutiveHtml -RunPath $script:htmlRun -AgentOutputContext $context } | Should -Throw 'HTML_ALIAS_REJECTED'
            $context.packageJson += ' '
            { Export-ApimExecutiveHtml -RunPath $script:htmlRun -AgentOutputContext $context } | Should -Throw 'HTML_PACKAGE_STALE'
        }
    }
}
