function New-SyntheticTelemetryRun {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $OutputRoot
    )

    if (-not $PSCmdlet.ShouldProcess($OutputRoot, 'Create synthetic telemetry evidence')) { return }
    . (Join-Path $RepoRoot 'tests/helpers/New-SyntheticCollectedRun.ps1')
    $inputRun = New-SyntheticCollectedRun -RepoRoot $RepoRoot -OutputRoot $OutputRoot -IncludeTelemetry
    $path = $inputRun.Run.Path
    $config = $inputRun.Config
    $config.Windows.MetricDays = 1
    $config.Windows.CostMonths = 2
    $config.Environments[0].CostScopes = @("/subscriptions/$($config.Environments[0].SubscriptionId)")
    $manifest = Get-RunManifest -RunPath $path
    $manifest.windows.metricDays = 1
    $manifest.windows.costMonths = 2
    $null = Save-RunManifest -RunPath $path -Manifest $manifest
    Save-ApimRunSetting -RunPath $path -Config $config -Environment $config.Environments[0]
    $workspace = $config.Environments[0].LogAnalyticsWorkspaceIds[0]
    $service = Read-ApimSmokeOutputJson -RunPath $path -RelativePath raw/service.json
    $service | Add-Member -NotePropertyName sku -NotePropertyValue @{ name = 'Premium'; capacity = 2 } -Force
    $null = Write-RunFile -RunPath $path -RelativePath raw/service.json -InputObject $service
    $metadata = @{
        schemaVersion = '1.0'
        workspaces = @(@{
            workspaceId = $workspace
            resourceId = "/subscriptions/$($manifest.subscriptionId)/resourceGroups/rg-example-prod/providers/Microsoft.OperationalInsights/workspaces/la-synthetic"
            retentionDays = 180; schema = 'ResourceSpecific'; mixed = $false
            tables = @(
                @{ name = 'ApiManagementGatewayLogs'; retentionDays = 180 }
                @{ name = 'Usage'; retentionDays = 180 }
            )
        })
    }
    $null = Write-RunFile -RunPath $path -RelativePath logs/workspaces.json -InputObject $metadata
    foreach ($kind in @('Usage', 'Security', 'Ingestion')) {
        $length = if ($kind -ceq 'Security') { $manifest.windows.securityLogDays } else { $manifest.windows.usageDays }
        $window = Get-ApimEvidenceWindow -EndUtc $manifest.startedUtc -Kind $kind -Length $length -RetentionDays 180
        Set-ApimEvidenceWindow -RunPath $path -Kind $kind -Target $workspace -Window $window `
            -Schema $(if ($kind -ceq 'Ingestion') { 'NotApplicable' } else { 'ResourceSpecific' }) `
            -Status Completed -Reason None
    }
    $files = @('logs/workspaces.json')
    $count = 0
    foreach ($kind in @('usageByApi', 'usageByRoute', 'usageMonthly', 'tls', 'noSubscriptionCalls', 'laIngestion')) {
        $rows = switch ($kind) {
            usageMonthly {
                @(
                    @{ apiId = 'orders-v1'; month = '2026-08-01'; calls = 1000000 }
                    @{ apiId = 'orders-v1'; month = '2026-09-01'; calls = 1000000 }
                )
            }
            laIngestion {
                @(
                    @{ dataType = 'ApiManagementGatewayLogs'; day = '2026-08-01'; gb = 10.0 }
                    @{ dataType = 'ApiManagementGatewayLogs'; day = '2026-09-01'; gb = 20.0 }
                )
            }
            default { @() }
        }
        $relative = if ($kind -ceq 'laIngestion') { 'cost/laIngestion.json' } else { "logs/$kind.json" }
        $null = Write-RunFile -RunPath $path -RelativePath $relative -InputObject @{
            schemaVersion = '1.0'; kind = $kind
            workspaces = @(@{ workspaceId = $workspace; status = 'Completed'; rows = @($rows) })
        }
        $files += $relative; $count += @($rows).Count
    }
    Set-RunCollectorStatus -RunPath $path -Name LogAnalytics -Status Completed -Items $count -Files $files
    $window = Get-ApimEvidenceWindow -EndUtc $manifest.startedUtc -Kind Metric -Length 1
    foreach ($kind in @('Apim', 'AppGateway')) {
        $id = if ($kind -ceq 'Apim') { $manifest.apim.resourceId } else {
            '/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Network/applicationGateways/{2}' -f
                $manifest.subscriptionId, $config.Environments[0].AppGateways[0].ResourceGroup,
                $config.Environments[0].AppGateways[0].Name
        }
        $metrics = @(
            foreach ($definition in Get-ApimMetricDefinition -Kind $kind) {
                $expected = if ($definition.Interval -ceq 'P1D') { 1 } else { 24 }
                $points = @(
                    for ($index = 0; $index -lt $expected; $index++) {
                        $point = [ordered]@{
                            timestamp = ([datetimeoffset] $window.startUtc).AddHours($index).ToString('O')
                            average = $null; maximum = $null; total = $null
                        }
                        foreach ($aggregation in $definition.Aggregations) {
                            $point[$aggregation.ToLowerInvariant()] = if ($aggregation -ceq 'Maximum') { 40.0 + $index } else { [double] $index }
                        }
                        [pscustomobject] $point
                    }
                )
                [pscustomobject]@{
                    name = $definition.Name; unit = $definition.Unit; interval = $definition.Interval
                    status = 'Completed'; expectedPoints = $expected; points = $points
                }
            }
        )
        $relative = if ($kind -ceq 'Apim') { 'metrics/apim.json' } else { 'metrics/appgw.json' }
        $null = Write-RunFile -RunPath $path -RelativePath $relative -InputObject @{
            schemaVersion = '1.0'; resources = @(@{ resourceId = $id; metrics = $metrics })
        }
        Set-ApimEvidenceWindow -RunPath $path -Kind Metric -Target $id -Window $window `
            -Schema NotApplicable -Status Completed -Reason None
    }
    Set-RunCollectorStatus -RunPath $path -Name Metrics -Status Completed -Items 145 `
        -Files @('metrics/apim.json', 'metrics/appgw.json')
    $logicId = "/subscriptions/$($manifest.subscriptionId)/resourceGroups/rg-example-prod/providers/Microsoft.Logic/workflows/logic-synthetic"
    $logicMetrics = @(
        foreach ($definition in Get-ApimMetricDefinition -Kind LogicConsumption) {
            @{
                name = $definition.Name; unit = $definition.Unit; interval = $definition.Interval
                expectedPoints = 1; status = 'Completed'
                points = @(@{ timestamp = $window.startUtc; average = $null; maximum = $null; total = 1000.0 })
            }
        }
    )
    $null = Write-RunFile -RunPath $path -RelativePath cost/logicApps.json -InputObject @{
        schemaVersion = '1.0'
        groups = @(@{
            resourceGroup = 'rg-example-prod'; status = 'Completed'
            resources = @(@{
                resourceId = $logicId.ToLowerInvariant(); kind = 'Consumption'
                planId = $null; sku = $null; instances = $null; metrics = $logicMetrics
            })
        })
    }
    Set-RunCollectorStatus -RunPath $path -Name LogicApps -Status Completed -Items 1 -Files @('cost/logicApps.json')
    $costRows = @(
        foreach ($id in @($manifest.apim.resourceId, $logicId)) {
            foreach ($month in @('2026-08-01', '2026-09-01')) {
                $amount = if ($id -eq $logicId) { if ($month -ceq '2026-08-01') { 10.0 } else { 16.0 } }
                    else { if ($month -ceq '2026-08-01') { 10.0 } else { 20.0 } }
                @{
                    day = $month; resourceId = $id.ToLowerInvariant(); meterCategory = 'Synthetic'
                    meterSubCategory = 'Synthetic'; cost = $amount; currency = 'USD'
                }
            }
        }
    )
    $scope = $config.Environments[0].CostScopes[0]
    $null = Write-RunFile -RunPath $path -RelativePath cost/daily.json -InputObject @{
        schemaVersion = '1.0'; scopes = @(@{ scope = $scope; status = 'Completed'; rows = $costRows })
    }
    $window = Get-ApimEvidenceWindow -EndUtc $manifest.startedUtc -Kind Cost -Length 2
    Set-ApimEvidenceWindow -RunPath $path -Kind Cost -Target $scope -Window $window `
        -Schema NotApplicable -Status Completed -Reason None
    Set-RunCollectorStatus -RunPath $path -Name Cost -Status Completed -Items 4 -Files @('cost/daily.json')
    return $inputRun
}
