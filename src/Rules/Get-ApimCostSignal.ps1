#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimIngestionCostSignal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Cost,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Apis
    )

    $bodyLogging = @($Apis | Where-Object bodyLogging -EQ $true).Count -gt 0
    foreach ($group in @($Cost.ingestion | Group-Object {
                "$($_.workspaceId)|$($_.dataType)"
            } -CaseSensitive)) {
        $months = @($group.Group | Where-Object completeMonth | Sort-Object month)
        $growth = $months.Count -ge 2 -and $months[0].gb -gt 0 -and
            $months[-1].gb -ge 2.0 * $months[0].gb
        $capture = $bodyLogging -and
            $group.Group[0].dataType -cin @('ApiManagementGatewayLogs', 'AzureDiagnostics') -and
            @($group.Group | Where-Object { $_.gb -gt 0 }).Count -gt 0
        if ($growth -or $capture) {
            [ordered]@{
                workspaceId = $group.Group[0].workspaceId; dataType = $group.Group[0].dataType
                doubled = [bool] $growth; bodyLogging = [bool] $capture
                firstMonth = if ($months.Count) { $months[0].month } else { $null }
                firstGb = if ($months.Count) { $months[0].gb } else { $null }
                lastMonth = if ($months.Count) { $months[-1].month } else { $null }
                lastGb = if ($months.Count) { $months[-1].gb } else { $null }
                attribution = 'WorkspaceTableNotIndividualResource'
            }
        }
    }
}

function Test-ApimLogicAppCostCoverage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Cost)

    if (@($Cost.missingInputs | Where-Object { $_ -cin @('logicApps', 'cost', 'costCoverage') }).Count) {
        return $false
    }
    foreach ($resource in $Cost.logicApps) {
        if (-not $resource.metricsComplete) { return $false }
        $id = if ($resource.kind -ceq 'Standard') { $resource.planId } else { $resource.resourceId }
        $comparable = $false
        foreach ($currency in @($Cost.monthly | Where-Object resourceId -IEQ $id |
                ForEach-Object currency | Sort-Object -Unique)) {
            $months = @($Cost.monthly | Where-Object {
                    $_.resourceId -ieq $id -and $_.currency -ceq $currency -and $_.completeMonth
                } | Select-Object -ExpandProperty month -Unique)
            if ($months.Count -ge 2) { $comparable = $true }
        }
        if (-not $comparable) { return $false }
    }
    return $true
}

function Get-ApimLogicAppCostSignal {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Cost)

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($resource in $Cost.logicApps) {
        $id = if ($resource.kind -ceq 'Standard') { $resource.planId } else { $resource.resourceId }
        if (-not $seen.Add($id) -or -not $resource.metricsComplete) { continue }
        foreach ($currency in @($Cost.monthly | Where-Object resourceId -IEQ $id |
                ForEach-Object currency | Sort-Object -Unique)) {
            $months = @(
                foreach ($group in @($Cost.monthly | Where-Object {
                            $_.resourceId -ieq $id -and $_.currency -ceq $currency -and $_.completeMonth
                        } | Group-Object month)) {
                    [pscustomobject]@{ month = $group.Name; cost = [double] (($group.Group | Measure-Object cost -Sum).Sum) }
                }

            )
            $months = @($months | Sort-Object month)
            if ($months.Count -lt 2 -or $months[0].cost -lt 0 -or
                $months[-1].cost -le 1.5 * $months[0].cost) { continue }
            $changes = @($months | Select-Object -Skip 1 | Where-Object { $_.cost -gt 1.5 * $months[0].cost })
            [ordered]@{
                resourceId = $id; kind = $resource.kind; currency = $currency
                firstMonth = $months[0].month; firstCost = $months[0].cost
                lastMonth = $months[-1].month; lastCost = $months[-1].cost
                changeStartDate = $changes[0].month
                currentSku = $resource.sku; currentInstances = $resource.instances
                historicalPlanChanges = $null; workflowReview = 'OutOfScope'
            }
        }
    }
}
