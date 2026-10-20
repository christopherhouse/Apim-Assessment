#Requires -Version 7.4
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$version = (Import-PowerShellDataFile (Join-Path $PSScriptRoot 'DevDependencies.psd1')).Bicep
$architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
$platform = if ($IsWindows) { 'win' } elseif ($IsLinux) { 'linux' } elseif ($IsMacOS) { 'osx' } else { throw 'Unsupported Bicep platform.' }
$asset = "bicep-$platform-$architecture"
if ($IsWindows) { $asset += '.exe' }
$hashes = @{
    'bicep-win-x64.exe' = '398af294cf16ac4becdbd008a77d148d0e8e91492309a6b60ec911b7e1cab082'
    'bicep-win-arm64.exe' = '613a0afb0ffed4dca106e6466688d780b7db0eac7cf3576f62ae9eab11554b05'
    'bicep-linux-x64' = 'b09ec25a9d376c1f8e33ede6ed22b587f915ad68488d5db77a6f9541748c7f6e'
    'bicep-linux-arm64' = '9cbf6a211137e894a863fbc842e355c2197fc2124a7bda902afe1bceffa35245'
    'bicep-osx-x64' = '6a8188d521a7c6740c8b58983093dfd9f7897d37bdf1551f775022e22397d7c5'
    'bicep-osx-arm64' = '62cd5958c62fa1b738e9b69f24799fabddb90ed83fdb7d6d2563dde376ce479d'
}
if ($version -cne '0.48.1' -or -not $hashes.ContainsKey($asset)) { throw 'Pinned Bicep asset is not defined.' }
$directory = Join-Path (Split-Path $PSScriptRoot -Parent) ".tools\bicep\$version"
$binary = Join-Path $directory $(if ($IsWindows) { 'bicep.exe' } else { 'bicep' })
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    $download = Join-Path $directory "$asset.download"
    try {
        Invoke-WebRequest -Uri "https://github.com/Azure/bicep/releases/download/v$version/$asset" `
            -OutFile $download -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ine $hashes[$asset]) {
            throw 'Pinned Bicep checksum mismatch.'
        }
        Move-Item -LiteralPath $download -Destination $binary -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $download -PathType Leaf) { Remove-Item -LiteralPath $download -Force }
    }
}
if ((Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash -ine $hashes[$asset]) {
    throw 'Installed Bicep checksum mismatch.'
}
if (-not $IsWindows) {
    & chmod u+x $binary
    if ($LASTEXITCODE -ne 0) { throw 'Unable to set Bicep executable permission.' }
}
$actual = & $binary --version
if ($LASTEXITCODE -ne 0 -or $actual -notmatch "^Bicep CLI version $([regex]::Escape($version))\b") {
    throw 'Pinned Bicep version verification failed.'
}
$foundation = Join-Path (Split-Path $PSScriptRoot -Parent) 'infra\live-validation-lab\foundation.bicep'
& $binary restore $foundation
if ($LASTEXITCODE -ne 0) { throw 'Pinned public Bicep module restore failed.' }
Write-Verbose "Ready: Bicep $version"
