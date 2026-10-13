#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimDiagnosticProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context,

        [switch] $AllowMissing
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return ,$InputObject[$Name]
        }
    }
    else {
        $property = $InputObject.PSObject.Properties[$Name]
        if ($null -ne $property) {
            return ,$property.Value
        }
    }
    if ($AllowMissing) {
        return $null
    }
    throw "$Context did not contain '$Name'."
}

function ConvertTo-ApimDiagnosticString {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context
    )

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -isnot [string] -or
        [string]::IsNullOrWhiteSpace([string] $Value)) {
        throw "$Context was not a non-empty string."
    }
    return [string] $Value
}

function ConvertTo-ApimDiagnosticHeaderList {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context
    )

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [string] -or
        $Value -isnot [System.Collections.IEnumerable]) {
        throw "$Context was not an array."
    }
    $headers = @(
        foreach ($header in @($Value)) {
            if ($header -isnot [string] -or
                [string]::IsNullOrWhiteSpace([string] $header)) {
                throw "$Context contained an invalid header name."
            }
            [string] $header
        }
    )
    return ,([string[]] @($headers | Sort-Object -Unique))
}

function ConvertTo-ApimDiagnosticNumber {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context,

        [double] $Minimum = 0,

        [double] $Maximum = [double]::PositiveInfinity,

        [switch] $Integer
    )

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [bool] -or $Value -is [string]) {
        throw "$Context was not numeric."
    }
    $number = 0.0
    if (-not [double]::TryParse(
            [string] $Value,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref] $number
        ) -or [double]::IsNaN($number) -or
        [double]::IsInfinity($number) -or
        $number -lt $Minimum -or $number -gt $Maximum -or
        ($Integer -and [math]::Floor($number) -ne $number)) {
        throw "$Context was outside the supported range."
    }
    if ($Integer) {
        return [int] $number
    }
    return $number
}

function ConvertTo-ApimDiagnosticMessageSetting {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context
    )

    if ($null -eq $Value) {
        return $null
    }
    $headerValue = Get-ApimDiagnosticProperty -InputObject $Value `
        -Name headers -Context $Context -AllowMissing
    $headers = if ($null -eq $headerValue) {
        $null
    }
    else {
        ConvertTo-ApimDiagnosticHeaderList -Value $headerValue `
            -Context "$Context headers"
    }
    $body = Get-ApimDiagnosticProperty -InputObject $Value -Name body `
        -Context $Context -AllowMissing
    $bodyBytes = if ($null -eq $body) {
        $null
    }
    else {
        ConvertTo-ApimDiagnosticNumber -Value (
            Get-ApimDiagnosticProperty -InputObject $body -Name bytes `
                -Context "$Context body" -AllowMissing
        ) -Context "$Context body bytes" -Integer
    }

    return [pscustomobject] [ordered]@{
        headers = $headers
        bodyBytes = $bodyBytes
    }
}

function ConvertTo-ApimDiagnosticPipelineSetting {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context
    )

    if ($null -eq $Value) {
        return $null
    }
    return [pscustomobject] [ordered]@{
        request = ConvertTo-ApimDiagnosticMessageSetting -Value (
            Get-ApimDiagnosticProperty -InputObject $Value -Name request `
                -Context $Context -AllowMissing
        ) -Context "$Context request"
        response = ConvertTo-ApimDiagnosticMessageSetting -Value (
            Get-ApimDiagnosticProperty -InputObject $Value -Name response `
                -Context $Context -AllowMissing
        ) -Context "$Context response"
    }
}

function ConvertTo-ApimCollectedLogger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Resource
    )

    $name = ConvertTo-ApimDiagnosticString -Value (
        Get-ApimDiagnosticProperty -InputObject $Resource -Name name `
            -Context 'APIM logger'
    ) -Context 'APIM logger name'
    $properties = Get-ApimDiagnosticProperty -InputObject $Resource `
        -Name properties -Context 'APIM logger'
    $loggerType = ConvertTo-ApimDiagnosticString -Value (
        Get-ApimDiagnosticProperty -InputObject $properties -Name loggerType `
            -Context 'APIM logger properties' -AllowMissing
    ) -Context 'APIM logger type'
    $resourceId = ConvertTo-ApimDiagnosticString -Value (
        Get-ApimDiagnosticProperty -InputObject $properties -Name resourceId `
            -Context 'APIM logger properties' -AllowMissing
    ) -Context 'APIM logger resource ID'
    $isBuffered = Get-ApimDiagnosticProperty -InputObject $properties `
        -Name isBuffered -Context 'APIM logger properties' -AllowMissing
    if ($null -ne $isBuffered -and $isBuffered -isnot [bool]) {
        throw 'APIM logger buffering setting was not Boolean.'
    }

    return [pscustomobject] [ordered]@{
        name = $name
        properties = [pscustomobject] [ordered]@{
            loggerType = $loggerType
            resourceId = $resourceId
            isBuffered = $isBuffered
        }
    }
}

function ConvertTo-ApimCollectedDiagnostic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Resource
    )

    $name = ConvertTo-ApimDiagnosticString -Value (
        Get-ApimDiagnosticProperty -InputObject $Resource -Name name `
            -Context 'APIM diagnostic'
    ) -Context 'APIM diagnostic name'
    $properties = Get-ApimDiagnosticProperty -InputObject $Resource `
        -Name properties -Context 'APIM diagnostic'
    $loggerId = ConvertTo-ApimDiagnosticString -Value (
        Get-ApimDiagnosticProperty -InputObject $properties -Name loggerId `
            -Context 'APIM diagnostic properties' -AllowMissing
    ) -Context 'APIM diagnostic logger ID'
    $alwaysLog = ConvertTo-ApimDiagnosticString -Value (
        Get-ApimDiagnosticProperty -InputObject $properties -Name alwaysLog `
            -Context 'APIM diagnostic properties' -AllowMissing
    ) -Context 'APIM diagnostic always-log setting'
    $verbosity = ConvertTo-ApimDiagnosticString -Value (
        Get-ApimDiagnosticProperty -InputObject $properties -Name verbosity `
            -Context 'APIM diagnostic properties' -AllowMissing
    ) -Context 'APIM diagnostic verbosity'
    $correlation = ConvertTo-ApimDiagnosticString -Value (
        Get-ApimDiagnosticProperty -InputObject $properties `
            -Name httpCorrelationProtocol `
            -Context 'APIM diagnostic properties' -AllowMissing
    ) -Context 'APIM diagnostic correlation protocol'
    $logClientIp = Get-ApimDiagnosticProperty -InputObject $properties `
        -Name logClientIp -Context 'APIM diagnostic properties' -AllowMissing
    if ($null -ne $logClientIp -and $logClientIp -isnot [bool]) {
        throw 'APIM diagnostic client-IP setting was not Boolean.'
    }

    $samplingValue = Get-ApimDiagnosticProperty -InputObject $properties `
        -Name sampling -Context 'APIM diagnostic properties' -AllowMissing
    $sampling = $null
    if ($null -ne $samplingValue) {
        $sampling = [pscustomobject] [ordered]@{
            samplingType = ConvertTo-ApimDiagnosticString -Value (
                Get-ApimDiagnosticProperty -InputObject $samplingValue `
                    -Name samplingType -Context 'APIM diagnostic sampling' `
                    -AllowMissing
            ) -Context 'APIM diagnostic sampling type'
            percentage = ConvertTo-ApimDiagnosticNumber -Value (
                Get-ApimDiagnosticProperty -InputObject $samplingValue `
                    -Name percentage -Context 'APIM diagnostic sampling' `
                    -AllowMissing
            ) -Context 'APIM diagnostic sampling percentage' `
                -Minimum 0 -Maximum 100
        }
    }

    return [pscustomobject] [ordered]@{
        name = $name
        properties = [pscustomobject] [ordered]@{
            loggerId = $loggerId
            alwaysLog = $alwaysLog
            sampling = $sampling
            verbosity = $verbosity
            logClientIp = $logClientIp
            httpCorrelationProtocol = $correlation
            frontend = ConvertTo-ApimDiagnosticPipelineSetting -Value (
                Get-ApimDiagnosticProperty -InputObject $properties `
                    -Name frontend -Context 'APIM diagnostic properties' `
                    -AllowMissing
            ) -Context 'APIM diagnostic frontend'
            backend = ConvertTo-ApimDiagnosticPipelineSetting -Value (
                Get-ApimDiagnosticProperty -InputObject $properties `
                    -Name backend -Context 'APIM diagnostic properties' `
                    -AllowMissing
            ) -Context 'APIM diagnostic backend'
        }
    }
}

function ConvertTo-ApimDiagnosticCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Payload,

        [Parameter(Mandatory)]
        [ValidateSet('Logger', 'Diagnostic')]
        [string] $Type
    )

    $names = @(Get-ApimCollectionResourceName -Payload $Payload `
            -CollectionName "APIM $Type")
    $resourceMap = [System.Collections.Generic.Dictionary[
        string,
        object
    ]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($resource in @($Payload.value)) {
        $resourceMap.Add([string] $resource.name, $resource)
    }
    return @(
        foreach ($name in $names) {
            if ($Type -eq 'Logger') {
                ConvertTo-ApimCollectedLogger -Resource $resourceMap[$name]
            }
            else {
                ConvertTo-ApimCollectedDiagnostic -Resource $resourceMap[$name]
            }
        }
    )
}

function Get-ApimCollectedApiName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath
    )

    $path = Resolve-RunFilePath -RunPath $RunPath `
        -RelativePath 'raw/apis.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'Collected APIM API inventory was unavailable.'
    }
    try {
        $payload = Get-Content -LiteralPath $path -Raw -ErrorAction Stop |
            ConvertFrom-Json -Depth 100 -ErrorAction Stop
    }
    catch {
        throw 'Collected APIM API inventory was invalid.'
    }
    return @(Get-ApimCollectionResourceName -Payload $payload `
            -CollectionName 'APIM API')
}

function Invoke-ApimDiagnosticsCollector {
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

    $collectorName = 'Diagnostics'
    $logPath = Join-Path $RunPath 'logs/run.log'
    $resourcePath = Get-ApimServiceResourcePath -Environment $Environment
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $filesWritten = 0

    Set-RunStageStatus -RunPath $RunPath -Stage collect -Status InProgress
    Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
        -Status InProgress
    try {
        $apiNames = @(Get-ApimCollectedApiName -RunPath $RunPath)
        $loggersResponse = Invoke-ApimArm -Uri (
            "$resourcePath/loggers?api-version=2024-05-01"
        ) -LogPath $logPath
        $diagnosticsResponse = Invoke-ApimArm -Uri (
            "$resourcePath/diagnostics?api-version=2024-05-01"
        ) -LogPath $logPath
        if ($null -eq $loggersResponse -or $null -eq $diagnosticsResponse) {
            throw 'APIM logger or diagnostic response was empty.'
        }
        $loggers = @(ConvertTo-ApimDiagnosticCollection `
                -Payload $loggersResponse -Type Logger)
        $serviceDiagnostics = @(ConvertTo-ApimDiagnosticCollection `
                -Payload $diagnosticsResponse -Type Diagnostic)

        $paths = [System.Collections.Generic.List[string]]::new()
        $paths.Add((Write-RunFile -RunPath $RunPath `
                    -RelativePath 'raw/loggers.json' `
                    -InputObject ([pscustomobject] [ordered]@{
                            value = $loggers
                        }) -Depth 50))
        $filesWritten++
        $paths.Add((Write-RunFile -RunPath $RunPath `
                    -RelativePath 'raw/diagnostics.json' `
                    -InputObject ([pscustomobject] [ordered]@{
                            value = $serviceDiagnostics
                        }) -Depth 50))
        $filesWritten++

        $requests = [System.Collections.Generic.List[object]]::new()
        for ($index = 0; $index -lt $apiNames.Count; $index++) {
            $segment = ConvertTo-ApimResourceSegment -Value $apiNames[$index]
            $requests.Add([pscustomobject]@{
                    Index = $index
                    Uri = "$resourcePath/apis/$segment/" +
                        'diagnostics?api-version=2024-05-01'
                    RelativePath = "raw/apiDiagnostics/$segment.json"
                })
        }
        $results = @(Invoke-ApimParallelArmRequest `
                -Requests $requests.ToArray() -ThrottleLimit $ThrottleLimit `
                -LogPath $logPath)
        $apiDiagnosticCount = 0
        foreach ($result in $results) {
            if ($null -eq $result.payload) {
                throw 'APIM API diagnostic response was empty.'
            }
            $records = @(ConvertTo-ApimDiagnosticCollection `
                    -Payload $result.payload -Type Diagnostic)
            $apiDiagnosticCount += $records.Count
            $paths.Add((Write-RunFile -RunPath $RunPath `
                        -RelativePath $result.relativePath `
                        -InputObject ([pscustomobject] [ordered]@{
                                value = $records
                            }) -Depth 50))
            $filesWritten++
        }

        $stopwatch.Stop()
        Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
            -Status Completed `
            -Items ($loggers.Count + $serviceDiagnostics.Count +
                $apiDiagnosticCount) `
            -DurationSec $stopwatch.Elapsed.TotalSeconds
        Write-RunLog -Path $logPath -Level Info -Collector $collectorName `
            -Message 'Collected allowlisted APIM logger and diagnostic settings.'
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
            -Message 'Diagnostics collector failed; see the restricted run log.'
        Write-RunLog -Path $logPath -Level Error -Collector $collectorName `
            -Message 'APIM diagnostics collection failed.'
        throw
    }
}
