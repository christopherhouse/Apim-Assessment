#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimOrganizationEndpoint {
    [CmdletBinding()]
    param()

    foreach ($kind in @('groups', 'tags', 'apiVersionSets', 'gateways',
            'workspaces', 'policyFragments', 'users')) {
        $file = if ($kind -ceq 'users') { 'raw/users.summary.json' }
            else { "raw/$kind.json" }
        [pscustomobject]@{ Kind = $kind; Endpoint = $kind; File = $file }
    }
}

function Get-ApimEmptyUserSummary {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        schemaVersion = '1.0'
        total = 0
        byState = [ordered]@{ active = 0; blocked = 0; pending = 0; deleted = 0; Unknown = 0 }
        byProvider = [ordered]@{
            basic = 0; aad = 0; aadB2C = 0; facebook = 0; google = 0
            microsoft = 0; twitter = 0; Unknown = 0
        }
    }
}

function ConvertTo-ApimUserSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Payload)

    Assert-ApimAuthObject -Value $Payload
    $users = Get-ApimAuthProperty -InputObject $Payload -Name value
    if ($users -isnot [array]) { throw 'User inventory collection is invalid.' }
    $summary = Get-ApimEmptyUserSummary
    $seen = [Collections.Generic.Dictionary[string, string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    foreach ($user in $users) {
        Assert-ApimAuthObject -Value $user
        $name = ConvertTo-ApimAuthName -Value (Get-ApimAuthProperty $user name)
        $properties = Get-ApimAuthProperty $user properties
        Assert-ApimAuthObject -Value $properties
        $state = Get-ApimAuthProperty $properties state
        if ($null -ne $state -and $state -isnot [string]) {
            throw 'User inventory state is invalid.'
        }
        if ($state -cnotin @('active', 'blocked', 'pending', 'deleted')) { $state = 'Unknown' }
        $providers = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $identities = Get-ApimAuthProperty $properties identities
        if ($null -ne $identities -and $identities -isnot [array]) {
            throw 'User inventory identities are invalid.'
        }
        foreach ($identity in $identities) {
            Assert-ApimAuthObject -Value $identity
            $provider = Get-ApimAuthProperty $identity provider
            if ($null -ne $provider -and $provider -isnot [string]) {
                throw 'User inventory provider is invalid.'
            }
            if ($provider -cnotin @('basic', 'aad', 'aadB2C', 'facebook', 'google', 'microsoft', 'twitter')) {
                $provider = 'Unknown'
            }
            $null = $providers.Add($provider)
        }
        if ($providers.Count -eq 0) { $null = $providers.Add('Unknown') }
        $signature = "$state|$(@($providers | Sort-Object -CaseSensitive) -join ',')"
        if ($seen.ContainsKey($name)) {
            if ($seen[$name] -cne $signature) {
                throw 'User inventory contains conflicting duplicate records.'
            }
            continue
        }
        $seen.Add($name, $signature)
        $summary.total++
        $summary.byState[$state]++
        foreach ($provider in $providers) { $summary.byProvider[$provider]++ }
    }
    return $summary
}

function ConvertTo-ApimOrganizationCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Payload,
        [Parameter(Mandatory)]
        [ValidateSet('groups', 'tags', 'apiVersionSets', 'gateways', 'workspaces', 'policyFragments')]
        [string] $Kind
    )

    Assert-ApimAuthObject -Value $Payload
    $value = Get-ApimAuthProperty $Payload value
    if ($value -isnot [array]) { throw 'Organization inventory collection is invalid.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $records = @(
        foreach ($resource in $value) {
            Assert-ApimAuthObject -Value $resource
            $name = ConvertTo-ApimAuthName -Value (Get-ApimAuthProperty $resource name)
            if (-not $seen.Add($name)) { throw 'Organization inventory contains duplicate names.' }
            $safe = [ordered]@{}
            if ($Kind -cin @('groups', 'apiVersionSets')) {
                $properties = Get-ApimAuthProperty $resource properties
                Assert-ApimAuthObject -Value $properties
                if ($Kind -ceq 'groups') {
                    $safe.type = ConvertTo-ApimAuthEnum -Value (
                        Get-ApimAuthProperty $properties type
                    ) -Allowed @('custom', 'system', 'external')
                    $safe.builtIn = ConvertTo-ApimAuthBoolean -Value (
                        Get-ApimAuthProperty $properties builtIn
                    )
                }
                else {
                    $safe.versioningScheme = ConvertTo-ApimAuthEnum -Value (
                        Get-ApimAuthProperty $properties versioningScheme
                    ) -Allowed @('Segment', 'Query', 'Header')
                }
            }
            [pscustomobject][ordered]@{ name = $name; properties = [pscustomobject]$safe }
        }
    )
    return [pscustomobject][ordered]@{
        value = @($records | Sort-Object name -CaseSensitive)
    }
}

function Test-ApimUserSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Payload)

    $safe = Get-ApimEmptyUserSummary
    $total = Get-ApimAuthProperty $Payload total
    if (($total -isnot [int] -and $total -isnot [long]) -or
        $total -lt 0 -or $total -gt [int]::MaxValue) {
        throw 'User inventory total is invalid.'
    }
    $safe.total = $total
    foreach ($field in @('byState', 'byProvider')) {
        $counts = Get-ApimAuthProperty $Payload $field
        Assert-ApimAuthObject -Value $counts
        foreach ($key in @($safe.$field.Keys)) {
            $count = Get-ApimAuthProperty $counts $key
            if (($count -isnot [int] -and $count -isnot [long]) -or
                $count -lt 0 -or $count -gt $total) {
                throw 'User inventory count is invalid.'
            }
            $safe.$field[$key] = $count
        }
    }
    $states = ($safe.byState.Values | Measure-Object -Sum).Sum
    $providers = ($safe.byProvider.Values | Measure-Object -Sum).Sum
    if ($states -ne $total -or $providers -lt $total -or
        -not (Test-ApimAuthSavedProjection -Payload $Payload -Projection $safe)) {
        throw 'User inventory summary is not a closed aggregate.'
    }
}

function Test-ApimOrganizationSavedOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][object] $Collector
    )

    $files = @(Get-ApimAuthSavedFile -Collector $Collector `
        -Expected @((Get-ApimOrganizationEndpoint).File))
    $count = 0
    foreach ($endpoint in Get-ApimOrganizationEndpoint) {
        if ($endpoint.File -cnotin $files) { continue }
        $payload = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath $endpoint.File
        if ($endpoint.Kind -ceq 'users') {
            Test-ApimUserSummary -Payload $payload
            $count += $payload.total
        }
        else {
            $safe = ConvertTo-ApimOrganizationCollection -Payload $payload -Kind $endpoint.Kind
            if (-not (Test-ApimAuthSavedProjection -Payload $payload -Projection $safe)) {
                throw 'Organization inventory saved output is not allowlisted.'
            }
            $count += $safe.value.Count
        }
    }
    return $count
}

function Invoke-ApimOrganizationCollector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Environment
    )

    Invoke-ApimAuthEndpointCollection -RunPath $RunPath -Environment $Environment `
        -Name Organization -Endpoints @(Get-ApimOrganizationEndpoint)
}
