#Requires -Version 7.4

Set-StrictMode -Version Latest

function ConvertTo-ApimSecurityModelStringArray {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context,

        [string[]] $AllowedValue = @()
    )

    if ($null -eq $Value) {
        return @()
    }
    if ($Value -is [string] -or
        $Value -isnot [System.Collections.IEnumerable]) {
        throw "$Context was not an array."
    }
    $values = [System.Collections.Generic.List[string]]::new()
    foreach ($item in @($Value)) {
        if ($item -isnot [string] -or
            [string]::IsNullOrWhiteSpace([string] $item) -or
            ($AllowedValue.Count -gt 0 -and
                [string] $item -cnotin $AllowedValue)) {
            throw "$Context contained an invalid value."
        }
        $values.Add([string] $item)
    }
    [string[]] $sorted = @($values | Sort-Object -Unique)
    return $sorted
}

function ConvertTo-ApimSecurityModelDate {
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

function Get-ApimSecurityModelKeyVaultFact {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $KeyVault,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context,

        [switch] $IncludeStatus
    )

    if ($null -eq $KeyVault) {
        return [pscustomobject] [ordered]@{
            backed = $false
            status = $null
            missingInputs = @()
        }
    }

    $secretIdentifier = Get-ApimModelValue -InputObject $KeyVault `
        -Name secretIdentifier -Context $Context -AllowMissing
    if ($null -ne $secretIdentifier -and
        ($secretIdentifier -isnot [string] -or
            [string]::IsNullOrWhiteSpace([string] $secretIdentifier))) {
        throw "$Context secret identifier was invalid."
    }
    $backed = if ($null -eq $secretIdentifier) { $null } else { $true }
    $missingInputs = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $backed) {
        $missingInputs.Add('keyVaultReference')
    }

    $status = $null
    if ($IncludeStatus -and $backed) {
        $lastStatus = Get-ApimModelValue -InputObject $KeyVault `
            -Name lastStatus -Context $Context -AllowMissing
        if ($null -ne $lastStatus) {
            $status = Get-ApimModelValue -InputObject $lastStatus `
                -Name code -Context "$Context status" -AllowMissing
            if ($null -ne $status -and
                ($status -isnot [string] -or
                    [string]::IsNullOrWhiteSpace([string] $status))) {
                throw "$Context status code was invalid."
            }
        }
        if ($null -eq $status) {
            $missingInputs.Add('keyVaultStatus')
        }
    }

    return [pscustomobject] [ordered]@{
        backed = $backed
        status = $status
        missingInputs = @($missingInputs | Sort-Object)
    }
}

function Get-ApimSecurityAssetModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $NamedValuesPayload,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $BackendsPayload,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $CertificatesPayload
    )

    $namedValues = [System.Collections.Generic.List[object]]::new()
    foreach ($resource in Get-ApimModelCollection `
            -Payload $NamedValuesPayload -Context 'APIM named-value payload') {
        $namedValueId = [string] (Get-ApimModelValue `
                -InputObject $resource -Name name -Context 'APIM named value')
        $properties = Get-ApimModelValue -InputObject $resource `
            -Name properties -Context 'APIM named value'
        $secret = Get-ApimModelValue -InputObject $properties -Name secret `
            -Context 'APIM named-value properties'
        if ($secret -isnot [bool]) {
            throw 'APIM named-value secret setting was not Boolean.'
        }
        $locations = @(
            ConvertTo-ApimSecurityModelStringArray -Value (
                Get-ApimModelValue -InputObject $properties `
                    -Name secretPatternLocations `
                    -Context 'APIM named-value properties'
            ) -Context 'APIM named-value secret locations' `
                -AllowedValue @('displayName', 'value')
        )
        $keyVault = Get-ApimSecurityModelKeyVaultFact -KeyVault (
            Get-ApimModelValue -InputObject $properties -Name keyVault `
                -Context 'APIM named-value properties' -AllowMissing
        ) -Context 'APIM named-value Key Vault metadata' -IncludeStatus
        $missingInputs = @($keyVault.missingInputs)

        $namedValues.Add([pscustomobject] [ordered]@{
                namedValueId = $namedValueId
                secret = [bool] $secret
                keyVaultBacked = $keyVault.backed
                keyVaultStatus = $keyVault.status
                secretPatternLocations = $locations
                plainTextSecretLike = -not [bool] $secret -and
                    $locations.Count -gt 0
                modelStatus = if ($missingInputs.Count -eq 0) {
                    'Complete'
                }
                else {
                    'Partial'
                }
                missingInputs = $missingInputs
            })
    }

    $backends = [System.Collections.Generic.List[object]]::new()
    foreach ($resource in Get-ApimModelCollection `
            -Payload $BackendsPayload -Context 'APIM backend payload') {
        $backendId = [string] (Get-ApimModelValue `
                -InputObject $resource -Name name -Context 'APIM backend')
        $properties = Get-ApimModelValue -InputObject $resource `
            -Name properties -Context 'APIM backend'
        $url = Get-ApimModelValue -InputObject $properties -Name url `
            -Context 'APIM backend properties'
        $uri = $null
        if ($url -isnot [string] -or
            -not [System.Uri]::TryCreate(
                [string] $url,
                [System.UriKind]::Absolute,
                [ref] $uri
            ) -or $uri.Scheme -notin @('http', 'https')) {
            throw 'APIM backend model URL was invalid.'
        }
        $tls = Get-ApimModelValue -InputObject $properties -Name tls `
            -Context 'APIM backend properties'
        $chain = Get-ApimModelValue -InputObject $tls `
            -Name validateCertificateChain -Context 'APIM backend TLS metadata'
        $name = Get-ApimModelValue -InputObject $tls `
            -Name validateCertificateName -Context 'APIM backend TLS metadata'
        foreach ($value in @($chain, $name)) {
            if ($null -ne $value -and $value -isnot [bool]) {
                throw 'APIM backend TLS validation setting was not Boolean.'
            }
        }
        $credentials = Get-ApimModelValue -InputObject $properties `
            -Name credentials -Context 'APIM backend properties'
        $credentialConfigured = Get-ApimModelValue `
            -InputObject $credentials -Name configured `
            -Context 'APIM backend credential metadata'
        $circuitBreakerConfigured = Get-ApimModelValue `
            -InputObject $properties -Name circuitBreakerConfigured `
            -Context 'APIM backend properties'
        $poolConfigured = Get-ApimModelValue -InputObject $properties `
            -Name poolConfigured -Context 'APIM backend properties'
        foreach ($value in @(
                $credentialConfigured,
                $circuitBreakerConfigured,
                $poolConfigured
            )) {
            if ($value -isnot [bool]) {
                throw 'APIM backend model setting was not Boolean.'
            }
        }

        $missingInputs = [System.Collections.Generic.List[string]]::new()
        $tlsChain = $null
        $tlsName = $null
        if ($uri.Scheme -eq 'https') {
            $tlsChain = $chain
            $tlsName = $name
            if ($null -eq $chain) {
                $missingInputs.Add('tlsValidationChain')
            }
            if ($null -eq $name) {
                $missingInputs.Add('tlsValidationName')
            }
        }

        $backends.Add([pscustomobject] [ordered]@{
                backendId = $backendId
                scheme = $uri.Scheme
                tlsValidationChain = $tlsChain
                tlsValidationName = $tlsName
                credentialConfigured = [bool] $credentialConfigured
                circuitBreakerConfigured = [bool] $circuitBreakerConfigured
                poolConfigured = [bool] $poolConfigured
                modelStatus = if ($missingInputs.Count -eq 0) {
                    'Complete'
                }
                else {
                    'Partial'
                }
                missingInputs = @($missingInputs | Sort-Object)
            })
    }

    $certificates = [System.Collections.Generic.List[object]]::new()
    foreach ($resource in Get-ApimModelCollection `
            -Payload $CertificatesPayload -Context 'APIM certificate payload') {
        $certificateId = [string] (Get-ApimModelValue `
                -InputObject $resource -Name name -Context 'APIM certificate')
        $properties = Get-ApimModelValue -InputObject $resource `
            -Name properties -Context 'APIM certificate'
        $expirationDate = ConvertTo-ApimSecurityModelDate -Value (
            Get-ApimModelValue -InputObject $properties -Name expirationDate `
                -Context 'APIM certificate properties' -AllowMissing
        ) -Context 'APIM certificate expiration date'
        $keyVault = Get-ApimSecurityModelKeyVaultFact -KeyVault (
            Get-ApimModelValue -InputObject $properties -Name keyVault `
                -Context 'APIM certificate properties' -AllowMissing
        ) -Context 'APIM certificate Key Vault metadata'
        $missingInputs = [System.Collections.Generic.List[string]]::new()
        foreach ($inputName in @($keyVault.missingInputs)) {
            $missingInputs.Add($inputName)
        }
        if ($null -eq $expirationDate) {
            $missingInputs.Add('expirationDate')
        }

        $certificates.Add([pscustomobject] [ordered]@{
                certificateId = $certificateId
                expirationDate = $expirationDate
                keyVaultBacked = $keyVault.backed
                modelStatus = if ($missingInputs.Count -eq 0) {
                    'Complete'
                }
                else {
                    'Partial'
                }
                missingInputs = @($missingInputs | Sort-Object)
            })
    }

    return [pscustomobject] [ordered]@{
        namedValues = @($namedValues | Sort-Object namedValueId)
        backends = @($backends | Sort-Object backendId)
        certificates = @($certificates | Sort-Object certificateId)
    }
}

function Write-ApimSecurityAssetModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Model
    )

    return Write-ApimModelSet -RunPath $RunPath -Models ([ordered]@{
            namedValues = @(Get-ApimModelValue -InputObject $Model `
                    -Name namedValues -Context 'Security asset model')
            backends = @(Get-ApimModelValue -InputObject $Model `
                    -Name backends -Context 'Security asset model')
            certificates = @(Get-ApimModelValue -InputObject $Model `
                    -Name certificates -Context 'Security asset model')
        })
}
