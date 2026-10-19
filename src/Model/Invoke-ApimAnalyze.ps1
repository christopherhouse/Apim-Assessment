#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimSavedPolicyMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunPath
    )

    $index = Read-ApimSmokeOutputJson -RunPath $RunPath `
        -RelativePath 'policies/index.json'
    $maps = @{
        Global = @{}
        Product = @{}
        Api = @{}
        Operation = @{}
        Fragment = @{}
    }
    foreach ($entry in $index.policies) {
        $xml = if ($entry.exists) {
            $path = Resolve-RunFilePath -RunPath $RunPath -RelativePath $entry.file
            Test-ConfigPathLink -Path $path -Context 'Saved policy'
            Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        }
        else { $null }
        $maps[$entry.scopeType].Add($entry.scope, $xml)
    }
    return $maps
}

function Get-ApimSavedApiModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [bool] $DiagnosticsAvailable
    )

    $apis = Read-ApimSmokeOutputJson -RunPath $RunPath `
        -RelativePath 'raw/apis.json' -Collection
    $products = Read-ApimSmokeOutputJson -RunPath $RunPath `
        -RelativePath 'raw/products.json' -Collection
    $operations = @{}
    $revisions = @{}
    $tags = @{}
    $memberships = @{}
    $diagnostics = @{}
    foreach ($api in $apis.value) {
        if (-not $api.properties.isCurrent) { continue }
        $segment = ConvertTo-ApimResourceSegment -Value $api.name
        $operations[$api.name] = Read-ApimSmokeOutputJson -RunPath $RunPath `
            -RelativePath "raw/operations/$segment.json" -Collection
        $revisions[$api.name] = Read-ApimSmokeOutputJson -RunPath $RunPath `
            -RelativePath "raw/apiRevisions/$segment.json" -Collection
        $tags[$api.name] = Read-ApimSmokeOutputJson -RunPath $RunPath `
            -RelativePath "raw/apiTags/$segment.json" -Collection
        if ($DiagnosticsAvailable) {
            $diagnostics[$api.name] = Read-ApimSmokeOutputJson -RunPath $RunPath `
                -RelativePath "raw/apiDiagnostics/$segment.json" -Collection
        }
    }
    foreach ($product in $products.value) {
        $segment = ConvertTo-ApimResourceSegment -Value $product.name
        $memberships[$product.name] = Read-ApimSmokeOutputJson -RunPath $RunPath `
            -RelativePath "raw/productApis/$segment.json" -Collection
    }
    $policies = Get-ApimSavedPolicyMap -RunPath $RunPath
    $flags = @(
        foreach ($api in $apis.value) {
            if (-not $api.properties.isCurrent) { continue }
            $productNames = @(
                foreach ($product in $products.value) {
                    if ($api.name -cin @($memberships[$product.name].value |
                            ForEach-Object { $_.name })) {
                        [string] $product.name
                    }
                }
            )
            foreach ($operation in $operations[$api.name].value) {
                $parameters = @{
                    GlobalPolicy = $policies.Global['global']
                    ProductPolicies = $policies.Product
                    ProductNames = $productNames
                    ApiPolicy = $policies.Api[$api.name]
                    OperationPolicy = $policies.Operation["$($api.name)|$($operation.name)"]
                    Fragments = $policies.Fragment
                    ApiName = $api.name
                    OperationName = $operation.name
                }
                foreach ($path in Merge-ApimPolicy @parameters) {
                    $fact = Get-ApimPolicyFlags -EffectiveXml $path.effectiveXml `
                        -BaseMissing $path.baseMissing
                    $record = [ordered]@{
                        product = $path.product
                        apiId = $path.apiId
                        operationId = $path.operationId
                    }
                    foreach ($property in $fact.PSObject.Properties) {
                        $record[$property.Name] = $property.Value
                    }
                    [pscustomobject] $record
                }
            }
        }
    )
    $arguments = @{
        ApisPayload = $apis
        OperationsByApi = $operations
        RevisionsByApi = $revisions
        TagsByApi = $tags
        ProductsPayload = $products
        ProductApisByProduct = $memberships
        PolicyFlags = $flags
    }
    if ($DiagnosticsAvailable) {
        $arguments.ServiceDiagnosticsPayload = Read-ApimSmokeOutputJson `
            -RunPath $RunPath -RelativePath 'raw/diagnostics.json' -Collection
        $arguments.DiagnosticsByApi = $diagnostics
    }
    return [pscustomobject]@{
        Model = Get-ApimApiPolicyModel @arguments
        PolicyPaths = $flags
    }
}

function Get-ApimSavedPortalModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][object] $Manifest,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Config,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Environment,
        [AllowNull()][object] $ServicePayload,
        [Parameter(Mandatory)][bool] $ProductsAvailable
    )

    $portalRecords = @($Manifest.collectors | Where-Object name -CEQ Portal)
    if ($portalRecords.Count -eq 0) { return $null }
    $portal = @{}
    $identity = $null
    foreach ($record in @($Manifest.collectors | Where-Object {
                $_.name -cin @('Portal', 'Identity') -and
                $_.status -cin @('Completed', 'Partial')
            })) {
        Test-ApimCollectorOutput -RunPath $RunPath -Environment $Environment -Collector $record
        foreach ($file in $record.files) {
            if ($record.name -ceq 'Portal' -and $file -cin @(
                    'raw/portal/signin.json', 'raw/portal/signup.json',
                    'raw/portal/delegation.json', 'raw/portal/config.json', 'raw/portal/revisions.json'
                )) {
                $name = [IO.Path]::GetFileNameWithoutExtension($file)
                $portal[$name] = Read-ApimSmokeOutputJson -RunPath $RunPath `
                    -RelativePath $file
            }
            elseif ($record.name -ceq 'Identity' -and $file -ceq 'raw/identityProviders.json') {
                $identity = Read-ApimSmokeOutputJson -RunPath $RunPath `
                    -RelativePath $file -Collection
            }
        }
    }
    $products = $null
    $groups = @{}
    if ($ProductsAvailable) {
        $products = Read-ApimSmokeOutputJson -RunPath $RunPath `
            -RelativePath 'raw/products.json' -Collection
        foreach ($product in $products.value) {
            $segment = ConvertTo-ApimResourceSegment -Value $product.name
            $groups[$product.name] = Read-ApimSmokeOutputJson -RunPath $RunPath `
                -RelativePath "raw/productGroups/$segment.json" -Collection
        }
    }
    $intent = @(if ($Config.Contains('Portal')) { $Config.Portal.ProductVisibility })
    return Get-ApimPortalModel -ServicePayload $ServicePayload -PortalPayloads $portal `
        -IdentityProvidersPayload $identity -ProductsPayload $products -ProductGroups $groups `
        -ProductVisibility $intent
}

function Get-ApimSavedNetworkModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][object] $Context,
        [Parameter(Mandatory)][object] $Service
    )

    $arguments = @{ Service = $Service }
    $gateways = @(
        foreach ($gateway in $Context.Environment.AppGateways) {
            $segment = ConvertTo-ApimResourceSegment -Value $gateway.Name
            Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath "raw/network/appgw.$segment.json"
        }
    )
    $arguments.AppGateways = $gateways
    $arguments.WafPolicies = @(
        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $RunPath 'raw/network') `
                -Filter 'wafPolicy.*.json' -File -ErrorAction Stop) {
            Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath "raw/network/$($file.Name)"
        }
    )
    foreach ($entry in @(
            @('ApimSubnetPayload', 'apimSubnet'), @('NsgPayload', 'nsgs'),
            @('PublicIpPayload', 'publicIps'), @('FrontDoorPayload', 'frontDoors')
        )) {
        $arguments[$entry[0]] = Read-ApimSmokeOutputJson -RunPath $RunPath `
            -RelativePath "raw/network/$($entry[1]).json" -Collection
    }
    return [pscustomobject]@{ Network = Get-ApimNetworkModel @arguments; Gateways = $gateways }
}

function Invoke-ApimAnalyze {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunFolder,

        [string] $RulesPath,

        [string[]] $OnlyRules,

        [string[]] $CompareRuns
    )

    if (@($PSBoundParameters.Keys | Where-Object {
                $_ -cin @('RulesPath', 'OnlyRules')
            }).Count -gt 0) {
        return [pscustomobject]@{ Status = 'Failed'; ExitCode = 1; ErrorCode = 'CAPABILITY_UNAVAILABLE' }
    }
    try {
        $context = Get-ApimRunSetting -RunPath $RunFolder
        Set-RunStageStatus -RunPath $RunFolder -Stage analyze -Status InProgress
        Set-RunStageStatus -RunPath $RunFolder -Stage report -Status NotStarted
        $manifest = $context.Manifest
        $manifest.modelSafe.build = 'NotStarted'
        $manifest.modelSafe.validation = 'NotRun'
        $manifest.modelSafe.promotion = 'NotStarted'
        $manifest.modelSafe.packageSha256 = $null
        $null = Save-RunManifest -RunPath $RunFolder -Manifest $manifest
        $available = @{}
        foreach ($check in Get-ApimCollectorRegistry) {
            $records = @($manifest.collectors | Where-Object name -CEQ $check.Name)
            if ($records.Count -gt 1) { throw 'Duplicate collector.' }
            $available[$check.Name] = $records.Count -eq 1 -and
                $records[0].status -ceq 'Completed'
            if ($available[$check.Name]) {
                Test-ApimCollectorOutput -RunPath $RunFolder `
                    -Environment $context.Environment -Collector $records[0] `
                    -CompletePolicyInventory
            }
        }
        foreach ($relative in @(
                @($script:ApimModelSchemaPaths.Keys | ForEach-Object { "model/$_.json" })
                'findings.json'
                'restricted/openapi-binding.json'
            )) {
            $path = Resolve-RunFilePath -RunPath $RunFolder -RelativePath $relative
            Test-ConfigPathLink -Path $path -Context 'Prior analysis output'
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            }
        }
        $models = [ordered]@{}
        $service = $null
        $apiModel = $null
        $gateways = @()
        if ($available.Service) {
            $service = Read-ApimSmokeOutputJson -RunPath $RunFolder `
                -RelativePath 'raw/service.json'
            $models.service = Get-ApimServiceSecurityModel -ServicePayload $service
        }
        if ($available.Apis -and $available.Products -and $available.Policies) {
            $apiModel = Get-ApimSavedApiModel -RunPath $RunFolder `
                -DiagnosticsAvailable $available.Diagnostics
            $models.apis = @($apiModel.Model.apis)
            $models.operations = @($apiModel.Model.operations)
            $models.policyMatrix = @($apiModel.Model.policyMatrix)
        }
        if ($available.Subscriptions) {
            $models.subscriptions = @(Get-ApimSubscriptionModel -SubscriptionsPayload (
                    Read-ApimSmokeOutputJson -RunPath $RunFolder `
                        -RelativePath 'raw/subscriptions.json' -Collection
                ))
        }
        if ($available.SecurityAssets) {
            $assets = Get-ApimSecurityAssetModel -NamedValuesPayload (
                Read-ApimSmokeOutputJson -RunPath $RunFolder `
                    -RelativePath 'raw/namedValues.json' -Collection
            ) -BackendsPayload (
                Read-ApimSmokeOutputJson -RunPath $RunFolder `
                    -RelativePath 'raw/backends.json' -Collection
            ) -CertificatesPayload (
                Read-ApimSmokeOutputJson -RunPath $RunFolder `
                    -RelativePath 'raw/certificates.json' -Collection
            )
            foreach ($name in @('namedValues', 'backends', 'certificates')) {
                $models[$name] = @($assets.$name)
            }
        }
        if ($available.Service -and $available.Network) {
            $network = Get-ApimSavedNetworkModel -RunPath $RunFolder -Context $context -Service $service
            $gateways = @($network.Gateways)
            $models.network = $network.Network
            if ($null -ne $apiModel) {
                $observed = Get-ApimSavedRouteUsage -RunPath $RunFolder -Context $context `
                    -Apis $models.apis -Operations $models.operations -Service $service -AppGateways $gateways
                $models.exposure = @(Get-ApimExposureModel -Apis $models.apis `
                        -Operations $models.operations -Network $models.network `
                        -Service $service -AppGateways $gateways `
                        -PolicyPaths $apiModel.PolicyPaths `
                        -AppGwSubnetCidrs $context.Settings.appGwSubnetCidrs `
                        -ObservedUsage $observed `
                        -Edge "$($context.Config.Edge.Provider)-Assumed")
                $models.apis = @(ConvertTo-ApimApiExposureModel -Apis $models.apis `
                        -ExposureRecords $models.exposure -ObservedUsage $observed)
            }
        }
        $portal = Get-ApimSavedPortalModel -RunPath $RunFolder -Manifest $manifest `
            -Config $context.Config -Environment $context.Environment `
            -ServicePayload $service -ProductsAvailable $available.Products
        if ($null -ne $portal) { $models.portal = $portal }
        $governance = Get-ApimSavedGovernanceModel -RunPath $RunFolder -Context $context
        foreach ($name in $governance.Keys) { $models[$name] = $governance[$name] }
        $telemetry = Get-ApimSavedTelemetryModel -RunPath $RunFolder -Context $context `
            -Service $(if ($models.Contains('service')) { $models.service } else { $null })
        foreach ($name in $telemetry.Keys) { $models[$name] = $telemetry[$name] }
        if ($models.Contains('apis') -and $models.Contains('operations')) {
            $quality = Get-ApimSavedOpenApiQuality -RunPath $RunFolder -Context $context `
                -Apis $models.apis -Operations $models.operations
            if ($null -ne $quality) {
                $models.openApiQuality = @($quality.Rows)
                foreach ($api in $models.apis) {
                    $row = @($models.openApiQuality | Where-Object apiId -CEQ $api.apiId)
                    if ($row.Count -ne 1) { throw 'OpenAPI quality API coverage rejected.' }
                    $api.openApiScore = $row[0].score
                }
                Save-ApimOpenApiQualityBinding -RunPath $RunFolder -Quality $models.openApiQuality `
                    -Context $context -Exports $quality.Exports
            }
        }
        $driftArguments = @{ RunPath = $RunFolder }
        if ($PSBoundParameters.ContainsKey('CompareRuns')) {
            if (@($CompareRuns).Count -eq 0) { throw 'Comparison inputs are empty.' }
            $driftArguments.CompareRuns = $CompareRuns
        }
        else { $driftArguments.UseSavedInputs = $true }
        $drift = Save-ApimDriftModel @driftArguments
        if ($null -ne $drift) { $models.drift = @($drift) }
        $rules = @(Get-ApimRuleCatalog -CatalogPath $script:ApimReportRuleCatalogPath)
        $findings = @(Invoke-ApimRuleEngine -Rules $rules -Models $models `
                -Manifest $manifest -Config $context.Config)
        if ($models.Count -gt 0) {
            $null = Write-ApimModelSet -RunPath $RunFolder -Models $models
        }
        $null = Write-ApimFindingSet -RunPath $RunFolder -Findings $findings
        if (@($script:ApimModelSchemaPaths.Keys | Where-Object {
                    $_ -cnotin @('drift', 'portal', 'openApiQuality', 'products', 'diagnosticCoverage',
                        'usage', 'capacity', 'cost') -and
                    -not $models.Contains($_)
                }).Count -gt 0) {
            throw 'Required models could not be constructed.'
        }
        $null = Get-ApimModelSet -RunPath $RunFolder
        Set-RunStageStatus -RunPath $RunFolder -Stage analyze -Status Completed
        return [pscustomobject]@{ Status = 'Completed'; ExitCode = 0; ErrorCode = $null }
    }
    catch {
        $recorded = Set-ApimStageFailure -RunPath $RunFolder -Stage analyze
        return [pscustomobject]@{
            Status = 'Failed'; ExitCode = 4
            ErrorCode = if ($recorded) { 'ANALYSIS_FAILED' } else { 'RUN_STATE_FAILED' }
        }
    }
}
