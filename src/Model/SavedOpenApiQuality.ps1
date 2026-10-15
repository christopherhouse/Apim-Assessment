#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimSavedOpenApiExport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][object] $Context
    )

    $records = @($Context.Manifest.collectors | Where-Object name -CEQ OpenApi)
    if ($records.Count -gt 1) { throw 'Duplicate OpenAPI collector.' }
    if ($records.Count -eq 0) { return $null }
    $entries = @()
    if ($records[0].status -cin @('Completed', 'Partial')) {
        Test-ApimCollectorOutput -RunPath $RunPath -Environment $Context.Environment `
            -Collector $records[0]
        if (@($records[0].files) -ccontains 'raw/openapi/index.json') {
            $index = Read-ApimSmokeOutputJson -RunPath $RunPath `
                -RelativePath 'raw/openapi/index.json'
            $entries = @($index.entries)
        }
    }
    return [pscustomobject]@{
        status = $records[0].status
        entries = $entries
    }
}

function Get-ApimOpenApiQualityPenalty {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Config)

    if ($Config.Contains('OpenApiQuality')) {
        Test-ConfigOpenApiQuality -Value $Config.OpenApiQuality
        return [ordered]@{
            errorPenalty = $Config.OpenApiQuality.ErrorPenalty
            warningPenalty = $Config.OpenApiQuality.WarningPenalty
        }
    }
    return [ordered]@{ errorPenalty = 10; warningPenalty = 2 }
}

function Get-ApimSavedOpenApiQuality {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][object] $Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Apis,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Operations
    )

    $exports = Get-ApimSavedOpenApiExport -RunPath $RunPath -Context $Context
    if ($null -eq $exports) { return $null }
    $penalties = Get-ApimOpenApiQualityPenalty -Config $Context.Config
    $orderedApis = [Collections.Generic.SortedDictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($api in $Apis) { $orderedApis.Add($api.apiId, $api) }
    $rows = @(
        foreach ($api in $orderedApis.Values) {
            $entries = @($exports.entries | Where-Object apiId -CEQ $api.apiId)
            $json = $null
            if ($entries.Count -eq 1 -and $entries[0].status -ceq 'Exported') {
                $path = Resolve-RunFilePath -RunPath $RunPath -RelativePath $entries[0].file
                Test-ConfigPathLink -Path $path -Context 'Saved OpenAPI document'
                $json = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
            }
            Get-ApimOpenApiQuality -Api $api `
                -Operations @($Operations | Where-Object apiId -CEQ $api.apiId) `
                -Json $json -ErrorPenalty $penalties.errorPenalty `
                -WarningPenalty $penalties.warningPenalty
        }
    )
    return [pscustomobject]@{ Rows = $rows; Exports = $exports }
}

function Get-ApimOpenApiQualityBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Quality,
        [Parameter(Mandatory)][object] $Context,
        [Parameter(Mandatory)][object] $Exports
    )

    $qualityByApi = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($row in $Quality) { $qualityByApi.Add($row.apiId, $row) }
    return [ordered]@{
        schemaVersion = '1.0'
        modelSha256 = Get-ApimLifecycleDigest -Value @{ quality = $qualityByApi }
        exportsSha256 = Get-ApimLifecycleDigest -Value $Exports
        settingsSha256 = Get-ApimLifecycleDigest -Value (
            Get-ApimOpenApiQualityPenalty -Config $Context.Config
        )
        rulesetSha256 = Get-ApimOpenApiRulesetHash
    }
}

function Save-ApimOpenApiQualityBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Quality,
        [Parameter(Mandatory)][object] $Context,
        [Parameter(Mandatory)][object] $Exports
    )

    $binding = Get-ApimOpenApiQualityBinding -Quality $Quality -Context $Context -Exports $Exports
    $null = Write-RunFile -RunPath $RunPath -RelativePath 'restricted/openapi-binding.json' `
        -InputObject $binding
}

function Test-ApimSavedOpenApiQuality {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Models
    )

    $bindingPath = Resolve-RunFilePath -RunPath $RunPath -RelativePath 'restricted/openapi-binding.json'
    Test-ConfigPathLink -Path $bindingPath -Context 'OpenAPI quality binding'
    if (-not $Models.Contains('openApiQuality')) {
        if (Test-Path -LiteralPath $bindingPath) { throw 'Saved OpenAPI quality model is unavailable.' }
        return
    }
    if (-not $Models.Contains('apis') -or -not $Models.Contains('operations')) {
        throw 'Saved OpenAPI quality dependencies are unavailable.'
    }
    $context = Get-ApimRunSetting -RunPath $RunPath
    $exports = Get-ApimSavedOpenApiExport -RunPath $RunPath -Context $context
    if ($null -eq $exports) { throw 'Saved OpenAPI export binding is unavailable.' }
    $document = $null
    try {
        if ((Get-Item -LiteralPath $bindingPath -ErrorAction Stop).Length -gt 4KB) {
            throw 'OpenAPI quality binding size limit exceeded.'
        }
        $json = Get-Content -LiteralPath $bindingPath -Raw -ErrorAction Stop
        $options = [Text.Json.JsonDocumentOptions]::new()
        $options.MaxDepth = 4
        $document = [Text.Json.JsonDocument]::Parse($json, $options)
        Assert-ApimAnalysisJsonMember -Element $document.RootElement
        $binding = ConvertFrom-Json -InputObject $json -Depth 4 -ErrorAction Stop
    }
    catch { throw 'Saved OpenAPI quality binding rejected.' }
    finally { if ($null -ne $document) { $document.Dispose() } }
    $expected = Get-ApimOpenApiQualityBinding -Quality @($Models.openApiQuality) `
        -Context $context -Exports $exports
    if ((Get-ApimLifecycleDigest -Value $binding) -cne
        (Get-ApimLifecycleDigest -Value $expected)) {
        throw 'Saved OpenAPI quality binding rejected.'
    }
    if (@($Models.openApiQuality).Count -ne @($Models.apis).Count -or
        -not (Test-ApimOpenApiQualityModel -Quality @($Models.openApiQuality) `
                -Apis @($Models.apis) -Operations @($Models.operations))) {
        throw 'Saved OpenAPI quality model semantics rejected.'
    }
    $penalties = Get-ApimOpenApiQualityPenalty -Config $context.Config
    foreach ($row in $Models.openApiQuality) {
        $entries = @($exports.entries | Where-Object apiId -CEQ $row.apiId)
        $sourceHash = if ($entries.Count -eq 1 -and $entries[0].status -ceq 'Exported') {
            $entries[0].sha256
        } else { $null }
        if ($row.sourceSha256 -cne $sourceHash -or
            $row.rulesetSha256 -cne $expected.rulesetSha256 -or
            $row.errorPenalty -ne $penalties.errorPenalty -or
            $row.warningPenalty -ne $penalties.warningPenalty) {
            throw 'Saved OpenAPI quality source or settings rejected.'
        }
    }
}
