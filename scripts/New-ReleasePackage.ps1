#Requires -Version 7.4
[CmdletBinding()]
param(
    [string] $OutputDirectory = 'dist'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$version = & (Join-Path $PSScriptRoot 'Get-ReleaseVersion.ps1')
if (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot $OutputDirectory
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$archivePath = Join-Path $OutputDirectory "ApimAssessment-$version.zip"
$checksumPath = "$archivePath.sha256"
if ((Test-Path -LiteralPath $archivePath) -or (Test-Path -LiteralPath $checksumPath)) {
    throw "Release output already exists in '$OutputDirectory'. Choose a fresh output directory; packages are not overwritten."
}

$files = @(
    Get-Item -LiteralPath (Join-Path $repoRoot 'ApimAssessment.psd1')
    Get-Item -LiteralPath (Join-Path $repoRoot 'ApimAssessment.psm1')
    Get-Item -LiteralPath (Join-Path $repoRoot 'README.md')
    Get-Item -LiteralPath (Join-Path $repoRoot 'CONTRIBUTING.md')
    Get-Item -LiteralPath (Join-Path $repoRoot 'config/sample.psd1')
)
foreach ($entryPoint in @(
        'Invoke-ApimCollect.ps1', 'Invoke-ApimAnalyze.ps1', 'Invoke-ApimReport.ps1',
        'Compare-ApimRun.ps1', 'Invoke-ApimAssessment.ps1'
    )) {
    $entryPath = Join-Path $repoRoot $entryPoint
    if (Test-Path -LiteralPath $entryPath) {
        $files += Get-Item -LiteralPath $entryPath
    }
}
$contentPaths = @(
    @{ Directory = 'src'; Pattern = '*.ps1' }
    @{ Directory = 'rules'; Pattern = '*.ps1' }
    @{ Directory = 'queries'; Pattern = '*.kql' }
    @{ Directory = 'schemas'; Pattern = '*.json' }
    @{ Directory = 'template'; Pattern = '*.xlsx' }
    @{ Directory = 'docs'; Pattern = '*.md' }
)
foreach ($contentPath in $contentPaths) {
    $files += Get-ChildItem -LiteralPath (Join-Path $repoRoot $contentPath.Directory) `
        -Filter $contentPath.Pattern -File -Recurse
}

$archive = [System.IO.Compression.ZipFile]::Open($archivePath, 'Create')
try {
    # Keep empty source areas importable before their first implementation lands.
    foreach ($area in @('Core', 'Collect', 'Model', 'Rules', 'Report')) {
        $archive.CreateEntry("src/$area/") | Out-Null
    }
    foreach ($file in $files | Sort-Object FullName -Unique) {
        $relativePath = [System.IO.Path]::GetRelativePath($repoRoot, $file.FullName)
        $entryName = $relativePath.Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $file.FullName, $entryName
        ) | Out-Null
    }
}
finally {
    $archive.Dispose()
}

$hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
$checksum = "$hash  $([System.IO.Path]::GetFileName($archivePath))`n"
[System.IO.File]::WriteAllText($checksumPath, $checksum, [System.Text.UTF8Encoding]::new($false))

[pscustomobject] @{
    Version  = $version
    Archive  = $archivePath
    Checksum = $checksumPath
}
