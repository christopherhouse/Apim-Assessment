#Requires -Version 7.4

Set-StrictMode -Version Latest

@(
    @{
        Id = 'APIM-COST-001'; Title = 'Premium capacity utilization (informational right-sizing)'
        Pillar = 'CostOptimization'; Mcsb = 'n/a'; Severity = 'Info'; Scope = 'Service'
        Requires = @('model/service.json', 'model/capacity.json')
        DataGaps = {
            param($ctx)
            if ($null -eq $ctx.Models.service.skuName -or
                ($ctx.Models.service.skuName -like 'Premium*' -and $ctx.Models.capacity.modelStatus -cne 'Complete')) {
                'model/capacity.json#capacity'
            }
        }
        Test = { param($x, $ctx); $null = $x; [bool] ($ctx.Models.service.skuName -like 'Premium*') }
        Evidence = {
            param($x, $ctx)
            $null = $x
            [ordered]@{
                capacityP95 = $ctx.Models.capacity.capacityP95; capacityMax = $ctx.Models.capacity.capacityMax
                capacityAvg = $ctx.Models.capacity.capacityAvg; currentUnits = $ctx.Models.capacity.units
                percentileMethod = $ctx.Models.capacity.percentileMethod
                currentZones = @($ctx.Models.service.zones); historicalUnits = $null
            }
        }
        EvidenceText = {
            param($x, $ctx); $null = $x; $null = $ctx
            'Premium utilization is available for advisory review. P95 is derived from hourly average samples; current units do not prove historical sizing or achievable savings.'
        }
        Recommendation = 'Review measured Premium utilization with workload peaks, zone redundancy and HA requirements; retain required resilience and do not infer a safe downsize from averages alone.'
        Effort = 'M'; References = @(); SourceFiles = @('model/service.json', 'model/capacity.json'); Enabled = $true
    }
    @{
        Id = 'APIM-COST-002'; Title = 'Cost per million calls trend'
        Pillar = 'CostOptimization'; Mcsb = 'n/a'; Severity = 'Info'; Scope = 'Service'
        Requires = @('model/cost.json')
        DataGaps = {
            param($ctx)
            if (@($ctx.Models.cost.normalized | Where-Object { $null -ne $_.changePercent }).Count -eq 0) {
                'model/cost.json#usage'
            }
        }
        Test = {
            param($x, $ctx); $null = $x
            [bool] (@($ctx.Models.cost.normalized | Where-Object { $null -ne $_.changePercent -and $_.changePercent -gt 0 }).Count -gt 0)
        }
        Evidence = {
            param($x, $ctx); $null = $x
            [ordered]@{ risingMonths = @($ctx.Models.cost.normalized | Where-Object {
                        $null -ne $_.changePercent -and $_.changePercent -gt 0
                    }); scope = 'ConfiguredApimAndAppGateways' }
        }
        EvidenceText = {
            param($x, $ctx); $null = $x; $null = $ctx
            'Combined APIM/App Gateway cost per million APIM calls increased across comparable complete adjacent months; currencies and incomplete periods are not combined.'
        }
        Recommendation = 'Review the normalized cost trend with traffic, service capacity and billing context; do not infer a utilization or pricing cause from cost alone.'
        Effort = 'M'; References = @(); SourceFiles = @('model/cost.json', 'model/usage.json'); Enabled = $true
    }
    @{
        Id = 'APIM-COST-003'; Title = 'Log Analytics ingestion growth from APIM/App Gateway'
        Pillar = 'CostOptimization'; Mcsb = 'n/a'; Severity = 'Medium'; Scope = 'Service'
        Requires = @('model/cost.json', 'model/apis.json')
        DataGaps = {
            param($ctx)
            if ('ingestion' -cin $ctx.Models.cost.missingInputs -and
                @(Get-ApimIngestionCostSignal -Cost $ctx.Models.cost -Apis @($ctx.Models.apis)).Count -eq 0) {
                'model/cost.json#ingestion'
            }
        }
        Test = {
            param($x, $ctx); $null = $x
            [bool] (@(Get-ApimIngestionCostSignal -Cost $ctx.Models.cost -Apis @($ctx.Models.apis)).Count -gt 0)
        }
        Evidence = {
            param($x, $ctx); $null = $x
            [ordered]@{ signals = @(Get-ApimIngestionCostSignal -Cost $ctx.Models.cost -Apis @($ctx.Models.apis))
                incompleteEvidence = @($ctx.Models.cost.missingInputs) }
        }
        EvidenceText = {
            param($x, $ctx); $null = $x; $null = $ctx
            'Relevant billable workspace-table ingestion at least doubled across complete months, or coexists with proven APIM body logging. Workspace totals do not establish individual-resource attribution.'
        }
        Recommendation = 'Review diagnostic sampling, body capture and top billable data types while preserving required security and operational evidence.'
        Effort = 'M'; References = @(); SourceFiles = @('model/cost.json', 'model/apis.json'); Enabled = $true
    }
    @{
        Id = 'APIM-COST-004'; Title = 'Logic Apps cost increase (cost-only)'
        Pillar = 'CostOptimization'; Mcsb = 'n/a'; Severity = 'Medium'; Scope = 'Service'
        Requires = @('model/cost.json')
        DataGaps = {
            param($ctx)
            if (@(Get-ApimLogicAppCostSignal -Cost $ctx.Models.cost).Count -eq 0 -and
                -not (Test-ApimLogicAppCostCoverage -Cost $ctx.Models.cost)) {
                'model/cost.json#logicApps'
            }
        }
        Test = {
            param($x, $ctx); $null = $x
            [bool] (@(Get-ApimLogicAppCostSignal -Cost $ctx.Models.cost).Count -gt 0)
        }
        Evidence = {
            param($x, $ctx); $null = $x
            [ordered]@{ signals = @(Get-ApimLogicAppCostSignal -Cost $ctx.Models.cost)
                incompleteEvidence = @($ctx.Models.cost.missingInputs) }
        }
        EvidenceText = {
            param($x, $ctx); $null = $x; $null = $ctx
            'Logic Apps workflow or linked Standard-plan cost exceeded 1.5 times the first complete month. SKU/instances are current snapshots, historical changes are unknown, and workflow review is out of scope.'
        }
        Recommendation = 'Review the cost change start date and authorized billing/plan history. Shared Standard-plan costs are not per-workflow charges; workflow review is out of scope.'
        Effort = 'M'; References = @(); SourceFiles = @('model/cost.json'); Enabled = $true
    }
    @{
        Id = 'APIM-COST-005'; Title = 'Non-production on Premium'
        Pillar = 'CostOptimization'; Mcsb = 'n/a'; Severity = 'Low'; Scope = 'Service'
        Requires = @('model/service.json')
        DataGaps = {
            param($ctx)
            if ($null -eq $ctx.Models.service.skuName) { 'model/service.json#skuName' }
        }
        Test = {
            param($x, $ctx); $null = $x
            [bool] ($ctx.Manifest.environment -ine 'Prod' -and $ctx.Models.service.skuName -like 'Premium*')
        }
        Evidence = {
            param($x, $ctx); $null = $x
            [ordered]@{ environment = $ctx.Manifest.environment; sku = $ctx.Models.service.skuName
                currentUnits = $ctx.Models.service.skuCapacity; currentZones = @($ctx.Models.service.zones) }
        }
        EvidenceText = {
            param($x, $ctx); $null = $x; $null = $ctx
            'The explicitly configured non-production environment uses Premium; this is a review opportunity, not proof of unnecessary capacity.'
        }
        Recommendation = 'Confirm non-production feature, networking, zone and HA requirements before considering a different tier or capacity; this assessment makes no changes.'
        Effort = 'M'; References = @(); SourceFiles = @('model/service.json'); Enabled = $true
    }
)
