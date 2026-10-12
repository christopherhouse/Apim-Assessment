BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $packageRepo = Join-Path $TestDrive 'source'
    New-Item -ItemType Directory -Path $packageRepo | Out-Null
    foreach ($file in @('ApimAssessment.psd1', 'ApimAssessment.psm1', 'README.md', 'CONTRIBUTING.md')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $file) -Destination $packageRepo
    }
    foreach ($directory in @('scripts', 'src', 'rules', 'queries', 'schemas', 'template', 'docs', 'config')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $directory) -Destination $packageRepo -Recurse -Force
    }
    foreach ($directory in @('runs', 'tests', 'artifacts', 'dist', '.git', '.github')) {
        $path = Join-Path $packageRepo $directory
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $path 'synthetic-private.json') -Value '{"sentinel":true}'
    }
    Set-Content -LiteralPath (Join-Path $packageRepo 'config/private.psd1') `
        -Value "@{ Customer = 'Synthetic private sentinel' }"
    $script:packageScript = Join-Path $packageRepo 'scripts/New-ReleasePackage.ps1'
}

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Release source package' {
    It 'ships an importable module and matching checksum without private data areas' {
        $package = & $script:packageScript -OutputDirectory (Join-Path $TestDrive 'package')
        $archive = [System.IO.Compression.ZipFile]::OpenRead($package.Archive)
        try {
            $entries = @($archive.Entries.FullName)
            $entries | Should -Contain 'ApimAssessment.psd1'
            $entries | Should -Contain 'config/sample.psd1'
            @($entries | Where-Object {
                $_ -match '^(runs|tests|artifacts|dist|\.git|\.github)/' -or
                ($_ -like 'config/*' -and $_ -ne 'config/sample.psd1')
            }) | Should -BeNullOrEmpty
        }
        finally {
            $archive.Dispose()
        }

        $hash = (Get-FileHash -LiteralPath $package.Archive -Algorithm SHA256).Hash.ToLowerInvariant()
        (Get-Content -LiteralPath $package.Checksum -Raw).Trim() |
            Should -Be "$hash  $([System.IO.Path]::GetFileName($package.Archive))"

        $expanded = Join-Path $TestDrive 'expanded'
        Expand-Archive -LiteralPath $package.Archive -DestinationPath $expanded
        { Import-Module (Join-Path $expanded 'ApimAssessment.psd1') -Force -ErrorAction Stop } |
            Should -Not -Throw
    }

    It 'refuses to overwrite an existing archive' {
        $outputDirectory = Join-Path $TestDrive 'existing'
        $original = & $script:packageScript -OutputDirectory $outputDirectory
        $originalHash = (Get-FileHash -LiteralPath $original.Archive).Hash
        { & $script:packageScript -OutputDirectory $outputDirectory } |
            Should -Throw '*already exists*'
        (Get-FileHash -LiteralPath $original.Archive).Hash | Should -Be $originalHash
    }
}
