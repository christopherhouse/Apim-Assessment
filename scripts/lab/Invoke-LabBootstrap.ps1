#Requires -Version 7.4
[CmdletBinding()]
param(
    [string] $ConfigPath,
    [string] $PlanPath,
    [ValidateSet('Preview', 'Apply')][string] $Mode = 'Preview',
    [ValidateSet('Identity', 'Runtime')][string] $Stage = 'Identity',
    [string] $ApprovedPlanSha256 = '',
    [switch] $OwnerAuthorized,
    [switch] $MicrosoftOwnedTestEnvironment
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    . (Join-Path $PSScriptRoot 'LabBootstrap.Transport.ps1')
    . (Join-Path $PSScriptRoot 'LabBootstrap.Core.ps1')
    $parameters = @{
        ConfigPath = $ConfigPath; PlanPath = $PlanPath; Mode = $Mode; Stage = $Stage
        ApprovedPlanSha256 = $ApprovedPlanSha256; OwnerAuthorized = $OwnerAuthorized
        MicrosoftOwnedTestEnvironment = $MicrosoftOwnedTestEnvironment
    }
    $result = Invoke-LabBootstrap @parameters 2>$null 3>$null 4>$null 5>$null 6>$null
    [Console]::Out.WriteLine($result.code)
    if ($result.state -cin @('Applied', 'PreviewReady')) { exit 0 }
    if ($result.state -ceq 'NotReady') { exit 2 }
    exit 1
}
catch {
    [Console]::Out.WriteLine('LAB_BOOTSTRAP_FAILED')
    exit 1
}
