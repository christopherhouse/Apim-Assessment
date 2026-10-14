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
    if ($settings.runId -cne $Manifest.runId -or
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
        [System.Collections.IDictionary] $Environment
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
        [System.Collections.IDictionary] $Environment
    )

    $settings = Get-ApimRunSettingSnapshot -RunPath $RunPath -Config $Config `
        -Environment $Environment
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
    return [pscustomobject]@{
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
}
