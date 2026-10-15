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
        if ($name -ceq 'drift' -and -not (Test-Path -LiteralPath $path)) {
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
    return $models
}
