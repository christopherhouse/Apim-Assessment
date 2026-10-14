#Requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $RunFolder
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

try {
    . (Join-Path $PSScriptRoot 'Write-ApimSecretScanTable.ps1')
    $secretSummary = [System.Collections.Generic.List[object]]::new()
    $onSecretSummary = {
        param($Rows)
        foreach ($row in $Rows) { $secretSummary.Add($row) }
    }.GetNewClosure()
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $module = Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') `
        -Force -PassThru -ErrorAction Stop
    $clean = & $module {
        param($folder, $repository, $summaryCallback)
        $fullPath = [System.IO.Path]::GetFullPath($folder)
        if (Test-ConfigPathOverlap -First $fullPath -Second $repository) {
            throw 'Secret scan run must be outside the repository.'
        }
        Test-ApimRunSecret -RunFolder $fullPath -WriteLocationReport `
            -OnSummary $summaryCallback
    } $RunFolder $repoRoot $onSecretSummary 2>$null 3>$null 4>$null 5>$null 6>$null
    if (-not $clean) {
        [Console]::Error.WriteLine('SECRET_SCAN_DETAILS: open secret-scan-locations.json in the supplied run folder locally. It lists file locations and match categories, not values. Do not paste it into Copilot.')
        Write-ApimSecretScanTable -Rows $secretSummary.ToArray()
    }
}
catch {
    [Console]::Error.WriteLine('SECRET_SCAN_DETAILS: no complete locations report is available for this attempt; an existing report may be absent or stale. Resolve local scan/read/write errors and rerun.')
    [Console]::Error.WriteLine('SECRET_SCAN_ERROR: scan incomplete; inspect the run locally. Exit code: 2.')
    exit 2
}
if (-not $clean) {
    [Console]::Error.WriteLine('SECRET_SCAN_FAIL: secret-like candidate detected; this may be a false positive. Exit code: 1.')
    exit 1
}
[Console]::Out.WriteLine('SECRET_SCAN_PASS: no supported secret patterns detected. Exit code: 0.')
exit 0
