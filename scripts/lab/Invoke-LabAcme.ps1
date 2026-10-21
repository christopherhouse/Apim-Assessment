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
$code = 90
try {
    . (Join-Path $PSScriptRoot 'LabAcme.Core.ps1')
    . (Join-Path $PSScriptRoot 'LabAcme.Process.ps1')
    $arguments = [Collections.Generic.List[string]]::new()
    foreach ($name in $PSBoundParameters.Keys) {
        $value = $PSBoundParameters[$name]
        if ($name -in @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction',
                'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer',
                'PipelineVariable', 'ProgressAction')) { continue }
        if ($value -is [Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) { $arguments.Add("-$name") }
        }
        else { $arguments.Add("-$name"); $arguments.Add([string]$value) }
    }
    $code = Invoke-LabAcmeWorkerProcess (Join-Path $PSScriptRoot 'LabAcme.Worker.ps1') $arguments.ToArray()
}
catch { $code = 90 }
$statuses = @{
    20 = 'LAB_ACME_HEALTHY'; 21 = 'LAB_ACME_RENEWAL_DUE'; 22 = 'LAB_ACME_EXPIRY_CRITICAL'
    23 = 'LAB_ACME_CERTIFICATE_MISSING'; 24 = 'LAB_ACME_STAGING_VALIDATED'
    25 = 'LAB_ACME_IMPORTED_PENDING_CONSUMER_VALIDATION'; 26 = 'LAB_ACME_NOT_DUE'
    27 = 'LAB_ACME_APPROVAL_READY'; 90 = 'LAB_ACME_INCOMPLETE'
}
Write-Output $statuses[$code]
if ($code -eq 90) { exit 1 }
if ($code -in @(21, 22, 23)) { exit 3 }
exit 0
