#Requires -Version 7.4

Set-StrictMode -Version Latest

$script:ApimRunSettingsSchemaPath = Join-Path (
    Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
) 'schemas/run-settings.schema.json'

function Test-ApimRunSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Json,

        [Parameter(Mandatory)]
        [object] $Manifest
    )

    if (-not (Test-Json -Json $Json -SchemaFile $script:ApimRunSettingsSchemaPath `
                -ErrorAction Stop)) {
        throw 'Run settings failed schema validation.'
    }
    $settings = ConvertFrom-Json -InputObject $Json -Depth 100 -AsHashtable `
        -ErrorAction Stop
    $expectedVersion = if ($Manifest.schemaVersion -ceq '1.2') { '1.1' } else { '1.0' }
    if ($settings.runId -cne $Manifest.runId -or
        $settings.schemaVersion -cne $expectedVersion -or
        $settings.toolVersion -cne $Manifest.toolVersion -or
        $settings.toolVersion -cne (Get-ApimAssessmentToolVersion) -or
        $settings.usageBuckets[0] -ne 0) {
        throw 'Run settings are incompatible.'
    }
    for ($index = 1; $index -lt $settings.usageBuckets.Count; $index++) {
        if ($settings.usageBuckets[$index] -le $settings.usageBuckets[$index - 1]) {
            throw 'Run usage bands must be strictly increasing.'
        }
    }
    foreach ($cidr in $settings.appGwSubnetCidrs) {
        if ($null -eq (Get-ApimIpv4Range -Value $cidr)) {
            throw 'Run subnet CIDR is invalid.'
        }
    }
    if ($settings.Contains('telemetry')) {
        foreach ($cidr in $settings.telemetry.internalCidrs) {
            if ($null -eq (Get-ApimIpv4Range -Value $cidr)) {
                throw 'Run internal subnet CIDR is invalid.'
            }
        }
    }
    if ($settings.Contains('governance')) {
        $governance = @{}
        if ($settings.governance.Contains('products')) {
            $governance.Products = @(
                foreach ($entry in $settings.governance.products) {
                    @{ ProductId = $entry.productId; HasOwner = $entry.hasOwner; IsExternal = $entry.isExternal }
                }
            )
        }
        if ($settings.governance.Contains('criticalApiIds')) {
            $governance.CriticalApiIds = @($settings.governance.criticalApiIds)
        }
        Test-ConfigGovernance -Value $governance
    }
    if ($settings.Contains('openApiQuality')) {
        Test-ConfigOpenApiQuality -Value @{
            ErrorPenalty = $settings.openApiQuality.errorPenalty
            WarningPenalty = $settings.openApiQuality.warningPenalty
        }
    }
    if ($settings.Contains('portalProductVisibility')) {
        Test-ConfigPortalProductVisibility -Value @(
            foreach ($entry in $settings.portalProductVisibility) {
                @{
                    ProductId = $entry.productId
                    IsPublic = $entry.isPublic
                    IntendedGroupIds = @($entry.intendedGroupIds)
                }
            }
        )
    }
    return $settings
}

function Get-ApimRunSettingSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Config,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Environment,

        [switch] $SkipLogs,

        [switch] $SkipCost
    )

    $manifest = Get-RunManifest -RunPath $RunPath
    $settings = [ordered]@{
        schemaVersion = '1.0'
        runId = $manifest.runId
        toolVersion = $manifest.toolVersion
        appGateways = @(
            foreach ($gateway in $Environment.AppGateways) {
                [ordered]@{ name = $gateway.Name; resourceGroup = $gateway.ResourceGroup }
            }
        )
        appGwSubnetCidrs = @($Config.Network.AppGwSubnetCidrs)
        certExpiryDays = $Config.Thresholds.CertExpiryDays
        criticalBackendIds = @(if ($Config.Contains('RuleTargets')) {
                $Config.RuleTargets.CriticalBackendIds
            })
        approvedPlainHttpBackendIds = @(if ($Config.Contains('RuleExceptions')) {
                $Config.RuleExceptions.ApprovedPlainHttpBackendIds
            })
        approvedPlainHttpOperationKeys = @(if ($Config.Contains('RuleExceptions')) {
                $Config.RuleExceptions.ApprovedPlainHttpOperationKeys
            })
        usageBuckets = @($Config.AnalysisPackage.UsageBuckets)
    }
    if ($manifest.schemaVersion -ceq '1.2') {
        $settings.schemaVersion = '1.1'
        $settings.telemetry = [ordered]@{
            workspaceIds = @($Environment.LogAnalyticsWorkspaceIds |
                    ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique)
            costScopes = @($Environment.CostScopes |
                    ForEach-Object { $_.TrimEnd('/').ToLowerInvariant() } | Sort-Object -Unique)
            logicAppResourceGroups = @($Environment.LogicAppResourceGroups |
                    ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique)
            internalCidrs = @($Config.Network.InternalCidrs | Sort-Object -Unique)
            skipLogs = [bool] $SkipLogs
            skipCost = [bool] $SkipCost
            unusedDays = [int] $Config.Thresholds.UnusedDays
        }
    }
    elseif ($SkipLogs -or $SkipCost) {
        throw 'Telemetry opt-outs cannot change legacy run settings.'
    }
    if ($Config.Contains('Governance')) {
        Test-ConfigGovernance -Value $Config.Governance
        $settings.governance = [ordered]@{}
        if ($Config.Governance.Contains('Products')) {
            $settings.governance.products = @(
                foreach ($entry in $Config.Governance.Products) {
                    [ordered]@{ productId = $entry.ProductId; hasOwner = $entry.HasOwner; isExternal = $entry.IsExternal }
                }
            )
        }
        if ($Config.Governance.Contains('CriticalApiIds')) {
            $settings.governance.criticalApiIds = @($Config.Governance.CriticalApiIds)
        }
    }
    if ($Config.Contains('OpenApiQuality')) {
        Test-ConfigOpenApiQuality -Value $Config.OpenApiQuality
        $settings.openApiQuality = [ordered]@{
            errorPenalty = $Config.OpenApiQuality.ErrorPenalty
            warningPenalty = $Config.OpenApiQuality.WarningPenalty
        }
    }
    if ($Config.Contains('Portal')) {
        Test-ConfigPortalProductVisibility -Value $Config.Portal.ProductVisibility
        $settings.portalProductVisibility = @(
            foreach ($entry in $Config.Portal.ProductVisibility) {
                [ordered]@{
                    productId = $entry.ProductId
                    isPublic = $entry.IsPublic
                    intendedGroupIds = @($entry.IntendedGroupIds | Sort-Object)
                }
            }
        )
    }
    $json = ConvertTo-Json -InputObject $settings -Depth 100 -WarningAction Stop
    $null = Test-ApimRunSetting -Json $json -Manifest $manifest
    return $settings
}

function Save-ApimRunSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Config,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Environment,

        [switch] $SkipLogs,

        [switch] $SkipCost
    )

    $settings = Get-ApimRunSettingSnapshot -RunPath $RunPath -Config $Config `
        -Environment $Environment -SkipLogs:$SkipLogs -SkipCost:$SkipCost
    $json = ConvertTo-Json -InputObject $settings -Depth 100 -WarningAction Stop
    $null = Write-RunFile -RunPath $RunPath `
        -RelativePath 'restricted/run-settings.json' -InputObject $json -Format Text
}

function Get-ApimRunSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunPath
    )

    Test-ConfigPathLink -Path $RunPath -Context 'Saved run'
    $path = Resolve-RunFilePath -RunPath $RunPath `
        -RelativePath 'restricted/run-settings.json'
    Test-ConfigPathLink -Path $path -Context 'Run settings'
    $manifestPath = Resolve-RunFilePath -RunPath $RunPath -RelativePath 'manifest.json'
    Test-ConfigPathLink -Path $manifestPath -Context 'Run manifest'
    $manifest = Get-RunManifest -RunPath $RunPath
    $json = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
    $settings = Test-ApimRunSetting -Json $json -Manifest $manifest
    $scoring = @{}
    foreach ($group in @('Severity', 'Exposure', 'Usage')) {
        $weights = @{}
        foreach ($property in $manifest.scoring.$group.PSObject.Properties) {
            $weights[$property.Name] = $property.Value
        }
        $scoring[$group] = $weights
    }
    $portalConfig = @{}
    if ($settings.Contains('portalProductVisibility')) {
        $portalConfig.ProductVisibility = @(
            foreach ($entry in $settings.portalProductVisibility) {
                @{
                    ProductId = $entry.productId
                    IsPublic = $entry.isPublic
                    IntendedGroupIds = @($entry.intendedGroupIds)
                }
            }
        )
    }
    $result = [pscustomobject]@{
        Settings = $settings
        Manifest = $manifest
        Config = @{
            Edge = @{ Provider = $manifest.edge.provider; Mode = $manifest.edge.mode }
            Scoring = $scoring
            Thresholds = @{ CertExpiryDays = $settings.certExpiryDays }
            RuleTargets = @{ CriticalBackendIds = @($settings.criticalBackendIds) }
            RuleExceptions = @{
                ApprovedPlainHttpBackendIds = @($settings.approvedPlainHttpBackendIds)
                ApprovedPlainHttpOperationKeys = @($settings.approvedPlainHttpOperationKeys)
            }
            AnalysisPackage = @{
                UsageMode = 'Bucketed'
                CostMode = 'RelativeOnly'
                UsageBuckets = @($settings.usageBuckets)
            }
        }
        Environment = @{
            Name = $manifest.environment
            AppGateways = @(
                foreach ($gateway in $settings.appGateways) {
                    @{ Name = $gateway.name; ResourceGroup = $gateway.resourceGroup }
                }
            )
        }
    }
    if ($settings.Contains('governance')) {
        $result.Config.Governance = @{}
        if ($settings.governance.Contains('products')) {
            $result.Config.Governance.Products = @(
                foreach ($entry in $settings.governance.products) {
                    @{ ProductId = $entry.productId; HasOwner = $entry.hasOwner; IsExternal = $entry.isExternal }
                }
            )
        }
        if ($settings.governance.Contains('criticalApiIds')) {
            $result.Config.Governance.CriticalApiIds = @($settings.governance.criticalApiIds)
        }
    }
    if ($settings.Contains('openApiQuality')) {
        $result.Config.OpenApiQuality = @{
            ErrorPenalty = $settings.openApiQuality.errorPenalty
            WarningPenalty = $settings.openApiQuality.warningPenalty
        }
    }
    if ($settings.Contains('portalProductVisibility')) {
        $result.Config.Portal = $portalConfig
    }
    if ($settings.Contains('telemetry')) {
        $result.Config.Windows = @{
            UsageDays = [int] $manifest.windows.usageDays
            SecurityLogDays = [int] $manifest.windows.securityLogDays
            CostMonths = [int] $manifest.windows.costMonths
            MetricDays = [int] $manifest.windows.metricDays
        }
        $result.Config.Thresholds.UnusedDays = [int] $settings.telemetry.unusedDays
        $result.Config.Network = @{
            AppGwSubnetCidrs = @($settings.appGwSubnetCidrs)
            InternalCidrs = @($settings.telemetry.internalCidrs)
        }
        $result.Environment.SubscriptionId = $manifest.subscriptionId
        $result.Environment.ApimResourceGroup = ($manifest.apim.resourceId -split '/')[4]
        $result.Environment.ApimName = ($manifest.apim.resourceId -split '/')[8]
        $result.Environment.LogAnalyticsWorkspaceIds = @($settings.telemetry.workspaceIds)
        $result.Environment.CostScopes = @($settings.telemetry.costScopes)
        $result.Environment.LogicAppResourceGroups = @($settings.telemetry.logicAppResourceGroups)
    }
    return $result
}
