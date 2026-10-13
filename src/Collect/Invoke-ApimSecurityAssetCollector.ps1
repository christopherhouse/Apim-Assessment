#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimSecurityAssetProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context,

        [switch] $AllowMissing
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            Write-Output -InputObject $InputObject[$Name] -NoEnumerate
            return
        }
    }
    else {
        $property = $InputObject.PSObject.Properties[$Name]
        if ($null -ne $property) {
            Write-Output -InputObject $property.Value -NoEnumerate
            return
        }
    }
    if ($AllowMissing) {
        return $null
    }
    throw "$Context did not contain '$Name'."
}

function Get-ApimSecurityAssetFieldName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $InputObject
    )

    $names = if ($InputObject -is [System.Collections.IDictionary]) {
        @($InputObject.Keys)
    }
    else {
        @($InputObject.PSObject.Properties.Name)
    }
    foreach ($name in $names) {
        if ($name -isnot [string] -or
            [string]::IsNullOrWhiteSpace([string] $name)) {
            throw 'Security asset metadata contained an invalid field name.'
        }
    }
    return @($names | Sort-Object -Unique)
}

function ConvertTo-ApimSecurityAssetStringArray {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context
    )

    if ($null -eq $Value) {
        return @()
    }
    if ($Value -is [string] -or
        $Value -isnot [System.Collections.IEnumerable]) {
        throw "$Context was not an array."
    }
    $values = @(
        foreach ($item in @($Value)) {
            if ($item -isnot [string] -or
                [string]::IsNullOrWhiteSpace([string] $item)) {
                throw "$Context contained an invalid string."
            }
            [string] $item
        }
    )
    return @($values | Sort-Object -Unique)
}

function ConvertTo-ApimSecurityAssetDate {
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
    $parsed = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse(
            [string] $Value,
            [System.Globalization.CultureInfo]::InvariantCulture,
            (
                [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
                [System.Globalization.DateTimeStyles]::AdjustToUniversal
            ),
            [ref] $parsed
        )) {
        throw "$Context was not a valid date-time."
    }
    return $parsed.ToUniversalTime().ToString('O')
}

function ConvertTo-ApimCollectedBackendUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Value
    )

    $uri = $null
    if (-not [System.Uri]::TryCreate(
            $Value,
            [System.UriKind]::Absolute,
            [ref] $uri
        ) -or $uri.Scheme -notin @('http', 'https')) {
        throw 'APIM backend URL was not an absolute HTTP(S) URL.'
    }
    $sanitized = -not [string]::IsNullOrWhiteSpace($uri.UserInfo) -or
        -not [string]::IsNullOrWhiteSpace($uri.Query) -or
        -not [string]::IsNullOrWhiteSpace($uri.Fragment)
    if (-not $sanitized) {
        return [pscustomobject]@{
            value = $Value
            sanitized = $false
        }
    }

    $builder = [System.UriBuilder]::new($uri)
    $builder.UserName = ''
    $builder.Password = ''
    $builder.Query = ''
    $builder.Fragment = ''
    $safeUrl = $builder.Uri.GetLeftPart([System.UriPartial]::Path)
    if ($uri.AbsolutePath -eq '/' -and -not $Value.EndsWith('/')) {
        $safeUrl = $safeUrl.TrimEnd('/')
    }
    return [pscustomobject]@{
        value = $safeUrl
        sanitized = $true
    }
}

function ConvertTo-ApimCollectedNamedValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Resource
    )

    $name = [string] (Get-ApimSecurityAssetProperty -InputObject $Resource `
            -Name name -Context 'APIM named value')
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw 'APIM named value contained an invalid resource name.'
    }
    $properties = Get-ApimSecurityAssetProperty -InputObject $Resource `
        -Name properties -Context 'APIM named value'
    $displayName = Get-ApimSecurityAssetProperty -InputObject $properties `
        -Name displayName -Context 'APIM named value properties'
    if ($displayName -isnot [string] -or
        [string]::IsNullOrWhiteSpace([string] $displayName)) {
        throw "APIM named value field 'displayName' was invalid."
    }
    $secret = Get-ApimSecurityAssetProperty -InputObject $properties `
        -Name secret -Context 'APIM named value properties'
    if ($secret -isnot [bool]) {
        throw "APIM named value field 'secret' was not Boolean."
    }
    $tags = @(
        ConvertTo-ApimSecurityAssetStringArray -Value (
            Get-ApimSecurityAssetProperty -InputObject $properties -Name tags `
                -Context 'APIM named value properties' -AllowMissing
        ) -Context 'APIM named value tags'
    )

    $keyVaultValue = Get-ApimSecurityAssetProperty -InputObject $properties `
        -Name keyVault -Context 'APIM named value properties' -AllowMissing
    $keyVault = $null
    if ($null -ne $keyVaultValue) {
        $secretIdentifier = Get-ApimSecurityAssetProperty `
            -InputObject $keyVaultValue -Name secretIdentifier `
            -Context 'APIM named value Key Vault metadata' -AllowMissing
        if ($null -ne $secretIdentifier -and
            ($secretIdentifier -isnot [string] -or
                [string]::IsNullOrWhiteSpace([string] $secretIdentifier))) {
            throw 'APIM named value Key Vault secret identifier was invalid.'
        }
        $lastStatusValue = Get-ApimSecurityAssetProperty `
            -InputObject $keyVaultValue -Name lastStatus `
            -Context 'APIM named value Key Vault metadata' -AllowMissing
        $lastStatus = $null
        if ($null -ne $lastStatusValue) {
            $code = Get-ApimSecurityAssetProperty `
                -InputObject $lastStatusValue -Name code `
                -Context 'APIM named value Key Vault status' -AllowMissing
            if ($null -ne $code -and
                ($code -isnot [string] -or
                    [string]::IsNullOrWhiteSpace([string] $code))) {
                throw 'APIM named value Key Vault status code was invalid.'
            }
            $lastStatus = [pscustomobject] [ordered]@{
                code = $code
            }
        }
        $keyVault = [pscustomobject] [ordered]@{
            secretIdentifier = $secretIdentifier
            lastStatus = $lastStatus
        }
    }

    $locations = [System.Collections.Generic.List[string]]::new()
    if (Test-ApimPolicySecretCandidate -Value ([string] $displayName)) {
        $locations.Add('displayName')
    }
    $value = Get-ApimSecurityAssetProperty -InputObject $properties `
        -Name value -Context 'APIM named value properties' -AllowMissing
    if ($null -ne $value) {
        if ($value -isnot [string]) {
            throw "APIM named value field 'value' was not a string."
        }
        if (Test-ApimPolicySecretCandidate -Value ([string] $value) `
                -ContextName ([string] $displayName)) {
            $locations.Add('value')
        }
    }

    return [pscustomobject] [ordered]@{
        name = $name
        properties = [pscustomobject] [ordered]@{
            displayName = [string] $displayName
            secret = [bool] $secret
            keyVault = $keyVault
            tags = $tags
            secretPatternLocations = @($locations | Sort-Object -Unique)
        }
    }
}

function ConvertTo-ApimBackendCredentialSummary {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value) {
        return [pscustomobject] [ordered]@{
            configured = $false
            types = @()
            authorizationScheme = $null
            certificateCount = 0
            headerNames = @()
            queryParameterNames = @()
            unknownFieldsPresent = $false
        }
    }

    $fields = @(Get-ApimSecurityAssetFieldName `
            -InputObject $Value)
    $allowedFields = @('authorization', 'certificate', 'header', 'query')
    $unknownFieldsPresent = @($fields | Where-Object {
            $_ -cnotin $allowedFields
        }).Count -gt 0

    $authorization = Get-ApimSecurityAssetProperty `
        -InputObject $Value -Name authorization `
        -Context 'APIM backend credentials' -AllowMissing
    $authorizationScheme = $null
    if ($null -ne $authorization) {
        $scheme = Get-ApimSecurityAssetProperty -InputObject $authorization `
            -Name scheme -Context 'APIM backend authorization' -AllowMissing
        if ($null -ne $scheme -and
            ($scheme -isnot [string] -or
                [string]::IsNullOrWhiteSpace([string] $scheme))) {
            throw 'APIM backend authorization scheme was invalid.'
        }
        $authorizationScheme = $scheme
    }

    $certificates = Get-ApimSecurityAssetProperty `
        -InputObject $Value -Name certificate `
        -Context 'APIM backend credentials' -AllowMissing
    $certificateCount = if ($null -eq $certificates) {
        0
    }
    else {
        if ($certificates -is [string] -or
            $certificates -isnot [System.Collections.IEnumerable]) {
            throw 'APIM backend certificate credentials were not an array.'
        }
        @($certificates).Count
    }

    $headerValue = Get-ApimSecurityAssetProperty `
        -InputObject $Value -Name header `
        -Context 'APIM backend credentials' -AllowMissing
    $headerNames = @(
        if ($null -ne $headerValue) {
            Get-ApimSecurityAssetFieldName -InputObject $headerValue
        }
    )
    $queryValue = Get-ApimSecurityAssetProperty `
        -InputObject $Value -Name query `
        -Context 'APIM backend credentials' -AllowMissing
    $queryNames = @(
        if ($null -ne $queryValue) {
            Get-ApimSecurityAssetFieldName -InputObject $queryValue
        }
    )

    $types = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $authorization) {
        $types.Add('Authorization')
    }
    if ($certificateCount -gt 0) {
        $types.Add('Certificate')
    }
    if ($headerNames.Count -gt 0) {
        $types.Add('Header')
    }
    if ($queryNames.Count -gt 0) {
        $types.Add('Query')
    }
    if ($unknownFieldsPresent) {
        $types.Add('Other')
    }

    return [pscustomobject] [ordered]@{
        configured = $types.Count -gt 0
        types = @($types | Sort-Object -Unique)
        authorizationScheme = $authorizationScheme
        certificateCount = $certificateCount
        headerNames = $headerNames
        queryParameterNames = $queryNames
        unknownFieldsPresent = $unknownFieldsPresent
    }
}

function ConvertTo-ApimCollectedBackend {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Resource
    )

    $name = [string] (Get-ApimSecurityAssetProperty -InputObject $Resource `
            -Name name -Context 'APIM backend')
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw 'APIM backend contained an invalid resource name.'
    }
    $properties = Get-ApimSecurityAssetProperty -InputObject $Resource `
        -Name properties -Context 'APIM backend'
    $url = Get-ApimSecurityAssetProperty -InputObject $properties `
        -Name url -Context 'APIM backend properties'
    $protocol = Get-ApimSecurityAssetProperty -InputObject $properties `
        -Name protocol -Context 'APIM backend properties'
    if ($url -isnot [string] -or
        [string]::IsNullOrWhiteSpace([string] $url) -or
        $protocol -isnot [string] -or
        [string]::IsNullOrWhiteSpace([string] $protocol)) {
        throw 'APIM backend contained an invalid URL or protocol.'
    }
    $safeUrl = ConvertTo-ApimCollectedBackendUrl -Value ([string] $url)

    $tlsValue = Get-ApimSecurityAssetProperty -InputObject $properties `
        -Name tls -Context 'APIM backend properties' -AllowMissing
    $validateCertificateChain = $null
    $validateCertificateName = $null
    if ($null -ne $tlsValue) {
        $validateCertificateChain = Get-ApimSecurityAssetProperty `
            -InputObject $tlsValue -Name validateCertificateChain `
            -Context 'APIM backend TLS metadata' -AllowMissing
        $validateCertificateName = Get-ApimSecurityAssetProperty `
            -InputObject $tlsValue -Name validateCertificateName `
            -Context 'APIM backend TLS metadata' -AllowMissing
        foreach ($tlsSetting in @(
                $validateCertificateChain,
                $validateCertificateName
            )) {
            if ($null -ne $tlsSetting -and $tlsSetting -isnot [bool]) {
                throw 'APIM backend TLS validation setting was not Boolean.'
            }
        }
    }

    $credentials = ConvertTo-ApimBackendCredentialSummary -Value (
            Get-ApimSecurityAssetProperty -InputObject $properties `
                -Name credentials -Context 'APIM backend properties' `
                -AllowMissing
        )
    $circuitBreaker = Get-ApimSecurityAssetProperty `
        -InputObject $properties -Name circuitBreaker `
        -Context 'APIM backend properties' -AllowMissing
    $pool = Get-ApimSecurityAssetProperty -InputObject $properties `
        -Name pool -Context 'APIM backend properties' -AllowMissing
    $poolBackendCount = 0
    if ($null -ne $pool) {
        $services = Get-ApimSecurityAssetProperty -InputObject $pool `
            -Name services -Context 'APIM backend pool' -AllowMissing
        if ($null -ne $services) {
            if ($services -is [string] -or
                $services -isnot [System.Collections.IEnumerable]) {
                throw 'APIM backend pool services were not an array.'
            }
            $poolBackendCount = @($services).Count
        }
    }
    $type = Get-ApimSecurityAssetProperty -InputObject $properties `
        -Name type -Context 'APIM backend properties' -AllowMissing
    if ($null -ne $type -and
        ($type -isnot [string] -or
            [string]::IsNullOrWhiteSpace([string] $type))) {
        throw 'APIM backend type was invalid.'
    }

    return [pscustomobject] [ordered]@{
        name = $name
        properties = [pscustomobject] [ordered]@{
            url = $safeUrl.value
            urlSanitized = $safeUrl.sanitized
            protocol = [string] $protocol
            tls = [pscustomobject] [ordered]@{
                validateCertificateChain = $validateCertificateChain
                validateCertificateName = $validateCertificateName
            }
            credentials = $credentials
            circuitBreakerConfigured = $null -ne $circuitBreaker
            poolConfigured = $null -ne $pool
            poolBackendCount = $poolBackendCount
            type = $type
        }
    }
}

function ConvertTo-ApimCollectedCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Resource
    )

    $name = [string] (Get-ApimSecurityAssetProperty -InputObject $Resource `
            -Name name -Context 'APIM certificate')
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw 'APIM certificate contained an invalid resource name.'
    }
    $properties = Get-ApimSecurityAssetProperty -InputObject $Resource `
        -Name properties -Context 'APIM certificate'
    $expirationDate = ConvertTo-ApimSecurityAssetDate -Value (
        Get-ApimSecurityAssetProperty -InputObject $properties `
            -Name expirationDate -Context 'APIM certificate properties' `
            -AllowMissing
    ) -Context 'APIM certificate expiration date'
    $keyVaultValue = Get-ApimSecurityAssetProperty -InputObject $properties `
        -Name keyVault -Context 'APIM certificate properties' -AllowMissing
    $keyVault = $null
    if ($null -ne $keyVaultValue) {
        $secretIdentifier = Get-ApimSecurityAssetProperty `
            -InputObject $keyVaultValue -Name secretIdentifier `
            -Context 'APIM certificate Key Vault metadata' -AllowMissing
        if ($null -ne $secretIdentifier -and
            ($secretIdentifier -isnot [string] -or
                [string]::IsNullOrWhiteSpace([string] $secretIdentifier))) {
            throw 'APIM certificate Key Vault secret identifier was invalid.'
        }
        $keyVault = [pscustomobject] [ordered]@{
            secretIdentifier = $secretIdentifier
        }
    }

    return [pscustomobject] [ordered]@{
        name = $name
        properties = [pscustomobject] [ordered]@{
            expirationDate = $expirationDate
            keyVault = $keyVault
        }
    }
}

function ConvertTo-ApimSecurityAssetCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Payload,

        [Parameter(Mandatory)]
        [ValidateSet('NamedValue', 'Backend', 'Certificate')]
        [string] $Type
    )

    $names = @(Get-ApimCollectionResourceName -Payload $Payload `
            -CollectionName "APIM $Type")
    $resources = @($Payload.value)
    $resourceMap = [System.Collections.Generic.Dictionary[
        string,
        object
    ]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($resource in $resources) {
        $resourceMap.Add([string] $resource.name, $resource)
    }

    return @(
        foreach ($name in $names) {
            switch ($Type) {
                NamedValue {
                    ConvertTo-ApimCollectedNamedValue `
                        -Resource $resourceMap[$name]
                }
                Backend {
                    ConvertTo-ApimCollectedBackend `
                        -Resource $resourceMap[$name]
                }
                Certificate {
                    ConvertTo-ApimCollectedCertificate `
                        -Resource $resourceMap[$name]
                }
            }
        }
    )
}

function Invoke-ApimSecurityAssetCollector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Environment
    )

    $collectorName = 'SecurityAssets'
    $logPath = Join-Path $RunPath 'logs/run.log'
    $resourcePath = Get-ApimServiceResourcePath -Environment $Environment
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $filesWritten = 0

    Set-RunStageStatus -RunPath $RunPath -Stage collect -Status InProgress
    Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
        -Status InProgress
    try {
        $definitions = @(
            [pscustomobject]@{
                Type = 'NamedValue'
                Endpoint = 'namedValues'
                RelativePath = 'raw/namedValues.json'
            }
            [pscustomobject]@{
                Type = 'Backend'
                Endpoint = 'backends'
                RelativePath = 'raw/backends.json'
            }
            [pscustomobject]@{
                Type = 'Certificate'
                Endpoint = 'certificates'
                RelativePath = 'raw/certificates.json'
            }
        )
        $staged = [System.Collections.Generic.List[object]]::new()
        foreach ($definition in $definitions) {
            $response = Invoke-ApimArm -Uri (
                "$resourcePath/$($definition.Endpoint)?api-version=2024-05-01"
            ) -LogPath $logPath
            if ($null -eq $response) {
                throw "APIM $($definition.Type) response was empty."
            }
            $records = @(ConvertTo-ApimSecurityAssetCollection `
                    -Payload $response -Type $definition.Type)
            $staged.Add([pscustomobject]@{
                    RelativePath = $definition.RelativePath
                    Payload = [pscustomobject] [ordered]@{
                        value = $records
                    }
                    Count = $records.Count
                })
        }

        $paths = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $staged) {
            $paths.Add((Write-RunFile -RunPath $RunPath `
                        -RelativePath $item.RelativePath `
                        -InputObject $item.Payload -Depth 50))
            $filesWritten++
        }

        $itemCount = ($staged | Measure-Object -Property Count -Sum).Sum
        $stopwatch.Stop()
        Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
            -Status Completed -Items $itemCount `
            -DurationSec $stopwatch.Elapsed.TotalSeconds
        Write-RunLog -Path $logPath -Level Info -Collector $collectorName `
            -Message 'Collected allowlisted APIM security asset metadata.'
        return $paths.ToArray()
    }
    catch {
        $stopwatch.Stop()
        $status = if ($filesWritten -gt 0) { 'Partial' } else { 'Failed' }
        Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
            -Status $status -Errors 1 `
            -DurationSec $stopwatch.Elapsed.TotalSeconds
        Add-RunWarning -RunPath $RunPath `
            -Message 'Security asset collector failed; see the restricted run log.'
        Write-RunLog -Path $logPath -Level Error -Collector $collectorName `
            -Message 'APIM security asset collection failed.'
        throw
    }
}
