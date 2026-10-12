BeforeAll {
    $script:repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}

Describe 'Repository data exclusions' {
    It 'ignores conventional restricted and model-safe output paths' -TestCases @(
        @{ Path = 'runs/synthetic/manifest.json' }
        @{ Path = 'model-safe/synthetic/analysis-package.json' }
        @{ Path = 'config/customer.psd1' }
    ) {
        Push-Location $script:repoRoot
        try {
            & git check-ignore --quiet -- $Path
            $LASTEXITCODE | Should -Be 0
        }
        finally {
            Pop-Location
        }
    }

    It 'keeps the synthetic sample configuration tracked' {
        Push-Location $script:repoRoot
        try {
            & git check-ignore --quiet -- 'config/sample.psd1'
            $LASTEXITCODE | Should -Be 1
            & git ls-files --error-unmatch -- 'config/sample.psd1' 2>$null
            $LASTEXITCODE | Should -Be 0
        }
        finally {
            Pop-Location
        }
    }
}
