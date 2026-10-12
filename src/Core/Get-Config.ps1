#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-RequiredConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Map,

        [Parameter(Mandatory)]
        [string] $Key,

        [Parameter(Mandatory)]
        [string] $Context
    )

    if (-not $Map.Contains($Key)) {
        throw "Configuration '$Context.$Key' is required."
    }

    Write-Output -InputObject $Map[$Key] -NoEnumerate
}

function Test-ConfigMap {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [string] $Context
    )

    if ($Value -isnot [System.Collections.IDictionary]) {
        throw "Configuration '$Context' must be a hashtable."
    }
}

function Test-ConfigString {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [string] $Context,

        [switch] $AllowEmpty
    )

    if ($Value -isnot [string]) {
        throw "Configuration '$Context' must be a string."
    }
    if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($Value)) {
        throw "Configuration '$Context' cannot be empty."
    }
}

function Test-ConfigStringArray {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [string] $Context,

        [switch] $AllowEmpty
    )

    if ($Value -is [string] -or $Value -isnot [System.Collections.IEnumerable]) {
        throw "Configuration '$Context' must be an array of strings."
    }

    $items = @($Value)
    if (-not $AllowEmpty -and $items.Count -eq 0) {
        throw "Configuration '$Context' must contain at least one value."
    }

    for ($index = 0; $index -lt $items.Count; $index++) {
        Test-ConfigString -Value $items[$index] -Context "$Context[$index]"
    }
}

function Test-ConfigBoolean {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [string] $Context
    )

    if ($Value -isnot [bool]) {
        throw "Configuration '$Context' must be a Boolean."
    }
}

function Test-ConfigNumber {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [string] $Context,

        [double] $Minimum = 0,

        [switch] $ExclusiveMinimum
    )

    $numericTypes = @(
        [byte], [sbyte], [int16], [uint16], [int32], [uint32], [int64], [uint64],
        [single], [double], [decimal]
    )
    if ($null -eq $Value -or $numericTypes -notcontains $Value.GetType()) {
        throw "Configuration '$Context' must be numeric."
    }

    $number = [double] $Value
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) {
        throw "Configuration '$Context' must be a finite number."
    }
    if (($ExclusiveMinimum -and $number -le $Minimum) -or
        (-not $ExclusiveMinimum -and $number -lt $Minimum)) {
        $comparison = if ($ExclusiveMinimum) { 'greater than' } else { 'at least' }
        throw "Configuration '$Context' must be $comparison $Minimum."
    }
}

function Resolve-ConfigPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Context
    )

    Test-ConfigString -Value $Path -Context $Context
    if (-not [System.IO.Path]::IsPathFullyQualified($Path)) {
        throw "Configuration '$Context' must be an absolute path."
    }

    try {
        return [System.IO.Path]::TrimEndingDirectorySeparator(
            [System.IO.Path]::GetFullPath($Path)
        )
    }
    catch {
        throw "Configuration '$Context' is not a valid absolute path."
    }
}

function Test-ConfigPathOverlap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $First,

        [Parameter(Mandatory)]
        [string] $Second
    )

    $comparison = [System.StringComparison]::OrdinalIgnoreCase
    if ([string]::Equals($First, $Second, $comparison)) {
        return $true
    }

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $firstPrefix = "$($First.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        ))$separator"
    $secondPrefix = "$($Second.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        ))$separator"

    return $First.StartsWith($secondPrefix, $comparison) -or
        $Second.StartsWith($firstPrefix, $comparison)
}

function Test-ConfigPathLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Context
    )

    $current = $Path
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            $isReparsePoint = ($item.Attributes -band
                    [System.IO.FileAttributes]::ReparsePoint) -ne 0
            $hasLinkType = $item.PSObject.Properties.Name -contains 'LinkType' -and
                -not [string]::IsNullOrWhiteSpace([string] $item.LinkType)
            if ($isReparsePoint -or $hasLinkType) {
                throw "Configuration '$Context' cannot use a symbolic link or junction."
            }
        }

        $parent = [System.IO.Directory]::GetParent($current)
        if ($null -eq $parent -or
            [string]::Equals(
                $parent.FullName,
                $current,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
            break
        }
        $current = $parent.FullName
    }
}

function Get-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [switch] $AgentAssisted,

        [string[]] $CopilotVisiblePath = @()
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Configuration file '$Path' was not found."
    }
    if ([System.IO.Path]::GetExtension($Path) -ne '.psd1') {
        throw "Configuration file '$Path' must use the .psd1 extension."
    }

    try {
        $config = Import-PowerShellDataFile -LiteralPath $Path -ErrorAction Stop
    }
    catch {
        throw "Configuration file '$Path' is not a valid PowerShell data file."
    }
    Test-ConfigMap -Value $config -Context 'root'

    Test-ConfigString -Value (Get-RequiredConfigValue $config 'Customer' 'root') `
        -Context 'Customer'

    $environmentsValue = Get-RequiredConfigValue $config 'Environments' 'root'
    if ($environmentsValue -is [string] -or
        $environmentsValue -isnot [System.Collections.IEnumerable]) {
        throw "Configuration 'Environments' must be an array of hashtables."
    }
    $environments = @($environmentsValue)
    if ($environments.Count -eq 0) {
        throw "Configuration 'Environments' must contain at least one environment."
    }

    $environmentNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    for ($environmentIndex = 0; $environmentIndex -lt $environments.Count;
        $environmentIndex++) {
        $environment = $environments[$environmentIndex]
        $context = "Environments[$environmentIndex]"
        Test-ConfigMap -Value $environment -Context $context

        $name = Get-RequiredConfigValue $environment 'Name' $context
        Test-ConfigString -Value $name -Context "$context.Name"
        if (-not $environmentNames.Add($name)) {
            throw "Configuration 'Environments' contains duplicate name '$name'."
        }

        $subscriptionId = Get-RequiredConfigValue $environment 'SubscriptionId' $context
        Test-ConfigString -Value $subscriptionId -Context "$context.SubscriptionId"
        $parsedGuid = [guid]::Empty
        if (-not [guid]::TryParse($subscriptionId, [ref] $parsedGuid)) {
            throw "Configuration '$context.SubscriptionId' must be a GUID."
        }

        foreach ($key in @('ApimResourceGroup', 'ApimName', 'GitPolicyRoot')) {
            Test-ConfigString -Value (Get-RequiredConfigValue $environment $key $context) `
                -Context "$context.$key"
        }
        Test-ConfigString -Value (
            Get-RequiredConfigValue $environment 'GitRepoPath' $context
        ) -Context "$context.GitRepoPath" -AllowEmpty

        foreach ($key in @(
                'NetworkResourceGroups',
                'LogAnalyticsWorkspaceIds',
                'CostScopes',
                'LogicAppResourceGroups'
            )) {
            Test-ConfigStringArray -Value (
                Get-RequiredConfigValue $environment $key $context
            ) -Context "$context.$key" -AllowEmpty
        }

        foreach ($workspaceId in @($environment.LogAnalyticsWorkspaceIds)) {
            $parsedWorkspaceId = [guid]::Empty
            if (-not [guid]::TryParse($workspaceId, [ref] $parsedWorkspaceId)) {
                throw "Configuration '$context.LogAnalyticsWorkspaceIds' must contain GUIDs."
            }
        }
        foreach ($costScope in @($environment.CostScopes)) {
            if (-not $costScope.StartsWith('/subscriptions/',
                    [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Configuration '$context.CostScopes' contains an invalid ARM scope."
            }
        }

        $appGatewaysValue = Get-RequiredConfigValue $environment 'AppGateways' $context
        if ($appGatewaysValue -is [string] -or
            $appGatewaysValue -isnot [System.Collections.IEnumerable]) {
            throw "Configuration '$context.AppGateways' must be an array of hashtables."
        }
        $appGateways = @($appGatewaysValue)
        for ($gatewayIndex = 0; $gatewayIndex -lt $appGateways.Count; $gatewayIndex++) {
            $gateway = $appGateways[$gatewayIndex]
            $gatewayContext = "$context.AppGateways[$gatewayIndex]"
            Test-ConfigMap -Value $gateway -Context $gatewayContext
            foreach ($key in @('ResourceGroup', 'Name')) {
                Test-ConfigString -Value (
                    Get-RequiredConfigValue $gateway $key $gatewayContext
                ) -Context "$gatewayContext.$key"
            }
        }
    }

    $edge = Get-RequiredConfigValue $config 'Edge' 'root'
    Test-ConfigMap -Value $edge -Context 'Edge'
    Test-ConfigString -Value (Get-RequiredConfigValue $edge 'Provider' 'Edge') `
        -Context 'Edge.Provider'
    $edgeMode = Get-RequiredConfigValue $edge 'Mode' 'Edge'
    Test-ConfigString -Value $edgeMode -Context 'Edge.Mode'
    if ($edgeMode -notin @('AssumedReachable', 'Collected')) {
        throw "Configuration 'Edge.Mode' must be AssumedReachable or Collected."
    }
    Test-ConfigStringArray -Value (
        Get-RequiredConfigValue $edge 'TrustedEdgeRanges' 'Edge'
    ) -Context 'Edge.TrustedEdgeRanges' -AllowEmpty
    Test-ConfigString -Value (
        Get-RequiredConfigValue $edge 'TrustedEdgeRangesFile' 'Edge'
    ) -Context 'Edge.TrustedEdgeRangesFile' -AllowEmpty

    $network = Get-RequiredConfigValue $config 'Network' 'root'
    Test-ConfigMap -Value $network -Context 'Network'
    Test-ConfigStringArray -Value (
        Get-RequiredConfigValue $network 'AppGwSubnetCidrs' 'Network'
    ) -Context 'Network.AppGwSubnetCidrs' -AllowEmpty
    Test-ConfigStringArray -Value (
        Get-RequiredConfigValue $network 'InternalCidrs' 'Network'
    ) -Context 'Network.InternalCidrs'

    $windows = Get-RequiredConfigValue $config 'Windows' 'root'
    Test-ConfigMap -Value $windows -Context 'Windows'
    foreach ($key in @('UsageDays', 'SecurityLogDays', 'CostMonths', 'MetricDays')) {
        Test-ConfigNumber -Value (Get-RequiredConfigValue $windows $key 'Windows') `
            -Context "Windows.$key" -Minimum 0 -ExclusiveMinimum
    }

    $scoring = Get-RequiredConfigValue $config 'Scoring' 'root'
    Test-ConfigMap -Value $scoring -Context 'Scoring'
    $scoringKeys = @{
        Severity = @('High', 'Medium', 'Low', 'Info')
        Exposure = @(
            'DirectPublic',
            'ExternalInUse',
            'ExternalUnintended',
            'Restricted',
            'Internal',
            'Platform',
            'Unknown'
        )
        Usage = @('InUse', 'Unused', 'NotApplicable')
    }
    foreach ($groupName in $scoringKeys.Keys) {
        $group = Get-RequiredConfigValue $scoring $groupName 'Scoring'
        Test-ConfigMap -Value $group -Context "Scoring.$groupName"
        foreach ($key in $scoringKeys[$groupName]) {
            Test-ConfigNumber -Value (
                Get-RequiredConfigValue $group $key "Scoring.$groupName"
            ) -Context "Scoring.$groupName.$key" -Minimum 0 -ExclusiveMinimum
        }
    }

    $thresholds = Get-RequiredConfigValue $config 'Thresholds' 'root'
    Test-ConfigMap -Value $thresholds -Context 'Thresholds'
    foreach ($key in @(
            'CertExpiryDays',
            'BackendP95Ms',
            'UnusedDays',
            'SubscriptionStaleDays',
            'MaxWriteRolePrincipals'
        )) {
        Test-ConfigNumber -Value (
            Get-RequiredConfigValue $thresholds $key 'Thresholds'
        ) -Context "Thresholds.$key" -Minimum 0 -ExclusiveMinimum
    }
    Test-ConfigNumber -Value (
        Get-RequiredConfigValue $thresholds 'Error5xxPct' 'Thresholds'
    ) -Context 'Thresholds.Error5xxPct' -Minimum 0

    $privacy = Get-RequiredConfigValue $config 'Privacy' 'root'
    Test-ConfigMap -Value $privacy -Context 'Privacy'
    foreach ($key in @('StoreUserIdentities', 'RedactPolicySecrets')) {
        Test-ConfigBoolean -Value (Get-RequiredConfigValue $privacy $key 'Privacy') `
            -Context "Privacy.$key"
    }

    $analysisPackage = Get-RequiredConfigValue $config 'AnalysisPackage' 'root'
    Test-ConfigMap -Value $analysisPackage -Context 'AnalysisPackage'
    $usageMode = Get-RequiredConfigValue $analysisPackage 'UsageMode' 'AnalysisPackage'
    Test-ConfigString -Value $usageMode -Context 'AnalysisPackage.UsageMode'
    if ($usageMode -ne 'Bucketed') {
        throw "Configuration 'AnalysisPackage.UsageMode' must be Bucketed."
    }
    $costMode = Get-RequiredConfigValue $analysisPackage 'CostMode' 'AnalysisPackage'
    Test-ConfigString -Value $costMode -Context 'AnalysisPackage.CostMode'
    if ($costMode -ne 'RelativeOnly') {
        throw "Configuration 'AnalysisPackage.CostMode' must be RelativeOnly."
    }

    $usageBucketsValue = Get-RequiredConfigValue $analysisPackage 'UsageBuckets' `
        'AnalysisPackage'
    if ($usageBucketsValue -is [string] -or
        $usageBucketsValue -isnot [System.Collections.IEnumerable]) {
        throw "Configuration 'AnalysisPackage.UsageBuckets' must be a numeric array."
    }
    $usageBuckets = @($usageBucketsValue)
    if ($usageBuckets.Count -lt 2) {
        throw "Configuration 'AnalysisPackage.UsageBuckets' must contain at least two values."
    }
    $previousBucket = $null
    for ($bucketIndex = 0; $bucketIndex -lt $usageBuckets.Count; $bucketIndex++) {
        $bucket = $usageBuckets[$bucketIndex]
        Test-ConfigNumber -Value $bucket `
            -Context "AnalysisPackage.UsageBuckets[$bucketIndex]" -Minimum 0
        if ($null -ne $previousBucket -and [double] $bucket -le [double] $previousBucket) {
            throw "Configuration 'AnalysisPackage.UsageBuckets' must be strictly ascending."
        }
        $previousBucket = $bucket
    }
    if ([double] $usageBuckets[0] -ne 0) {
        throw "Configuration 'AnalysisPackage.UsageBuckets' must start at zero."
    }

    $output = Get-RequiredConfigValue $config 'Output' 'root'
    Test-ConfigMap -Value $output -Context 'Output'
    $restrictedRoot = Resolve-ConfigPath -Path (
        Get-RequiredConfigValue $output 'Root' 'Output'
    ) -Context 'Output.Root'
    $modelSafeRoot = Resolve-ConfigPath -Path (
        Get-RequiredConfigValue $output 'ModelSafeRoot' 'Output'
    ) -Context 'Output.ModelSafeRoot'

    Test-ConfigPathLink -Path $restrictedRoot -Context 'Output.Root'
    Test-ConfigPathLink -Path $modelSafeRoot -Context 'Output.ModelSafeRoot'
    if (Test-ConfigPathOverlap -First $restrictedRoot -Second $modelSafeRoot) {
        throw "Configuration output roots cannot overlap."
    }

    if ($AgentAssisted) {
        $visiblePaths = @($CopilotVisiblePath |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($visiblePaths.Count -eq 0) {
            throw 'Agent-assisted validation requires at least one Copilot-visible path.'
        }

        foreach ($visiblePath in $visiblePaths) {
            $resolvedVisiblePath = Resolve-ConfigPath -Path $visiblePath `
                -Context 'CopilotVisiblePath'
            Test-ConfigPathLink -Path $resolvedVisiblePath -Context 'CopilotVisiblePath'
            if (Test-ConfigPathOverlap -First $restrictedRoot `
                    -Second $resolvedVisiblePath) {
                throw "Configuration 'Output.Root' must be outside every Copilot-visible path."
            }
        }
    }

    $config.Output.Root = $restrictedRoot
    $config.Output.ModelSafeRoot = $modelSafeRoot
    return $config
}
