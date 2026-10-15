#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimAuthProperty {
    [CmdletBinding()]
    param(
        [AllowNull()][object] $InputObject,
        [Parameter(Mandatory)][string] $Name
    )

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        return ,$InputObject[$Name]
    }
    if ($InputObject -isnot [pscustomobject]) {
        throw 'Authentication configuration contains an invalid object.'
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return ,$property.Value
}

function Assert-ApimAuthObject {
    [CmdletBinding()]
    param([AllowNull()][object] $Value)

    if ($Value -isnot [pscustomobject] -and
        $Value -isnot [System.Collections.IDictionary]) {
        throw 'Authentication configuration contains an invalid object.'
    }
}

function ConvertTo-ApimAuthBoolean {
    [CmdletBinding()]
    param([AllowNull()][object] $Value)

    if ($null -ne $Value -and $Value -isnot [bool]) {
        throw 'Authentication configuration contains an invalid Boolean.'
    }
    return $Value
}

function ConvertTo-ApimAuthEnum {
    [CmdletBinding()]
    param(
        [AllowNull()][object] $Value,
        [Parameter(Mandatory)][string[]] $Allowed,
        [switch] $Array
    )

    if ($null -eq $Value) { return $null }
    if ($Array) {
        if ($Value -isnot [array]) {
            throw 'Authentication configuration contains an invalid enum array.'
        }
        $values = @(
            foreach ($entry in $Value) {
                ConvertTo-ApimAuthEnum -Value $entry -Allowed $Allowed
                if ($null -eq $entry) {
                    throw 'Authentication configuration contains an invalid enum.'
                }
            }
        )
        return ,@($values | Sort-Object -Unique -CaseSensitive)
    }
    if ($Value -isnot [string] -or $Value -cnotin $Allowed) {
        throw 'Authentication configuration contains an unsupported enum.'
    }
    return $Value
}

function ConvertTo-ApimAuthName {
    [CmdletBinding()]
    param([AllowNull()][object] $Value, [switch] $Optional)

    if ($null -eq $Value -and $Optional) { return $null }
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) {
        throw 'Authentication configuration contains an invalid resource name.'
    }
    return $Value
}

# REST 2024-05-01 contracts verified against Microsoft Learn:
# identity-provider, authorization-server, openid-connect-provider and
# authorization-provider /list-by-service. Only documented structural facts
# survive. No client/tenant identifiers, endpoint URLs or parameter values.
function ConvertTo-ApimIdentityResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Resource,
        [Parameter(Mandatory)]
        [ValidateSet('identityProviders', 'authorizationServers',
            'openidConnectProviders', 'authorizationProviders')]
        [string] $Kind,
        [switch] $Saved
    )

    Assert-ApimAuthObject -Value $Resource
    $name = ConvertTo-ApimAuthName -Value (
        Get-ApimAuthProperty -InputObject $Resource -Name name
    )
    $properties = Get-ApimAuthProperty -InputObject $Resource -Name properties
    Assert-ApimAuthObject -Value $properties
    $safe = [ordered]@{}
    switch ($Kind) {
        identityProviders {
            $safe.type = ConvertTo-ApimAuthEnum -Value (
                Get-ApimAuthProperty -InputObject $properties -Name type
            ) -Allowed @('aad', 'aadB2C', 'facebook', 'google', 'microsoft', 'twitter')
        }
        authorizationServers {
            $enums = [ordered]@{
                authorizationMethods = @('HEAD', 'OPTIONS', 'TRACE', 'GET', 'POST', 'PUT', 'PATCH', 'DELETE')
                clientAuthenticationMethod = @('Basic', 'Body')
                grantTypes = @('authorizationCode', 'implicit', 'resourceOwnerPassword', 'clientCredentials')
                bearerTokenSendingMethods = @('authorizationHeader', 'query')
            }
            foreach ($field in $enums.Keys) {
                $safe[$field] = ConvertTo-ApimAuthEnum -Value (
                    Get-ApimAuthProperty -InputObject $properties -Name $field
                ) -Allowed $enums[$field] -Array
            }
            foreach ($field in @('supportState', 'useInApiDocumentation', 'useInTestConsole')) {
                $safe[$field] = ConvertTo-ApimAuthBoolean -Value (
                    Get-ApimAuthProperty -InputObject $properties -Name $field
                )
            }
        }
        openidConnectProviders {
            foreach ($field in @('useInApiDocumentation', 'useInTestConsole')) {
                $safe[$field] = ConvertTo-ApimAuthBoolean -Value (
                    Get-ApimAuthProperty -InputObject $properties -Name $field
                )
            }
        }
        authorizationProviders {
            if ($Saved) {
                foreach ($field in @('authorizationCodeConfigured', 'clientCredentialsConfigured')) {
                    $safe[$field] = ConvertTo-ApimAuthBoolean -Value (
                        Get-ApimAuthProperty -InputObject $properties -Name $field
                    )
                }
                break
            }
            $oauth2 = Get-ApimAuthProperty -InputObject $properties -Name oauth2
            if ($null -ne $oauth2) { Assert-ApimAuthObject -Value $oauth2 }
            $grants = Get-ApimAuthProperty -InputObject $oauth2 -Name grantTypes
            if ($null -ne $grants) { Assert-ApimAuthObject -Value $grants }
            # Presence only; grant dictionaries can contain credentials and
            # arbitrary parameters. Missing/null is unknown; {} is configured.
            foreach ($grant in @('authorizationCode', 'clientCredentials')) {
                $value = Get-ApimAuthProperty -InputObject $grants -Name $grant
                $configured = $null
                if ($null -ne $value) {
                    Assert-ApimAuthObject -Value $value
                    $configured = $true
                }
                $safe["${grant}Configured"] = $configured
            }
        }
    }
    return [pscustomobject][ordered]@{ name = $name; properties = [pscustomobject]$safe }
}

function ConvertTo-ApimAuthCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Payload,
        [Parameter(Mandatory)][string] $Kind,
        [switch] $Saved
    )

    Assert-ApimAuthObject -Value $Payload
    $value = Get-ApimAuthProperty -InputObject $Payload -Name value
    if ($value -isnot [array]) {
        throw 'Authentication configuration contains an invalid collection.'
    }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $records = @(
        foreach ($resource in $value) {
            Assert-ApimAuthObject -Value $resource
            $record = if ($Kind -eq 'revisions') {
                ConvertTo-ApimPortalResource -Resource $resource -Kind revisions
            }
            else {
                ConvertTo-ApimIdentityResource -Resource $resource -Kind $Kind -Saved:$Saved
            }
            if (-not $seen.Add($record.name)) {
                throw 'Authentication configuration contains duplicate resource names.'
            }
            $record
        }
    )
    return [pscustomobject][ordered]@{
        value = @($records | Sort-Object -Property name -CaseSensitive)
    }
}

function Invoke-ApimAuthEndpointCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Environment,
        [Parameter(Mandatory)][ValidateSet('Identity', 'Portal')][string] $Name,
        [Parameter(Mandatory)][object[]] $Endpoints
    )

    $logPath = Join-Path $RunPath 'logs/run.log'
    $root = Get-ApimServiceResourcePath -Environment $Environment
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $paths = [Collections.Generic.List[string]]::new()
    $files = [Collections.Generic.List[string]]::new()
    $items = 0
    $failures = 0
    Set-RunStageStatus -RunPath $RunPath -Stage collect -Status InProgress
    Set-RunCollectorStatus -RunPath $RunPath -Name $Name -Status InProgress -Files @()
    foreach ($endpoint in $Endpoints) {
        try {
            # Invoke-ApimArm performs guarded GET pagination; no other transport.
            $response = Invoke-ApimArm -Method GET -Uri (
                "$root/$($endpoint.Endpoint)?api-version=2024-05-01"
            ) -LogPath $logPath
            Assert-ApimAuthObject -Value $response
            $payload = if ($Name -eq 'Identity' -or $endpoint.Kind -eq 'revisions') {
                ConvertTo-ApimAuthCollection -Payload $response -Kind $endpoint.Kind
            }
            else {
                ConvertTo-ApimPortalResource -Resource $response -Kind $endpoint.Kind
            }
            $paths.Add((Write-RunFile -RunPath $RunPath `
                -RelativePath $endpoint.File -InputObject $payload -Depth 30))
            $files.Add($endpoint.File)
            $items += if ($Name -eq 'Identity' -or $endpoint.Kind -eq 'revisions') {
                $payload.value.Count
            }
            else { 1 }
        }
        catch {
            $failures++
            # Never forward a response, endpoint error text, or a secret value.
            Write-RunLog -Path $logPath -Level Error -Collector $Name `
                -Message "$Name endpoint collection failed."
        }
    }
    $watch.Stop()
    $status = if ($failures -eq 0) { 'Completed' }
        elseif ($paths.Count -gt 0) { 'Partial' } else { 'Failed' }
    Set-RunCollectorStatus -RunPath $RunPath -Name $Name -Status $status `
        -Items $items -Errors $failures -DurationSec $watch.Elapsed.TotalSeconds `
        -Files $files.ToArray()
    if ($failures -gt 0) {
        Add-RunWarning -RunPath $RunPath `
            -Message "$Name collection incomplete; unavailable endpoints are unknown."
        throw "$Name collection incomplete."
    }
    Write-RunLog -Path $logPath -Level Info -Collector $Name `
        -Message "Collected allowlisted APIM $Name settings."
    return $paths.ToArray()
}

function Invoke-ApimIdentityCollector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Environment
    )

    $endpoints = @(
        foreach ($kind in @('identityProviders', 'authorizationServers',
                'openidConnectProviders', 'authorizationProviders')) {
            [pscustomobject]@{ Kind = $kind; Endpoint = $kind; File = "raw/$kind.json" }
        }
    )
    Invoke-ApimAuthEndpointCollection -RunPath $RunPath -Environment $Environment `
        -Name Identity -Endpoints $endpoints
}
