#Requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $RunFolder,
    [string] $RulesPath,
    [string[]] $OnlyRules,
    [string[]] $CompareRuns
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    Import-Module (Join-Path $PSScriptRoot 'ApimAssessment.psd1') -Force `
        -ErrorAction Stop 3>$null 4>$null 5>$null 6>$null
    $result = Invoke-ApimAnalyze @PSBoundParameters 2>$null 3>$null 4>$null 5>$null 6>$null
    [Console]::Out.WriteLine("ANALYZE_$($result.Status.ToUpperInvariant()) EXIT_$($result.ExitCode)")
    exit $result.ExitCode
}
catch {
    [Console]::Error.WriteLine('ANALYZE_FAILED EXIT_4')
    exit 4
}
