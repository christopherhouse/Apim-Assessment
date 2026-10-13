$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'APIM exposure model' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)

        $script:exposureFixtureRoot = Join-Path $RepoRoot (
            'tests/fixtures/synthetic-reference'
        )
        $script:exposureSchemaPath = Join-Path $RepoRoot (
            'schemas/exposure.schema.json'
        )

        BeforeAll {
            function Read-ExposureFixture {
                param(
                    [Parameter(Mandatory)]
                    [string] $RelativePath
                )

                return Get-Content -LiteralPath (
                    Join-Path $script:exposureFixtureRoot $RelativePath
                ) -Raw | ConvertFrom-Json -Depth 100
            }

            function Copy-ExposureObject {
                param(
                    [Parameter(Mandatory)]
                    [object] $InputObject
                )

                return $InputObject | ConvertTo-Json -Depth 100 |
                    ConvertFrom-Json -Depth 100
            }

            function Get-SyntheticExposureInput {
                $merge = Read-ExposureFixture 'model/policyMerge.json'
                $baseMissingByKey = @{}
                foreach ($entry in $merge.effectivePolicies) {
                    $key = "$($entry.apiId)|$($entry.operationId)|$($entry.product)"
                    $baseMissingByKey[$key] = @($entry.baseMissing)
                }
                $flagSummary = Read-ExposureFixture 'model/policyFlags.json'
                $policyPaths = @(
                    foreach ($entry in $flagSummary.policies) {
                        $record = [ordered]@{
                            product = $entry.product
                            apiId = $entry.apiId
                            operationId = $entry.operationId
                            evaluationStatus = $entry.evaluationStatus
                        }
                        foreach ($property in $entry.flags.PSObject.Properties) {
                            $record[$property.Name] = $property.Value
                        }
                        $key = "$($entry.apiId)|$($entry.operationId)|$($entry.product)"
                        $record.ipFilters = @()
                        $record.hostRestrictions = @()
                        $record.baseMissingDetails = @($baseMissingByKey[$key])
                        [pscustomobject] $record
                    }
                )
                return @{
                    Apis = @(
                        Read-ExposureFixture 'model/apis.json'
                    )
                    Operations = @(
                        Read-ExposureFixture 'model/operations.json'
                    )
                    Network = Read-ExposureFixture 'model/network.json'
                    Service = Read-ExposureFixture 'raw/service.json'
                    AppGateways = @(
                        Read-ExposureFixture (
                            'raw/network/appgw.agw-synthetic-prod.json'
                        )
                    )
                    PolicyPaths = $policyPaths
                    AppGwSubnetCidrs = @('10.20.1.0/24')
                }
            }

            function Get-ExposureRecord {
                param(
                    [Parameter(Mandatory)]
                    [object[]] $Records,

                    [Parameter(Mandatory)]
                    [string] $ApiId
                )

                return $Records | Where-Object apiId -EQ $ApiId |
                    Select-Object -First 1
            }

            function Get-BlockingIpFilter {
                return [pscustomobject]@{
                    location = '/policies[1]/inbound[1]/ip-filter[1]'
                    scope = 'api:orders-v1'
                    action = 'allow'
                    addresses = @('192.0.2.10')
                    addressRanges = @()
                }
            }
        }

        It 'classifies Basic host-wide forwarding with usage-dependent labels unknown' {
            $inputData = Get-SyntheticExposureInput

            $records = @(Get-ApimExposureModel @inputData)
            $orders = Get-ExposureRecord -Records $records -ApiId 'orders-v1'
            $status = Get-ExposureRecord -Records $records -ApiId 'status-v1'

            $records.Count | Should -Be 2
            $orders.pattern | Should -Be '/*'
            $orders.ruleType | Should -Be 'Basic'
            $orders.listenerHost | Should -Be 'api.synthetic.invalid'
            $orders.backendHost | Should -Be 'api.synthetic.invalid'
            $orders.reachability | Should -Be 'Reachable'
            $orders.exposure | Should -Be 'Unknown'
            $orders.missingInputs | Should -Be @('usage')
            $orders.confidence | Should -Be 'Medium'
            $status.reachability | Should -Be 'Reachable'
            ($records | ConvertTo-Json -Depth 100 -Compress) |
                Should -Be (
                    (Read-ExposureFixture 'model/exposure.json') |
                        ConvertTo-Json -Depth 100 -Compress
                )

            $apis = @(ConvertTo-ApimApiExposureModel `
                    -Apis $inputData.Apis -ExposureRecords $records)
            ($apis | Where-Object apiId -EQ 'orders-v1').reachability |
                Should -Be 'Reachable'
            ($apis | Where-Object apiId -EQ 'orders-v1').exposure |
                Should -Be 'Unknown'
            ($apis | Where-Object apiId -EQ 'orders-v1').missingInputs |
                Should -Not -Contain 'exposure'
            ($apis | ConvertTo-Json -Depth 100 -Compress) |
                Should -Be (
                    (Read-ExposureFixture 'model/apis.exposure.json') |
                        ConvertTo-Json -Depth 100 -Compress
                )
        }

        It 'matches only APIs covered by a path-based route' {
            $inputData = Get-SyntheticExposureInput
            $gateway = $inputData.AppGateways[0]
            $rule = $gateway.properties.requestRoutingRules[0]
            $rule.properties.ruleType = 'PathBasedRouting'
            $rule.properties.PSObject.Properties.Remove('backendAddressPool')
            $rule.properties.PSObject.Properties.Remove('backendHttpSettings')
            $pathMapId = (
                "$($gateway.id)/urlPathMaps/apis"
            )
            $rule.properties |
                Add-Member -NotePropertyName urlPathMap `
                    -NotePropertyValue ([pscustomobject]@{ id = $pathMapId })
            $gateway.properties |
                Add-Member -NotePropertyName urlPathMaps `
                    -NotePropertyValue @(
                        [pscustomobject]@{
                            id = $pathMapId
                            name = 'apis'
                            properties = [pscustomobject]@{
                                pathRules = @(
                                    [pscustomobject]@{
                                        name = 'orders'
                                        properties = [pscustomobject]@{
                                            paths = @('/orders*')
                                            backendAddressPool = [pscustomobject]@{
                                                id = $gateway.properties.
                                                    backendAddressPools[0].id
                                            }
                                            backendHttpSettings = [pscustomobject]@{
                                                id = $gateway.properties.
                                                    backendHttpSettingsCollection[0].id
                                            }
                                        }
                                    }
                                )
                            }
                        }
                    )

            $records = @(Get-ApimExposureModel @inputData)

            (Get-ExposureRecord $records 'orders-v1').reachability |
                Should -Be 'Reachable'
            (Get-ExposureRecord $records 'status-v1').reachability |
                Should -Be 'NotRoutable'
            (Get-ExposureRecord $records 'status-v1').exposure |
                Should -Be 'Internal'
        }

        It 'marks conditional path rewrites unknown with low confidence' {
            $inputData = Get-SyntheticExposureInput
            $gateway = $inputData.AppGateways[0]
            $rewriteId = "$($gateway.id)/rewriteRuleSets/conditional"
            $gateway.properties.requestRoutingRules[0].properties |
                Add-Member -NotePropertyName rewriteRuleSet `
                    -NotePropertyValue ([pscustomobject]@{ id = $rewriteId })
            $gateway.properties |
                Add-Member -NotePropertyName rewriteRuleSets `
                    -NotePropertyValue @(
                        [pscustomobject]@{
                            id = $rewriteId
                            name = 'conditional'
                            properties = [pscustomobject]@{
                                rewriteRules = @(
                                    [pscustomobject]@{
                                        name = 'rewrite'
                                        properties = [pscustomobject]@{
                                            conditions = @(
                                                [pscustomobject]@{
                                                    variable = 'http_req_Path'
                                                    pattern = '^/legacy'
                                                }
                                            )
                                            actionSet = [pscustomobject]@{
                                                urlConfiguration = [pscustomobject]@{
                                                    modifiedPath = '/orders'
                                                }
                                            }
                                        }
                                    }
                                )
                            }
                        }
                    )

            $record = Get-ExposureRecord `
                -Records @(Get-ApimExposureModel @inputData) `
                -ApiId 'orders-v1'

            $record.reachability | Should -Be 'Unknown'
            $record.exposure | Should -Be 'Unknown'
            $record.confidence | Should -Be 'Low'
            $record.missingInputs | Should -Contain 'rewrite'
        }

        It 'keeps DirectPublic authoritative when an App Gateway rewrite is unresolved' {
            $inputData = Get-SyntheticExposureInput
            $inputData.Network.directPublic = $true
            $gateway = $inputData.AppGateways[0]
            $rewriteId = "$($gateway.id)/rewriteRuleSets/conditional"
            $gateway.properties.requestRoutingRules[0].properties |
                Add-Member -NotePropertyName rewriteRuleSet `
                    -NotePropertyValue ([pscustomobject]@{ id = $rewriteId })
            $gateway.properties |
                Add-Member -NotePropertyName rewriteRuleSets `
                    -NotePropertyValue @(
                        [pscustomobject]@{
                            id = $rewriteId
                            properties = [pscustomobject]@{
                                rewriteRules = @(
                                    [pscustomobject]@{
                                        properties = [pscustomobject]@{
                                            conditions = @(
                                                [pscustomobject]@{
                                                    variable = 'http_req_Path'
                                                    pattern = '^/legacy'
                                                }
                                            )
                                            actionSet = [pscustomobject]@{
                                                urlConfiguration = [pscustomobject]@{
                                                    modifiedPath = '/orders'
                                                }
                                            }
                                        }
                                    }
                                )
                            }
                        }
                    )

            $records = @(Get-ApimExposureModel @inputData)

            $records.exposure | Should -Be @('DirectPublic', 'DirectPublic')
            $records.confidence | Should -Be @('High', 'High')
            @($records | ForEach-Object missingInputs) |
                Should -Not -Contain 'rewrite'
        }

        It 'applies one unconditional literal path rewrite before API matching' {
            $inputData = Get-SyntheticExposureInput
            $gateway = $inputData.AppGateways[0]
            $rewriteId = "$($gateway.id)/rewriteRuleSets/literal"
            $gateway.properties.requestRoutingRules[0].properties |
                Add-Member -NotePropertyName rewriteRuleSet `
                    -NotePropertyValue ([pscustomobject]@{ id = $rewriteId })
            $gateway.properties |
                Add-Member -NotePropertyName rewriteRuleSets `
                    -NotePropertyValue @(
                        [pscustomobject]@{
                            id = $rewriteId
                            name = 'literal'
                            properties = [pscustomobject]@{
                                rewriteRules = @(
                                    [pscustomobject]@{
                                        name = 'rewrite'
                                        properties = [pscustomobject]@{
                                            conditions = @()
                                            actionSet = [pscustomobject]@{
                                                urlConfiguration = [pscustomobject]@{
                                                    modifiedPath = '/status'
                                                }
                                            }
                                        }
                                    }
                                )
                            }
                        }
                    )

            $records = @(Get-ApimExposureModel @inputData)

            (Get-ExposureRecord $records 'orders-v1').reachability |
                Should -Be 'NotRoutable'
            (Get-ExposureRecord $records 'status-v1').reachability |
                Should -Be 'Reachable'
            (Get-ExposureRecord $records 'status-v1').pattern |
                Should -Be '/status'
        }

        It 'applies a default path-map rewrite before classifying the default route' {
            $inputData = Get-SyntheticExposureInput
            $gateway = $inputData.AppGateways[0]
            $rule = $gateway.properties.requestRoutingRules[0]
            $rule.properties.ruleType = 'PathBasedRouting'
            $rule.properties.PSObject.Properties.Remove('backendAddressPool')
            $rule.properties.PSObject.Properties.Remove('backendHttpSettings')
            $pathMapId = "$($gateway.id)/urlPathMaps/default"
            $rewriteId = "$($gateway.id)/rewriteRuleSets/default-conditional"
            $rule.properties |
                Add-Member -NotePropertyName urlPathMap `
                    -NotePropertyValue ([pscustomobject]@{ id = $pathMapId })
            $gateway.properties |
                Add-Member -NotePropertyName urlPathMaps `
                    -NotePropertyValue @(
                        [pscustomobject]@{
                            id = $pathMapId
                            properties = [pscustomobject]@{
                                defaultBackendAddressPool = [pscustomobject]@{
                                    id = $gateway.properties.
                                        backendAddressPools[0].id
                                }
                                defaultBackendHttpSettings = [pscustomobject]@{
                                    id = $gateway.properties.
                                        backendHttpSettingsCollection[0].id
                                }
                                defaultRewriteRuleSet = [pscustomobject]@{
                                    id = $rewriteId
                                }
                                pathRules = @()
                            }
                        }
                    )
            $gateway.properties |
                Add-Member -NotePropertyName rewriteRuleSets `
                    -NotePropertyValue @(
                        [pscustomobject]@{
                            id = $rewriteId
                            properties = [pscustomobject]@{
                                rewriteRules = @(
                                    [pscustomobject]@{
                                        properties = [pscustomobject]@{
                                            conditions = @(
                                                [pscustomobject]@{
                                                    variable = 'http_req_Path'
                                                    pattern = '^/legacy'
                                                }
                                            )
                                            actionSet = [pscustomobject]@{
                                                urlConfiguration = [pscustomobject]@{
                                                    modifiedPath = '/status'
                                                }
                                            }
                                        }
                                    }
                                )
                            }
                        }
                    )

            $records = @(Get-ApimExposureModel @inputData)

            $records.reachability | Should -Be @('Unknown', 'Unknown')
            $records.missingInputs | Should -Contain 'rewrite'
        }

        It 'uses DirectPublic as a service-level override without App Gateway routes' {
            $inputData = Get-SyntheticExposureInput
            $inputData.Network.directPublic = $true
            $inputData.AppGateways = @()

            $records = @(Get-ApimExposureModel @inputData)

            $records.Count | Should -Be 2
            $records.exposure | Should -Be @('DirectPublic', 'DirectPublic')
            $records.ruleType | Should -Be @('DirectPublic', 'DirectPublic')
            $records.confidence | Should -Be @('High', 'High')
        }

        It 'recognizes the canonical APIM gateway URL as a backend target' {
            $inputData = Get-SyntheticExposureInput
            $inputData.Service.properties |
                Add-Member -NotePropertyName gatewayUrl `
                    -NotePropertyValue 'https://apim-synthetic-prod.azure-api.net'
            $inputData.Service.properties.hostnameConfigurations = @(
                [pscustomobject]@{
                    type = 'DeveloperPortal'
                    hostName = 'portal.synthetic.invalid'
                }
            )
            $gateway = $inputData.AppGateways[0]
            $gateway.properties.backendAddressPools[0].properties.
                backendAddresses[0].fqdn = 'apim-synthetic-prod.azure-api.net'
            $gateway.properties.backendHttpSettingsCollection[0].properties.
                hostName = 'apim-synthetic-prod.azure-api.net'
            $gateway.properties.httpListeners[0].properties.hostName =
                'apim-synthetic-prod.azure-api.net'

            $records = @(Get-ApimExposureModel @inputData)

            $records.reachability | Should -Be @('Reachable', 'Reachable')
        }

        It 'emits distinct records for a multi-site listener host list' {
            $inputData = Get-SyntheticExposureInput
            $listener = $inputData.AppGateways[0].properties.httpListeners[0]
            $listener.properties.PSObject.Properties.Remove('hostName')
            $listener.properties |
                Add-Member -NotePropertyName hostNames `
                    -NotePropertyValue @(
                        'api.synthetic.invalid',
                        'public.synthetic.invalid'
                    )

            $records = @(Get-ApimExposureModel @inputData)

            $records.Count | Should -Be 4
            @($records.listenerHost | Sort-Object -Unique) |
                Should -Be @(
                    'api.synthetic.invalid',
                    'public.synthetic.invalid'
                )
            @($records.routeKey | Sort-Object -Unique).Count | Should -Be 4
        }

        It 'does not publish portal hostnames as APIM gateway backends' {
            $inputData = Get-SyntheticExposureInput
            $inputData.Service.properties.hostnameConfigurations = @(
                [pscustomobject]@{
                    type = 'DeveloperPortal'
                    hostName = 'portal.synthetic.invalid'
                }
            )
            $gateway = $inputData.AppGateways[0]
            $gateway.properties.backendAddressPools[0].properties.
                backendAddresses[0].fqdn = 'portal.synthetic.invalid'
            $gateway.properties.backendHttpSettingsCollection[0].properties.
                hostName = 'portal.synthetic.invalid'

            $records = @(Get-ApimExposureModel @inputData)

            $records.reachability | Should -Be @('NotRoutable', 'NotRoutable')
            $records.exposure | Should -Be @('Internal', 'Internal')
        }

        It 'rejects an unrelated host override on an APIM-address backend' {
            $inputData = Get-SyntheticExposureInput
            $gateway = $inputData.AppGateways[0]
            $backend = $gateway.properties.backendAddressPools[0].properties.
                backendAddresses[0]
            $backend.PSObject.Properties.Remove('fqdn')
            $backend | Add-Member -NotePropertyName ipAddress `
                -NotePropertyValue '10.20.2.4'
            $gateway.properties.backendHttpSettingsCollection[0].properties.
                hostName = 'unrelated.synthetic.invalid'

            $records = @(Get-ApimExposureModel @inputData)

            $records.reachability | Should -Be @('NotRoutable', 'NotRoutable')
        }

        It 'classifies IP filters that exclude the App Gateway subnet' {
            $inputData = Get-SyntheticExposureInput
            foreach ($path in @(
                    $inputData.PolicyPaths |
                        Where-Object apiId -EQ 'orders-v1'
                )) {
                $path.ipFilters = @(Get-BlockingIpFilter)
            }

            $record = Get-ExposureRecord `
                -Records @(Get-ApimExposureModel @inputData) `
                -ApiId 'orders-v1'

            $record.restriction | Should -Be 'IpFilter'
            $record.exposure | Should -Be 'Restricted'
            $record.restrictedOperations.Count | Should -Be 2
        }

        It 'keeps IP-filter restrictions unknown when the gateway subnet is missing' {
            $inputData = Get-SyntheticExposureInput
            $inputData.AppGwSubnetCidrs = @()
            foreach ($path in @(
                    $inputData.PolicyPaths |
                        Where-Object apiId -EQ 'orders-v1'
                )) {
                $path.ipFilters = @(Get-BlockingIpFilter)
            }

            $record = Get-ExposureRecord `
                -Records @(Get-ApimExposureModel @inputData) `
                -ApiId 'orders-v1'

            $record.restriction | Should -Be 'Unknown'
            $record.exposure | Should -Be 'Unknown'
            $record.missingInputs | Should -Contain 'appGwSubnet'
        }

        It 'classifies a host check that blocks the published hostname' {
            $inputData = Get-SyntheticExposureInput
            foreach ($path in @(
                    $inputData.PolicyPaths |
                        Where-Object apiId -EQ 'orders-v1'
                )) {
                $path.hostRestrictions = @(
                    [pscustomobject]@{
                        location = '/policies[1]/inbound[1]/choose[1]/when[1]'
                        scope = 'api:orders-v1'
                        condition = (
                            '@(context.Request.OriginalUrl.Host != ' +
                            '"internal.synthetic.invalid")'
                        )
                        statusCode = '403'
                    }
                )
            }

            $record = Get-ExposureRecord `
                -Records @(Get-ApimExposureModel @inputData) `
                -ApiId 'orders-v1'

            $record.restriction | Should -Be 'HostCheck'
            $record.exposure | Should -Be 'Restricted'
        }

        It 'evaluates host checks against the hostname delivered to APIM' {
            $inputData = Get-SyntheticExposureInput
            $gateway = $inputData.AppGateways[0]
            $gateway.properties.httpListeners[0].properties.hostName =
                'public.synthetic.invalid'
            foreach ($path in @(
                    $inputData.PolicyPaths |
                        Where-Object apiId -EQ 'orders-v1'
                )) {
                $path.hostRestrictions = @(
                    [pscustomobject]@{
                        location = '/policies[1]/inbound[1]/choose[1]/when[1]'
                        scope = 'api:orders-v1'
                        condition = (
                            '@(context.Request.OriginalUrl.Host != ' +
                            '"api.synthetic.invalid")'
                        )
                        statusCode = '403'
                    }
                )
            }

            $record = Get-ExposureRecord `
                -Records @(Get-ApimExposureModel @inputData) `
                -ApiId 'orders-v1'

            $record.listenerHost | Should -Be 'public.synthetic.invalid'
            $record.backendHost | Should -Be 'api.synthetic.invalid'
            $record.restriction | Should -Be 'None'
        }

        It 'retains an unrestricted base-missing product path conservatively' {
            $inputData = Get-SyntheticExposureInput
            $internal = $inputData.PolicyPaths |
                Where-Object {
                    $_.apiId -eq 'orders-v1' -and
                    $_.product -eq 'internal'
                }
            $partner = $inputData.PolicyPaths |
                Where-Object {
                    $_.apiId -eq 'orders-v1' -and
                    $_.product -eq 'partner'
                }
            $internal.ipFilters = @(Get-BlockingIpFilter)
            $partner.ipFilters = @()
            $partner.baseMissingDetails = @(
                [pscustomobject]@{
                    scope = 'product:partner'
                    section = 'inbound'
                }
            )

            $record = Get-ExposureRecord `
                -Records @(Get-ApimExposureModel @inputData) `
                -ApiId 'orders-v1'

            $record.restriction | Should -Be 'None'
            $record.baseMissingBypass | Should -BeTrue
            $record.exposure | Should -Be 'Unknown'
            $record.restrictedOperations.Count | Should -Be 1
        }

        It 'keeps missing operation evidence unknown rather than internal' {
            $inputData = Get-SyntheticExposureInput
            $inputData.Operations = @(
                $inputData.Operations | Where-Object apiId -NE 'orders-v1'
            )

            $record = Get-ExposureRecord `
                -Records @(Get-ApimExposureModel @inputData) `
                -ApiId 'orders-v1'

            $record.reachability | Should -Be 'Unknown'
            $record.exposure | Should -Be 'Unknown'
            $record.missingInputs | Should -Contain 'operations'
        }

        It 'keeps missing policy-path evidence explicit without aborting analysis' {
            $inputData = Get-SyntheticExposureInput
            $inputData.PolicyPaths = @(
                $inputData.PolicyPaths | Where-Object apiId -NE 'orders-v1'
            )

            $record = Get-ExposureRecord `
                -Records @(Get-ApimExposureModel @inputData) `
                -ApiId 'orders-v1'

            $record.restriction | Should -Be 'Unknown'
            $record.exposure | Should -Be 'Unknown'
            $record.missingInputs | Should -Contain 'policyEvidence'
        }

        It 'retains a known unrestricted product path when another path is missing' {
            $inputData = Get-SyntheticExposureInput
            $inputData.PolicyPaths = @(
                $inputData.PolicyPaths | Where-Object {
                    $_.apiId -ne 'orders-v1' -or $_.product -eq 'internal'
                }
            )

            $record = Get-ExposureRecord `
                -Records @(Get-ApimExposureModel @inputData) `
                -ApiId 'orders-v1'

            $record.restriction | Should -Be 'None'
            $record.missingInputs | Should -Contain 'policyEvidence'
        }

        It 'applies the optional usage hook to final labels' {
            $inputData = Get-SyntheticExposureInput
            $inputData.UsageByRoute = @(
                [pscustomobject]@{
                    apiId = 'orders-v1'
                    route = 'ViaAppGw'
                    calls = 25
                },
                [pscustomobject]@{
                    apiId = 'orders-v1'
                    route = 'Internal'
                    calls = 10
                },
                [pscustomobject]@{
                    apiId = 'status-v1'
                    route = 'Internal'
                    calls = 12
                }
            )
            $inputData.UsageComplete = $true

            $records = @(Get-ApimExposureModel @inputData)

            (Get-ExposureRecord $records 'orders-v1').exposure |
                Should -Be 'ExternalInUse'
            (Get-ExposureRecord $records 'status-v1').exposure |
                Should -Be 'ExternalUnintended'
        }

        It 'requires usage telemetry to be explicitly complete' {
            $inputData = Get-SyntheticExposureInput
            $inputData.UsageByRoute = @(
                [pscustomobject]@{
                    apiId = 'orders-v1'
                    route = 'ViaAppGw'
                    calls = 0
                }
            )

            { Get-ApimExposureModel @inputData } |
                Should -Throw '*complete telemetry evidence*'
        }

        It 'keeps mixed zero and missing route evidence unknown in API backfill' {
            $inputData = Get-SyntheticExposureInput
            $routes = @(Get-ApimExposureModel @inputData)
            $zero = Copy-ExposureObject $routes[0]
            $zero.routeKey = 'zero-route'
            $zero.exposure = 'ExternalUnintended'
            $zero.callsViaAppGw = 0
            $zero.callsInternal = 5
            $zero.modelStatus = 'Complete'
            $zero.missingInputs = @()
            $unknown = Copy-ExposureObject $routes[0]
            $unknown.routeKey = 'unknown-route'

            $apis = @(ConvertTo-ApimApiExposureModel `
                    -Apis @($inputData.Apis | Where-Object apiId -EQ 'orders-v1') `
                    -ExposureRecords @($zero, $unknown))

            $apis[0].exposure | Should -Be 'Unknown'
            $apis[0].missingInputs | Should -Contain 'usage'
            $apis[0].modelStatus | Should -Be 'Partial'
        }

        It 'writes exposure and API backfill only after both schemas validate' {
            $inputData = Get-SyntheticExposureInput
            $exposure = @(Get-ApimExposureModel @inputData)
            $apis = @(ConvertTo-ApimApiExposureModel `
                    -Apis $inputData.Apis -ExposureRecords $exposure)
            $runPath = Join-Path $TestDrive 'exposure-model'
            $null = New-Item -ItemType Directory -Path $runPath

            $paths = @(Write-ApimExposureModel -RunPath $runPath `
                    -ExposureRecords $exposure -ApiRecords $apis)

            $paths.Count | Should -Be 2
            $json = Get-Content -LiteralPath (
                Join-Path $runPath 'model/exposure.json'
            ) -Raw
            ($json | Test-Json -SchemaFile $script:exposureSchemaPath) |
                Should -BeTrue
        }

        It 'fails closed before writing either file when exposure is invalid' {
            $inputData = Get-SyntheticExposureInput
            $exposure = @(Get-ApimExposureModel @inputData)
            $apis = @(ConvertTo-ApimApiExposureModel `
                    -Apis $inputData.Apis -ExposureRecords $exposure)
            $invalid = Copy-ExposureObject $exposure[0]
            $invalid | Add-Member -NotePropertyName unexpected `
                -NotePropertyValue $true
            $exposure[0] = $invalid
            $runPath = Join-Path $TestDrive 'invalid-exposure-model'
            $null = New-Item -ItemType Directory -Path $runPath

            {
                Write-ApimExposureModel -RunPath $runPath `
                    -ExposureRecords $exposure -ApiRecords $apis
            } | Should -Throw
            Test-Path -LiteralPath (
                Join-Path $runPath 'model/exposure.json'
            ) | Should -BeFalse
            Test-Path -LiteralPath (
                Join-Path $runPath 'model/apis.json'
            ) | Should -BeFalse
        }
    }
}
