#Requires -Version 7.4

Set-StrictMode -Version Latest

$modelSchemaRoot = Join-Path (
    Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
) 'schemas'
$script:ApimModelSchemaPaths = [ordered]@{
    service = Join-Path $modelSchemaRoot 'service.schema.json'
    apis = Join-Path $modelSchemaRoot 'apis.schema.json'
    operations = Join-Path $modelSchemaRoot 'operations.schema.json'
    policyMatrix = Join-Path $modelSchemaRoot 'policyMatrix.schema.json'
    subscriptions = Join-Path $modelSchemaRoot 'subscriptions.schema.json'
    namedValues = Join-Path $modelSchemaRoot 'namedValues.schema.json'
    backends = Join-Path $modelSchemaRoot 'backends.schema.json'
    certificates = Join-Path $modelSchemaRoot 'certificates.schema.json'
    network = Join-Path $modelSchemaRoot 'network.schema.json'
    exposure = Join-Path $modelSchemaRoot 'exposure.schema.json'
    drift = Join-Path $modelSchemaRoot 'drift.schema.json'
    portal = Join-Path $modelSchemaRoot 'portal.schema.json'
    openApiQuality = Join-Path $modelSchemaRoot 'openApiQuality.schema.json'
    products = Join-Path $modelSchemaRoot 'products.schema.json'
    diagnosticCoverage = Join-Path $modelSchemaRoot 'diagnosticCoverage.schema.json'
    usage = Join-Path $modelSchemaRoot 'usage.schema.json'
    capacity = Join-Path $modelSchemaRoot 'capacity.schema.json'
    cost = Join-Path $modelSchemaRoot 'cost.schema.json'
}

function Test-ApimModelJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Json
    )

    if (@($script:ApimModelSchemaPaths.Keys) -cnotcontains $Name) {
        throw 'Model name is not supported by the schema gate.'
    }
    $schemaPath = $script:ApimModelSchemaPaths[$Name]
    if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
        throw "Model schema '$Name' was unavailable."
    }

    if ($Name -cin @('openApiQuality', 'products', 'diagnosticCoverage', 'usage', 'capacity', 'cost')) {
        $document = $null
        try {
            if ([Text.Encoding]::UTF8.GetByteCount($Json) -gt 16MB) {
                throw 'OpenAPI quality size limit exceeded.'
            }
            $options = [Text.Json.JsonDocumentOptions]::new()
            $options.MaxDepth = 12
            $document = [Text.Json.JsonDocument]::Parse($Json, $options)
            Assert-ApimAnalysisJsonMember -Element $document.RootElement
        }
        catch { throw "Model '$Name' failed schema validation." }
        finally { if ($null -ne $document) { $document.Dispose() } }
    }
    try {
        $isValid = Test-Json -Json $Json -SchemaFile $schemaPath `
            -ErrorAction Stop
    }
    catch {
        throw "Model '$Name' failed schema validation."
    }
    if (-not $isValid) {
        throw "Model '$Name' failed schema validation."
    }
    if ($Name -cin @('products', 'diagnosticCoverage')) {
        $rows = ConvertFrom-Json -InputObject $Json -Depth 8 -NoEnumerate -ErrorAction Stop
        $idField = if ($Name -ceq 'products') { 'productId' } else { 'apiId' }
        $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($row in $rows) {
            if (-not $ids.Add($row.$idField) -or
                ($row.modelStatus -ceq 'Complete') -ne ($row.missingInputs.Count -eq 0)) {
                throw "Model '$Name' failed semantic validation."
            }
        }
    }
}

function Write-ApimModelSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Models
    )

    if ($Models.Count -eq 0) {
        throw 'At least one model is required for persistence.'
    }
    foreach ($name in $Models.Keys) {
        if ($name -isnot [string] -or
            @($script:ApimModelSchemaPaths.Keys) -cnotcontains $name) {
            throw 'Model name is not supported by the schema gate.'
        }
    }

    $snapshots = [ordered]@{}
    foreach ($name in $Models.Keys) {
        try {
            $json = ConvertTo-Json -InputObject $Models[$name] -Depth 100 `
                -WarningAction Stop -ErrorAction Stop
        }
        catch {
            throw "Model '$name' could not be serialized."
        }
        Test-ApimModelJson -Name $name -Json $json
        $snapshots[$name] = $json
    }

    foreach ($name in $snapshots.Keys) {
        $path = Resolve-RunFilePath -RunPath $RunPath `
            -RelativePath (Join-Path 'model' "$name.json")
        Test-ConfigPathLink -Path $path -Context 'Model file path'
    }

    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $snapshots.Keys) {
        $paths.Add((Write-RunFile -RunPath $RunPath `
                    -RelativePath (Join-Path 'model' "$name.json") `
                    -InputObject $snapshots[$name] -Format Text))
    }
    return $paths.ToArray()
}

function Get-ApimModelSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath
    )

    $models = [ordered]@{}
    foreach ($name in $script:ApimModelSchemaPaths.Keys) {
        $path = Resolve-RunFilePath -RunPath $RunPath `
            -RelativePath (Join-Path 'model' "$name.json")
        Test-ConfigPathLink -Path $path -Context 'Model file path'
        if ($name -cin @('drift', 'portal', 'openApiQuality', 'products', 'diagnosticCoverage',
                'usage', 'capacity', 'cost') -and
            -not (Test-Path -LiteralPath $path)) {
            continue
        }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Required model '$name' was unavailable."
        }
        try {
            $json = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        }
        catch {
            throw "Model '$name' could not be read."
        }
        Test-ApimModelJson -Name $name -Json $json
        try {
            $models[$name] = ConvertFrom-Json -InputObject $json `
                -Depth 100 -NoEnumerate -ErrorAction Stop
        }
        catch {
            throw "Model '$name' could not be parsed."
        }
    }
    Test-ApimSavedDrift -RunPath $RunPath -Models $models
    Test-ApimSavedOpenApiQuality -RunPath $RunPath -Models $models
    Test-ApimSavedGovernanceModel -RunPath $RunPath -Models $models
    Test-ApimSavedExposureModel -RunPath $RunPath -Models $models
    $manifestPath = Resolve-RunFilePath -RunPath $RunPath -RelativePath 'manifest.json'
    Test-ConfigPathLink -Path $manifestPath -Context 'Model manifest path'
    $telemetryManifest = if (Test-Path -LiteralPath $manifestPath) {
        Get-RunManifest -RunPath $RunPath
    }
    if (($null -ne $telemetryManifest -and $telemetryManifest.schemaVersion -ceq '1.2') -or
        @('usage', 'capacity', 'cost' | Where-Object { $models.Contains($_) }).Count) {
        Test-ApimSavedTelemetryModel -RunPath $RunPath -Models $models
    }
    return $models
}
