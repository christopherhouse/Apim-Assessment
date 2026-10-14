#Requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $RunFolder,
    [string] $PreviousReport
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    Import-Module (Join-Path $PSScriptRoot 'ApimAssessment.psd1') -Force `
        -ErrorAction Stop 3>$null 4>$null 5>$null 6>$null
    $result = Invoke-ApimReport @PSBoundParameters 2>$null 3>$null 4>$null 5>$null 6>$null
    [Console]::Out.WriteLine("REPORT_$($result.Status.ToUpperInvariant()) EXIT_$($result.ExitCode)")
    exit $result.ExitCode
}
catch {
    [Console]::Error.WriteLine('REPORT_FAILED EXIT_4')
    exit 4
}
