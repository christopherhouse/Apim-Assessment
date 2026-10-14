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

function ConvertTo-ApimServiceZoneArray {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value) {
        return @()
    }
    if ($Value -is [string] -or
        $Value -isnot [System.Collections.IEnumerable]) {
        throw 'APIM service zones were not an array.'
    }
    $zones = [System.Collections.Generic.List[string]]::new()
    foreach ($zone in @($Value)) {
        if ($zone -isnot [string] -or
            [string]::IsNullOrWhiteSpace([string] $zone)) {
            throw 'APIM service zones contained an invalid value.'
        }
        $zones.Add([string] $zone)
    }
    return @($zones | Sort-Object -Unique)
}

function ConvertTo-ApimServiceModelDate {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context
    )

    if ($null -eq $Value -or
        [string]::IsNullOrWhiteSpace([string] $Value)) {
        return $null
    }
    $parsed = if ($Value -is [datetimeoffset]) {
        [datetimeoffset] $Value
    }
    elseif ($Value -is [datetime]) {
        [datetimeoffset] ([datetime] $Value).ToUniversalTime()
    }
    else {
        $candidate = [datetimeoffset]::MinValue
        if (-not [datetimeoffset]::TryParse(
                [string] $Value,
                [System.Globalization.CultureInfo]::InvariantCulture,
                (
                    [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
                    [System.Globalization.DateTimeStyles]::AdjustToUniversal
                ),
                [ref] $candidate
            )) {
            throw "$Context was not a valid date-time."
        }
        $candidate
    }
    return $parsed.ToUniversalTime().ToString('O')
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

    $sku = Get-ApimModelValue -InputObject $ServicePayload `
        -Name sku -Context 'APIM service' -AllowMissing
    $skuName = $null
    $skuCapacity = $null
    if ($null -ne $sku) {
        Test-ApimServiceModelMap -Value $sku -Context 'APIM service SKU'
        $skuNameValue = Get-ApimModelValue -InputObject $sku -Name name `
            -Context 'APIM service SKU' -AllowMissing
        if ($null -ne $skuNameValue) {
            if ($skuNameValue -isnot [string] -or
                [string]::IsNullOrWhiteSpace([string] $skuNameValue)) {
                throw 'APIM service SKU name was invalid.'
            }
            $skuName = [string] $skuNameValue
        }
        $skuCapacityValue = Get-ApimModelValue -InputObject $sku `
            -Name capacity -Context 'APIM service SKU' -AllowMissing
        if ($null -ne $skuCapacityValue) {
            if ($skuCapacityValue -isnot [System.ValueType] -or
                [double]::IsNaN([double] $skuCapacityValue) -or
                [double]::IsInfinity([double] $skuCapacityValue) -or
                [double] $skuCapacityValue -lt 0 -or
                [double] $skuCapacityValue -ne
                    [math]::Truncate([double] $skuCapacityValue) -or
                [double] $skuCapacityValue -gt [int]::MaxValue) {
                throw 'APIM service SKU capacity was invalid.'
            }
            $skuCapacity = [int] $skuCapacityValue
        }
    }
    $zones = @(
        ConvertTo-ApimServiceZoneArray -Value (
            Get-ApimModelValue -InputObject $ServicePayload -Name zones `
                -Context 'APIM service' -AllowMissing
        )
    )
    $platformVersionValue = Get-ApimModelValue -InputObject $properties `
        -Name platformVersion -Context 'APIM service properties' `
        -AllowMissing
    $platformVersion = $null
    if ($null -ne $platformVersionValue) {
        if ($platformVersionValue -isnot [string] -or
            [string]::IsNullOrWhiteSpace(
                [string] $platformVersionValue
            )) {
            throw 'APIM service platform version was invalid.'
        }
        $platformVersion = ([string] $platformVersionValue).ToLowerInvariant()
    }
    $hostnameCertificateExpirations = [System.Collections.Generic.List[string]]::new()
    $hostnameCertificateExpiryMissing = $false
    foreach ($hostnameConfiguration in @(
            Get-ApimModelValue -InputObject $properties `
                -Name hostnameConfigurations `
                -Context 'APIM service properties' -AllowMissing
        )) {
        if ($null -eq $hostnameConfiguration) {
            continue
        }
        Test-ApimServiceModelMap -Value $hostnameConfiguration `
            -Context 'APIM hostname configuration'
        $certificate = Get-ApimModelValue `
            -InputObject $hostnameConfiguration -Name certificate `
            -Context 'APIM hostname configuration' -AllowMissing
        if ($null -eq $certificate) {
            $hostnameCertificateExpiryMissing = $true
            continue
        }
        Test-ApimServiceModelMap -Value $certificate `
            -Context 'APIM hostname certificate'
        $expiration = ConvertTo-ApimServiceModelDate -Value (
            Get-ApimModelValue -InputObject $certificate -Name expiry `
                -Context 'APIM hostname certificate' -AllowMissing
        ) -Context 'APIM hostname certificate expiry'
        if ($null -eq $expiration) {
            $hostnameCertificateExpiryMissing = $true
            continue
        }
        $hostnameCertificateExpirations.Add($expiration)
    }

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
    if ($null -eq $skuName) {
        $missingInputs += 'skuName'
    }
    if ($null -eq $skuCapacity) {
        $missingInputs += 'skuCapacity'
    }
    if ($null -eq $platformVersion) {
        $missingInputs += 'platformVersion'
    }
    if ($hostnameCertificateExpiryMissing) {
        $missingInputs += 'hostnameCertificateExpirations'
    }
    $missingInputs = @($missingInputs | Sort-Object -Unique)

    return [pscustomobject] [ordered]@{
        skuName = $skuName
        skuCapacity = $skuCapacity
        zones = $zones
        platformVersion = $platformVersion
        hostnameCertificateExpirations = @(
            $hostnameCertificateExpirations | Sort-Object -Unique
        )
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
