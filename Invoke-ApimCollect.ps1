#Requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Config,
    [Parameter(Mandatory)][string] $Environment,
    [string] $Resume,
    [ValidateRange(1, 64)][int] $ThrottleLimit = 6,
    [switch] $SkipCost,
    [switch] $SkipLogs,
    [switch] $SkipGit
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    Import-Module (Join-Path $PSScriptRoot 'ApimAssessment.psd1') -Force `
        -ErrorAction Stop 3>$null 4>$null 5>$null 6>$null
    $result = Invoke-ApimCollect @PSBoundParameters 2>$null 3>$null 4>$null 5>$null 6>$null
    [Console]::Out.WriteLine("COLLECT_$($result.Status.ToUpperInvariant()) EXIT_$($result.ExitCode)")
    exit $result.ExitCode
}
catch {
    [Console]::Error.WriteLine('COLLECT_FAILED EXIT_4')
    exit 4
}
