#Requires -Version 7.4

Set-StrictMode -Version Latest

function Invoke-ApimOpenApiCollector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Environment,
        [ValidateRange(1, 64)][int] $ThrottleLimit = 6
    )

    Set-RunCollectorStatus -RunPath $RunPath -Name OpenApi -Status InProgress
    Write-Verbose "OpenAPI serial collection uses at most $ThrottleLimit concurrent requests."
    $files = [Collections.Generic.List[string]]::new()
    $entries = [Collections.Generic.List[object]]::new()
    $failures = 0
    $exported = 0
    try {
        $apis = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath raw/apis.json -Collection
        $names = @(Get-ApimCollectionResourceName -Payload $apis -CollectionName 'APIM API')
        [array]::Sort($names, [StringComparer]::Ordinal)
        $service = Get-ApimServiceResourcePath -Environment $Environment
        # Serial bounded work is intentionally within every supplied throttle.
        foreach ($name in $names) {
            $api = @($apis.value | Where-Object name -CEQ $name)[0]
            if (-not (Test-ApimOpenApiCurrent -Api $api)) { continue }
            $type = Get-ApimOpenApiType -Api $api
            $entry = [ordered]@{
                apiId = $name; apiType = $type; status = 'Skipped'
                reasonCode = 'UnsupportedApiType'; file = $null; sha256 = $null
            }
            if ($type -ceq 'http') {
                $entry.status = 'Failed'
                $entry.reasonCode = 'ExportFailed'
                try {
                    $segment = ConvertTo-ApimResourceSegment -Value $name
                    $json = Get-ApimOpenApiExportJson -ResourcePath "$service/apis/$segment" `
                        -LogPath (Join-Path $RunPath 'logs/run.log')
                    $entry.reasonCode = 'DocumentRejected'
                    $null = ConvertFrom-ApimOpenApiDocument -Json $json
                    $entry.reasonCode = 'PersistenceFailed'
                    $file = Get-ApimOpenApiFile -ApiId $name
                    $path = Write-RunFile -RunPath $RunPath -RelativePath $file `
                        -InputObject $json -Format Text
                    $entry.sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
                    $entry.file = $file
                    $entry.status = 'Exported'
                    $entry.reasonCode = 'Exported'
                    $files.Add($file)
                    $exported++
                }
                catch { $failures++ }
            }
            $entries.Add([pscustomobject] $entry)
        }
        $null = Write-RunFile -RunPath $RunPath -RelativePath raw/openapi/index.json `
            -InputObject ([ordered]@{ schemaVersion = '1.0'; entries = @($entries.ToArray()) })
        $files.Insert(0, 'raw/openapi/index.json')
        $status = if ($failures) { 'Partial' } else { 'Completed' }
        Set-RunCollectorStatus -RunPath $RunPath -Name OpenApi -Status $status `
            -Items $exported -Errors $failures -Files $files.ToArray()
    }
    catch {
        Set-RunCollectorStatus -RunPath $RunPath -Name OpenApi -Status Failed -Errors 1
        throw 'OpenAPI collection failed.'
    }
    if ($failures) { throw 'OpenAPI collection incomplete.' }
}
