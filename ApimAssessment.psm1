#Requires -Version 7.4

Set-StrictMode -Version Latest

$sourceRoot = Join-Path $PSScriptRoot 'src'
foreach ($area in @('Core', 'Collect', 'Model', 'Rules', 'Report')) {
    $areaPath = Join-Path $sourceRoot $area
    foreach ($sourceFile in Get-ChildItem -LiteralPath $areaPath -Filter '*.ps1' -File -Recurse |
            Sort-Object FullName) {
        . $sourceFile.FullName
    }
}

# Public commands are added to this list and the manifest together when implemented.
Export-ModuleMember -Function @() -Alias @()
