BeforeAll {
    $script:profileRepository = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}

Describe 'Assessment profile tool admission declarations' {
    It 'declares the exact broker-only allowlist for <Profile>' -ForEach @(
        @{ Profile = 'apim-architecture-exposure'; Tools = @('read_validated_analysis_package') }
        @{ Profile = 'apim-security-analyst'; Tools = @('read_validated_analysis_package') }
        @{ Profile = 'apim-executive-synthesizer'; Tools = @('read_validated_analysis_package', 'read_validated_agent_outputs') }
        @{ Profile = 'apim-assessment-orchestrator'; Tools = @('run_assessment', 'get_assessment_status', 'promote_analysis_package', 'read_validated_analysis_package', 'validate_agent_output', 'read_validated_agent_outputs', 'render_reports') }
    ) {
        $text = Get-Content -LiteralPath (
            Join-Path $script:profileRepository ".github/agents/$Profile.agent.md"
        ) -Raw
        $header = ($text -split '---', 3)[1]
        $header | Should -Match 'disable-model-invocation: true'
        $header | Should -Not -Match 'mcp-servers:'
        $line = [regex]::Match($header, '(?m)^tools: (\[[^\r\n]+\])\r?$')
        $line.Success | Should -BeTrue
        $actual = @(ConvertFrom-Json -InputObject $line.Groups[1].Value)
        $expected = @($Tools | ForEach-Object { "apim-assessment/$_" })
        $actual | Should -Be $expected
        $actual | Should -Not -Match '\*|^(read|execute|edit|search|agent|web)$'
    }
}

Describe 'Executive template normal-text contrast' {
    BeforeAll {
        $script:contrastHtml = Get-Content -LiteralPath (
            Join-Path $script:profileRepository 'template/ApimExecutiveSummary.html'
        ) -Raw
        function Get-TemplateLuminance {
            param([string] $Hex)
            $channels = @(0, 2, 4 | ForEach-Object {
                    $value = [Convert]::ToInt32($Hex.Substring($_, 2), 16) / 255
                    if ($value -le 0.04045) { $value / 12.92 }
                    else { [Math]::Pow(($value + 0.055) / 1.055, 2.4) }
                })
            return 0.2126 * $channels[0] + 0.7152 * $channels[1] + 0.0722 * $channels[2]
        }
    }
    It 'meets 4.5:1 for all used text/background pairs in <Theme> mode' -ForEach @(
        @{ Theme = 'light'; Selector = ':root' }
        @{ Theme = 'dark'; Selector = 'html[data-theme="dark"]' }
    ) {
        $block = [regex]::Match($script:contrastHtml, [regex]::Escape($Selector) + '\s*\{([^}]+)\}').Groups[1].Value
        $colors = @{}
        foreach ($match in [regex]::Matches($block, '(--cp-[a-z-]+): #([0-9a-f]{6});')) {
            $colors[$match.Groups[1].Value] = $match.Groups[2].Value
        }
        foreach ($pair in @(
                @('--cp-text', '--cp-bg'), @('--cp-text', '--cp-surface'),
                @('--cp-text', '--cp-surface-soft'), @('--cp-text-soft', '--cp-bg'),
                @('--cp-text-soft', '--cp-surface'), @('--cp-link', '--cp-surface'),
                @('--cp-accent', '--cp-surface')
            )) {
            $first = Get-TemplateLuminance $colors[$pair[0]]
            $second = Get-TemplateLuminance $colors[$pair[1]]
            $ratio = ([Math]::Max($first, $second) + 0.05) / ([Math]::Min($first, $second) + 0.05)
            $ratio | Should -BeGreaterOrEqual 4.5 -Because "$($pair -join '/') is used for normal text"
        }
    }
}
