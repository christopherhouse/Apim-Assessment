BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:releaseVersion = Join-Path $repoRoot 'scripts/Get-ReleaseVersion.ps1'
    $script:releaseManifestPath = Join-Path $TestDrive 'release.psd1'
}

Describe 'Release SemVer guard' {
    BeforeEach {
        Set-Content -LiteralPath $script:releaseManifestPath -Value "@{ ModuleVersion = '1.2.3' }"
    }

    It 'allows an initial release with no tags' {
        & $script:releaseVersion -ManifestPath $script:releaseManifestPath | Should -Be '1.2.3'
    }

    It 'compares version components numerically rather than lexically' {
        Set-Content -LiteralPath $script:releaseManifestPath -Value "@{ ModuleVersion = '1.10.0' }"
        & $script:releaseVersion -ManifestPath $script:releaseManifestPath -ExistingTags @('v1.9.9', 'v0.20.0') |
            Should -Be '1.10.0'
    }

    It 'ignores nonstable version tags' {
        & $script:releaseVersion -ManifestPath $script:releaseManifestPath `
            -ExistingTags @('initial', 'v2.0.0-beta.1') | Should -Be '1.2.3'
    }

    It 'rejects an existing or regressive release compared with <Tag>' -TestCases @(
        @{ Tag = 'v1.2.3' }
        @{ Tag = 'v1.2.4' }
        @{ Tag = 'v2.0.0' }
    ) {
        { & $script:releaseVersion -ManifestPath $script:releaseManifestPath -ExistingTags @('v0.1.0', $Tag) } |
            Should -Throw '*must be newer*'
    }

    It 'rejects invalid ModuleVersion <Version>' -TestCases @(
        @{ Version = '1.2' }
        @{ Version = '1.2.3.4' }
        @{ Version = '1.02.3' }
        @{ Version = '01.2.3' }
        @{ Version = '1.2.3-beta' }
        @{ Version = '' }
    ) {
        Set-Content -LiteralPath $script:releaseManifestPath -Value "@{ ModuleVersion = '$Version' }"
        { & $script:releaseVersion -ManifestPath $script:releaseManifestPath } | Should -Throw '*three-part SemVer*'
    }
}
