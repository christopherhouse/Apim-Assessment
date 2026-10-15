#Requires -Version 7.4
<#
.SYNOPSIS
Explicit maintainer/developer installation of the optional pinned Spectral CLI.
.DESCRIPTION
Requires Node 22 or >=24 and npm. Never called by assessment execution.
Installs only in ignored .tools/spectral, with dependency lifecycle scripts disabled.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$dependency = (Import-PowerShellDataFile (Join-Path $PSScriptRoot 'OptionalDependencies.psd1')).Spectral
$nodeVersion = & node --version
if ($LASTEXITCODE -ne 0 -or $nodeVersion -notmatch '^v(\d+)\.' -or
    ([int]$Matches[1] -ne 22 -and [int]$Matches[1] -lt 24)) {
    throw 'Optional Spectral installation requires Node 22 or >=24.'
}
$root = Split-Path $PSScriptRoot -Parent
$target = Join-Path $root $dependency.Directory
New-Item -ItemType Directory -Path $target -Force | Out-Null
& npm install --prefix $target --ignore-scripts --no-audit --no-fund --save-exact `
    "$($dependency.Package)@$($dependency.Version)"
if ($LASTEXITCODE -ne 0) { throw 'Optional Spectral installation failed.' }
Write-Verbose 'Pinned optional Spectral installed; assessment commands never install tools.'
