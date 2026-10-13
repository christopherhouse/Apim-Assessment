#Requires -Version 7.4

Set-StrictMode -Version Latest

function ConvertTo-ApimKustoStringLiteral {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    return "'$($Value.Replace("'", "''"))'"
}

function Get-ApimNetworkObjectValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [switch] $AllowMissing
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }
    }
    else {
        $property = $InputObject.PSObject.Properties[$Name]
        if ($null -ne $property) {
            return $property.Value
        }
    }
    if ($AllowMissing) {
        return $null
    }
    throw "Network input did not contain '$Name'."
}

function Read-ApimNetworkCollectorJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RelativePath
    )

    $path = Resolve-RunFilePath -RunPath $RunPath -RelativePath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required network collector input '$RelativePath' was not found."
    }
    try {
        return Get-Content -LiteralPath $path -Raw |
            ConvertFrom-Json -Depth 100 -ErrorAction Stop
    }
    catch {
        throw "Required network collector input '$RelativePath' was not valid JSON."
    }
}

function Invoke-ApimResourceGraphQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Query,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SubscriptionId
    )

    if ($null -eq (Get-Command -Name Search-AzGraph -ErrorAction SilentlyContinue)) {
        throw 'Search-AzGraph is unavailable. Install and import Az.ResourceGraph.'
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $seenTokens = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $skipToken = $null
    do {
        $parameters = @{
            Query = $Query
            Subscription = $SubscriptionId
            First = 1000
            ErrorAction = 'Stop'
        }
        if ($null -ne $skipToken) {
            $parameters.SkipToken = $skipToken
        }

        $response = Search-AzGraph @parameters
        if ($null -eq $response) {
            break
        }
        $dataProperty = $response.PSObject.Properties['Data']
        $items = if ($null -ne $dataProperty) {
            @($dataProperty.Value)
        }
        else {
            @($response)
        }
        foreach ($item in $items) {
            if ($null -ne $item) {
                $results.Add($item)
            }
        }

        $tokenProperty = $response.PSObject.Properties['SkipToken']
        $nextToken = if ($null -ne $tokenProperty) {
            [string] $tokenProperty.Value
        }
        else {
            $tokenValues = @(
                foreach ($item in @($response)) {
                    $itemToken = $item.PSObject.Properties['SkipToken']
                    if ($null -ne $itemToken) {
                        [string] $itemToken.Value
                    }
                }
            )
            if ($tokenValues.Count -gt 0) {
                [string] $tokenValues[0]
            }
            else {
                $null
            }
        }
        if ([string]::IsNullOrWhiteSpace($nextToken)) {
            break
        }
        if (-not $seenTokens.Add($nextToken)) {
            throw 'Resource Graph returned a repeated skip token.'
        }
        $skipToken = $nextToken
    } while ($true)

    return $results.ToArray()
}

function ConvertTo-ApimResourceGraphPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Query,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SubscriptionId
    )

    return [pscustomobject] [ordered]@{
        value = @(Invoke-ApimResourceGraphQuery `
                -Query $Query -SubscriptionId $SubscriptionId)
    }
}

function Get-ApimNetworkResourceQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $ResourceGroups,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceTypes
    )

    $groups = @(
        $ResourceGroups |
            Sort-Object -Unique |
            ForEach-Object { ConvertTo-ApimKustoStringLiteral $_ }
    )
    $types = @(
        $ResourceTypes |
            Sort-Object -Unique |
            ForEach-Object {
                ConvertTo-ApimKustoStringLiteral $_.ToLowerInvariant()
            }
    )
    if ($groups.Count -eq 0) {
        throw 'A Resource Graph query requires at least one resource group.'
    }

    $query = @(
        'resources'
        "| where resourceGroup in~ ($($groups -join ', '))"
        "| where type in~ ($($types -join ', '))"
    )
    $query += '| project id, name, type, resourceGroup, location, properties'
    $query += '| order by tolower(id) asc'
    return $query -join [Environment]::NewLine
}

function Get-ApimNetworkTargetSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Service
    )

    $properties = Get-ApimNetworkObjectValue `
        -InputObject $Service -Name properties
    $targets = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($name in @('privateIPAddresses', 'publicIpAddresses')) {
        foreach ($address in @(
                Get-ApimNetworkObjectValue -InputObject $properties `
                    -Name $name -AllowMissing
            )) {
            if (-not [string]::IsNullOrWhiteSpace([string] $address)) {
                $null = $targets.Add([string] $address)
            }
        }
    }
    foreach ($hostname in @(
            Get-ApimNetworkObjectValue -InputObject $properties `
                -Name hostnameConfigurations -AllowMissing
        )) {
        if ($null -eq $hostname) {
            continue
        }
        $value = [string] (Get-ApimNetworkObjectValue `
                -InputObject $hostname -Name hostName -AllowMissing)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $null = $targets.Add($value)
        }
    }
    return @($targets | Sort-Object)
}

function Get-ApimServicePublicIpIdSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Service
    )

    $properties = Get-ApimNetworkObjectValue `
        -InputObject $Service -Name properties
    $ids = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($name in @('publicIpAddressId', 'publicIpAddressIds')) {
        foreach ($id in @(
                Get-ApimNetworkObjectValue -InputObject $properties `
                    -Name $name -AllowMissing
            )) {
            if (-not [string]::IsNullOrWhiteSpace([string] $id)) {
                $null = $ids.Add([string] $id)
            }
        }
    }
    return @($ids | Sort-Object)
}

function Get-ApimPublicIpResourceQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroups,

        [AllowEmptyCollection()]
        [string[]] $ServicePublicIpIds = @(),

        [AllowEmptyCollection()]
        [string[]] $ConfiguredAppGatewayIds = @()
    )

    $groups = @(
        $ResourceGroups |
            Sort-Object -Unique |
            ForEach-Object { ConvertTo-ApimKustoStringLiteral $_ }
    )
    $servicePublicIpLiterals = @(
        $ServicePublicIpIds |
            Sort-Object -Unique |
            ForEach-Object {
                ConvertTo-ApimKustoStringLiteral $_.ToLowerInvariant()
            }
    )
    $configuredGatewayExpressions = @(
        $ConfiguredAppGatewayIds |
            Sort-Object -Unique |
            ForEach-Object {
                $literal = ConvertTo-ApimKustoStringLiteral (
                    "$($_.ToLowerInvariant())/"
                )
                "ipConfigurationId startswith $literal"
            }
    )

    $classification = [System.Collections.Generic.List[string]]::new()
    if ($servicePublicIpLiterals.Count -gt 0) {
        $classification.Add(
            "id in~ ($($servicePublicIpLiterals -join ', ')), 'TargetsApim'"
        )
    }
    $classification.Add(
        "isempty(ipConfigurationId), 'KnownOther'"
    )
    if ($configuredGatewayExpressions.Count -gt 0) {
        $classification.Add(
            "$($configuredGatewayExpressions -join ' or '), 'KnownOther'"
        )
    }
    $classification.Add("'Unknown'")

    return @(
        'resources'
        "| where resourceGroup in~ ($($groups -join ', '))"
        "| where type =~ 'microsoft.network/publicipaddresses'"
        '| extend ipConfigurationId = tolower(tostring(properties.ipConfiguration.id))'
        "| extend targetClassification = case($($classification -join ', '))"
        (
            '| project id, name, type, resourceGroup, location, properties, ' +
            'targetClassification'
        )
        '| order by tolower(id) asc'
    ) -join [Environment]::NewLine
}

function Get-ApimFrontDoorResourceQuerySet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroups,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ApimTargets,

        [AllowEmptyCollection()]
        [string[]] $ExcludedResourceIds = @()
    )

    $groups = @(
        $ResourceGroups |
            Sort-Object -Unique |
            ForEach-Object { ConvertTo-ApimKustoStringLiteral $_ }
    )
    $targets = @(
        $ApimTargets |
            Sort-Object -Unique |
            ForEach-Object {
                ConvertTo-ApimKustoStringLiteral $_.ToLowerInvariant()
            }
    )
    $excludedClause = if ($ExcludedResourceIds.Count -gt 0) {
        $excluded = @(
            $ExcludedResourceIds |
                Sort-Object -Unique |
                ForEach-Object {
                    ConvertTo-ApimKustoStringLiteral $_.ToLowerInvariant()
                }
        )
        "| where id !in~ ($($excluded -join ', '))"
    }
    else {
        $null
    }

    $sources = @(
        [pscustomobject]@{
            Type = 'microsoft.network/applicationgateways'
            Expand = @(
                '| mv-expand pool = properties.backendAddressPools'
                '| mv-expand backend = pool.properties.backendAddresses'
                (
                    '| extend backendTarget = tolower(coalesce(' +
                    'tostring(backend.fqdn), tostring(backend.ipAddress)))'
                )
            )
            ExcludeConfigured = $true
        }
        [pscustomobject]@{
            Type = 'microsoft.network/frontdoors'
            Expand = @(
                '| mv-expand pool = properties.backendPools'
                '| mv-expand backend = pool.properties.backends'
                '| extend backendTarget = tolower(tostring(backend.properties.address))'
            )
            ExcludeConfigured = $false
        }
        [pscustomobject]@{
            Type = 'microsoft.cdn/profiles/origingroups/origins'
            Expand = @(
                '| extend backendTarget = tolower(tostring(properties.hostName))'
            )
            ExcludeConfigured = $false
        }
    )
    return @(
        foreach ($source in $sources) {
            $query = @(
                'resources'
                "| where resourceGroup in~ ($($groups -join ', '))"
                "| where type =~ '$($source.Type)'"
            )
            if ($source.ExcludeConfigured -and $null -ne $excludedClause) {
                $query += $excludedClause
            }
            $query += @($source.Expand)
            $query += @(
                "| where backendTarget in~ ($($targets -join ', '))"
                '| extend targetsApim = true'
                (
                    '| project id, name, type, resourceGroup, location, ' +
                    'properties, targetsApim'
                )
                '| order by tolower(id) asc'
            )
            $query -join [Environment]::NewLine
        }
    )
}

function Get-ApimNetworkWafPolicyId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $AppGateway,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SubscriptionId
    )

    $properties = Get-ApimNetworkObjectValue `
        -InputObject $AppGateway -Name properties
    $policy = Get-ApimNetworkObjectValue -InputObject $properties `
        -Name firewallPolicy -AllowMissing
    if ($null -eq $policy) {
        return $null
    }
    $policyId = [string] (Get-ApimNetworkObjectValue `
            -InputObject $policy -Name id -AllowMissing)
    if ([string]::IsNullOrWhiteSpace($policyId)) {
        throw 'Application Gateway firewall policy link was invalid.'
    }

    $pattern = (
        '^/subscriptions/{0}/resourceGroups/[^/]+/providers/' +
        'Microsoft\.Network/ApplicationGatewayWebApplicationFirewallPolicies/' +
        '[^/]+$'
    ) -f [regex]::Escape($SubscriptionId)
    if ($policyId -notmatch $pattern) {
        throw 'Application Gateway firewall policy link was outside the expected scope.'
    }
    return $policyId
}

function Invoke-ApimNetworkCollector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Environment
    )

    $collectorName = 'Network'
    $logPath = Join-Path $RunPath 'logs/run.log'
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Set-RunStageStatus -RunPath $RunPath -Stage collect -Status InProgress
    Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
        -Status InProgress
    try {
        $service = Read-ApimNetworkCollectorJson -RunPath $RunPath `
            -RelativePath 'raw/service.json'
        $subscriptionId = [string] $Environment.SubscriptionId
        $appGatewayIds = [System.Collections.Generic.List[string]]::new()
        $wafPolicyIdsByPath = [System.Collections.Generic.Dictionary[
            string,
            string
        ]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $filePayloads = [ordered]@{}

        foreach ($gateway in @($Environment.AppGateways)) {
            $resourceGroup = [string] $gateway.ResourceGroup
            $name = [string] $gateway.Name
            $groupSegment = ConvertTo-ApimResourceSegment -Value $resourceGroup
            $nameSegment = ConvertTo-ApimResourceSegment -Value $name
            $resourceId = (
                '/subscriptions/{0}/resourceGroups/{1}/providers/' +
                'Microsoft.Network/applicationGateways/{2}'
            ) -f $subscriptionId, $groupSegment, $nameSegment
            $payload = Invoke-ApimArm `
                -Uri "${resourceId}?api-version=2024-05-01" `
                -LogPath $logPath
            if ($null -eq $payload) {
                throw 'Application Gateway response was empty.'
            }
            if ($filePayloads.Contains("raw/network/appgw.${nameSegment}.json")) {
                throw 'Application Gateway configuration contained duplicate names.'
            }
            $filePayloads["raw/network/appgw.${nameSegment}.json"] = $payload
            $payloadId = [string] (Get-ApimNetworkObjectValue `
                    -InputObject $payload -Name id)
            if ([string]::IsNullOrWhiteSpace($payloadId)) {
                throw 'Application Gateway response contained an invalid resource ID.'
            }
            $appGatewayIds.Add($payloadId)

            $policyId = Get-ApimNetworkWafPolicyId `
                -AppGateway $payload -SubscriptionId $subscriptionId
            if ($null -ne $policyId) {
                $policyName = [System.Uri]::UnescapeDataString(
                    ($policyId -split '/')[-1]
                )
                $policySegment = ConvertTo-ApimResourceSegment `
                    -Value $policyName
                $relativePath = "raw/network/wafPolicy.${policySegment}.json"
                if ($wafPolicyIdsByPath.ContainsKey($relativePath)) {
                    if (-not $wafPolicyIdsByPath[$relativePath].Equals(
                            $policyId,
                            [System.StringComparison]::OrdinalIgnoreCase
                        )) {
                        throw 'WAF policy configuration contained duplicate names.'
                    }
                }
                else {
                    $policyPayload = Invoke-ApimArm `
                        -Uri "${policyId}?api-version=2024-05-01" `
                        -LogPath $logPath
                    if ($null -eq $policyPayload) {
                        throw 'Application Gateway WAF policy response was empty.'
                    }
                    $wafPolicyIdsByPath.Add($relativePath, $policyId)
                    $filePayloads[$relativePath] = $policyPayload
                }
            }
        }

        $networkGroups = @($Environment.NetworkResourceGroups)
        $serviceProperties = Get-ApimNetworkObjectValue `
            -InputObject $service -Name properties
        $vnetConfiguration = Get-ApimNetworkObjectValue `
            -InputObject $serviceProperties -Name virtualNetworkConfiguration `
            -AllowMissing
        $subnetId = if ($null -eq $vnetConfiguration) {
            $null
        }
        else {
            [string] (Get-ApimNetworkObjectValue `
                    -InputObject $vnetConfiguration `
                    -Name subnetResourceId -AllowMissing)
        }

        if ([string]::IsNullOrWhiteSpace($subnetId)) {
            $filePayloads['raw/network/apimSubnet.json'] = [pscustomobject]@{
                value = @()
            }
        }
        else {
            $subnetMatch = [regex]::Match(
                $subnetId,
                (
                    '^(?<vnetId>/subscriptions/[^/]+/resourceGroups/[^/]+/' +
                    'providers/Microsoft\.Network/virtualNetworks/[^/]+)/' +
                    'subnets/(?<subnetName>[^/]+)$'
                ),
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            )
            if (-not $subnetMatch.Success) {
                throw 'APIM service subnet resource ID was invalid.'
            }
            $vnetId = $subnetMatch.Groups['vnetId'].Value
            $subnetName = [System.Uri]::UnescapeDataString(
                $subnetMatch.Groups['subnetName'].Value
            )
            $subnetQuery = @(
                'resources'
                "| where id =~ $(ConvertTo-ApimKustoStringLiteral $vnetId)"
                "| where type =~ 'microsoft.network/virtualnetworks'"
                '| mv-expand subnet = properties.subnets'
                (
                    '| where tostring(subnet.name) =~ ' +
                    (ConvertTo-ApimKustoStringLiteral $subnetName)
                )
                (
                    "| project id = tostring(subnet.id), " +
                    "name = tostring(subnet.name), " +
                    "type = 'microsoft.network/virtualnetworks/subnets', " +
                    'resourceGroup, location, properties = subnet.properties'
                )
            ) -join [Environment]::NewLine
            $filePayloads['raw/network/apimSubnet.json'] = `
                ConvertTo-ApimResourceGraphPayload -Query $subnetQuery `
                -SubscriptionId $subscriptionId
        }

        $queryTypes = [ordered]@{
            'raw/network/nsgs.json' = @(
                'microsoft.network/networksecuritygroups'
            )
            'raw/network/privateEndpoints.json' = @(
                'microsoft.network/privateendpoints'
            )
            'raw/network/privateDnsZones.json' = @(
                'microsoft.network/privatednszones'
            )
            'raw/network/routeTables.json' = @(
                'microsoft.network/routetables'
            )
        }
        foreach ($relativePath in $queryTypes.Keys) {
            if ($networkGroups.Count -eq 0) {
                $filePayloads[$relativePath] = [pscustomobject]@{ value = @() }
                continue
            }
            $query = Get-ApimNetworkResourceQuery `
                -ResourceGroups $networkGroups `
                -ResourceTypes $queryTypes[$relativePath]
            $filePayloads[$relativePath] = ConvertTo-ApimResourceGraphPayload `
                -Query $query -SubscriptionId $subscriptionId
        }

        if ($networkGroups.Count -eq 0) {
            $filePayloads['raw/network/publicIps.json'] = [pscustomobject]@{
                value = @()
            }
        }
        else {
            $publicIpQuery = Get-ApimPublicIpResourceQuery `
                -ResourceGroups $networkGroups `
                -ServicePublicIpIds (
                    Get-ApimServicePublicIpIdSet -Service $service
                ) `
                -ConfiguredAppGatewayIds $appGatewayIds.ToArray()
            $filePayloads['raw/network/publicIps.json'] = `
                ConvertTo-ApimResourceGraphPayload -Query $publicIpQuery `
                -SubscriptionId $subscriptionId
        }

        if ($networkGroups.Count -eq 0) {
            $filePayloads['raw/network/frontDoors.json'] = [pscustomobject]@{
                value = @()
            }
        }
        else {
            $frontDoorQueries = @(Get-ApimFrontDoorResourceQuerySet `
                -ResourceGroups $networkGroups `
                -ApimTargets (Get-ApimNetworkTargetSet -Service $service) `
                -ExcludedResourceIds $appGatewayIds.ToArray())
            $frontDoorResources = [System.Collections.Generic.Dictionary[
                string,
                object
            ]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($query in $frontDoorQueries) {
                foreach ($item in @(Invoke-ApimResourceGraphQuery `
                            -Query $query -SubscriptionId $subscriptionId)) {
                    $id = [string] (Get-ApimNetworkObjectValue `
                            -InputObject $item -Name id)
                    if ([string]::IsNullOrWhiteSpace($id)) {
                        throw 'Front-door query returned an invalid resource ID.'
                    }
                    if (-not $frontDoorResources.ContainsKey($id)) {
                        $frontDoorResources.Add($id, $item)
                    }
                }
            }
            [string[]] $sortedIds = @($frontDoorResources.Keys)
            [System.Array]::Sort(
                $sortedIds, [System.StringComparer]::OrdinalIgnoreCase
            )
            $filePayloads['raw/network/frontDoors.json'] = [pscustomobject]@{
                value = @(foreach ($id in $sortedIds) {
                        $frontDoorResources[$id]
                    })
            }
        }

        $paths = [System.Collections.Generic.List[string]]::new()
        foreach ($relativePath in $filePayloads.Keys) {
            $paths.Add((Write-RunFile -RunPath $RunPath `
                        -RelativePath $relativePath `
                        -InputObject $filePayloads[$relativePath] -Depth 100))
        }

        $stopwatch.Stop()
        Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
            -Status Completed -Items $paths.Count `
            -DurationSec $stopwatch.Elapsed.TotalSeconds
        Write-RunLog -Path $logPath -Level Info -Collector $collectorName `
            -Message 'Collected network configuration evidence.'
        return $paths.ToArray()
    }
    catch {
        $stopwatch.Stop()
        Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
            -Status Failed -Errors 1 `
            -DurationSec $stopwatch.Elapsed.TotalSeconds
        Add-RunWarning -RunPath $RunPath `
            -Message 'Network collector failed; see the restricted run log.'
        Write-RunLog -Path $logPath -Level Error -Collector $collectorName `
            -Message 'Network collection failed.'
        throw
    }
}
