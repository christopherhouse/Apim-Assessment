#Requires -Version 7.4

Set-StrictMode -Version Latest

function Test-ApimArmRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Method,

        [Parameter(Mandatory)]
        [string] $Uri
    )

    $normalizedMethod = $Method.ToUpperInvariant()
    $decodedUri = $Uri
    for ($decodeAttempt = 0; $decodeAttempt -lt 3; $decodeAttempt++) {
        $nextDecodedUri = [System.Uri]::UnescapeDataString($decodedUri)
        if ($nextDecodedUri -eq $decodedUri) {
            break
        }
        $decodedUri = $nextDecodedUri
    }

    $absoluteUri = $null
    $requestPath = $null
    if ($decodedUri -match '^[A-Za-z][A-Za-z0-9+.-]*://') {
        if (-not [System.Uri]::TryCreate(
                $decodedUri,
                [System.UriKind]::Absolute,
                [ref] $absoluteUri
            )) {
            throw 'ARM URL is not a valid absolute URI.'
        }
        $allowedHosts = @(
            'management.azure.com',
            'management.usgovcloudapi.net',
            'management.chinacloudapi.cn',
            'management.microsoftazure.de'
        )
        if ($absoluteUri.Scheme -ne 'https' -or
            $absoluteUri.Host -notin $allowedHosts -or
            -not $absoluteUri.IsDefaultPort -or
            -not [string]::IsNullOrEmpty($absoluteUri.UserInfo)) {
            throw 'ARM URL must use an approved Azure Resource Manager endpoint.'
        }
        $requestPath = $absoluteUri.AbsolutePath
    }
    else {
        if (-not $decodedUri.StartsWith('/',
                [System.StringComparison]::Ordinal) -or
            $decodedUri.StartsWith('//',
                [System.StringComparison]::Ordinal) -or
            $decodedUri.StartsWith('/\',
                [System.StringComparison]::Ordinal)) {
            throw 'ARM URL must be an absolute Azure Resource Manager URL or a relative ARM path.'
        }
        $requestPath = ($decodedUri -split '[?#]', 2)[0]
    }

    $denyPatterns = @(
        'listSecrets',
        'listValue',
        'listKeys',
        '/secrets',
        'regenerate',
        'token'
    )
    foreach ($pattern in $denyPatterns) {
        if ($decodedUri.Contains($pattern, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "ARM URL is prohibited by the read-only safety policy."
        }
    }

    if ($normalizedMethod -eq 'GET') {
        return
    }

    $isCostQuery = $normalizedMethod -eq 'POST' -and
        $requestPath -match '(?i)/providers/Microsoft\.CostManagement/query/?$'
    if (-not $isCostQuery) {
        throw "ARM method '$normalizedMethod' is prohibited by the read-only safety policy."
    }
}

function Invoke-ApimArmRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Method,

        [Parameter(Mandatory)]
        [string] $Uri,

        [AllowNull()]
        [string] $Body
    )

    $parameters = @{
        Method      = $Method
        ErrorAction = 'Stop'
    }
    if ([System.Uri]::IsWellFormedUriString($Uri, [System.UriKind]::Absolute)) {
        $parameters.Uri = $Uri
    }
    else {
        $parameters.Path = $Uri
    }
    if ($null -ne $Body) {
        $parameters.Payload = $Body
    }

    return Invoke-AzRestMethod @parameters
}

function Get-ApimArmStatusCode {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    foreach ($propertyName in @('StatusCode', 'Status')) {
        $property = $InputObject.PSObject.Properties[$propertyName]
        if ($null -ne $property -and $null -ne $property.Value) {
            try {
                return [int] $property.Value
            }
            catch {
                continue
            }
        }
    }

    return $null
}

function Get-ApimArmHeaderMap {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $InputObject
    )

    $result = @{}
    if ($null -eq $InputObject) {
        return $result
    }

    $headersProperty = $InputObject.PSObject.Properties['Headers']
    if ($null -eq $headersProperty -or $null -eq $headersProperty.Value) {
        return $result
    }
    $headers = $headersProperty.Value

    if ($headers -is [System.Collections.IDictionary]) {
        foreach ($key in $headers.Keys) {
            $result[[string] $key] = $headers[$key]
        }
        return $result
    }

    if ($headers -is [System.Collections.IEnumerable]) {
        foreach ($entry in $headers) {
            $keyProperty = $entry.PSObject.Properties['Key']
            $valueProperty = $entry.PSObject.Properties['Value']
            if ($null -ne $keyProperty -and $null -ne $valueProperty) {
                $result[[string] $keyProperty.Value] = $valueProperty.Value
            }
        }
        if ($result.Count -gt 0) {
            return $result
        }
    }

    foreach ($property in $headers.PSObject.Properties) {
        $result[$property.Name] = $property.Value
    }
    return $result
}

function Get-ApimArmRetryDelay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Headers,

        [Parameter(Mandatory)]
        [ValidateRange(0, 3600)]
        [double] $FallbackSeconds
    )

    $candidate = $null
    foreach ($key in $Headers.Keys) {
        $headerName = [string] $key
        if ($headerName.Equals('Retry-After',
                [System.StringComparison]::OrdinalIgnoreCase)) {
            $candidate = @($Headers[$key])[0]
            break
        }
    }
    if ($null -eq $candidate) {
        foreach ($key in $Headers.Keys) {
            $headerName = [string] $key
            if ($headerName -match
                '(?i)^x-ms-ratelimit-microsoft\.costmanagement-.*-retry-after$') {
                $candidate = @($Headers[$key])[0]
                break
            }
        }
    }
    if ($null -eq $candidate) {
        return $FallbackSeconds
    }

    $seconds = 0.0
    if ([double]::TryParse([string] $candidate, [ref] $seconds) -and $seconds -ge 0) {
        return $seconds
    }

    $retryAt = [datetimeoffset]::MinValue
    if ([datetimeoffset]::TryParse([string] $candidate, [ref] $retryAt)) {
        return [math]::Max(0, ($retryAt - [datetimeoffset]::UtcNow).TotalSeconds)
    }

    return $FallbackSeconds
}

function ConvertFrom-ApimArmResponse {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Response
    )

    if ($null -eq $Response) {
        return $null
    }

    $contentProperty = $Response.PSObject.Properties['Content']
    if ($null -eq $contentProperty) {
        return $Response
    }
    $content = $contentProperty.Value
    if ($null -eq $content -or [string]::IsNullOrWhiteSpace([string] $content)) {
        return $null
    }
    if ($content -isnot [string]) {
        return $content
    }

    try {
        return $content | ConvertFrom-Json -Depth 100 -ErrorAction Stop
    }
    catch {
        throw 'ARM response content was not valid JSON.'
    }
}

function Get-ApimArmFailure {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [Nullable[int]] $StatusCode,

        [Parameter(Mandatory)]
        [int] $Attempts
    )

    $message = if ($null -eq $StatusCode) {
        "ARM request failed before a usable response was received after $Attempts attempt(s)."
    }
    else {
        "ARM request failed with HTTP status $StatusCode after $Attempts attempt(s)."
    }
    $exception = [System.InvalidOperationException]::new($message)
    if ($null -ne $StatusCode) {
        $exception.Data['StatusCode'] = [int] $StatusCode
    }
    return $exception
}

function Invoke-ApimArm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Uri,

        [string] $Method = 'GET',

        [AllowNull()]
        [object] $Body,

        [ValidateRange(1, 6)]
        [int] $MaxAttempts = 6,

        [ValidateRange(0, 60)]
        [double] $InitialDelaySeconds = 2,

        [string] $LogPath
    )

    $normalizedMethod = $Method.ToUpperInvariant()
    $serializedBody = if ($null -eq $Body -or $Body -is [string]) {
        $Body
    }
    else {
        $Body | ConvertTo-Json -Depth 50 -Compress
    }

    $currentUri = $Uri
    $firstPayload = $null
    $pagedItems = [System.Collections.Generic.List[object]]::new()
    $isPagedResult = $false

    while (-not [string]::IsNullOrWhiteSpace($currentUri)) {
        Test-ApimArmRequest -Method $normalizedMethod -Uri $currentUri

        $response = $null
        $attempt = 0
        while ($attempt -lt $MaxAttempts) {
            $attempt++
            try {
                $response = Invoke-ApimArmRequest -Method $normalizedMethod `
                    -Uri $currentUri -Body $serializedBody
            }
            catch {
                $responseProperty = $_.Exception.PSObject.Properties['Response']
                $errorResponse = if ($null -ne $responseProperty) {
                    $responseProperty.Value
                }
                else {
                    $null
                }
                $statusCode = Get-ApimArmStatusCode -InputObject $errorResponse
                $retryable = $statusCode -eq 429 -or
                    ($null -ne $statusCode -and $statusCode -ge 500 -and
                    $statusCode -le 599)
                if (-not $retryable -or $attempt -ge $MaxAttempts) {
                    throw (Get-ApimArmFailure -StatusCode $statusCode -Attempts $attempt)
                }

                $headers = Get-ApimArmHeaderMap -InputObject $errorResponse
                $fallback = $InitialDelaySeconds * [math]::Pow(2, $attempt - 1)
                $delay = Get-ApimArmRetryDelay -Headers $headers `
                    -FallbackSeconds $fallback
                if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
                    Write-RunLog -Path $LogPath -Level Warning -Collector 'ARM' `
                        -Message "Retrying after HTTP $statusCode (attempt $attempt)." `
                        -Url $currentUri
                }
                Start-Sleep -Seconds $delay
                continue
            }

            $statusCode = Get-ApimArmStatusCode -InputObject $response
            if ($null -eq $statusCode) {
                $statusCode = 200
            }
            if ($statusCode -ge 200 -and $statusCode -le 299) {
                break
            }

            $retryable = $statusCode -eq 429 -or
                ($statusCode -ge 500 -and $statusCode -le 599)
            if (-not $retryable -or $attempt -ge $MaxAttempts) {
                throw (Get-ApimArmFailure -StatusCode $statusCode -Attempts $attempt)
            }

            $headers = Get-ApimArmHeaderMap -InputObject $response
            $fallback = $InitialDelaySeconds * [math]::Pow(2, $attempt - 1)
            $delay = Get-ApimArmRetryDelay -Headers $headers `
                -FallbackSeconds $fallback
            if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
                Write-RunLog -Path $LogPath -Level Warning -Collector 'ARM' `
                    -Message "Retrying after HTTP $statusCode (attempt $attempt)." `
                    -Url $currentUri
            }
            Start-Sleep -Seconds $delay
        }

        $payload = ConvertFrom-ApimArmResponse -Response $response
        if ($null -eq $firstPayload) {
            $firstPayload = $payload
        }

        $valueProperty = if ($null -ne $payload) {
            $payload.PSObject.Properties['value']
        }
        else {
            $null
        }
        $nextLinkProperty = if ($null -ne $payload) {
            $payload.PSObject.Properties['nextLink']
        }
        else {
            $null
        }

        if ($null -ne $valueProperty) {
            $isPagedResult = $true
            foreach ($item in @($valueProperty.Value)) {
                $pagedItems.Add($item)
            }
        }
        elseif ($null -ne $nextLinkProperty -and
            -not [string]::IsNullOrWhiteSpace([string] $nextLinkProperty.Value)) {
            throw 'ARM response included nextLink without a value collection.'
        }

        $currentUri = if ($null -ne $nextLinkProperty) {
            [string] $nextLinkProperty.Value
        }
        else {
            $null
        }
    }

    if (-not $isPagedResult) {
        return $firstPayload
    }

    $result = [ordered]@{}
    foreach ($property in $firstPayload.PSObject.Properties) {
        if ($property.Name -notin @('value', 'nextLink')) {
            $result[$property.Name] = $property.Value
        }
    }
    $result.value = $pagedItems.ToArray()
    return [pscustomobject] $result
}
