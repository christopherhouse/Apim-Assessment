#Requires -Version 7.4

Set-StrictMode -Version Latest

function Invoke-ApimApiCatalogCollector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Environment,

        [ValidateRange(1, 64)]
        [int] $ThrottleLimit = 6
    )

    $collectorName = 'Apis'
    $logPath = Join-Path $RunPath 'logs/run.log'
    $resourcePath = Get-ApimServiceResourcePath -Environment $Environment
    $listUri = "${resourcePath}/apis?api-version=2024-05-01" +
        '&expandApiVersionSet=true'
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $filesWritten = 0

    Set-RunStageStatus -RunPath $RunPath -Stage collect -Status InProgress
    Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
        -Status InProgress
    try {
        $apis = Invoke-ApimArm -Uri $listUri -LogPath $logPath
        if ($null -eq $apis) {
            throw 'APIM API response was empty.'
        }

        $paths = [System.Collections.Generic.List[string]]::new()
        $paths.Add((Write-RunFile -RunPath $RunPath `
                    -RelativePath 'raw/apis.json' -InputObject $apis -Depth 50))
        $filesWritten++

        $apiNames = @(Get-ApimCollectionResourceName -Payload $apis `
                -CollectionName 'APIM API')
        $requests = [System.Collections.Generic.List[object]]::new()
        $requestIndex = 0
        foreach ($apiName in $apiNames) {
            $segment = ConvertTo-ApimResourceSegment -Value $apiName
            foreach ($request in @(
                    @{
                        Endpoint = 'revisions'
                        Directory = 'apiRevisions'
                    },
                    @{
                        Endpoint = 'operations'
                        Directory = 'operations'
                    },
                    @{
                        Endpoint = 'tags'
                        Directory = 'apiTags'
                    }
                )) {
                $requests.Add([pscustomobject]@{
                        Index = $requestIndex
                        Uri = "${resourcePath}/apis/${segment}/" +
                            "$($request.Endpoint)?api-version=2024-05-01"
                        RelativePath = "raw/$($request.Directory)/${segment}.json"
                    })
                $requestIndex++
            }
        }

        $results = @(Invoke-ApimParallelArmRequest `
                -Requests $requests.ToArray() -ThrottleLimit $ThrottleLimit `
                -LogPath $logPath)
        foreach ($result in $results) {
            if ($null -eq $result.payload) {
                throw 'APIM API child response was empty.'
            }
            $paths.Add((Write-RunFile -RunPath $RunPath `
                        -RelativePath $result.relativePath `
                        -InputObject $result.payload -Depth 50))
            $filesWritten++
        }

        $stopwatch.Stop()
        Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
            -Status Completed -Items $apiNames.Count `
            -DurationSec $stopwatch.Elapsed.TotalSeconds
        Write-RunLog -Path $logPath -Level Info -Collector $collectorName `
            -Message 'Collected APIM APIs, revisions, operations, and tags.'
        return $paths.ToArray()
    }
    catch {
        $stopwatch.Stop()
        $status = if ($filesWritten -gt 0) { 'Partial' } else { 'Failed' }
        $failureCount = Get-ApimCollectorFailureCount -ErrorRecord $_
        Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
            -Status $status -Errors $failureCount `
            -DurationSec $stopwatch.Elapsed.TotalSeconds
        Add-RunWarning -RunPath $RunPath `
            -Message 'API catalog collector failed; see the restricted run log.'
        Write-RunLog -Path $logPath -Level Error -Collector $collectorName `
            -Message 'APIM API catalog collection failed.'
        throw
    }
}
