#Requires -Version 7.4
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path $PSScriptRoot -Parent
$version = (Import-PowerShellDataFile (Join-Path $PSScriptRoot 'DevDependencies.psd1')).DotNetSdk
$existing = @(Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue)
if ($existing.Count -gt 0) {
    $installed = @(& $existing[0].Source --list-sdks 2>&1)
    if ($LASTEXITCODE -eq 0 -and @($installed | Where-Object { "$_" -match "^$([regex]::Escape($version)) " }).Count -gt 0) {
        return
    }
}
$architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
$platform = if ($IsWindows) { 'win' } elseif ($IsLinux) { 'linux' } elseif ($IsMacOS) { 'osx' } else { throw 'Unsupported SDK platform.' }
$rid = "$platform-$architecture"
$hashes = @{
    'win-x64' = 'ae4fd528cb7e9f6af6aaf7de36715a69f761f183744f1bb3025d19f5a92447090ec561410e46266c1d10a63781ed6f3de771760bc76c876d87daabc367b898cd'
    'win-arm64' = 'd736fefa5c089ed5e1e854e1c07e5686e1e22638d627f6797633b92b60b1b5daddb607650be07c9f178cdbed1a944646c1a5cf3f12fb6aeef7c8cf149c9ba328'
    'linux-x64' = '1904a98dda2db34ba78ba3c4fb1b224455329af91c341d83547843c1839e112b04ae699ee92fa2449a8f62249196a938723078c0c60b9f65c88539d5687729c2'
    'linux-arm64' = 'db85ae85527251fbb1290720ac3bf324bb1d9eea74516ef291ed4bb1f8ff6ec63a17593367f49b456115e8b24ead6d0c2ece2801e501f36a6cd4444ed01a498f'
    'osx-x64' = '1628e0a07261f5bd54dde370c53b90cb72f0c88667d7cde34bd62997a29ff8f32310f81e08c85962a2b0221c05368df37fb04909b6f1431b293f445ecf895292'
    'osx-arm64' = 'ee0d379c144ebddef6efe851e1514883d1b695430d13b3fb13e8153f8476e1e5ac7abc42c08668471aaf4d738ff367cf53009845f94d224ba126febe74d00b75'
}
if ($version -cne '10.0.402' -or -not $hashes.ContainsKey($rid)) { throw 'Pinned SDK archive is not defined.' }
$directory = Join-Path $repo ".tools\dotnet\$version"
$binary = Join-Path $directory $(if ($IsWindows) { 'dotnet.exe' } else { 'dotnet' })
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $extension = if ($IsWindows) { 'zip' } else { 'tar.gz' }
    $archive = Join-Path $directory "sdk.$extension"
    try {
        Invoke-WebRequest -Uri "https://builds.dotnet.microsoft.com/dotnet/Sdk/$version/dotnet-sdk-$version-$rid.$extension" `
            -OutFile $archive -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $archive -Algorithm SHA512).Hash -ine $hashes[$rid]) {
            throw 'Pinned SDK checksum mismatch.'
        }
        if ($IsWindows) { [IO.Compression.ZipFile]::ExtractToDirectory($archive, $directory, $true) }
        else {
            & tar -xzf $archive -C $directory
            if ($LASTEXITCODE -ne 0) { throw 'Pinned SDK extraction failed.' }
        }
    }
    finally { if (Test-Path -LiteralPath $archive -PathType Leaf) { Remove-Item -LiteralPath $archive -Force } }
}
$actual = & $binary --list-sdks
if ($LASTEXITCODE -ne 0 -or @($actual | Where-Object { $_ -match "^$([regex]::Escape($version)) " }).Count -eq 0) {
    throw 'Pinned SDK verification failed.'
}
