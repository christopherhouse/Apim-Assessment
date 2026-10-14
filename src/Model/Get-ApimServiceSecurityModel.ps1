#Requires -Version 7.4

Set-StrictMode -Version Latest

function Test-ApimServiceModelMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context
    )

    if ($Value -isnot [System.Collections.IDictionary] -and
        $Value -isnot [pscustomobject]) {
        throw "$Context was not an object."
    }
}

function ConvertTo-ApimLegacyTlsSetting {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context
    )

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -isnot [string] -or
        [string]::IsNullOrWhiteSpace($Value) -or
        $Value -notin @('True', 'False')) {
        throw "$Context was not a Boolean string."
    }
    return $Value -ieq 'True'
}

function ConvertTo-ApimManagedIdentityType {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Identity
    )

    if ($null -eq $Identity) {
        return 'None'
    }
    Test-ApimServiceModelMap -Value $Identity `
        -Context 'APIM service identity'
    $type = Get-ApimModelValue -InputObject $Identity -Name type `
        -Context 'APIM service identity'
    if ($type -isnot [string] -or
        [string]::IsNullOrWhiteSpace($type)) {
        throw 'APIM service identity type was invalid.'
    }
    $parts = @($type.Split(',') | ForEach-Object { $_.Trim() })
    if ($parts.Count -eq 1 -and $parts[0] -ieq 'None') {
        return 'None'
    }
    $normalizedParts = @($parts | ForEach-Object {
            if ($_ -ieq 'SystemAssigned') {
                'SystemAssigned'
            }
            elseif ($_ -ieq 'UserAssigned') {
                'UserAssigned'
            }
            else {
                throw 'APIM service identity type was invalid.'
            }
        })
    if ($normalizedParts.Count -eq 0 -or
        $normalizedParts.Count -gt 2 -or
        @($normalizedParts | Select-Object -Unique).Count -ne
            $normalizedParts.Count) {
        throw 'APIM service identity type was invalid.'
    }
    if ($normalizedParts.Count -eq 2) {
        return 'SystemAssignedUserAssigned'
    }
    return $normalizedParts[0]
}

function Get-ApimServiceSecurityModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $ServicePayload
    )

    $properties = Get-ApimModelValue -InputObject $ServicePayload `
        -Name properties -Context 'APIM service'
    Test-ApimServiceModelMap -Value $properties `
        -Context 'APIM service properties'
    $customProperties = Get-ApimModelValue -InputObject $properties `
        -Name customProperties -Context 'APIM service properties' `
        -AllowMissing
    if ($null -ne $customProperties) {
        Test-ApimServiceModelMap -Value $customProperties `
            -Context 'APIM custom properties'
    }
    $legacyControls = [ordered]@{
        GatewayTls10 = (
            'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.' +
            'Protocols.Tls10'
        )
        GatewayTls11 = (
            'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.' +
            'Protocols.Tls11'
        )
        GatewayTripleDes168 = (
            'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.' +
            'Ciphers.TripleDes168'
        )
        BackendTls10 = (
            'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.' +
            'Protocols.Tls10'
        )
        BackendTls11 = (
            'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.' +
            'Protocols.Tls11'
        )
    }
    $enabledControls = [System.Collections.Generic.List[string]]::new()
    $missingLegacyControl = $false
    foreach ($control in $legacyControls.GetEnumerator()) {
        $value = if ($null -eq $customProperties) {
            $null
        }
        else {
            Get-ApimModelValue -InputObject $customProperties `
                -Name $control.Value -Context 'APIM custom properties' `
                -AllowMissing
        }
        $enabled = ConvertTo-ApimLegacyTlsSetting -Value $value `
            -Context "APIM legacy TLS control '$($control.Key)'"
        if ($null -eq $enabled) {
            $missingLegacyControl = $true
        }
        elseif ($enabled) {
            $enabledControls.Add($control.Key)
        }
    }

    $apiVersionConstraint = Get-ApimModelValue -InputObject $properties `
        -Name apiVersionConstraint -Context 'APIM service properties' `
        -AllowMissing
    if ($null -ne $apiVersionConstraint) {
        Test-ApimServiceModelMap -Value $apiVersionConstraint `
            -Context 'APIM API version constraint'
    }
    $minApiVersion = if ($null -eq $apiVersionConstraint) {
        $null
    }
    else {
        Get-ApimModelValue -InputObject $apiVersionConstraint `
            -Name minApiVersion -Context 'APIM API version constraint' `
            -AllowMissing
    }
    if ($null -ne $minApiVersion -and
        ($minApiVersion -isnot [string] -or
            [string]::IsNullOrWhiteSpace($minApiVersion))) {
        throw 'APIM minimum API version was invalid.'
    }

    $identity = Get-ApimModelValue -InputObject $ServicePayload `
        -Name identity -Context 'APIM service' -AllowMissing
    $managedIdentity = ConvertTo-ApimManagedIdentityType -Identity $identity
    $legacyTlsEnabled = if ($enabledControls.Count -gt 0) {
        $true
    }
    elseif ($missingLegacyControl) {
        $null
    }
    else {
        $false
    }
    [string[]] $missingInputs = @()
    if ($missingLegacyControl) {
        $missingInputs = @('legacyTlsControls')
    }

    return [pscustomobject] [ordered]@{
        legacyTlsEnabled = $legacyTlsEnabled
        enabledLegacyTlsControls = $enabledControls.ToArray()
        minApiVersion = $minApiVersion
        managedIdentity = $managedIdentity
        modelStatus = if ($missingInputs.Count -eq 0) {
            'Complete'
        }
        else {
            'Partial'
        }
        missingInputs = $missingInputs
    }
}

function Write-ApimServiceSecurityModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Model
    )

    return Write-ApimModelSet -RunPath $RunPath `
        -Models ([ordered]@{ service = $Model })
}
