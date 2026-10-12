#Requires -Version 7.4

Set-StrictMode -Version Latest

function Invoke-ApimServiceCollector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Environment
    )

    $collectorName = 'Service'
    $logPath = Join-Path $RunPath 'logs/run.log'
    $resourcePath = Get-ApimServiceResourcePath -Environment $Environment
    $uri = "${resourcePath}?api-version=2024-05-01"
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Set-RunStageStatus -RunPath $RunPath -Stage collect -Status InProgress
    Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
        -Status InProgress
    try {
        $service = Invoke-ApimArm -Uri $uri -LogPath $logPath
        if ($null -eq $service) {
            throw 'APIM service response was empty.'
        }

        $filePath = Write-RunFile -RunPath $RunPath `
            -RelativePath 'raw/service.json' -InputObject $service -Depth 50
        $stopwatch.Stop()
        Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
            -Status Completed -Items 1 -DurationSec $stopwatch.Elapsed.TotalSeconds
        Write-RunLog -Path $logPath -Level Info -Collector $collectorName `
            -Message 'Collected APIM service configuration.'
        return $filePath
    }
    catch {
        $stopwatch.Stop()
        Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
            -Status Failed -Errors 1 -DurationSec $stopwatch.Elapsed.TotalSeconds
        Add-RunWarning -RunPath $RunPath `
            -Message 'Service collector failed; see the restricted run log.'
        Write-RunLog -Path $logPath -Level Error -Collector $collectorName `
            -Message 'APIM service collection failed.'
        throw
    }
}
