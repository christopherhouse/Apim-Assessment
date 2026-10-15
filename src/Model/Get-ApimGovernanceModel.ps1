#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimProductGovernanceModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $ProductsPayload,
        [AllowEmptyCollection()][object[]] $ProductIntent = @()
    )

    Test-ConfigGovernance -Value @{ Products = @($ProductIntent) }
    $products = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($product in @(Get-ApimModelCollection -Payload $ProductsPayload -Context 'Governance products')) {
        $id = ConvertTo-ApimAuthName -Value (Get-ApimPortalValue $product @('name'))
        if (-not $products.TryAdd($id, $product)) { throw 'Governance product IDs are duplicated.' }
    }
    $intent = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($entry in $ProductIntent) { $intent.Add($entry.ProductId, $entry) }
    $rows = @(
        foreach ($id in @(@($products.Keys) + @($intent.Keys) | Sort-Object -Unique -CaseSensitive)) {
            $found = $products.ContainsKey($id)
            $missing = [Collections.Generic.List[string]]::new()
            $hasDescription = $null; $hasOwner = $null; $isExternal = $null; $approval = $null
            if ($found) {
                $properties = Get-ApimPortalValue $products[$id] @('properties')
                Test-ApimServiceModelMap -Value $properties -Context 'Governance product properties'
                $description = Get-ApimPortalValue $properties @('description')
                if ($null -ne $description -and $description -isnot [string]) {
                    throw 'Governance product description is invalid.'
                }
                $hasDescription = -not [string]::IsNullOrWhiteSpace($description)
                $approval = Get-ApimPortalBoolean $properties @('approvalRequired')
                if ($intent.ContainsKey($id)) {
                    $hasOwner = $intent[$id].HasOwner
                    $isExternal = $intent[$id].IsExternal
                }
                else {
                    $missing.Add('ownerIntent')
                    $missing.Add('externalIntent')
                }
                if ($isExternal -eq $true -and $null -eq $approval) { $missing.Add('approval') }
            }
            else { $missing.Add('product') }
            [pscustomobject][ordered]@{
                productId = $id; productFound = $found; hasDescription = $hasDescription
                hasOwner = $hasOwner; isExternal = $isExternal; approvalRequired = $approval
                modelStatus = if ($missing.Count) { 'Partial' } else { 'Complete' }
                missingInputs = @($missing | Sort-Object -CaseSensitive)
            }
        }
    )
    return ,$rows
}

function Get-ApimDiagnosticCoverageModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $ApisPayload,
        [AllowNull()][object] $LoggersPayload,
        [AllowNull()][object] $ServiceDiagnosticsPayload,
        [System.Collections.IDictionary] $DiagnosticsByApi = @{},
        [AllowNull()][System.Collections.IDictionary] $Governance,
        [Parameter(Mandatory)][string] $ServiceResourcePath
    )

    if ($null -ne $Governance) { Test-ConfigGovernance -Value $Governance }
    $apis = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($api in @(Get-ApimModelCollection -Payload $ApisPayload -Context 'Diagnostic API catalog')) {
        if ((Get-ApimPortalBoolean $api @('properties', 'isCurrent')) -ne $true) { continue }
        $id = ConvertTo-ApimAuthName -Value (Get-ApimPortalValue $api @('name'))
        if (-not $apis.TryAdd($id, $api)) { throw 'Diagnostic API IDs are duplicated.' }
    }
    $criticalKnown = $null -ne $Governance -and $Governance.Contains('CriticalApiIds')
    $critical = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if ($criticalKnown) {
        foreach ($id in $Governance.CriticalApiIds) { $null = $critical.Add($id) }
    }
    $loggerIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($null -ne $LoggersPayload) {
        foreach ($logger in @(Get-ApimModelCollection -Payload $LoggersPayload -Context 'Governance loggers')) {
            $name = ConvertTo-ApimAuthName -Value (Get-ApimPortalValue $logger @('name'))
            $null = $loggerIds.Add("/loggers/$name")
            $null = $loggerIds.Add("$ServiceResourcePath/loggers/$name")
        }
    }
    $serviceDiagnostics = @(if ($null -ne $ServiceDiagnosticsPayload) {
            Get-ApimModelCollection -Payload $ServiceDiagnosticsPayload -Context 'Governance service diagnostics'
        })
    $rows = @(
        foreach ($id in @(@($apis.Keys) + @($critical) | Sort-Object -Unique -CaseSensitive)) {
            $found = $apis.ContainsKey($id)
            $missing = [Collections.Generic.List[string]]::new()
            $configured = $null; $resolved = $null; $sampling = $null; $sourceScope = 'Unknown'
            $isCritical = if ($criticalKnown) { $critical.Contains($id) } else { $null }
            if (-not $criticalKnown) { $missing.Add('criticalIntent') }
            if (-not $found) { $missing.Add('api') }
            elseif (-not $DiagnosticsByApi.Contains($id)) { $missing.Add('diagnostics') }
            else {
                $effective = @(Get-ApimModelCollection -Payload $DiagnosticsByApi[$id] `
                    -Context 'Governance API diagnostics')
                if ($effective.Count -gt 0) { $sourceScope = 'Api' }
                elseif ($null -ne $ServiceDiagnosticsPayload) {
                    $effective = $serviceDiagnostics
                    $sourceScope = if ($effective.Count) { 'Service' } else { 'None' }
                }
                else { $missing.Add('diagnostics') }
                if ($sourceScope -cne 'Unknown') {
                    $configured = $effective.Count -gt 0
                    if ($configured) {
                        $unresolved = $false; $loggerUnknown = $false
                        $percentages = [Collections.Generic.List[double]]::new()
                        $samplingUnknown = $false
                        foreach ($diagnostic in $effective) {
                            $loggerId = Get-ApimPortalValue $diagnostic @('properties', 'loggerId')
                            if ($null -eq $loggerId -or $null -eq $LoggersPayload) { $loggerUnknown = $true }
                            elseif ($loggerId -isnot [string]) { throw 'Governance logger reference is invalid.' }
                            elseif (-not $loggerIds.Contains($loggerId)) { $unresolved = $true }
                            $percentage = ConvertTo-ApimDiagnosticNumber -Value (
                                Get-ApimPortalValue $diagnostic @('properties', 'sampling', 'percentage')
                            ) -Context 'Governance sampling' -Minimum 0 -Maximum 100
                            $samplingType = Get-ApimPortalValue $diagnostic @('properties', 'sampling', 'samplingType')
                            if ($null -eq $percentage -or $samplingType -cne 'fixed') { $samplingUnknown = $true }
                            else { $percentages.Add($percentage) }
                        }
                        $resolved = if ($unresolved) { $false } elseif ($loggerUnknown) { $null } else { $true }
                        if ($null -eq $resolved) { $missing.Add('logger') }
                        $minimum = if ($percentages.Count) { ($percentages | Measure-Object -Minimum).Minimum }
                            else { $null }
                        if (-not $samplingUnknown -or ($null -ne $minimum -and $minimum -lt 100)) {
                            $sampling = $minimum
                        }
                        if ($isCritical -ne $false -and $samplingUnknown) { $missing.Add('sampling') }
                    }
                }
            }
            [pscustomobject][ordered]@{
                apiId = $id; apiFound = $found; configured = $configured
                loggerResolved = $resolved; samplingPercentage = $sampling
                sourceScope = $sourceScope; isCritical = $isCritical
                modelStatus = if ($missing.Count) { 'Partial' } else { 'Complete' }
                missingInputs = @($missing | Sort-Object -CaseSensitive)
            }
        }
    )
    return ,$rows
}

function Get-ApimSavedGovernanceModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][object] $Context
    )

    $available = @{}
    foreach ($name in @('Products', 'Apis', 'Diagnostics')) {
        $records = @($Context.Manifest.collectors | Where-Object name -CEQ $name)
        if ($records.Count -gt 1) { throw 'Governance collector inventory is duplicated.' }
        $available[$name] = $records.Count -eq 1 -and $records[0].status -ceq 'Completed'
        if ($available[$name]) {
            Test-ApimCollectorOutput -RunPath $RunPath -Environment $Context.Environment -Collector $records[0]
        }
    }
    $intent = if ($Context.Config.Contains('Governance')) { $Context.Config.Governance } else { $null }
    $result = [ordered]@{}
    if ($available.Products) {
        $products = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath raw/products.json -Collection
        $productIntent = @(if ($null -ne $intent -and $intent.Contains('Products')) { $intent.Products })
        $result.products = Get-ApimProductGovernanceModel -ProductsPayload $products -ProductIntent $productIntent
    }
    if ($available.Apis) {
        $apis = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath raw/apis.json -Collection
        $loggers = $null; $diagnostics = $null; $byApi = @{}
        if ($available.Diagnostics) {
            $loggers = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath raw/loggers.json -Collection
            $diagnostics = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath raw/diagnostics.json -Collection
            foreach ($api in $apis.value) {
                if ((Get-ApimPortalBoolean $api @('properties', 'isCurrent')) -ne $true) { continue }
                $segment = ConvertTo-ApimResourceSegment -Value $api.name
                $byApi[$api.name] = Read-ApimSmokeOutputJson -RunPath $RunPath `
                    -RelativePath "raw/apiDiagnostics/$segment.json" -Collection
            }
        }
        $result.diagnosticCoverage = Get-ApimDiagnosticCoverageModel -ApisPayload $apis `
            -LoggersPayload $loggers -ServiceDiagnosticsPayload $diagnostics `
            -DiagnosticsByApi $byApi -Governance $intent `
            -ServiceResourcePath $Context.Manifest.apim.resourceId
    }
    return $result
}

function Test-ApimSavedGovernanceModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Models
    )

    $names = @('products', 'diagnosticCoverage' | Where-Object { $Models.Contains($_) })
    if ($names.Count -eq 0) { return }
    $expected = Get-ApimSavedGovernanceModel -RunPath $RunPath `
        -Context (Get-ApimRunSetting -RunPath $RunPath)
    foreach ($name in $names) {
        if (-not $expected.Contains($name)) {
            throw 'Saved governance evidence does not match the validated source and intent.'
        }
        $idField = if ($name -ceq 'products') { 'productId' } else { 'apiId' }
        $actual = @($Models[$name] | Sort-Object -Property $idField -CaseSensitive)
        $rebuilt = @($expected[$name] | Sort-Object -Property $idField -CaseSensitive)
        if (-not (Test-ApimAuthSavedProjection -Payload $actual -Projection $rebuilt)) {
            throw 'Saved governance evidence does not match the validated source and intent.'
        }
    }
}
