#Requires -Version 7.4

Set-StrictMode -Version Latest

function Invoke-ApimProductCollector {
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

    $collectorName = 'Products'
    $logPath = Join-Path $RunPath 'logs/run.log'
    $resourcePath = Get-ApimServiceResourcePath -Environment $Environment
    $listUri = "${resourcePath}/products?api-version=2024-05-01"
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $filesWritten = 0

    Set-RunStageStatus -RunPath $RunPath -Stage collect -Status InProgress
    Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
        -Status InProgress
    try {
        $products = Invoke-ApimArm -Uri $listUri -LogPath $logPath
        if ($null -eq $products) {
            throw 'APIM product response was empty.'
        }

        $paths = [System.Collections.Generic.List[string]]::new()
        $paths.Add((Write-RunFile -RunPath $RunPath `
                    -RelativePath 'raw/products.json' -InputObject $products -Depth 50))
        $filesWritten++

        $productNames = @(Get-ApimCollectionResourceName -Payload $products `
                -CollectionName 'APIM product')
        $requests = [System.Collections.Generic.List[object]]::new()
        $requestIndex = 0
        foreach ($productName in $productNames) {
            $segment = ConvertTo-ApimResourceSegment -Value $productName
            foreach ($request in @(
                    @{
                        Endpoint = 'apis'
                        Directory = 'productApis'
                    },
                    @{
                        Endpoint = 'groups'
                        Directory = 'productGroups'
                    }
                )) {
                $requests.Add([pscustomobject]@{
                        Index = $requestIndex
                        Uri = "${resourcePath}/products/${segment}/" +
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
                throw 'APIM product child response was empty.'
            }
            $paths.Add((Write-RunFile -RunPath $RunPath `
                        -RelativePath $result.relativePath `
                        -InputObject $result.payload -Depth 50))
            $filesWritten++
        }

        $stopwatch.Stop()
        Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
            -Status Completed -Items $productNames.Count `
            -DurationSec $stopwatch.Elapsed.TotalSeconds
        Write-RunLog -Path $logPath -Level Info -Collector $collectorName `
            -Message 'Collected APIM products, API memberships, and groups.'
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
            -Message 'Product collector failed; see the restricted run log.'
        Write-RunLog -Path $logPath -Level Error -Collector $collectorName `
            -Message 'APIM product collection failed.'
        throw
    }
}
