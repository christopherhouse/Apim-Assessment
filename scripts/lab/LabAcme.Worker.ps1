#Requires -Version 7.4
[CmdletBinding()]
param(
    [string] $ConfigPath,
    [string] $Mode = 'Check',
    [string] $Stage = 'Staging',
    [string] $PlanPath,
    [string] $ApprovedPlanSha256,
    [switch] $OwnerAuthorized,
    [switch] $MicrosoftOwnedTestEnvironment,
    [switch] $AcceptPublicDnsQueries,
    [switch] $AcceptAcmeTerms,
    [switch] $AcceptCertificateTransparency,
    [switch] $Rotate
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    foreach ($name in @('Core', 'Transport', 'Dns', 'Certificate', 'Workflow')) {
        . (Join-Path $PSScriptRoot "LabAcme.$name.ps1")
    }
    $code = Invoke-LabAcmeWorkflow @PSBoundParameters
    if ($code -notin @(20, 21, 22, 23, 24, 25, 26, 27, 90)) { exit 90 }
    exit $code
}
catch { exit 90 }
