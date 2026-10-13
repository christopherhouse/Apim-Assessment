#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimNetworkPayloadItemCollection {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Payload,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context
    )

    if ($null -eq $Payload) {
        return $null
    }
    $value = Get-ApimModelValue -InputObject $Payload -Name value `
        -Context $Context
    return @($value)
}

function Get-ApimNetworkResourceId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Resource,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context
    )

    $id = [string] (Get-ApimModelValue -InputObject $Resource -Name id `
            -Context $Context)
    if ([string]::IsNullOrWhiteSpace($id)) {
        throw "$Context contained an invalid resource ID."
    }
    return $id
}

function Get-ApimNetworkResourceName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Resource,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context
    )

    $name = [string] (Get-ApimModelValue -InputObject $Resource -Name name `
            -Context $Context)
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw "$Context contained an invalid resource name."
    }
    return $name
}

function Test-ApimNsgPort443 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Properties
    )

    $ranges = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @('destinationPortRange', 'destinationPortRanges')) {
        foreach ($range in @(
                Get-ApimModelValue -InputObject $Properties -Name $name `
                    -Context 'NSG rule properties' -AllowMissing
            )) {
            if ($null -ne $range) {
                $ranges.Add([string] $range)
            }
        }
    }
    foreach ($range in $ranges) {
        $normalized = $range.Trim()
        if ($normalized -eq '*' -or $normalized -eq '443') {
            return $true
        }
        if ($normalized -match '^(\d+)-(\d+)$' -and
            [int] $Matches[1] -le 443 -and
            [int] $Matches[2] -ge 443) {
            return $true
        }
    }
    return $false
}

function Test-ApimNsgBroadSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Properties
    )

    foreach ($name in @('sourceAddressPrefix', 'sourceAddressPrefixes')) {
        foreach ($prefix in @(
                Get-ApimModelValue -InputObject $Properties -Name $name `
                    -Context 'NSG rule properties' -AllowMissing
            )) {
            if ([string] $prefix -in @(
                    '*',
                    'Internet',
                    '0.0.0.0/0',
                    '::/0'
                )) {
                return $true
            }
        }
    }
    return $false
}

function Get-ApimNsgAssessment {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Subnet,

        [AllowNull()]
        [object] $NsgPayload
    )

    if ($null -eq $Subnet) {
        return [pscustomobject]@{
            evaluation = 'Unknown'
            name = $null
            missingInput = 'apimSubnet'
        }
    }
    $subnetProperties = Get-ApimModelValue -InputObject $Subnet `
        -Name properties -Context 'APIM subnet'
    $networkSecurityGroup = Get-ApimModelValue `
        -InputObject $subnetProperties -Name networkSecurityGroup `
        -Context 'APIM subnet properties' -AllowMissing
    if ($null -eq $networkSecurityGroup) {
        return [pscustomobject]@{
            evaluation = 'Missing'
            name = $null
            missingInput = $null
        }
    }
    $nsgId = [string] (Get-ApimModelValue `
            -InputObject $networkSecurityGroup -Name id `
            -Context 'APIM subnet network security group')
    if ([string]::IsNullOrWhiteSpace($nsgId)) {
        throw 'APIM subnet contained an invalid network security group ID.'
    }
    if ($null -eq $NsgPayload) {
        return [pscustomobject]@{
            evaluation = 'Unknown'
            name = $null
            missingInput = 'nsgs'
        }
    }

    $matchingNsgs = @(
        foreach ($resource in @(
                Get-ApimNetworkPayloadItemCollection -Payload $NsgPayload `
                    -Context 'Network security group payload'
            )) {
            $resourceId = Get-ApimNetworkResourceId -Resource $resource `
                -Context 'Network security group'
            if ($resourceId.Equals(
                    $nsgId,
                    [System.StringComparison]::OrdinalIgnoreCase
                )) {
                $resource
            }
        }
    )
    if ($matchingNsgs.Count -ne 1) {
        return [pscustomobject]@{
            evaluation = 'Unknown'
            name = $null
            missingInput = 'nsgs'
        }
    }

    $nsg = $matchingNsgs[0]
    $nsgProperties = Get-ApimModelValue -InputObject $nsg -Name properties `
        -Context 'Network security group'
    $candidateRules = [System.Collections.Generic.List[object]]::new()
    foreach ($collectionName in @('securityRules', 'defaultSecurityRules')) {
        foreach ($rule in @(
                Get-ApimModelValue -InputObject $nsgProperties `
                    -Name $collectionName -Context 'Network security group properties' `
                    -AllowMissing
            )) {
            if ($null -ne $rule) {
                $properties = Get-ApimModelValue -InputObject $rule `
                    -Name properties -Context 'Network security group rule'
                $direction = [string] (Get-ApimModelValue `
                        -InputObject $properties -Name direction `
                        -Context 'Network security group rule properties')
                $protocol = [string] (Get-ApimModelValue `
                        -InputObject $properties -Name protocol `
                        -Context 'Network security group rule properties')
                if ($direction -ieq 'Inbound' -and
                    $protocol -in @('*', 'Tcp') -and
                    (Test-ApimNsgPort443 -Properties $properties) -and
                    (Test-ApimNsgBroadSource -Properties $properties)) {
                    $priority = [int] (Get-ApimModelValue `
                            -InputObject $properties -Name priority `
                            -Context 'Network security group rule properties')
                    $access = [string] (Get-ApimModelValue `
                            -InputObject $properties -Name access `
                            -Context 'Network security group rule properties')
                    $candidateRules.Add([pscustomobject]@{
                            priority = $priority
                            access = $access
                        })
                }
            }
        }
    }

    $effectiveRule = $candidateRules |
        Sort-Object priority |
        Select-Object -First 1
    $evaluation = if ($null -ne $effectiveRule -and
        $effectiveRule.access -ieq 'Allow') {
        'Broad'
    }
    else {
        'Restricted'
    }
    return [pscustomobject]@{
        evaluation = $evaluation
        name = Get-ApimNetworkResourceName -Resource $nsg `
            -Context 'Network security group'
        missingInput = $null
    }
}

function Get-ApimAppGatewayTlsAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $AppGateways
    )

    $statuses = [System.Collections.Generic.List[string]]::new()
    $policyNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($gateway in $AppGateways) {
        $properties = Get-ApimModelValue -InputObject $gateway `
            -Name properties -Context 'Application Gateway'
        $sslPolicy = Get-ApimModelValue -InputObject $properties `
            -Name sslPolicy -Context 'Application Gateway properties' `
            -AllowMissing
        if ($null -eq $sslPolicy) {
            $statuses.Add('Unknown')
            continue
        }
        $policyName = [string] (Get-ApimModelValue `
                -InputObject $sslPolicy -Name policyName `
                -Context 'Application Gateway SSL policy' -AllowMissing)
        if (-not [string]::IsNullOrWhiteSpace($policyName)) {
            $null = $policyNames.Add($policyName)
        }
        $minimumProtocol = [string] (Get-ApimModelValue `
                -InputObject $sslPolicy -Name minProtocolVersion `
                -Context 'Application Gateway SSL policy' -AllowMissing)
        if ($minimumProtocol -in @('TLSv1_0', 'TLSv1_1')) {
            $statuses.Add('Weak')
            continue
        }
        if ($policyName -match '^AppGwSslPolicy(\d{8})' -and
            [int] $Matches[1] -lt 20220101) {
            $statuses.Add('Weak')
            continue
        }
        if ($minimumProtocol -in @('TLSv1_2', 'TLSv1_3') -or
            (
                $policyName -match '^AppGwSslPolicy(\d{8})' -and
                [int] $Matches[1] -ge 20220101
            )) {
            $statuses.Add('Strong')
            continue
        }
        $statuses.Add('Unknown')
    }

    $status = if ($statuses -contains 'Weak') {
        'Weak'
    }
    elseif ($statuses.Count -gt 0 -and $statuses -notcontains 'Unknown') {
        'Strong'
    }
    else {
        'Unknown'
    }
    return [pscustomobject]@{
        status = $status
        policyNames = @($policyNames | Sort-Object)
    }
}

function Get-ApimWafAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $AppGateways,

        [AllowNull()]
        [object[]] $WafPolicies
    )

    $policyById = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    if ($null -ne $WafPolicies) {
        foreach ($policy in $WafPolicies) {
            $policyById.Add(
                (Get-ApimNetworkResourceId -Resource $policy `
                    -Context 'Application Gateway WAF policy'),
                $policy
            )
        }
    }

    $states = [System.Collections.Generic.List[string]]::new()
    $modes = [System.Collections.Generic.List[string]]::new()
    $missingPolicy = $false
    foreach ($gateway in $AppGateways) {
        $properties = Get-ApimModelValue -InputObject $gateway `
            -Name properties -Context 'Application Gateway'
        $policyLink = Get-ApimModelValue -InputObject $properties `
            -Name firewallPolicy -Context 'Application Gateway properties' `
            -AllowMissing
        if ($null -ne $policyLink) {
            $policyId = [string] (Get-ApimModelValue `
                    -InputObject $policyLink -Name id `
                    -Context 'Application Gateway firewall policy')
            if ($null -eq $WafPolicies -or
                -not $policyById.ContainsKey($policyId)) {
                $states.Add('Unknown')
                $modes.Add('Unknown')
                $missingPolicy = $true
                continue
            }
            $policyProperties = Get-ApimModelValue `
                -InputObject $policyById[$policyId] -Name properties `
                -Context 'Application Gateway WAF policy'
            $settings = Get-ApimModelValue -InputObject $policyProperties `
                -Name policySettings `
                -Context 'Application Gateway WAF policy properties'
            $state = [string] (Get-ApimModelValue `
                    -InputObject $settings -Name state `
                    -Context 'Application Gateway WAF policy settings')
            $mode = [string] (Get-ApimModelValue `
                    -InputObject $settings -Name mode `
                    -Context 'Application Gateway WAF policy settings')
            if ($state -notin @('Enabled', 'Disabled') -or
                $mode -notin @('Prevention', 'Detection')) {
                throw 'Application Gateway WAF policy settings were unsupported.'
            }
            $states.Add($state)
            $modes.Add($mode)
            continue
        }

        $legacy = Get-ApimModelValue -InputObject $properties `
            -Name webApplicationFirewallConfiguration `
            -Context 'Application Gateway properties' -AllowMissing
        if ($null -eq $legacy) {
            $states.Add('Disabled')
            $modes.Add('Unknown')
            continue
        }
        $enabled = Get-ApimModelValue -InputObject $legacy -Name enabled `
            -Context 'Application Gateway legacy WAF configuration'
        if ($enabled -isnot [bool]) {
            throw 'Application Gateway legacy WAF enabled value was not Boolean.'
        }
        $states.Add($(if ($enabled) { 'Enabled' } else { 'Disabled' }))
        $mode = [string] (Get-ApimModelValue -InputObject $legacy `
                -Name firewallMode `
                -Context 'Application Gateway legacy WAF configuration' `
                -AllowMissing)
        $modes.Add($(if ([string]::IsNullOrWhiteSpace($mode)) {
                    'Unknown'
                }
                else {
                    $mode
                }))
    }

    $state = if ($states -contains 'Disabled') {
        'Disabled'
    }
    elseif ($states.Count -gt 0 -and $states -notcontains 'Unknown') {
        'Enabled'
    }
    else {
        'Unknown'
    }
    $mode = if ($modes -contains 'Detection') {
        'Detection'
    }
    elseif ($modes.Count -gt 0 -and $modes -notcontains 'Unknown') {
        'Prevention'
    }
    else {
        'Unknown'
    }
    return [pscustomobject]@{
        state = $state
        mode = $mode
        missingPolicy = $missingPolicy
    }
}

function Get-ApimTargetingNetworkResourceAssessment {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Payload,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context,

        [Parameter(Mandatory)]
        [ValidateSet('Boolean', 'Classification')]
        [string] $Mode
    )

    if ($null -eq $Payload) {
        return $null
    }
    $names = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $complete = $true
    foreach ($resource in @(
            Get-ApimNetworkPayloadItemCollection `
                -Payload $Payload -Context $Context
        )) {
        $targetsApim = $false
        if ($Mode -eq 'Boolean') {
            $targetProperty = Get-ApimModelValue -InputObject $resource `
                -Name targetsApim -Context $Context -AllowMissing
            if ($null -eq $targetProperty) {
                $complete = $false
                continue
            }
            if ($targetProperty -isnot [bool]) {
                throw "$Context field 'targetsApim' was not Boolean."
            }
            $targetsApim = [bool] $targetProperty
        }
        else {
            $classification = [string] (Get-ApimModelValue `
                    -InputObject $resource -Name targetClassification `
                    -Context $Context -AllowMissing)
            if ($classification -notin @(
                    'TargetsApim',
                    'KnownOther',
                    'Unknown'
                )) {
                throw "$Context contained an invalid target classification."
            }
            if ($classification -eq 'Unknown') {
                $complete = $false
                continue
            }
            $targetsApim = $classification -eq 'TargetsApim'
        }
        if ($targetsApim) {
            $null = $names.Add((Get-ApimNetworkResourceName `
                        -Resource $resource -Context $Context))
        }
    }
    return [pscustomobject]@{
        names = @($names | Sort-Object)
        complete = $complete
    }
}

function Get-ApimNetworkModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Service,

        [AllowNull()]
        [object[]] $AppGateways,

        [AllowNull()]
        [object[]] $WafPolicies,

        [AllowNull()]
        [object] $ApimSubnetPayload,

        [AllowNull()]
        [object] $NsgPayload,

        [AllowNull()]
        [object] $PublicIpPayload,

        [AllowNull()]
        [object] $FrontDoorPayload,

        [AllowNull()]
        [System.Collections.IDictionary] $OperatorEvidence
    )

    $missingInputs = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $serviceProperties = Get-ApimModelValue -InputObject $Service `
        -Name properties -Context 'APIM service'
    $virtualNetworkType = [string] (Get-ApimModelValue `
            -InputObject $serviceProperties -Name virtualNetworkType `
            -Context 'APIM service properties')
    if ($virtualNetworkType -notin @('None', 'External', 'Internal')) {
        throw 'APIM service virtual network type was unsupported.'
    }
    $publicNetworkAccessValue = Get-ApimModelValue `
        -InputObject $serviceProperties -Name publicNetworkAccess `
        -Context 'APIM service properties' -AllowMissing
    $publicNetworkAccess = if ($null -eq $publicNetworkAccessValue -or
        [string]::IsNullOrWhiteSpace([string] $publicNetworkAccessValue)) {
        $null = $missingInputs.Add('publicNetworkAccess')
        $null
    }
    else {
        [string] $publicNetworkAccessValue
    }
    if ($null -ne $publicNetworkAccess -and
        $publicNetworkAccess -notin @('Enabled', 'Disabled')) {
        throw 'APIM service public network access was unsupported.'
    }

    $subnetItems = if ($null -eq $ApimSubnetPayload) {
        $null
    }
    else {
        @(Get-ApimNetworkPayloadItemCollection `
                -Payload $ApimSubnetPayload -Context 'APIM subnet payload')
    }
    $subnet = if ($null -eq $subnetItems -or $subnetItems.Count -eq 0) {
        $null
    }
    elseif ($subnetItems.Count -eq 1) {
        $subnetItems[0]
    }
    else {
        throw 'APIM subnet payload contained more than one resource.'
    }
    $apimSubnetId = if ($null -eq $subnet) {
        $null
    }
    else {
        Get-ApimNetworkResourceId -Resource $subnet -Context 'APIM subnet'
    }
    $nsgAssessment = Get-ApimNsgAssessment `
        -Subnet $subnet -NsgPayload $NsgPayload
    if ($null -ne $nsgAssessment.missingInput) {
        $null = $missingInputs.Add([string] $nsgAssessment.missingInput)
    }

    $gatewayNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    if ($null -eq $AppGateways) {
        $null = $missingInputs.Add('appGateways')
        $effectiveAppGateways = @()
        $outputAppGateways = $null
    }
    else {
        $effectiveAppGateways = @($AppGateways)
        $outputAppGateways = @()
    }
    foreach ($gateway in $effectiveAppGateways) {
        $null = $gatewayNames.Add((Get-ApimNetworkResourceName `
                    -Resource $gateway -Context 'Application Gateway'))
    }
    if ($null -ne $outputAppGateways) {
        $outputAppGateways = @($gatewayNames | Sort-Object)
    }
    $tlsAssessment = Get-ApimAppGatewayTlsAssessment `
        -AppGateways $effectiveAppGateways
    if ($tlsAssessment.status -eq 'Unknown') {
        $null = $missingInputs.Add('appGatewayTlsPolicy')
    }
    $wafAssessment = Get-ApimWafAssessment `
        -AppGateways $effectiveAppGateways -WafPolicies $WafPolicies
    if ($wafAssessment.missingPolicy) {
        $null = $missingInputs.Add('wafPolicies')
    }

    $frontDoorAssessment = Get-ApimTargetingNetworkResourceAssessment `
        -Payload $FrontDoorPayload -Context 'Other front door payload' `
        -Mode Boolean
    if ($null -eq $frontDoorAssessment) {
        $null = $missingInputs.Add('frontDoors')
        $otherFrontDoors = @()
        $outputOtherFrontDoors = $null
    }
    else {
        $otherFrontDoors = @($frontDoorAssessment.names)
        $outputOtherFrontDoors = $otherFrontDoors
        if (-not $frontDoorAssessment.complete) {
            $null = $missingInputs.Add('frontDoorTargets')
        }
    }
    $publicIpAssessment = Get-ApimTargetingNetworkResourceAssessment `
        -Payload $PublicIpPayload -Context 'Public IP payload' `
        -Mode Classification
    if ($null -eq $publicIpAssessment) {
        $null = $missingInputs.Add('publicIps')
        $otherPublicIpRoutes = @()
        $outputOtherPublicIpRoutes = $null
    }
    else {
        $otherPublicIpRoutes = @($publicIpAssessment.names)
        $outputOtherPublicIpRoutes = $otherPublicIpRoutes
        if (-not $publicIpAssessment.complete) {
            $null = $missingInputs.Add('publicIpRoutes')
        }
    }

    $reasons = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    if ($virtualNetworkType -in @('None', 'External')) {
        $null = $reasons.Add('PublicVNetMode')
    }
    if ($publicNetworkAccess -eq 'Enabled' -and
        $virtualNetworkType -ne 'Internal') {
        $null = $reasons.Add('PublicNetworkAccess')
    }
    if ($nsgAssessment.evaluation -eq 'Broad') {
        $null = $reasons.Add('BroadNsg443')
    }
    if ($otherFrontDoors.Count -gt 0) {
        $null = $reasons.Add('OtherFrontDoor')
    }
    if ($otherPublicIpRoutes.Count -gt 0) {
        $null = $reasons.Add('PublicIpRoute')
    }

    $directPublic = if ($reasons.Count -gt 0) {
        $true
    }
    elseif ($virtualNetworkType -eq 'Internal' -and
        $nsgAssessment.evaluation -eq 'Restricted' -and
        $null -ne $frontDoorAssessment -and
        $frontDoorAssessment.complete -and
        $null -ne $publicIpAssessment -and
        $publicIpAssessment.complete) {
        $false
    }
    else {
        $null
    }
    if ($null -eq $directPublic) {
        $null = $missingInputs.Add('directPublicEvidence')
    }

    $edgeOriginAssessment = $null
    $auxiliaryRoutes = $null
    if ($null -ne $OperatorEvidence) {
        $expectedKeys = @('edgeRangesOnly', 'originAuthentication', 'auxiliaryRoutes')
        if ($OperatorEvidence.Count -ne $expectedKeys.Count -or
            @($OperatorEvidence.Keys | Where-Object {
                    $_ -isnot [string] -or $_ -cnotin $expectedKeys
                }).Count -gt 0) {
            throw 'Network operator evidence has an invalid contract.'
        }
        $edgeRangesOnly = $OperatorEvidence['edgeRangesOnly']
        $originAuthentication = $OperatorEvidence['originAuthentication']
        if (($null -ne $edgeRangesOnly -and $edgeRangesOnly -isnot [bool]) -or
            $originAuthentication -cnotin @('Present', 'Absent', 'Unknown')) {
            throw 'Network edge/origin evidence has an invalid contract.'
        }
        if ($edgeRangesOnly -eq $true -and $null -ne $outputAppGateways -and
            $outputAppGateways.Count -eq 0) {
            throw 'Edge-only ingress cannot be attested without an Application Gateway.'
        }
        $edgeOriginAssessment = [pscustomobject] [ordered]@{
            edgeRangesOnly = $edgeRangesOnly
            originAuthentication = $originAuthentication
            source = 'OperatorAttestation'
        }

        if ($null -ne $OperatorEvidence['auxiliaryRoutes']) {
            if ($OperatorEvidence['auxiliaryRoutes'] -isnot [array]) {
                throw 'Network auxiliary route evidence must be an array.'
            }
            $routes = [System.Collections.Generic.SortedDictionary[string, object]]::new(
                [System.StringComparer]::Ordinal
            )
            foreach ($route in $OperatorEvidence['auxiliaryRoutes']) {
                if ($route -isnot [System.Collections.IDictionary] -or
                    $route.Count -ne 4 -or
                    @($route.Keys | Where-Object {
                            $_ -isnot [string] -or
                            $_ -cnotin @('routeKey', 'endpointType',
                                'publicListener', 'ownerNeed')
                        }).Count -gt 0 -or
                    $route['routeKey'] -isnot [string] -or
                    [string]::IsNullOrWhiteSpace($route['routeKey']) -or
                    $route['endpointType'] -cnotin @('Portal', 'Management') -or
                    $route['publicListener'] -isnot [bool] -or
                    $route['ownerNeed'] -cnotin @(
                        'Needed', 'NotNeeded', 'Unknown'
                    )) {
                    throw 'Network auxiliary route evidence has an invalid contract.'
                }
                if ($routes.ContainsKey($route['routeKey'])) {
                    throw 'Network auxiliary route evidence has duplicate route keys.'
                }
                $routes.Add($route['routeKey'], [pscustomobject] [ordered]@{
                        routeKey = $route['routeKey']
                        endpointType = $route['endpointType']
                        publicListener = $route['publicListener']
                        ownerNeed = $route['ownerNeed']
                        source = 'OperatorAttestation'
                    })
            }
            $auxiliaryRoutes = @($routes.Values)
        }
    }

    [string[]] $sortedMissingInputs = @($missingInputs)
    [System.Array]::Sort(
        $sortedMissingInputs,
        [System.StringComparer]::Ordinal
    )
    return [pscustomobject] [ordered]@{
        virtualNetworkType = $virtualNetworkType
        publicNetworkAccess = $publicNetworkAccess
        apimSubnetId = $apimSubnetId
        nsgName = $nsgAssessment.name
        nsgEvaluation = $nsgAssessment.evaluation
        directPublic = $directPublic
        directPublicReasons = @($reasons | Sort-Object)
        appGateways = $outputAppGateways
        appGatewayTlsPolicy = $tlsAssessment.status
        appGatewayTlsPolicyNames = $tlsAssessment.policyNames
        wafState = $wafAssessment.state
        wafMode = $wafAssessment.mode
        otherFrontDoors = $outputOtherFrontDoors
        otherPublicIpRoutes = $outputOtherPublicIpRoutes
        edgeOriginAssessment = $edgeOriginAssessment
        auxiliaryRoutes = $auxiliaryRoutes
        modelStatus = $(if ($sortedMissingInputs.Count -eq 0) {
                'Complete'
            }
            else {
                'Partial'
            })
        missingInputs = $sortedMissingInputs
    }
}

function Write-ApimNetworkModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Record
    )

    return Write-ApimModelSet -RunPath $RunPath `
        -Models ([ordered]@{ network = $Record })
}
