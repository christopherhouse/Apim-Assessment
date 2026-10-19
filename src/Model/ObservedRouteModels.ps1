#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimCompleteRouteAggregate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Context,
        [Parameter(Mandatory)][object] $Payload,
        [Parameter(Mandatory)][ValidateSet('Usage', 'AppGateway')][string] $Family
    )

    $canonical = $null
    $selected = $null
    foreach ($workspace in $Payload.workspaces) {
        $entry = @($Context.Manifest.evidenceWindows | Where-Object {
                $_.kind -ceq $Family -and $_.target -ceq $workspace.workspaceId
            })
        if ($workspace.status -cne 'Completed' -or $entry.Count -ne 1 -or
            $entry[0].status -cne 'Completed' -or
            $entry[0].schema -cnotin @('ResourceSpecific', 'Legacy')) { return $null }
        $rows = @($workspace.rows | Sort-Object apiId, operationId, productId, route,
                gatewayId, listener, rule, host -CaseSensitive)
        $digest = Get-ApimConfigDigest -Config @{
            rows = $rows
            startUtc = ([datetimeoffset] $entry[0].startUtc).ToUniversalTime().ToString('O')
            endUtc = ([datetimeoffset] $entry[0].endUtc).ToUniversalTime().ToString('O')
        }
        if ($null -eq $canonical) {
            $canonical = $digest
            $selected = [pscustomobject]@{ Rows = $rows; Window = $entry[0] }
        }
        elseif ($canonical -cne $digest) { return $null }
    }
    return $selected
}

function Get-ApimSavedRouteUsage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][object] $Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Apis,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Operations,
        [Parameter(Mandatory)][object] $Service,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $AppGateways
    )

    if ($Context.Settings.schemaVersion -cne '1.2') { return $null }
    $usage = $null; $listeners = $null
    $records = @($Context.Manifest.collectors | Where-Object name -CEQ LogAnalytics)
    if ($records.Count -gt 1) { throw 'Observed-route collector is duplicated.' }
    if ($records.Count -eq 1 -and $records[0].status -cin @('Completed', 'Partial', 'Skipped')) {
        Test-ApimCollectorOutput -RunPath $RunPath -Environment $Context.Environment -Collector $records[0]
        if ($records[0].status -cne 'Skipped') {
            $usage = Get-ApimCompleteRouteAggregate -Context $Context -Family Usage -Payload (
                Read-ApimLogEvidence -RunPath $RunPath -Kind usageByRoute
            )
            $listeners = Get-ApimCompleteRouteAggregate -Context $Context -Family AppGateway -Payload (
                Read-ApimObservedRouteEvidence -RunPath $RunPath -Kind appgwByListener
            )
        }
    }
    $routes = @(Get-ApimPublishedRouteSet -Service $Service -AppGateways $AppGateways)
    $result = [ordered]@{}
    foreach ($api in $Apis) {
        $gaps = [Collections.Generic.List[string]]::new()
        $via = $null; $internal = $null; $confidence = 'Medium'
        if ($null -eq $usage -or $Context.Settings.appGwSubnetCidrs.Count -eq 0) {
            $gaps.Add('usage')
            if ($Context.Settings.appGwSubnetCidrs.Count -eq 0) { $gaps.Add('appGwSubnet') }
        }
        else {
            $apiRows = @($usage.Rows | Where-Object apiId -IEQ $api.apiId)
            $via = 0L; $internal = 0L
            foreach ($row in $apiRows) {
                if ($row.route -ceq 'ViaAppGw') { $via += $row.calls }
                elseif ($row.route -ceq 'Internal') { $internal += $row.calls }
            }
            $via = ConvertTo-ApimTelemetryNumber -Value $via -Integer
            $internal = ConvertTo-ApimTelemetryNumber -Value $internal -Integer
            $confidence = 'High'
            if ($usage.Window.isCapped) { $gaps.Add('usageWindowCapped'); $confidence = 'Medium' }
            if (@($apiRows | Where-Object { $_.route -ceq 'Unknown' -and $_.calls -gt 0 }).Count) {
                $via = $null; $gaps.Add('unknownCallerRoute'); $confidence = 'Medium'
            }
            if ($null -ne $via -and $via -gt 0) {
                $paths = @($Operations | Where-Object apiId -IEQ $api.apiId | ForEach-Object fullPath)
                $matching = @(
                    foreach ($route in $routes) {
                        if ($route.rewriteUnresolved -or @($paths | Where-Object {
                                    Test-ApimExposurePathMatch -Pattern $route.pattern -Path $_
                                }).Count) { $route }
                    }
                )
                $public = @($matching | Where-Object frontendType -CEQ Public)
                $private = @($matching | Where-Object frontendType -CEQ Private)
                if ($public.Count -gt 1) {
                    $via = $null; $gaps.Add('routeAttribution'); $confidence = 'Medium'
                }
                elseif ($private.Count -gt 0 -and $public.Count -gt 0) {
                    $usable = $null -ne $listeners -and
                        [datetimeoffset] $listeners.Window.startUtc -eq [datetimeoffset] $usage.Window.startUtc -and
                        [datetimeoffset] $listeners.Window.endUtc -eq [datetimeoffset] $usage.Window.endUtc
                    $publicCalls = 0L; $privateCalls = 0L; $unmapped = $false
                    if ($usable) {
                        foreach ($row in $listeners.Rows) {
                            if ($row.calls -eq 0) { continue }
                            $mapped = @($routes | Where-Object {
                                    $_.gatewayId -ieq $row.gatewayId -and $_.listener -ieq $row.listener -and
                                    $_.ruleName -ieq $row.rule
                                })
                            if ($mapped.Count -eq 0) { $unmapped = $true; continue }
                            if (@($private | Where-Object {
                                        $_.gatewayId -ieq $row.gatewayId -and $_.listener -ieq $row.listener -and
                                        $_.ruleName -ieq $row.rule
                                    }).Count) { $privateCalls += $row.calls }
                            if (@($public | Where-Object {
                                        $_.gatewayId -ieq $row.gatewayId -and $_.listener -ieq $row.listener -and
                                        $_.ruleName -ieq $row.rule
                                    }).Count) { $publicCalls += $row.calls }
                        }
                    }
                    if (-not $usable -or $unmapped -or $privateCalls -gt 0 -or $publicCalls -eq 0) {
                        $via = $null; $gaps.Add('privateListener')
                    }
                    $confidence = 'Medium'
                }
            }
        }
        $result[$api.apiId] = [pscustomobject]@{
            callsViaAppGw = $via; callsInternal = $internal; confidence = $confidence
            missingInputs = @($gaps | Sort-Object -Unique -CaseSensitive)
        }
    }
    return $result
}

function Test-ApimSavedExposureModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Models
    )

    $settingsPath = Resolve-RunFilePath -RunPath $RunPath -RelativePath 'restricted/run-settings.json'
    Test-ConfigPathLink -Path $settingsPath -Context 'Exposure settings'
    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) { return }
    $context = Get-ApimRunSetting -RunPath $RunPath
    if ($context.Settings.schemaVersion -cne '1.2') { return }
    $required = @('Service', 'Apis', 'Products', 'Policies', 'Network')
    foreach ($name in $required) {
        $records = @($context.Manifest.collectors | Where-Object name -CEQ $name)
        if ($records.Count -ne 1 -or $records[0].status -cne 'Completed') {
            throw 'Saved observed exposure is missing required collection evidence.'
        }
        Test-ApimCollectorOutput -RunPath $RunPath -Environment $context.Environment `
            -Collector $records[0] -CompletePolicyInventory
    }
    $diagnostics = @($context.Manifest.collectors | Where-Object {
            $_.name -ceq 'Diagnostics' -and $_.status -ceq 'Completed'
        }).Count -eq 1
    $api = Get-ApimSavedApiModel -RunPath $RunPath -DiagnosticsAvailable $diagnostics
    $service = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath raw/service.json
    $network = Get-ApimSavedNetworkModel -RunPath $RunPath -Context $context -Service $service
    $gateways = @($network.Gateways)
    if ((Get-ApimConfigDigest -Config @{ network = $network.Network }) -cne
        (Get-ApimConfigDigest -Config @{ network = $Models.network })) {
        throw 'Saved exposure network does not match its validated sources and settings.'
    }
    $observed = Get-ApimSavedRouteUsage -RunPath $RunPath -Context $context -Apis $api.Model.apis `
        -Operations $api.Model.operations -Service $service -AppGateways $gateways
    $exposure = @(Get-ApimExposureModel -Apis $api.Model.apis -Operations $api.Model.operations `
            -Network $Models.network -Service $service -AppGateways $gateways -PolicyPaths $api.PolicyPaths `
            -AppGwSubnetCidrs $context.Settings.appGwSubnetCidrs -ObservedUsage $observed `
            -Edge "$($context.Config.Edge.Provider)-Assumed")
    $expected = @(ConvertTo-ApimApiExposureModel -Apis $api.Model.apis -ExposureRecords $exposure `
            -ObservedUsage $observed)
    if ($expected.Count -ne $Models.apis.Count) { throw 'Saved exposure API inventory is inconsistent.' }
    if ((Get-ApimConfigDigest -Config @{ rows = $exposure }) -cne
        (Get-ApimConfigDigest -Config @{ rows = @($Models.exposure | Sort-Object gateway, listener, pattern, apiId) })) {
        throw 'Saved exposure model does not match its validated sources and settings.'
    }
    foreach ($row in $expected) {
        $actual = @($Models.apis | Where-Object apiId -CEQ $row.apiId)
        if ($actual.Count -ne 1) { throw 'Saved exposure API inventory is inconsistent.' }
        foreach ($field in @('reachability', 'exposure', 'callsViaAppGw', 'callsInternal')) {
            if ($actual[0].$field -cne $row.$field) {
                throw 'Saved API exposure does not match its validated sources and settings.'
            }
        }
        foreach ($gap in $row.missingInputs) {
            if ($gap -cnotin $actual[0].missingInputs) {
                throw 'Saved API exposure is missing its evidence qualifications.'
            }
        }
    }
}
