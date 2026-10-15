#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimPortalValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object] $InputObject,
        [Parameter(Mandatory)][string[]] $Path
    )

    $value = $InputObject
    foreach ($name in $Path) {
        if ($null -eq $value) { return $null }
        Test-ApimServiceModelMap -Value $value -Context 'Portal evidence'
        if ($value -is [System.Collections.IDictionary]) {
            if ($value.Contains($name)) { $value = $value[$name] }
            else { $value = $null }
        }
        else {
            $property = $value.PSObject.Properties[$name]
            if ($null -ne $property) { $value = $property.Value }
            else { $value = $null }
        }
    }
    return ,$value
}

function Get-ApimPortalBoolean {
    [CmdletBinding()]
    param(
        [AllowNull()][object] $InputObject,
        [Parameter(Mandatory)][string[]] $Path
    )

    $value = Get-ApimPortalValue -InputObject $InputObject -Path $Path
    if ($null -ne $value -and $value -isnot [bool]) {
        throw 'Portal evidence contained a non-Boolean setting.'
    }
    return $value
}

function Get-ApimPortalModel {
    [CmdletBinding()]
    param(
        [AllowNull()][object] $ServicePayload,
        [Parameter(Mandatory)][System.Collections.IDictionary] $PortalPayloads,
        [AllowNull()][object] $IdentityProvidersPayload,
        [AllowNull()][object] $ProductsPayload,
        [System.Collections.IDictionary] $ProductGroups = @{},
        [AllowEmptyCollection()][object[]] $ProductVisibility = @()
    )

    Test-ConfigPortalProductVisibility -Value @($ProductVisibility)
    $missing = [System.Collections.Generic.List[string]]::new()
    $result = [ordered]@{}
    foreach ($field in @('developerPortalStatus', 'legacyPortalStatus')) {
        $value = Get-ApimPortalValue -InputObject $ServicePayload `
            -Path @('properties', $field)
        if ($null -ne $value -and $value -cnotin @('Enabled', 'Disabled')) {
            throw 'Portal service status was unsupported.'
        }
        $result[$field] = $value
        if ($null -eq $value) { $missing.Add($field) }
    }
    $result.published = $null
    if ($PortalPayloads.Contains('revisions')) {
        $rows = @(Get-ApimModelCollection -Payload $PortalPayloads.revisions `
                -Context 'Portal revisions')
        $unknown = $false
        $currentCompleted = $false
        $currentCount = 0
        foreach ($row in $rows) {
            $current = Get-ApimPortalBoolean $row @('properties', 'isCurrent')
            $status = Get-ApimPortalValue $row @('properties', 'status')
            if ($null -ne $status -and $status -cnotin @('pending', 'publishing', 'completed', 'failed')) {
                throw 'Portal revision status was unsupported.'
            }
            if ($current -eq $true -and $status -ceq 'completed') { $currentCompleted = $true }
            if ($current -eq $true) { $currentCount++ }
            if ($null -eq $current -or ($current -eq $true -and $null -eq $status)) {
                $unknown = $true
            }
        }
        if ($currentCount -gt 1) { $result.published = $null }
        elseif ($currentCompleted) { $result.published = $true }
        elseif (-not $unknown) { $result.published = $false }
    }
    if ($null -eq $result.published) { $missing.Add('published') }
    foreach ($setting in @(
            @('basicAuthEnabled', 'config', 'properties', 'enableBasicAuth'),
            @('signinRequired', 'config', 'properties', 'signin', 'require'),
            @('signinEnabled', 'signin', 'properties', 'enabled'),
            @('signupEnabled', 'signup', 'properties', 'enabled')
        )) {
        $payload = $PortalPayloads[$setting[1]]
        $result[$setting[0]] = Get-ApimPortalBoolean -InputObject $payload `
            -Path @($setting[2..($setting.Count - 1)])
        if ($null -eq $result[$setting[0]]) { $missing.Add($setting[0]) }
    }
    $result.basicAuthEvidence = if ($null -eq $result.basicAuthEnabled) { 'Unknown' } else { 'Direct' }
    foreach ($setting in @(
            @('delegatedRegistration', 'userRegistration', 'delegateRegistration'),
            @('delegatedSubscriptions', 'subscriptions', 'delegateSubscription')
        )) {
        $legacy = Get-ApimPortalBoolean $PortalPayloads['delegation'] `
            @('properties', $setting[1], 'enabled')
        $modern = Get-ApimPortalBoolean $PortalPayloads['config'] `
            @('properties', 'delegation', $setting[2])
        $result[$setting[0]] = if ($null -ne $legacy -and $null -ne $modern -and
            $legacy -ne $modern) { $null }
        elseif ($null -ne $modern) { $modern }
        else { $legacy }
        if ($null -eq $result[$setting[0]]) { $missing.Add($setting[0]) }
    }
    $result.identityProviderTypes = @()
    $result.nonEntraProviderEnabled = $null
    if ($null -ne $IdentityProvidersPayload) {
        $unknownProvider = $false
        $types = @(
            foreach ($provider in @(Get-ApimModelCollection -Payload $IdentityProvidersPayload `
                        -Context 'Portal identity providers')) {
                $type = Get-ApimPortalValue $provider @('properties', 'type')
                if ($null -eq $type) { $unknownProvider = $true; continue }
                if ($type -isnot [string] -or $type -cnotin @(
                        'aad', 'aadB2C', 'facebook', 'google', 'microsoft', 'twitter'
                    )) { throw 'Portal identity provider type was unsupported.' }
                $type
            }
        )
        $result.identityProviderTypes = @($types | Sort-Object -Unique -CaseSensitive)
        $nonEntra = @($types | Where-Object {
                $_ -cnotin @('aad', 'aadB2C')
            }).Count -gt 0
        $result.nonEntraProviderEnabled = if ($nonEntra) { $true }
        elseif ($unknownProvider) { $null }
        else { $false }
        if ($unknownProvider) { $missing.Add('identityProviderTypes') }
    }
    else { $missing.Add('identityProviderTypes') }
    $hostnames = Get-ApimPortalValue $ServicePayload @('properties', 'hostnameConfigurations')
    if ($null -ne $hostnames -and ($hostnames -is [string] -or
            $hostnames -isnot [System.Collections.IEnumerable] -or
            $hostnames -is [System.Collections.IDictionary])) {
        throw 'Portal hostname configurations were not an array.'
    }
    $domains = @(
        foreach ($hostname in @($hostnames)) {
            if ($null -eq $hostname) { continue }
            $type = Get-ApimPortalValue $hostname @('type')
            if ($type -cin @('DeveloperPortal', 'Portal')) {
                $name = Get-ApimPortalValue $hostname @('hostName')
                if ($name -isnot [string] -or [string]::IsNullOrWhiteSpace($name)) {
                    throw 'Portal custom domain was invalid.'
                }
                [pscustomobject]@{ type = $type; hostName = $name }
            }
        }
    )
    if ($null -eq $hostnames) {
        $result.customDomains = $null
        $missing.Add('customDomains')
    }
    else { $result.customDomains = @($domains | Sort-Object type, hostName) }
    $result.productVisibility = @()
    if ($null -eq $ProductsPayload -or $ProductVisibility.Count -eq 0) {
        $missing.Add('productVisibility')
    }
    if ($null -ne $ProductsPayload) {
        $products = @(Get-ApimModelCollection -Payload $ProductsPayload -Context 'Portal products')
        $productIds = @($products | ForEach-Object {
                $id = Get-ApimPortalValue $_ @('name')
                if ($id -isnot [string] -or [string]::IsNullOrWhiteSpace($id)) {
                    throw 'Portal product ID was invalid.'
                }
                $id
            })
        if (@($productIds | Where-Object {
                    $_ -inotin @($ProductVisibility | ForEach-Object { $_.ProductId })
                }).Count -gt 0 -and -not $missing.Contains('productVisibility')) {
            $missing.Add('productVisibility')
        }
        $visibility = @(
            foreach ($intent in @($ProductVisibility | Sort-Object ProductId)) {
                $id = $intent.ProductId
                $found = $id -iin $productIds
                $groups = @()
                $mismatch = $null
                $complete = $found -and $ProductGroups.Contains($id)
                if ($complete) {
                    $groups = @(
                        foreach ($group in @(Get-ApimModelCollection -Payload $ProductGroups[$id] `
                                    -Context 'Portal product groups')) {
                            $name = Get-ApimPortalValue $group @('name')
                            if ($name -isnot [string] -or [string]::IsNullOrWhiteSpace($name)) {
                                throw 'Portal product group ID was invalid.'
                            }
                            $name
                        }
                    )
                    $mismatch = (-not $intent.IsPublic -and 'guests' -iin $groups) -or
                        @($intent.IntendedGroupIds | Where-Object { $_ -inotin $groups }).Count -gt 0
                }
                else {
                    if (-not $missing.Contains('productVisibility')) { $missing.Add('productVisibility') }
                }
                [pscustomobject]@{
                    productId = $id; productFound = $found; isPublic = $intent.IsPublic
                    intendedGroupIds = @($intent.IntendedGroupIds | Sort-Object)
                    actualGroupIds = @($groups | Sort-Object -Unique)
                    visibilityMismatch = $mismatch
                }
            }
        )
        $result.productVisibility = $visibility
    }
    else {
        $result.productVisibility = @(
            foreach ($intent in @($ProductVisibility | Sort-Object ProductId)) {
                [pscustomobject]@{
                    productId = $intent.ProductId; productFound = $null; isPublic = $intent.IsPublic
                    intendedGroupIds = @($intent.IntendedGroupIds | Sort-Object)
                    actualGroupIds = @(); visibilityMismatch = $null
                }
            }
        )
    }
    $result.modelStatus = if ($missing.Count -gt 0) { 'Partial' } else { 'Complete' }
    $result.missingInputs = @($missing | Sort-Object -Unique)
    $json = ConvertTo-Json -InputObject $result -Depth 30
    Test-ApimModelJson -Name portal -Json $json
    return [pscustomobject] $result
}
