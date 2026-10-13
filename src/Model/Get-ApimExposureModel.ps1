#Requires -Version 7.4

Set-StrictMode -Version Latest

function ConvertTo-ApimIpv4Number {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Address
    )

    $parsed = [System.Net.IPAddress]::None
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref] $parsed) -or
        $parsed.AddressFamily -ne
            [System.Net.Sockets.AddressFamily]::InterNetwork) {
        return $null
    }
    $bytes = $parsed.GetAddressBytes()
    return [uint64] (
        ([uint32] $bytes[0] -shl 24) -bor
        ([uint32] $bytes[1] -shl 16) -bor
        ([uint32] $bytes[2] -shl 8) -bor
        [uint32] $bytes[3]
    )
}

function Get-ApimIpv4Range {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Value
    )

    $trimmed = $Value.Trim()
    if ($trimmed -notmatch '^(?<address>[^/]+)(?:/(?<prefix>\d{1,2}))?$') {
        return $null
    }
    $address = $Matches['address']
    $prefixText = $Matches['prefix']
    $number = ConvertTo-ApimIpv4Number -Address $address
    if ($null -eq $number) {
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($prefixText)) {
        return [pscustomobject]@{
            start = $number
            end = $number
        }
    }
    $prefix = [int] $prefixText
    if ($prefix -lt 0 -or $prefix -gt 32) {
        return $null
    }
    [uint64] $size = [math]::Pow(2, 32 - $prefix)
    [uint64] $start = [math]::Floor($number / $size) * $size
    return [pscustomobject]@{
        start = $start
        end = $start + $size - 1
    }
}

function Test-ApimIpv4RangeOverlap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Left,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Right
    )

    return [uint64] $Left.start -le [uint64] $Right.end -and
        [uint64] $Right.start -le [uint64] $Left.end
}

function ConvertTo-ApimExposureResourceMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Resources,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context
    )

    $map = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($resource in $Resources) {
        if ($null -eq $resource) {
            throw "$Context contained a null resource."
        }
        $id = [string] (Get-ApimModelValue -InputObject $resource -Name id `
                -Context $Context)
        if ([string]::IsNullOrWhiteSpace($id) -or $map.ContainsKey($id)) {
            throw "$Context contained an invalid or duplicate resource ID."
        }
        $map.Add($id, $resource)
    }
    return ,$map
}

function Get-ApimExposureReferenceId {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Reference,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context,

        [switch] $AllowMissing
    )

    if ($null -eq $Reference) {
        if ($AllowMissing) {
            return $null
        }
        throw "$Context was missing."
    }
    $id = [string] (Get-ApimModelValue -InputObject $Reference -Name id `
            -Context $Context)
    if ([string]::IsNullOrWhiteSpace($id)) {
        throw "$Context contained an invalid resource ID."
    }
    return $id
}

function Get-ApimExposureServiceTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Service
    )

    $properties = Get-ApimModelValue -InputObject $Service `
        -Name properties -Context 'APIM service'
    $hostNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $addresses = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $gatewayUrl = [string] (Get-ApimModelValue -InputObject $properties `
            -Name gatewayUrl -Context 'APIM service properties' -AllowMissing)
    if (-not [string]::IsNullOrWhiteSpace($gatewayUrl)) {
        $gatewayUri = $null
        if (-not [uri]::TryCreate(
                $gatewayUrl,
                [System.UriKind]::Absolute,
                [ref] $gatewayUri
            ) -or
            $gatewayUri.Scheme -ne 'https' -or
            [string]::IsNullOrWhiteSpace($gatewayUri.Host)) {
            throw 'APIM gateway URL was invalid.'
        }
        $null = $hostNames.Add($gatewayUri.Host)
    }
    foreach ($configuration in @(
            Get-ApimModelValue -InputObject $properties `
                -Name hostnameConfigurations `
                -Context 'APIM service properties' -AllowMissing
        )) {
        if ($null -eq $configuration) {
            continue
        }
        $type = [string] (Get-ApimModelValue `
                -InputObject $configuration -Name type `
                -Context 'APIM hostname configuration' -AllowMissing)
        if ($type -notin @('Proxy', 'Gateway')) {
            continue
        }
        $hostName = [string] (Get-ApimModelValue `
                -InputObject $configuration -Name hostName `
                -Context 'APIM hostname configuration' -AllowMissing)
        if (-not [string]::IsNullOrWhiteSpace($hostName)) {
            $null = $hostNames.Add($hostName)
        }
    }
    foreach ($name in @('privateIPAddresses', 'publicIpAddresses')) {
        foreach ($address in @(
                Get-ApimModelValue -InputObject $properties -Name $name `
                    -Context 'APIM service properties' -AllowMissing
            )) {
            if (-not [string]::IsNullOrWhiteSpace([string] $address)) {
                $null = $addresses.Add([string] $address)
            }
        }
    }
    if ($hostNames.Count -eq 0 -and $addresses.Count -eq 0) {
        throw 'APIM service contained no gateway hostname or address targets.'
    }
    return [pscustomobject]@{
        hostNames = $hostNames
        addresses = $addresses
    }
}

function Test-ApimExposureBackendPool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Pool,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]] $ServiceHostNames,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]] $ServiceAddresses
    )

    $properties = Get-ApimModelValue -InputObject $Pool -Name properties `
        -Context 'Application Gateway backend pool'
    foreach ($backend in @(
            Get-ApimModelValue -InputObject $properties `
                -Name backendAddresses `
                -Context 'Application Gateway backend pool properties' `
                -AllowMissing
        )) {
        if ($null -eq $backend) {
            continue
        }
        $fqdn = [string] (Get-ApimModelValue -InputObject $backend `
                -Name fqdn -Context 'Application Gateway backend address' `
                -AllowMissing)
        if (-not [string]::IsNullOrWhiteSpace($fqdn) -and
            $ServiceHostNames.Contains($fqdn)) {
            return $true
        }
        $address = [string] (Get-ApimModelValue -InputObject $backend `
                -Name ipAddress -Context 'Application Gateway backend address' `
                -AllowMissing)
        if (-not [string]::IsNullOrWhiteSpace($address) -and
            $ServiceAddresses.Contains($address)) {
            return $true
        }
    }
    return $false
}

function Get-ApimExposureBackendHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Pool,

        [AllowNull()]
        [object] $HttpSettings,

        [AllowNull()]
        [string] $ListenerHost
    )

    if ($null -ne $HttpSettings) {
        $properties = Get-ApimModelValue -InputObject $HttpSettings `
            -Name properties -Context 'Application Gateway HTTP settings'
        $hostName = [string] (Get-ApimModelValue -InputObject $properties `
                -Name hostName `
                -Context 'Application Gateway HTTP settings properties' `
                -AllowMissing)
        if (-not [string]::IsNullOrWhiteSpace($hostName)) {
            return $hostName
        }
        $pickHost = Get-ApimModelValue -InputObject $properties `
            -Name pickHostNameFromBackendAddress `
            -Context 'Application Gateway HTTP settings properties' `
            -AllowMissing
        if ($null -ne $pickHost -and $pickHost -isnot [bool]) {
            throw 'Application Gateway pick-host setting was not Boolean.'
        }
        if ([bool] $pickHost) {
            $poolProperties = Get-ApimModelValue -InputObject $Pool `
                -Name properties -Context 'Application Gateway backend pool'
            $fqdns = @(
                foreach ($backend in @(
                        Get-ApimModelValue -InputObject $poolProperties `
                            -Name backendAddresses `
                            -Context 'Application Gateway backend pool properties' `
                            -AllowMissing
                    )) {
                    if ($null -ne $backend) {
                        $fqdn = [string] (Get-ApimModelValue `
                                -InputObject $backend -Name fqdn `
                                -Context 'Application Gateway backend address' `
                                -AllowMissing)
                        if (-not [string]::IsNullOrWhiteSpace($fqdn)) {
                            $fqdn
                        }
                    }
                }
            )
            if ($fqdns.Count -gt 0) {
                return [string] ($fqdns | Sort-Object | Select-Object -First 1)
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ListenerHost)) {
        return $ListenerHost
    }
    $poolProperties = Get-ApimModelValue -InputObject $Pool `
        -Name properties -Context 'Application Gateway backend pool'
    $poolFqdn = @(
        foreach ($backend in @(
                Get-ApimModelValue -InputObject $poolProperties `
                    -Name backendAddresses `
                    -Context 'Application Gateway backend pool properties' `
                    -AllowMissing
            )) {
            if ($null -ne $backend) {
                $fqdn = [string] (Get-ApimModelValue `
                        -InputObject $backend -Name fqdn `
                        -Context 'Application Gateway backend address' `
                        -AllowMissing)
                if (-not [string]::IsNullOrWhiteSpace($fqdn)) {
                    $fqdn
                }
            }
        }
    )
    if ($poolFqdn.Count -gt 0) {
        return [string] ($poolFqdn | Sort-Object | Select-Object -First 1)
    }
    return $null
}

function Get-ApimExposureRewriteAssessment {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Reference,

        [Parameter(Mandatory)]
        [System.Collections.Generic.Dictionary[string, object]] $RewriteSets
    )

    if ($null -eq $Reference) {
        return [pscustomobject]@{
            unresolved = $false
            fixedPath = $null
        }
    }
    $id = Get-ApimExposureReferenceId -Reference $Reference `
        -Context 'Application Gateway rewrite set reference'
    if (-not $RewriteSets.ContainsKey($id)) {
        return [pscustomobject]@{
            unresolved = $true
            fixedPath = $null
        }
    }
    $properties = Get-ApimModelValue -InputObject $RewriteSets[$id] `
        -Name properties -Context 'Application Gateway rewrite set'
    $fixedPaths = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($rule in @(
            Get-ApimModelValue -InputObject $properties -Name rewriteRules `
                -Context 'Application Gateway rewrite set properties' `
                -AllowMissing
        )) {
        if ($null -eq $rule) {
            continue
        }
        $ruleProperties = Get-ApimModelValue -InputObject $rule `
            -Name properties -Context 'Application Gateway rewrite rule'
        if (@(
                Get-ApimModelValue -InputObject $ruleProperties `
                    -Name conditions `
                    -Context 'Application Gateway rewrite rule properties' `
                    -AllowMissing
            ).Count -gt 0) {
            return [pscustomobject]@{
                unresolved = $true
                fixedPath = $null
            }
        }
        $actionSet = Get-ApimModelValue -InputObject $ruleProperties `
            -Name actionSet `
            -Context 'Application Gateway rewrite rule properties' -AllowMissing
        if ($null -eq $actionSet) {
            continue
        }
        $urlConfiguration = Get-ApimModelValue -InputObject $actionSet `
            -Name urlConfiguration `
            -Context 'Application Gateway rewrite action set' -AllowMissing
        if ($null -eq $urlConfiguration) {
            continue
        }
        $modifiedPath = [string] (Get-ApimModelValue `
                -InputObject $urlConfiguration -Name modifiedPath `
                -Context 'Application Gateway rewrite URL configuration' `
                -AllowMissing)
        if ([string]::IsNullOrWhiteSpace($modifiedPath)) {
            continue
        }
        if ($modifiedPath -match '[{}]') {
            return [pscustomobject]@{
                unresolved = $true
                fixedPath = $null
            }
        }
        $normalized = '/' + $modifiedPath.Trim().TrimStart('/')
        $null = $fixedPaths.Add($normalized)
    }
    if ($fixedPaths.Count -gt 1) {
        return [pscustomobject]@{
            unresolved = $true
            fixedPath = $null
        }
    }
    return [pscustomobject]@{
        unresolved = $false
        fixedPath = if ($fixedPaths.Count -eq 1) {
            [string] @($fixedPaths)[0]
        }
        else {
            $null
        }
    }
}

function Get-ApimPublishedRouteSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Service,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $AppGateways
    )

    $serviceTargets = Get-ApimExposureServiceTarget -Service $Service
    $routes = [System.Collections.Generic.List[object]]::new()
    foreach ($gateway in $AppGateways) {
        $gatewayName = Get-ApimNetworkResourceName -Resource $gateway `
            -Context 'Application Gateway'
        $properties = Get-ApimModelValue -InputObject $gateway `
            -Name properties -Context 'Application Gateway'
        $frontends = ConvertTo-ApimExposureResourceMap `
            -Resources @(
                Get-ApimModelValue -InputObject $properties `
                    -Name frontendIPConfigurations `
                    -Context 'Application Gateway properties'
            ) -Context 'Application Gateway frontend configurations'
        $listeners = ConvertTo-ApimExposureResourceMap `
            -Resources @(
                Get-ApimModelValue -InputObject $properties -Name httpListeners `
                    -Context 'Application Gateway properties'
            ) -Context 'Application Gateway listeners'
        $pools = ConvertTo-ApimExposureResourceMap `
            -Resources @(
                Get-ApimModelValue -InputObject $properties `
                    -Name backendAddressPools `
                    -Context 'Application Gateway properties'
            ) -Context 'Application Gateway backend pools'
        $settings = ConvertTo-ApimExposureResourceMap `
            -Resources @(
                Get-ApimModelValue -InputObject $properties `
                    -Name backendHttpSettingsCollection `
                    -Context 'Application Gateway properties' -AllowMissing |
                    Where-Object { $null -ne $_ }
            ) -Context 'Application Gateway HTTP settings'
        $pathMaps = ConvertTo-ApimExposureResourceMap `
            -Resources @(
                Get-ApimModelValue -InputObject $properties -Name urlPathMaps `
                    -Context 'Application Gateway properties' -AllowMissing |
                    Where-Object { $null -ne $_ }
            ) -Context 'Application Gateway URL path maps'
        $rewriteSets = ConvertTo-ApimExposureResourceMap `
            -Resources @(
                Get-ApimModelValue -InputObject $properties `
                    -Name rewriteRuleSets `
                    -Context 'Application Gateway properties' -AllowMissing |
                    Where-Object { $null -ne $_ }
            ) -Context 'Application Gateway rewrite sets'

        foreach ($rule in @(
                Get-ApimModelValue -InputObject $properties `
                    -Name requestRoutingRules `
                    -Context 'Application Gateway properties'
            )) {
            $ruleName = Get-ApimNetworkResourceName -Resource $rule `
                -Context 'Application Gateway routing rule'
            $ruleProperties = Get-ApimModelValue -InputObject $rule `
                -Name properties -Context 'Application Gateway routing rule'
            $ruleType = [string] (Get-ApimModelValue `
                    -InputObject $ruleProperties -Name ruleType `
                    -Context 'Application Gateway routing rule properties')
            if ($ruleType -notin @('Basic', 'PathBasedRouting')) {
                throw 'Application Gateway routing rule type was unsupported.'
            }
            $listenerId = Get-ApimExposureReferenceId `
                -Reference (Get-ApimModelValue -InputObject $ruleProperties `
                    -Name httpListener `
                    -Context 'Application Gateway routing rule properties') `
                -Context 'Application Gateway listener reference'
            if (-not $listeners.ContainsKey($listenerId)) {
                throw 'Application Gateway routing rule referenced an unknown listener.'
            }
            $listener = $listeners[$listenerId]
            $listenerName = Get-ApimNetworkResourceName -Resource $listener `
                -Context 'Application Gateway listener'
            $listenerProperties = Get-ApimModelValue -InputObject $listener `
                -Name properties -Context 'Application Gateway listener'
            $singleListenerHost = [string] (Get-ApimModelValue `
                    -InputObject $listenerProperties -Name hostName `
                    -Context 'Application Gateway listener properties' `
                    -AllowMissing)
            $listenerHosts = @(
                @(
                    if (-not [string]::IsNullOrWhiteSpace(
                            $singleListenerHost
                        )) {
                        $singleListenerHost
                    }
                    foreach ($hostName in @(
                            Get-ApimModelValue -InputObject $listenerProperties `
                                -Name hostNames `
                                -Context 'Application Gateway listener properties' `
                                -AllowMissing
                        )) {
                        if (-not [string]::IsNullOrWhiteSpace(
                                [string] $hostName
                            )) {
                            [string] $hostName
                        }
                    }
                ) | Sort-Object -Unique
            )
            if ($listenerHosts.Count -eq 0) {
                $listenerHosts = @($null)
            }
            $frontendId = Get-ApimExposureReferenceId `
                -Reference (Get-ApimModelValue `
                    -InputObject $listenerProperties `
                    -Name frontendIPConfiguration `
                    -Context 'Application Gateway listener properties') `
                -Context 'Application Gateway frontend reference'
            if (-not $frontends.ContainsKey($frontendId)) {
                throw 'Application Gateway listener referenced an unknown frontend.'
            }
            $frontendProperties = Get-ApimModelValue `
                -InputObject $frontends[$frontendId] -Name properties `
                -Context 'Application Gateway frontend'
            $frontendType = if ($null -ne (Get-ApimModelValue `
                        -InputObject $frontendProperties -Name publicIPAddress `
                        -Context 'Application Gateway frontend properties' `
                        -AllowMissing)) {
                'Public'
            }
            elseif ($null -ne (Get-ApimModelValue `
                        -InputObject $frontendProperties -Name privateIPAddress `
                        -Context 'Application Gateway frontend properties' `
                        -AllowMissing) -or
                $null -ne (Get-ApimModelValue `
                        -InputObject $frontendProperties -Name subnet `
                        -Context 'Application Gateway frontend properties' `
                        -AllowMissing)) {
                'Private'
            }
            else {
                throw 'Application Gateway frontend type was unsupported.'
            }
            $ruleRewrite = Get-ApimModelValue -InputObject $ruleProperties `
                -Name rewriteRuleSet `
                -Context 'Application Gateway routing rule properties' `
                -AllowMissing

            $addRoute = {
                param(
                    [object] $PoolReference,
                    [object] $SettingsReference,
                    [object] $RewriteReference,
                    [string[]] $Patterns
                )
                if ($null -eq $PoolReference) {
                    return
                }
                $poolId = Get-ApimExposureReferenceId `
                    -Reference $PoolReference `
                    -Context 'Application Gateway backend pool reference'
                if (-not $pools.ContainsKey($poolId)) {
                    throw 'Application Gateway route referenced an unknown backend pool.'
                }
                $pool = $pools[$poolId]
                if (-not (Test-ApimExposureBackendPool -Pool $pool `
                            -ServiceHostNames $serviceTargets.hostNames `
                            -ServiceAddresses $serviceTargets.addresses)) {
                    return
                }
                $httpSettings = $null
                if ($null -ne $SettingsReference) {
                    $settingsId = Get-ApimExposureReferenceId `
                        -Reference $SettingsReference `
                        -Context 'Application Gateway HTTP settings reference'
                    if (-not $settings.ContainsKey($settingsId)) {
                        throw 'Application Gateway route referenced unknown HTTP settings.'
                    }
                    $httpSettings = $settings[$settingsId]
                }
                $rewrite = Get-ApimExposureRewriteAssessment `
                    -Reference $RewriteReference -RewriteSets $rewriteSets
                $effectivePatterns = if ($null -ne $rewrite.fixedPath) {
                    @([string] $rewrite.fixedPath)
                }
                else {
                    @($Patterns)
                }
                foreach ($listenerHost in $listenerHosts) {
                    $backendHost = Get-ApimExposureBackendHost `
                        -Pool $pool -HttpSettings $httpSettings `
                        -ListenerHost $listenerHost
                    if ([string]::IsNullOrWhiteSpace($backendHost) -or
                        -not $serviceTargets.hostNames.Contains($backendHost)) {
                        continue
                    }
                    foreach ($pattern in $effectivePatterns) {
                        $normalizedPattern = '/' + ([string] $pattern).
                            Trim().TrimStart('/')
                        $routes.Add([pscustomobject] [ordered]@{
                                gateway = $gatewayName
                                listener = $listenerName
                                listenerHost = $listenerHost
                                backendHost = $backendHost
                                frontendType = $frontendType
                                ruleType = $ruleType
                                ruleName = $ruleName
                                pattern = $normalizedPattern
                                rewriteUnresolved = [bool] $rewrite.unresolved
                            })
                    }
                }
            }

            if ($ruleType -eq 'Basic') {
                & $addRoute `
                    (Get-ApimModelValue -InputObject $ruleProperties `
                        -Name backendAddressPool `
                        -Context 'Application Gateway routing rule properties' `
                        -AllowMissing) `
                    (Get-ApimModelValue -InputObject $ruleProperties `
                        -Name backendHttpSettings `
                        -Context 'Application Gateway routing rule properties' `
                        -AllowMissing) `
                    $ruleRewrite @('/*')
                continue
            }

            $pathMapId = Get-ApimExposureReferenceId `
                -Reference (Get-ApimModelValue -InputObject $ruleProperties `
                    -Name urlPathMap `
                    -Context 'Application Gateway routing rule properties') `
                -Context 'Application Gateway URL path map reference'
            if (-not $pathMaps.ContainsKey($pathMapId)) {
                throw 'Application Gateway routing rule referenced an unknown path map.'
            }
            $pathMapProperties = Get-ApimModelValue `
                -InputObject $pathMaps[$pathMapId] -Name properties `
                -Context 'Application Gateway URL path map'
            $defaultRewrite = Get-ApimModelValue `
                -InputObject $pathMapProperties -Name defaultRewriteRuleSet `
                -Context 'Application Gateway URL path map properties' `
                -AllowMissing
            if ($null -eq $defaultRewrite) {
                $defaultRewrite = $ruleRewrite
            }
            & $addRoute `
                (Get-ApimModelValue -InputObject $pathMapProperties `
                    -Name defaultBackendAddressPool `
                    -Context 'Application Gateway URL path map properties' `
                    -AllowMissing) `
                (Get-ApimModelValue -InputObject $pathMapProperties `
                    -Name defaultBackendHttpSettings `
                    -Context 'Application Gateway URL path map properties' `
                    -AllowMissing) `
                $defaultRewrite @('/*')
            foreach ($pathRule in @(
                    Get-ApimModelValue -InputObject $pathMapProperties `
                        -Name pathRules `
                        -Context 'Application Gateway URL path map properties' `
                        -AllowMissing
                )) {
                if ($null -eq $pathRule) {
                    continue
                }
                $pathRuleProperties = Get-ApimModelValue `
                    -InputObject $pathRule -Name properties `
                    -Context 'Application Gateway path rule'
                $pathRewrite = Get-ApimModelValue `
                    -InputObject $pathRuleProperties -Name rewriteRuleSet `
                    -Context 'Application Gateway path rule properties' `
                    -AllowMissing
                if ($null -eq $pathRewrite) {
                    $pathRewrite = $ruleRewrite
                }
                & $addRoute `
                    (Get-ApimModelValue -InputObject $pathRuleProperties `
                        -Name backendAddressPool `
                        -Context 'Application Gateway path rule properties' `
                        -AllowMissing) `
                    (Get-ApimModelValue -InputObject $pathRuleProperties `
                        -Name backendHttpSettings `
                        -Context 'Application Gateway path rule properties' `
                        -AllowMissing) `
                    $pathRewrite @(
                        Get-ApimModelValue -InputObject $pathRuleProperties `
                            -Name paths `
                            -Context 'Application Gateway path rule properties'
                    )
            }
        }
    }
    return @($routes | Sort-Object gateway, listener, pattern, ruleName)
}

function Test-ApimExposurePathMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Pattern,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    $matcher = [System.Management.Automation.WildcardPattern]::new(
        $Pattern,
        [System.Management.Automation.WildcardOptions]::IgnoreCase
    )
    return $matcher.IsMatch($Path)
}

function Get-ApimIpFilterAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Filter,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $AppGatewayRanges
    )

    if ($AppGatewayRanges.Count -eq 0) {
        return 'Unknown'
    }
    $action = [string] (Get-ApimModelValue -InputObject $Filter `
            -Name action -Context 'Policy IP filter')
    if ($action -notin @('allow', 'forbid')) {
        return 'Unknown'
    }
    $filterRanges = [System.Collections.Generic.List[object]]::new()
    $unknownValue = $false
    foreach ($address in @(
            Get-ApimModelValue -InputObject $Filter -Name addresses `
                -Context 'Policy IP filter' -AllowMissing
        )) {
        $range = Get-ApimIpv4Range -Value ([string] $address)
        if ($null -eq $range) {
            $unknownValue = $true
        }
        else {
            $filterRanges.Add($range)
        }
    }
    foreach ($addressRange in @(
            Get-ApimModelValue -InputObject $Filter -Name addressRanges `
                -Context 'Policy IP filter' -AllowMissing
        )) {
        if ($null -eq $addressRange) {
            $unknownValue = $true
            continue
        }
        $start = ConvertTo-ApimIpv4Number -Address ([string] (
                Get-ApimModelValue -InputObject $addressRange -Name from `
                    -Context 'Policy IP filter range'
            ))
        $end = ConvertTo-ApimIpv4Number -Address ([string] (
                Get-ApimModelValue -InputObject $addressRange -Name to `
                    -Context 'Policy IP filter range'
            ))
        if ($null -eq $start -or $null -eq $end -or $start -gt $end) {
            $unknownValue = $true
        }
        else {
            $filterRanges.Add([pscustomobject]@{
                    start = $start
                    end = $end
                })
        }
    }
    if ($filterRanges.Count -eq 0) {
        return 'Unknown'
    }
    $overlap = $false
    foreach ($gatewayRange in $AppGatewayRanges) {
        foreach ($filterRange in $filterRanges) {
            if (Test-ApimIpv4RangeOverlap `
                    -Left $gatewayRange -Right $filterRange) {
                $overlap = $true
                break
            }
        }
        if ($overlap) {
            break
        }
    }
    if ($action -eq 'allow') {
        return $(if ($overlap) { 'Allowed' } else { 'Blocked' })
    }
    if ($overlap) {
        return 'Blocked'
    }
    return $(if ($unknownValue) { 'Unknown' } else { 'Allowed' })
}

function Get-ApimHostRestrictionAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Restriction,

        [AllowNull()]
        [string] $PublishedHost
    )

    if ([string]::IsNullOrWhiteSpace($PublishedHost)) {
        return 'Unknown'
    }
    $condition = [string] (Get-ApimModelValue `
            -InputObject $Restriction -Name condition `
            -Context 'Policy host restriction')
    if ($condition -match '&&|\|\|') {
        return 'Unknown'
    }
    $comparison = [regex]::Match(
        $condition,
        '(?i)(?<operator>==|!=)\s*["''](?<host>[^"'']+)["'']'
    )
    if (-not $comparison.Success) {
        return 'Unknown'
    }
    $expectedHost = $comparison.Groups['host'].Value
    $equals = $PublishedHost.Equals(
        $expectedHost,
        [System.StringComparison]::OrdinalIgnoreCase
    )
    $blocked = if ($comparison.Groups['operator'].Value -eq '!=') {
        -not $equals
    }
    else {
        $equals
    }
    return $(if ($blocked) { 'Blocked' } else { 'Allowed' })
}

function Get-ApimExposureRestrictionAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $PolicyPaths,

        [AllowNull()]
        [string] $PublishedHost,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $AppGatewayRanges
    )

    $pathResults = [System.Collections.Generic.List[object]]::new()
    foreach ($path in $PolicyPaths) {
        $evaluationStatus = [string] (Get-ApimModelValue `
                -InputObject $path -Name evaluationStatus `
                -Context 'Exposure policy path')
        if ($evaluationStatus -notin @('Complete', 'Partial')) {
            throw 'Exposure policy path contained an invalid evaluation status.'
        }
        $operationId = [string] (Get-ApimModelValue -InputObject $path `
                -Name operationId -Context 'Exposure policy path')
        $productValue = Get-ApimModelValue -InputObject $path -Name product `
            -Context 'Exposure policy path' -AllowMissing
        $product = if ($null -eq $productValue) {
            '<none>'
        }
        else {
            [string] $productValue
        }
        $baseMissingDetails = @(
            Get-ApimModelValue -InputObject $path -Name baseMissingDetails `
                -Context 'Exposure policy path' -AllowMissing
        )
        $hasInboundBaseMissing = @($baseMissingDetails | Where-Object {
                [string] (Get-ApimModelValue -InputObject $_ -Name section `
                    -Context 'Base-missing detail') -eq 'inbound'
            }).Count -gt 0

        $restriction = 'None'
        $unknown = $false
        foreach ($filter in @(
                Get-ApimModelValue -InputObject $path -Name ipFilters `
                    -Context 'Exposure policy path' -AllowMissing
            )) {
            $assessment = Get-ApimIpFilterAssessment -Filter $filter `
                -AppGatewayRanges $AppGatewayRanges
            if ($assessment -eq 'Blocked') {
                $restriction = 'IpFilter'
                break
            }
            if ($assessment -eq 'Unknown') {
                $unknown = $true
            }
        }
        if ($restriction -eq 'None') {
            foreach ($hostRestriction in @(
                    Get-ApimModelValue -InputObject $path `
                        -Name hostRestrictions `
                        -Context 'Exposure policy path' -AllowMissing
                )) {
                $assessment = Get-ApimHostRestrictionAssessment `
                    -Restriction $hostRestriction -PublishedHost $PublishedHost
                if ($assessment -eq 'Blocked') {
                    $restriction = 'HostCheck'
                    break
                }
                if ($assessment -eq 'Unknown') {
                    $unknown = $true
                }
            }
        }
        if ($restriction -eq 'None' -and
            ($unknown -or $evaluationStatus -eq 'Partial')) {
            $restriction = 'Unknown'
        }
        $pathResults.Add([pscustomobject]@{
                operationId = $operationId
                product = $product
                restriction = $restriction
                inboundBaseMissing = $hasInboundBaseMissing
            })
    }

    if (@($pathResults | Where-Object restriction -EQ 'None').Count -gt 0) {
        $restricted = @($pathResults | Where-Object {
                $_.restriction -in @('IpFilter', 'HostCheck')
            })
        $bypass = $restricted.Count -gt 0 -and
            @($pathResults | Where-Object {
                    $_.restriction -eq 'None' -and $_.inboundBaseMissing
                }).Count -gt 0
        return [pscustomobject]@{
            restriction = 'None'
            baseMissingBypass = $bypass
            restrictedOperations = @(
                $restricted |
                    ForEach-Object {
                        "$($_.operationId)|$($_.product)|$($_.restriction)"
                    } |
                    Sort-Object -Unique
            )
        }
    }
    if (@($pathResults | Where-Object restriction -EQ 'Unknown').Count -gt 0) {
        return [pscustomobject]@{
            restriction = 'Unknown'
            baseMissingBypass = $false
            restrictedOperations = @()
        }
    }
    $restriction = if (@(
            $pathResults | Where-Object restriction -EQ 'IpFilter'
        ).Count -gt 0) {
        'IpFilter'
    }
    elseif (@(
            $pathResults | Where-Object restriction -EQ 'HostCheck'
        ).Count -gt 0) {
        'HostCheck'
    }
    else {
        'None'
    }
    return [pscustomobject]@{
        restriction = $restriction
        baseMissingBypass = $false
        restrictedOperations = @(
            $pathResults |
                Where-Object {
                    $_.restriction -in @('IpFilter', 'HostCheck')
                } |
                ForEach-Object {
                    "$($_.operationId)|$($_.product)|$($_.restriction)"
                } |
                Sort-Object -Unique
        )
    }
}

function Get-ApimExposureModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Apis,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Operations,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Network,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Service,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $AppGateways,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $PolicyPaths,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $AppGwSubnetCidrs,

        [AllowNull()]
        [object[]] $UsageByRoute,

        [switch] $UsageComplete,

        [ValidateSet('Cloudflare-Assumed')]
        [string] $Edge = 'Cloudflare-Assumed'
    )

    $apiMap = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($api in $Apis) {
        $apiId = [string] (Get-ApimModelValue -InputObject $api -Name apiId `
                -Context 'API model record')
        if ([string]::IsNullOrWhiteSpace($apiId) -or
            $apiMap.ContainsKey($apiId)) {
            throw 'API model records contained an invalid or duplicate API ID.'
        }
        $apiMap.Add($apiId, $api)
    }
    $operationsByApi = @{}
    foreach ($apiId in $apiMap.Keys) {
        $operationsByApi[$apiId] = [System.Collections.Generic.List[object]]::new()
    }
    foreach ($operation in $Operations) {
        $apiId = [string] (Get-ApimModelValue `
                -InputObject $operation -Name apiId `
                -Context 'Operation model record')
        if (-not $apiMap.ContainsKey($apiId)) {
            throw 'Operation model record referenced an unknown API.'
        }
        $operationsByApi[$apiId].Add($operation)
    }
    $operationsComplete = @{}
    foreach ($apiId in $apiMap.Keys) {
        $expectedCount = Get-ApimModelValue -InputObject $apiMap[$apiId] `
            -Name operationCount -Context 'API model record'
        if (
            (
                $expectedCount -isnot [byte] -and
                $expectedCount -isnot [int16] -and
                $expectedCount -isnot [int32] -and
                $expectedCount -isnot [int64]
            ) -or
            [int64] $expectedCount -lt 0
        ) {
            throw 'API operation count was invalid.'
        }
        $operationsComplete[$apiId] = (
            $operationsByApi[$apiId].Count -eq $expectedCount
        )
    }

    $policyMap = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($path in $PolicyPaths) {
        $apiId = [string] (Get-ApimModelValue -InputObject $path -Name apiId `
                -Context 'Exposure policy path')
        $operationId = [string] (Get-ApimModelValue `
                -InputObject $path -Name operationId `
                -Context 'Exposure policy path')
        $productValue = Get-ApimModelValue -InputObject $path -Name product `
            -Context 'Exposure policy path' -AllowMissing
        $product = if ($null -eq $productValue) { $null } else {
            [string] $productValue
        }
        $key = Get-ApimPolicyFlagPathKey -ApiId $apiId `
            -OperationId $operationId -Product $product
        if ($policyMap.ContainsKey($key)) {
            throw 'Exposure policy paths contained a duplicate path.'
        }
        $policyMap.Add($key, $path)
    }

    $gatewayRanges = @(
        foreach ($cidr in $AppGwSubnetCidrs) {
            $range = Get-ApimIpv4Range -Value $cidr
            if ($null -eq $range) {
                throw 'Application Gateway subnet CIDR was invalid.'
            }
            $range
        }
    )
    $usageMap = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    if ($null -ne $UsageByRoute -and -not $UsageComplete) {
        throw 'Usage-by-route records require complete telemetry evidence.'
    }
    if ($UsageComplete) {
        foreach ($apiId in $apiMap.Keys) {
            $usageMap.Add($apiId, [pscustomobject]@{
                    callsViaAppGw = [double] 0
                    callsInternal = [double] 0
                })
        }
        foreach ($usage in $UsageByRoute) {
            $apiId = [string] (Get-ApimModelValue -InputObject $usage `
                    -Name apiId -Context 'Usage-by-route record')
            if (-not $usageMap.ContainsKey($apiId)) {
                throw 'Usage-by-route record referenced an unknown API.'
            }
            $route = [string] (Get-ApimModelValue -InputObject $usage `
                    -Name route -Context 'Usage-by-route record')
            if ($route -notin @('ViaAppGw', 'Internal')) {
                throw 'Usage-by-route record contained an unsupported route.'
            }
            $calls = Get-ApimModelValue -InputObject $usage -Name calls `
                -Context 'Usage-by-route record'
            if (
                (
                    $calls -isnot [byte] -and
                    $calls -isnot [int16] -and
                    $calls -isnot [int32] -and
                    $calls -isnot [int64] -and
                    $calls -isnot [single] -and
                    $calls -isnot [double] -and
                    $calls -isnot [decimal]
                ) -or
                [double] $calls -lt 0
            ) {
                throw 'Usage-by-route call count was invalid.'
            }
            $property = if ($route -eq 'ViaAppGw') {
                'callsViaAppGw'
            }
            else {
                'callsInternal'
            }
            $usageMap[$apiId].$property += [double] $calls
        }
    }

    $routes = @(Get-ApimPublishedRouteSet `
            -Service $Service -AppGateways $AppGateways)
    $publicRoutes = @($routes | Where-Object frontendType -EQ 'Public')
    $hasPrivateRoute = @($routes |
            Where-Object frontendType -EQ 'Private').Count -gt 0
    $directPublic = Get-ApimModelValue -InputObject $Network `
        -Name directPublic -Context 'Network model'
    if ($null -ne $directPublic -and $directPublic -isnot [bool]) {
        throw 'Network directPublic value was not Boolean or null.'
    }
    $wafState = [string] (Get-ApimModelValue `
            -InputObject $Network -Name wafState -Context 'Network model')
    $wafMode = [string] (Get-ApimModelValue `
            -InputObject $Network -Name wafMode -Context 'Network model')

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($apiId in @($apiMap.Keys | Sort-Object)) {
        $apiRoutes = if ($directPublic -eq $true) {
            @([pscustomobject]@{
                    gateway = 'None'
                    listener = 'None'
                    listenerHost = $null
                    backendHost = $null
                    frontendType = 'Public'
                    ruleType = 'DirectPublic'
                    ruleName = 'None'
                    pattern = '/*'
                    rewriteUnresolved = $false
                })
        }
        elseif ($publicRoutes.Count -gt 0) {
            $publicRoutes
        }
        else {
            @([pscustomobject]@{
                    gateway = 'None'
                    listener = 'None'
                    listenerHost = $null
                    backendHost = $null
                    frontendType = 'Private'
                    ruleType = 'None'
                    ruleName = 'None'
                    pattern = $null
                    rewriteUnresolved = $false
                })
        }
        foreach ($route in $apiRoutes) {
            $missingInputs = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal
            )
            $matchedOperations = @()
            $reachability = if ($directPublic -eq $true) {
                $matchedOperations = @($operationsByApi[$apiId])
                'Reachable'
            }
            elseif (-not $operationsComplete[$apiId]) {
                $null = $missingInputs.Add('operations')
                'Unknown'
            }
            elseif ($route.rewriteUnresolved) {
                'Unknown'
            }
            elseif ($null -eq $route.pattern) {
                if ($null -eq $directPublic) { 'Unknown' } else { 'NotRoutable' }
            }
            else {
                $matchedOperations = @(
                    $operationsByApi[$apiId] | Where-Object {
                        Test-ApimExposurePathMatch `
                            -Pattern $route.pattern -Path ([string] $_.fullPath)
                    }
                )
                if ($matchedOperations.Count -gt 0) {
                    'Reachable'
                }
                else {
                    'NotRoutable'
                }
            }

            $restriction = [pscustomobject]@{
                restriction = 'None'
                baseMissingBypass = $false
                restrictedOperations = @()
            }
            $policyEvidenceMissing = $false
            $requiresGatewayRanges = $false
            if ($reachability -eq 'Reachable' -and
                $route.ruleType -ne 'DirectPublic') {
                $operationAssessments = [System.Collections.Generic.List[object]]::new()
                foreach ($operation in $matchedOperations) {
                    $operationId = [string] $operation.operationId
                    $products = @($operation.products)
                    if ($products.Count -eq 0) {
                        $products = @($null)
                    }
                    $paths = @(
                        foreach ($product in $products) {
                            $key = Get-ApimPolicyFlagPathKey -ApiId $apiId `
                                -OperationId $operationId -Product $product
                            if (-not $policyMap.ContainsKey($key)) {
                                $policyEvidenceMissing = $true
                                [pscustomobject]@{
                                    apiId = $apiId
                                    operationId = $operationId
                                    product = $product
                                    evaluationStatus = 'Partial'
                                    ipFilters = @()
                                    hostRestrictions = @()
                                    baseMissingDetails = @()
                                }
                                continue
                            }
                            $policyMap[$key]
                        }
                    )
                    if (@(
                            foreach ($path in $paths) {
                                Get-ApimModelValue -InputObject $path `
                                    -Name ipFilters `
                                    -Context 'Exposure policy path' `
                                    -AllowMissing
                            }
                        ).Count -gt 0) {
                        $requiresGatewayRanges = $true
                    }
                    $operationAssessments.Add(
                        (Get-ApimExposureRestrictionAssessment `
                            -PolicyPaths $paths `
                            -PublishedHost $route.backendHost `
                            -AppGatewayRanges $gatewayRanges)
                    )
                }
                if (@($operationAssessments |
                        Where-Object restriction -EQ 'None').Count -gt 0) {
                    $restriction = [pscustomobject]@{
                        restriction = 'None'
                        baseMissingBypass = @($operationAssessments |
                                Where-Object baseMissingBypass).Count -gt 0
                        restrictedOperations = @(
                            $operationAssessments |
                                ForEach-Object restrictedOperations |
                                Sort-Object -Unique
                        )
                    }
                }
                elseif (@($operationAssessments |
                        Where-Object restriction -EQ 'Unknown').Count -gt 0) {
                    $restriction = [pscustomobject]@{
                        restriction = 'Unknown'
                        baseMissingBypass = $false
                        restrictedOperations = @()
                    }
                }
                else {
                    $restriction = [pscustomobject]@{
                        restriction = if (@($operationAssessments |
                                Where-Object restriction -EQ 'IpFilter').Count `
                                -gt 0) {
                            'IpFilter'
                        }
                        else {
                            'HostCheck'
                        }
                        baseMissingBypass = $false
                        restrictedOperations = @(
                            $operationAssessments |
                                ForEach-Object restrictedOperations |
                                Sort-Object -Unique
                        )
                    }
                }
            }

            $callsViaAppGw = $null
            $callsInternal = $null
            if ($usageMap.ContainsKey($apiId)) {
                $usage = $usageMap[$apiId]
                foreach ($name in @('callsViaAppGw', 'callsInternal')) {
                    $value = Get-ApimModelValue -InputObject $usage -Name $name `
                        -Context 'Usage-by-route record'
                    if (
                        (
                            $value -isnot [byte] -and
                            $value -isnot [int16] -and
                            $value -isnot [int32] -and
                            $value -isnot [int64] -and
                            $value -isnot [single] -and
                            $value -isnot [double] -and
                            $value -isnot [decimal]
                        ) -or
                        [double] $value -lt 0
                    ) {
                        throw "Usage-by-route field '$name' was invalid."
                    }
                    if ($name -eq 'callsViaAppGw') {
                        $callsViaAppGw = [double] $value
                    }
                    else {
                        $callsInternal = [double] $value
                    }
                }
            }

            if ($null -eq $directPublic) {
                $null = $missingInputs.Add('directPublic')
            }
            if ($reachability -eq 'Reachable' -and
                $restriction.restriction -eq 'None' -and
                -not $directPublic -and
                $null -eq $callsViaAppGw) {
                $null = $missingInputs.Add('usage')
            }
            if ($restriction.restriction -eq 'Unknown' -or
                $policyEvidenceMissing) {
                $null = $missingInputs.Add('policyEvidence')
            }
            if ($requiresGatewayRanges -and $gatewayRanges.Count -eq 0) {
                $null = $missingInputs.Add('appGwSubnet')
            }
            if ($route.rewriteUnresolved -and
                $route.ruleType -ne 'DirectPublic') {
                $null = $missingInputs.Add('rewrite')
            }

            $exposure = if ($directPublic) {
                'DirectPublic'
            }
            elseif ($route.rewriteUnresolved -or
                $reachability -eq 'Unknown' -or
                $null -eq $directPublic -or
                $restriction.restriction -eq 'Unknown') {
                'Unknown'
            }
            elseif ($reachability -eq 'NotRoutable') {
                'Internal'
            }
            elseif ($restriction.restriction -ne 'None') {
                'Restricted'
            }
            elseif ($null -eq $callsViaAppGw) {
                'Unknown'
            }
            elseif ($callsViaAppGw -gt 0) {
                'ExternalInUse'
            }
            else {
                'ExternalUnintended'
            }
            $confidence = if ($directPublic) {
                'High'
            }
            elseif ($route.rewriteUnresolved -or
                $reachability -eq 'Unknown' -or
                $null -eq $directPublic -or
                $restriction.restriction -eq 'Unknown') {
                'Low'
            }
            elseif ($hasPrivateRoute -or
                (
                    $reachability -eq 'Reachable' -and
                    $restriction.restriction -eq 'None' -and
                    -not $directPublic -and
                    $null -eq $callsViaAppGw
                )) {
                'Medium'
            }
            else {
                'High'
            }
            [string[]] $sortedMissingInputs = @($missingInputs)
            [System.Array]::Sort(
                $sortedMissingInputs,
                [System.StringComparer]::Ordinal
            )
            $routeKey = '{0}|{1}|{2}|{3}|{4}' -f
                $route.gateway,
                $route.listener,
                $(if ($null -eq $route.listenerHost) { '<none>' } else {
                        $route.listenerHost
                    }),
                $(if ($null -eq $route.pattern) { '<none>' } else {
                        $route.pattern
                    }),
                $apiId
            $records.Add([pscustomobject] [ordered]@{
                    routeKey = $routeKey
                    gateway = $route.gateway
                    listener = $route.listener
                    listenerHost = $route.listenerHost
                    backendHost = $route.backendHost
                    frontendType = $route.frontendType
                    ruleType = $route.ruleType
                    pattern = $route.pattern
                    wafState = $wafState
                    wafMode = $wafMode
                    edge = if ($route.ruleType -in @('DirectPublic', 'None')) {
                        'NotApplicable'
                    }
                    else {
                        $Edge
                    }
                    apiId = $apiId
                    reachability = $reachability
                    restriction = $restriction.restriction
                    exposure = $exposure
                    callsViaAppGw = $callsViaAppGw
                    callsInternal = $callsInternal
                    confidence = $confidence
                    baseMissingBypass = [bool] $restriction.baseMissingBypass
                    restrictedOperations = @(
                        $restriction.restrictedOperations |
                            Sort-Object -Unique
                    )
                    modelStatus = if ($sortedMissingInputs.Count -eq 0) {
                        'Complete'
                    }
                    else {
                        'Partial'
                    }
                    missingInputs = $sortedMissingInputs
                })
        }
    }
    return @($records | Sort-Object gateway, listener, pattern, apiId)
}

function ConvertTo-ApimApiExposureModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Apis,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $ExposureRecords
    )

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($api in $Apis) {
        $copy = $api | ConvertTo-Json -Depth 100 |
            ConvertFrom-Json -Depth 100
        $apiId = [string] $copy.apiId
        $routes = @($ExposureRecords | Where-Object apiId -EQ $apiId)
        if ($routes.Count -eq 0) {
            throw 'Exposure records were missing an API.'
        }
        $copy.reachability = if (@(
                $routes | Where-Object reachability -EQ 'Reachable'
            ).Count -gt 0) {
            'Reachable'
        }
        elseif (@($routes | Where-Object reachability -EQ 'Unknown').Count `
            -gt 0) {
            'Unknown'
        }
        else {
            'NotRoutable'
        }
        $exposureOrder = @(
            'DirectPublic',
            'ExternalInUse',
            'Unknown',
            'ExternalUnintended',
            'Restricted',
            'Internal'
        )
        $copy.exposure = $null
        foreach ($candidate in $exposureOrder) {
            if (@($routes | Where-Object exposure -EQ $candidate).Count -gt 0) {
                $copy.exposure = $candidate
                break
            }
        }
        $copy.missingInputs = @(
            @(
                $copy.missingInputs |
                    Where-Object { $_ -ne 'exposure' }
                $routes.missingInputs
            ) |
                Sort-Object -Unique
        )
        $copy.modelStatus = if ($copy.missingInputs.Count -eq 0) {
            'Complete'
        }
        else {
            'Partial'
        }
        $records.Add($copy)
    }
    return @($records | Sort-Object apiId)
}

function Write-ApimExposureModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $ExposureRecords,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $ApiRecords
    )

    return Write-ApimModelSet -RunPath $RunPath -Models ([ordered]@{
            exposure = $ExposureRecords
            apis = $ApiRecords
        })
}
