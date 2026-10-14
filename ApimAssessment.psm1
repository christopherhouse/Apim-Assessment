#Requires -Version 7.4

Set-StrictMode -Version Latest

$sourceRoot = Join-Path $PSScriptRoot 'src'
foreach ($area in @('Core', 'Collect', 'Model', 'Rules', 'Package', 'Report')) {
    $areaPath = Join-Path $sourceRoot $area
    foreach ($sourceFile in Get-ChildItem -LiteralPath $areaPath -Filter '*.ps1' -File -Recurse |
            Sort-Object FullName) {
        . $sourceFile.FullName
    }
}

Export-ModuleMember -Function @(
    'Invoke-ApimCollect', 'Invoke-ApimAnalyze', 'Invoke-ApimReport',
    'Invoke-ApimAssessment', 'Compare-ApimRun'
) -Alias @()
