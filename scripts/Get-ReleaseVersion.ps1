#Requires -Version 7.4
[CmdletBinding()]
param(
    [string] $ManifestPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'ApimAssessment.psd1'),
    [string[]] $ExistingTags = @()
)

$ErrorActionPreference = 'Stop'
$manifest = Import-PowerShellDataFile -LiteralPath $ManifestPath
$versionText = [string] $manifest.ModuleVersion
$semverPattern = '(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'

if ($versionText -cnotmatch "^$semverPattern$") {
    throw "ModuleVersion '$versionText' must be three-part SemVer (MAJOR.MINOR.PATCH), without leading zeros or prerelease suffixes."
}

$candidate = [version] $versionText
foreach ($tag in $ExistingTags) {
    if ($tag -cmatch "^v($semverPattern)$") {
        $existing = [version] $Matches[1]
        if ($candidate -le $existing) {
            throw "Release v$versionText must be newer than existing tag '$tag'. Published versions cannot be overwritten."
        }
    }
}

$versionText
