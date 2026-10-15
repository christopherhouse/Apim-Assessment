#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimProductGovernanceReason {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Product)

    if (-not $Product.productFound) { return }
    if ($Product.hasDescription -eq $false) { 'DescriptionMissing' }
    if ($Product.hasOwner -eq $false) { 'OwnerMissing' }
    if ($Product.isExternal -eq $true -and $Product.approvalRequired -eq $false) {
        'ExternalApprovalDisabled'
    }
}

function Get-ApimDiagnosticCoverageReason {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Coverage)

    if (-not $Coverage.apiFound) { return }
    if ($Coverage.configured -eq $false) { 'DiagnosticsAbsent' }
    elseif ($Coverage.configured -eq $true -and $Coverage.loggerResolved -eq $false) {
        'LoggerUnresolved'
    }
    if ($Coverage.isCritical -eq $true -and $null -ne $Coverage.samplingPercentage -and
        $Coverage.samplingPercentage -lt 100) {
        'CriticalSamplingBelowFull'
    }
}
