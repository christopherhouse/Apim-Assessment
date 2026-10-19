#Requires -Version 7.4

Set-StrictMode -Version Latest

function Read-ApimSmokeOutputJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RelativePath,

        [switch] $Collection
    )

    $path = Resolve-RunFilePath -RunPath $RunPath -RelativePath $RelativePath
    Test-ConfigPathLink -Path $path -Context 'Smoke output'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'Smoke output is missing a required file.'
    }
    try {
        $payload = Get-Content -LiteralPath $path -Raw -ErrorAction Stop |
            ConvertFrom-Json -Depth 100 -ErrorAction Stop
    }
    catch {
        throw 'Smoke output contains invalid JSON.'
    }
    if ($payload -isnot [pscustomobject]) {
        throw 'Smoke output has an invalid JSON object.'
    }
    if ($Collection -and
        ($null -eq $payload.PSObject.Properties['value'] -or
            $payload.value -isnot [array])) {
        throw 'Smoke output has an invalid collection.'
    }
    return $payload
}

function Test-ApimSmokeOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Result,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Environment
    )

    Test-ConfigPathLink -Path $RunPath -Context 'Smoke run'
    Test-ConfigPathLink -Path (Join-Path $RunPath 'manifest.json') `
        -Context 'Smoke manifest'
    $manifest = Get-RunManifest -RunPath $RunPath
    $expectedNames = @((Get-ApimCollectorRegistry).Name)
    $telemetryNames = @()
    if ($manifest.schemaVersion -ceq '1.2') {
        $telemetryNames = @((Get-ApimTelemetryCollectorRegistry).Name)
        $expectedNames += $telemetryNames
        $saved = Get-ApimRunSetting -RunPath $RunPath
        if ($saved.Settings.schemaVersion -cne '1.2') {
            throw 'Smoke telemetry settings do not include observed-route collection.'
        }
    }
    if ($manifest.runId -ne $Result.RunId -or
        $manifest.environment -ne $Environment.Name -or
        $null -eq $manifest.completedUtc -or
        $manifest.stages.collect -ne $Result.Status -or
        $manifest.stages.analyze -ne 'NotStarted' -or
        $manifest.stages.report -ne 'NotStarted' -or
        @($Result.Checks).Count -ne $expectedNames.Count -or
        @($manifest.collectors).Count -ne $expectedNames.Count) {
        throw 'Smoke manifest does not match the completed run.'
    }

    $collectors = @{}
    foreach ($collector in $manifest.collectors) {
        if ($collectors.ContainsKey($collector.name)) {
            throw 'Smoke manifest contains a duplicate collector.'
        }
        $collectors[$collector.name] = $collector
    }
    for ($index = 0; $index -lt $expectedNames.Count; $index++) {
        $name = $expectedNames[$index]
        if ($Result.Checks[$index].Name -cne $name -or
            -not $collectors.ContainsKey($name) -or
            $collectors[$name].status -cne $Result.Checks[$index].Status) {
            throw 'Smoke manifest collector status does not match the run.'
        }
    }

    $completed = @($Result.Checks | Where-Object Status -EQ Completed)
    $incomplete = @($Result.Checks | Where-Object {
            $_.Status -cne 'Completed' -and
            -not ($_.Name -cin @('LogAnalytics', 'Cost', 'LogicApps') -and
                $_.Status -ceq 'Skipped')
        })
    if (($Result.Status -eq 'Completed') -ne
        ($incomplete.Count -eq 0)) {
        throw 'Smoke run status does not match its collectors.'
    }

    foreach ($check in $completed) {
        Test-ApimCollectorOutput -RunPath $RunPath -Environment $Environment `
            -Collector $collectors[$check.Name]
    }
    foreach ($check in @($Result.Checks | Where-Object {
                ($_.Status -ceq 'Partial' -and
                    $_.Name -cin @('Identity', 'Portal', 'OpenApi', 'Organization')) -or
                ($_.Name -cin $telemetryNames -and $_.Status -cin @('Partial', 'Skipped'))
            })) {
        Test-ApimCollectorOutput -RunPath $RunPath -Environment $Environment `
            -Collector $collectors[$check.Name]
    }
}

function Get-ApimSmokeQueryCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][object] $Result
    )

    $logCheck = @($Result.Checks | Where-Object Name -CEQ LogAnalytics)
    if ($logCheck.Count -eq 0) { return }
    foreach ($kind in @('appgwByListener', 'appgwNonEdge', 'directNonAppGw', 'headersLogged')) {
        $status = if ($logCheck[0].Status -cin @('Failed', 'Skipped')) {
            $logCheck[0].Status
        }
        else {
            $payload = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath "logs/$kind.json"
            $statuses = @($payload.workspaces.status | Sort-Object -Unique)
            if ($statuses.Count -eq 1 -and
                $statuses[0] -cin @('Completed', 'Partial', 'Failed', 'Skipped')) {
                $statuses[0]
            }
            else { 'Partial' }
        }
        [pscustomobject]@{ Name = $kind; Status = $status }
    }
}

function Get-ApimAuthSavedFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Collector,
        [Parameter(Mandatory)][string[]] $Expected
    )

    $property = $Collector.PSObject.Properties['files']
    if ($null -eq $property -or $property.Value -isnot [array]) {
        throw 'Authentication collector file inventory is missing or invalid.'
    }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($file in $property.Value) {
        if ($file -isnot [string] -or $file -cnotin $Expected -or -not $seen.Add($file)) {
            throw 'Authentication collector file inventory is invalid.'
        }
    }
    if (($Collector.status -ceq 'Completed' -and $seen.Count -ne $Expected.Count) -or
        ($Collector.status -ceq 'Partial' -and
            ($seen.Count -eq 0 -or $seen.Count -ge $Expected.Count)) -or
        $Collector.status -cnotin @('Completed', 'Partial')) {
        throw 'Authentication collector file inventory does not match its status.'
    }
    return @($property.Value)
}

function Test-ApimAuthSavedProjection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Payload,
        [Parameter(Mandatory)][object] $Projection
    )

    # Compare JSON data, not PowerShell's extended scalar properties. Object
    # member order is immaterial; field presence, nulls and array order are not.
    $actual = [System.Text.Json.Nodes.JsonNode]::Parse(
        (ConvertTo-Json -InputObject $Payload -Depth 30 -Compress)
    )
    $expected = [System.Text.Json.Nodes.JsonNode]::Parse(
        (ConvertTo-Json -InputObject $Projection -Depth 30 -Compress)
    )
    return [System.Text.Json.Nodes.JsonNode]::DeepEquals($actual, $expected)
}

function Test-ApimCollectorOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Environment,

        [Parameter(Mandatory)]
        [object] $Collector,

        [switch] $CompletePolicyInventory
    )

        $name = $Collector.name
        $items = [int] $Collector.items
        $apiNames = @()
        if ($name -in @('Diagnostics', 'Policies')) {
            $apis = Read-ApimSmokeOutputJson -RunPath $RunPath `
                -RelativePath 'raw/apis.json' -Collection
            $apiNames = @(Get-ApimCollectionResourceName -Payload $apis `
                    -CollectionName 'APIM API')
        }
        $actual = switch ($name) {
            'LogAnalytics' { Test-ApimLogSavedOutput -RunPath $RunPath -Collector $Collector }
            'Metrics' { Test-ApimMetricSavedOutput -RunPath $RunPath -Collector $Collector }
            'Cost' { Test-ApimCostSavedOutput -RunPath $RunPath -Collector $Collector }
            'LogicApps' { Test-ApimLogicAppSavedOutput -RunPath $RunPath -Collector $Collector }
            'Organization' {
                Test-ApimOrganizationSavedOutput -RunPath $RunPath -Collector $Collector
            }
            'OpenApi' {
                Test-ApimOpenApiSavedOutput -RunPath $RunPath -Collector $Collector
            }
            'Service' {
                $null = Read-ApimSmokeOutputJson -RunPath $RunPath `
                    -RelativePath 'raw/service.json'
                1
            }
            'Apis' {
                $apis = Read-ApimSmokeOutputJson -RunPath $RunPath `
                    -RelativePath 'raw/apis.json' -Collection
                $apiNames = @(Get-ApimCollectionResourceName -Payload $apis `
                        -CollectionName 'APIM API')
                foreach ($apiName in $apiNames) {
                    $segment = ConvertTo-ApimResourceSegment -Value $apiName
                    foreach ($directory in @('apiRevisions', 'operations', 'apiTags')) {
                        $null = Read-ApimSmokeOutputJson -RunPath $RunPath `
                            -RelativePath "raw/$directory/$segment.json" -Collection
                    }
                }
                $apiNames.Count
            }
            'Products' {
                $products = Read-ApimSmokeOutputJson -RunPath $RunPath `
                    -RelativePath 'raw/products.json' -Collection
                $productNames = @(Get-ApimCollectionResourceName `
                        -Payload $products -CollectionName 'APIM product')
                foreach ($productName in $productNames) {
                    $segment = ConvertTo-ApimResourceSegment -Value $productName
                    foreach ($directory in @('productApis', 'productGroups')) {
                        $null = Read-ApimSmokeOutputJson -RunPath $RunPath `
                            -RelativePath "raw/$directory/$segment.json" -Collection
                    }
                }
                $productNames.Count
            }
            'Subscriptions' {
                $subscriptions = Read-ApimSmokeOutputJson -RunPath $RunPath `
                    -RelativePath 'raw/subscriptions.json' -Collection
                $subscriptions.value.Count
            }
            'Identity' {
                $count = 0
                $expected = @('raw/identityProviders.json', 'raw/authorizationServers.json',
                    'raw/openidConnectProviders.json', 'raw/authorizationProviders.json')
                $files = @(Get-ApimAuthSavedFile -Collector $Collector -Expected $expected)
                foreach ($kind in @('identityProviders', 'authorizationServers',
                        'openidConnectProviders', 'authorizationProviders')) {
                    if ("raw/$kind.json" -cnotin $files) { continue }
                    $payload = Read-ApimSmokeOutputJson -RunPath $RunPath `
                        -RelativePath "raw/$kind.json" -Collection
                    $safe = ConvertTo-ApimAuthCollection -Payload $payload -Kind $kind -Saved
                    # Closed shape, types and enum validation also gates reuse.
                    if (-not (Test-ApimAuthSavedProjection -Payload $payload -Projection $safe)) {
                        throw 'Identity saved output is not allowlisted.'
                    }
                    $count += $safe.value.Count
                }
                $count
            }
            'Portal' {
                $count = 0
                $files = @(Get-ApimAuthSavedFile -Collector $Collector `
                    -Expected @((Get-ApimPortalEndpoint).File))
                foreach ($endpoint in Get-ApimPortalEndpoint) {
                    if ($endpoint.File -cnotin $files) { continue }
                    $payload = Read-ApimSmokeOutputJson -RunPath $RunPath `
                        -RelativePath $endpoint.File
                    $safe = if ($endpoint.Kind -eq 'revisions') {
                        ConvertTo-ApimAuthCollection -Payload $payload -Kind revisions
                    }
                    else {
                        ConvertTo-ApimPortalResource -Resource $payload -Kind $endpoint.Kind
                    }
                    if (-not (Test-ApimAuthSavedProjection -Payload $payload -Projection $safe)) {
                        throw 'Portal saved output is not allowlisted.'
                    }
                    $count += if ($endpoint.Kind -eq 'revisions') { $safe.value.Count }
                        else { 1 }
                }
                $count
            }
            'SecurityAssets' {
                $count = 0
                foreach ($file in @('namedValues', 'backends', 'certificates')) {
                    $payload = Read-ApimSmokeOutputJson -RunPath $RunPath `
                        -RelativePath "raw/$file.json" -Collection
                    $count += $payload.value.Count
                }
                $count
            }
            'Diagnostics' {
                $count = 0
                foreach ($file in @('loggers', 'diagnostics')) {
                    $payload = Read-ApimSmokeOutputJson -RunPath $RunPath `
                        -RelativePath "raw/$file.json" -Collection
                    $count += $payload.value.Count
                }
                foreach ($apiName in $apiNames) {
                    $segment = ConvertTo-ApimResourceSegment -Value $apiName
                    $payload = Read-ApimSmokeOutputJson -RunPath $RunPath `
                        -RelativePath "raw/apiDiagnostics/$segment.json" -Collection
                    $count += $payload.value.Count
                }
                $count
            }
            'Policies' {
                $index = Read-ApimSmokeOutputJson -RunPath $RunPath `
                    -RelativePath 'policies/index.json'
                if ($index.schemaVersion -cne '1.0' -or
                    $index.policies -isnot [array]) {
                    throw 'Smoke policy index is invalid.'
                }
                foreach ($policy in $index.policies) {
                    if ($policy.file -cnotmatch
                        '^policies/(global|(?:product|api|op|fragment)\.[A-Za-z0-9._~%-]+)\.xml$' -or
                        $policy.exists -isnot [bool]) {
                        throw 'Smoke policy index contains an invalid entry.'
                    }
                    $path = Resolve-RunFilePath -RunPath $RunPath `
                        -RelativePath $policy.file
                    Test-ConfigPathLink -Path $path -Context 'Smoke policy'
                    if ($policy.exists) {
                        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
                            $policy.sha256 -cnotmatch '^[a-f0-9]{64}$') {
                            throw 'Smoke policy output is missing or invalid.'
                        }
                        $xml = Get-Content -LiteralPath $path -Raw `
                            -ErrorAction Stop
                        if ((Get-ApimPolicySha256 -Xml $xml) -cne
                            $policy.sha256) {
                            throw 'Smoke policy hash does not match the index.'
                        }
                    }
                    elseif ($null -ne $policy.sha256 -or
                        (Test-Path -LiteralPath $path)) {
                        throw 'Smoke policy absence does not match the index.'
                    }
                }
                if ($CompletePolicyInventory) {
                    $expected = [Collections.Generic.HashSet[string]]::new(
                        [StringComparer]::Ordinal
                    )
                    $null = $expected.Add('Global|global')
                    $products = Read-ApimSmokeOutputJson -RunPath $RunPath `
                        -RelativePath 'raw/products.json' -Collection
                    foreach ($product in Get-ApimCollectionResourceName `
                            -Payload $products -CollectionName 'APIM product') {
                        $null = $expected.Add("Product|$product")
                    }
                    foreach ($api in $apiNames) {
                        $null = $expected.Add("Api|$api")
                        $segment = ConvertTo-ApimResourceSegment -Value $api
                        $operations = Read-ApimSmokeOutputJson -RunPath $RunPath `
                            -RelativePath "raw/operations/$segment.json" -Collection
                        foreach ($operation in Get-ApimCollectionResourceName `
                                -Payload $operations -CollectionName 'APIM operation') {
                            $null = $expected.Add("Operation|$api|$operation")
                        }
                    }
                    $seen = [Collections.Generic.HashSet[string]]::new(
                        [StringComparer]::Ordinal
                    )
                    $files = [Collections.Generic.HashSet[string]]::new(
                        [StringComparer]::Ordinal
                    )
                    foreach ($policy in $index.policies) {
                        $key = "$($policy.scopeType)|$($policy.scope)"
                        if (-not $seen.Add($key) -or -not $files.Add($policy.file) -or
                            ($policy.scopeType -cne 'Fragment' -and
                                -not $expected.Contains($key)) -or
                            $policy.scopeType -cnotin @('Global', 'Product', 'Api', 'Operation', 'Fragment')) {
                            throw 'Policy scope inventory is invalid.'
                        }
                        $expectedFile = switch -CaseSensitive ($policy.scopeType) {
                            Global { 'policies/global.xml' }
                            Product { 'policies/product.{0}.xml' -f (ConvertTo-ApimResourceSegment -Value $policy.scope) }
                            Api { 'policies/api.{0}.xml' -f (ConvertTo-ApimResourceSegment -Value $policy.scope) }
                            Fragment { 'policies/fragment.{0}.xml' -f (ConvertTo-ApimResourceSegment -Value $policy.scope) }
                            Operation {
                                $parts = $policy.scope.Split('|')
                                if ($parts.Count -ne 2) { throw 'Policy scope inventory is invalid.' }
                                'policies/op.{0}.{1}.xml' -f (
                                    ConvertTo-ApimResourceSegment -Value $parts[0]
                                ), (ConvertTo-ApimResourceSegment -Value $parts[1])
                            }
                        }
                        if ($policy.file -cne $expectedFile) {
                            throw 'Policy scope file binding is invalid.'
                        }
                    }
                    foreach ($key in $expected) {
                        if (-not $seen.Contains($key)) {
                            throw 'Policy scope inventory is incomplete.'
                        }
                    }
                }
                $index.policies.Count
            }
            'Network' {
                $directory = Resolve-RunFilePath -RunPath $RunPath `
                    -RelativePath 'raw/network'
                Test-ConfigPathLink -Path $directory -Context 'Smoke network'
                foreach ($file in @(
                        'apimSubnet', 'nsgs', 'privateEndpoints',
                        'privateDnsZones', 'routeTables', 'publicIps', 'frontDoors'
                    )) {
                    $null = Read-ApimSmokeOutputJson -RunPath $RunPath `
                        -RelativePath "raw/network/$file.json" -Collection
                }
                foreach ($gateway in @($Environment.AppGateways)) {
                    $segment = ConvertTo-ApimResourceSegment -Value $gateway.Name
                    $null = Read-ApimSmokeOutputJson -RunPath $RunPath `
                        -RelativePath "raw/network/appgw.$segment.json"
                }
                $files = @(Get-ChildItem -LiteralPath $directory -File `
                        -ErrorAction Stop)
                foreach ($file in $files) {
                    if ($file.Extension -cne '.json' -or
                        $file.Name -cnotmatch
                        '^(?:apimSubnet|nsgs|privateEndpoints|privateDnsZones|routeTables|publicIps|frontDoors|appgw\.[A-Za-z0-9._~%-]+|wafPolicy\.[A-Za-z0-9._~%-]+)\.json$') {
                        throw 'Smoke network output contains an unexpected file.'
                    }
                    $null = Read-ApimSmokeOutputJson -RunPath $RunPath `
                        -RelativePath "raw/network/$($file.Name)"
                }
                $files.Count
            }
            default { throw 'Collector output validation is unavailable.' }
        }
        if ($items -ne $actual) {
            throw 'Smoke collector item count does not match saved output.'
        }
}
