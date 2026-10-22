#Requires -Version 7.4
Set-StrictMode -Version Latest

function Get-CurrentPluginType { 'dns-01' }

function Add-DnsTxt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string] $RecordName,
        [Parameter(Mandatory, Position = 1)][string] $TxtValue,
        [Parameter(Mandatory)][string] $LabSessionNonce,
        [Parameter(ValueFromRemainingArguments)][object] $ExtraParams
    )
    $dispatch = [AppDomain]::CurrentDomain.GetData('ApimAssessment.LabAcme.DnsDispatch')
    if ($dispatch -isnot [scriptblock]) {
        throw 'LAB_ACME_DISPATCH_UNAVAILABLE'
    }
    $null = $ExtraParams
    & $dispatch 'Add' $RecordName $TxtValue $LabSessionNonce
}

function Remove-DnsTxt {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string] $RecordName,
        [Parameter(Mandatory, Position = 1)][string] $TxtValue,
        [Parameter(Mandatory)][string] $LabSessionNonce,
        [Parameter(ValueFromRemainingArguments)][object] $ExtraParams
    )
    $dispatch = [AppDomain]::CurrentDomain.GetData('ApimAssessment.LabAcme.DnsDispatch')
    if ($dispatch -isnot [scriptblock]) {
        throw 'LAB_ACME_DISPATCH_UNAVAILABLE'
    }
    if (-not $PSCmdlet.ShouldProcess('approved lab DNS challenge', 'Remove owned TXT value')) {
        throw 'LAB_ACME_DNS_CHANGE_DECLINED'
    }
    $null = $ExtraParams
    & $dispatch 'Remove' $RecordName $TxtValue $LabSessionNonce
}

function Save-DnsTxt {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)][object] $ExtraParams)
    $null = $ExtraParams
}
