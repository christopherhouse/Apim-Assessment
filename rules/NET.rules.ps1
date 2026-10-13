#Requires -Version 7.4

Set-StrictMode -Version Latest

@(
    @{
        Id = 'APIM-NET-002'
        Title = 'WAF disabled or in Detection mode on Application Gateway'
        Pillar = 'Security'
        Mcsb = 'NS-6'
        Severity = 'High'
        Scope = 'Network'
        Requires = @('model/network.json')
        DataGaps = {
            param($ctx)
            $network = $ctx.Models.network
            if ($null -eq $network.appGateways) {
                'model/network.json#appGateways'
            }
            elseif ($network.appGateways.Count -gt 0) {
                if ($network.wafState -eq 'Unknown' -and
                    $network.wafMode -ne 'Detection') {
                    'model/network.json#wafState'
                }
                if ($network.wafMode -eq 'Unknown' -and
                    $network.wafState -ne 'Disabled') {
                    'model/network.json#wafMode'
                }
            }
        }
        Applies = {
            param($x, $ctx)
            $null = $ctx
            $null -ne $x.appGateways -and $x.appGateways.Count -gt 0
        }
        Test = {
            param($x, $ctx)
            $null = $ctx
            $x.wafState -eq 'Disabled' -or $x.wafMode -eq 'Detection'
        }
        Evidence = {
            param($x, $ctx)
            [ordered]@{
                wafState = $x.wafState
                wafMode = $x.wafMode
                edgeAssumed = $ctx.Config.Edge.Mode -eq 'AssumedReachable'
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $ctx
            "Application Gateway WAF state: $($x.wafState); mode: $($x.wafMode)."
        }
        Recommendation = 'Review WAF prevention at each public entry point; confirm the edge WAF independently.'
        Effort = 'M'
        References = @()
        SourceFiles = @('raw/network/', 'model/network.json')
        Enabled = $true
    }
    @{
        Id = 'APIM-NET-004'
        Title = 'Host-wide forwarding publishes the APIM catalog'
        Pillar = 'Security'
        Mcsb = 'NS-2'
        Severity = 'High'
        Scope = 'Route'
        Requires = @('model/exposure.json')
        DataGaps = {
            param($ctx)
            $candidates = @($ctx.Models.exposure | Where-Object {
                    $_.frontendType -eq 'Public' -and
                    $_.ruleType -eq 'Basic' -and
                    $_.pattern -eq '/*'
                })
            if ($candidates.Count -gt 0 -and
                @($candidates | Where-Object {
                        $_.reachability -eq 'Reachable'
                    }).Count -eq 0 -and
                @($candidates | Where-Object {
                        $_.reachability -eq 'Unknown'
                    }).Count -gt 0) {
                'model/exposure.json#reachability'
            }
        }
        Applies = {
            param($x, $ctx)
            $null = $ctx
            $x.frontendType -eq 'Public' -and
                $x.ruleType -eq 'Basic' -and $x.pattern -eq '/*'
        }
        Test = {
            param($x, $ctx)
            $null = $ctx
            $x.reachability -eq 'Reachable'
        }
        Evidence = {
            param($x, $ctx)
            $siblings = @($ctx.Models.exposure | Where-Object {
                    $_.gateway -ceq $x.gateway -and
                    $_.listener -ceq $x.listener -and
                    $_.pattern -ceq $x.pattern -and
                    $_.frontendType -eq 'Public' -and
                    $_.ruleType -eq 'Basic'
                })
            $reachable = @($siblings | Where-Object {
                    $_.reachability -eq 'Reachable'
                })
            $unintended = if (@($reachable | Where-Object {
                        $_.exposure -eq 'Unknown'
                    }).Count -gt 0) {
                $null
            }
            else {
                @($reachable | Where-Object {
                        $_.exposure -eq 'ExternalUnintended'
                    } | Select-Object -ExpandProperty apiId -Unique).Count
            }
            [ordered]@{
                routeKey = $x.routeKey
                pattern = $x.pattern
                configuredApiCount = @($siblings |
                    Select-Object -ExpandProperty apiId -Unique).Count
                reachableApiCount = @($reachable |
                    Select-Object -ExpandProperty apiId -Unique).Count
                externalUnintendedApiCount = $unintended
                confidence = $x.confidence
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $ctx
            "Public Basic route $($x.pattern) forwards the APIM API catalog; usage-based classification may be unavailable."
        }
        Recommendation = 'Review which APIs need public exposure and restrict the published route or effective policy as appropriate.'
        Effort = 'M'
        References = @()
        SourceFiles = @('raw/network/', 'raw/apis.json', 'model/exposure.json')
        Enabled = $true
    }
    @{
        Id = 'APIM-NET-006'
        Title = 'APIM gateway directly reachable outside the intended front door'
        Pillar = 'Security'
        Mcsb = 'NS-2'
        Severity = 'High'
        Scope = 'Service'
        Requires = @('model/network.json')
        DataGaps = {
            param($ctx)
            if ($null -eq $ctx.Models.network.directPublic) {
                'model/network.json#directPublic'
            }
        }
        Test = {
            param($x, $ctx)
            $null = $x
            $ctx.Models.network.directPublic -eq $true
        }
        Evidence = {
            param($x, $ctx)
            $null = $x
            [ordered]@{
                directPublic = $ctx.Models.network.directPublic
                reasons = @($ctx.Models.network.directPublicReasons)
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $x
            $null = $ctx
            'A direct public APIM gateway path was detected.'
        }
        Recommendation = 'Review public gateway access and constrain unintended paths around the approved front door.'
        Effort = 'M'
        References = @()
        SourceFiles = @('raw/service.json', 'raw/network/', 'model/network.json')
        Enabled = $true
    }
    @{
        Id = 'APIM-NET-007'
        Title = 'APIM subnet NSG permits broad inbound HTTPS'
        Pillar = 'Security'
        Mcsb = 'NS-1'
        Severity = 'Medium'
        Scope = 'Network'
        Requires = @('model/network.json')
        DataGaps = {
            param($ctx)
            $network = $ctx.Models.network
            if ($network.virtualNetworkType -ne 'None' -and
                $network.nsgEvaluation -in @('Missing', 'Unknown')) {
                'model/network.json#nsgEvaluation'
            }
        }
        Applies = {
            param($x, $ctx)
            $null = $ctx
            $x.virtualNetworkType -ne 'None'
        }
        Test = {
            param($x, $ctx)
            $null = $ctx
            $x.nsgEvaluation -eq 'Broad'
        }
        Evidence = {
            param($x, $ctx)
            $null = $ctx
            [ordered]@{
                virtualNetworkType = $x.virtualNetworkType
                nsgEvaluation = $x.nsgEvaluation
                nsgName = $x.nsgName
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $ctx
            "APIM subnet inbound HTTPS evaluation: $($x.nsgEvaluation)."
        }
        Recommendation = 'Review effective NSG priorities and narrow inbound HTTPS to intended entry points.'
        Effort = 'M'
        References = @()
        SourceFiles = @('raw/network/nsgs.json', 'model/network.json')
        Enabled = $true
    }
    @{
        Id = 'APIM-NET-008'
        Title = 'Weak Application Gateway TLS policy'
        Pillar = 'Security'
        Mcsb = 'DP-3'
        Severity = 'Medium'
        Scope = 'Network'
        Requires = @('model/network.json')
        DataGaps = {
            param($ctx)
            $network = $ctx.Models.network
            if ($null -eq $network.appGateways) {
                'model/network.json#appGateways'
            }
            elseif ($network.appGateways.Count -gt 0 -and
                $network.appGatewayTlsPolicy -eq 'Unknown') {
                'model/network.json#appGatewayTlsPolicy'
            }
        }
        Applies = {
            param($x, $ctx)
            $null = $ctx
            $null -ne $x.appGateways -and $x.appGateways.Count -gt 0
        }
        Test = {
            param($x, $ctx)
            $null = $ctx
            $x.appGatewayTlsPolicy -eq 'Weak'
        }
        Evidence = {
            param($x, $ctx)
            $null = $ctx
            [ordered]@{
                tlsPolicy = $x.appGatewayTlsPolicy
                policyNames = @($x.appGatewayTlsPolicyNames)
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $ctx
            "Application Gateway TLS policy assessment: $($x.appGatewayTlsPolicy)."
        }
        Recommendation = 'Review the listener TLS baseline and use a supported stronger policy compatible with clients.'
        Effort = 'M'
        References = @()
        SourceFiles = @('raw/network/', 'model/network.json')
        Enabled = $true
    }
)
