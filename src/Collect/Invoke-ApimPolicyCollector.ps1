#Requires -Version 7.4

Set-StrictMode -Version Latest

function Read-ApimPolicyDependency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RelativePath
    )

    $path = Resolve-RunFilePath -RunPath $RunPath -RelativePath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required policy collector input '$RelativePath' was not found."
    }
    try {
        return Get-Content -LiteralPath $path -Raw |
            ConvertFrom-Json -Depth 100 -ErrorAction Stop
    }
    catch {
        throw "Required policy collector input '$RelativePath' was not valid JSON."
    }
}

function Get-ApimPolicyResponseXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Payload
    )

    $propertiesProperty = $Payload.PSObject.Properties['properties']
    if ($null -eq $propertiesProperty -or
        $null -eq $propertiesProperty.Value) {
        throw 'APIM policy response did not contain properties.'
    }
    $valueProperty = $propertiesProperty.Value.PSObject.Properties['value']
    if ($null -eq $valueProperty -or
        [string]::IsNullOrWhiteSpace([string] $valueProperty.Value)) {
        throw 'APIM policy response did not contain policy XML.'
    }
    return [string] $valueProperty.Value
}

function Invoke-ApimPolicyCollector {
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

    $collectorName = 'Policies'
    $logPath = Join-Path $RunPath 'logs/run.log'
    $resourcePath = Get-ApimServiceResourcePath -Environment $Environment
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $filesWritten = 0

    Set-RunStageStatus -RunPath $RunPath -Stage collect -Status InProgress
    Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
        -Status InProgress
    try {
        $apis = Read-ApimPolicyDependency -RunPath $RunPath `
            -RelativePath 'raw/apis.json'
        $products = Read-ApimPolicyDependency -RunPath $RunPath `
            -RelativePath 'raw/products.json'
        $apiNames = @(Get-ApimCollectionResourceName -Payload $apis `
                -CollectionName 'APIM API')
        $productNames = @(Get-ApimCollectionResourceName -Payload $products `
                -CollectionName 'APIM product')

        $fragmentPayload = Invoke-ApimArm `
            -Uri "${resourcePath}/policyFragments?api-version=2024-05-01" `
            -LogPath $logPath
        if ($null -eq $fragmentPayload) {
            throw 'APIM policy fragment response was empty.'
        }
        $fragmentNames = @(Get-ApimCollectionResourceName `
                -Payload $fragmentPayload -CollectionName 'APIM policy fragment')

        $requests = [System.Collections.Generic.List[object]]::new()
        $requestIndex = 0
        $requests.Add([pscustomobject]@{
                Index         = $requestIndex
                Uri           = "${resourcePath}/policies/policy" +
                    '?format=xml&api-version=2024-05-01'
                RelativePath  = 'policies/global.xml'
                ScopeType     = 'Global'
                Scope         = 'global'
                AllowNotFound = $true
            })
        $requestIndex++

        foreach ($productName in $productNames) {
            $segment = ConvertTo-ApimResourceSegment -Value $productName
            $requests.Add([pscustomobject]@{
                    Index         = $requestIndex
                    Uri           = "${resourcePath}/products/${segment}/" +
                        'policies/policy?format=xml&api-version=2024-05-01'
                    RelativePath  = "policies/product.${segment}.xml"
                    ScopeType     = 'Product'
                    Scope         = $productName
                    AllowNotFound = $true
                })
            $requestIndex++
        }

        foreach ($apiName in $apiNames) {
            $apiSegment = ConvertTo-ApimResourceSegment -Value $apiName
            $requests.Add([pscustomobject]@{
                    Index         = $requestIndex
                    Uri           = "${resourcePath}/apis/${apiSegment}/" +
                        'policies/policy?format=xml&api-version=2024-05-01'
                    RelativePath  = "policies/api.${apiSegment}.xml"
                    ScopeType     = 'Api'
                    Scope         = $apiName
                    AllowNotFound = $true
                })
            $requestIndex++

            $operationPayload = Read-ApimPolicyDependency -RunPath $RunPath `
                -RelativePath "raw/operations/${apiSegment}.json"
            $operationNames = @(Get-ApimCollectionResourceName `
                    -Payload $operationPayload `
                    -CollectionName 'APIM operation')
            foreach ($operationName in $operationNames) {
                $operationSegment = ConvertTo-ApimResourceSegment `
                    -Value $operationName
                $requests.Add([pscustomobject]@{
                        Index         = $requestIndex
                        Uri           = "${resourcePath}/apis/${apiSegment}/" +
                            "operations/${operationSegment}/policies/policy" +
                            '?format=xml&api-version=2024-05-01'
                        RelativePath  = (
                            "policies/op.${apiSegment}.${operationSegment}.xml"
                        )
                        ScopeType     = 'Operation'
                        Scope         = "$apiName|$operationName"
                        AllowNotFound = $true
                    })
                $requestIndex++
            }
        }

        foreach ($fragmentName in $fragmentNames) {
            $segment = ConvertTo-ApimResourceSegment -Value $fragmentName
            $requests.Add([pscustomobject]@{
                    Index         = $requestIndex
                    Uri           = "${resourcePath}/policyFragments/${segment}" +
                        '?api-version=2024-05-01&format=xml'
                    RelativePath  = "policies/fragment.${segment}.xml"
                    ScopeType     = 'Fragment'
                    Scope         = $fragmentName
                    AllowNotFound = $true
                })
            $requestIndex++
        }

        $results = @(Invoke-ApimParallelArmRequest `
                -Requests $requests.ToArray() -ThrottleLimit $ThrottleLimit `
                -LogPath $logPath)
        $requestByIndex = @{}
        foreach ($request in $requests) {
            $requestByIndex[[int] $request.Index] = $request
        }

        $paths = [System.Collections.Generic.List[string]]::new()
        $indexEntries = [System.Collections.Generic.List[object]]::new()
        $secretCandidateCount = 0
        foreach ($result in $results) {
            $request = $requestByIndex[[int] $result.index]
            $isNotFound = $false
            $notFoundProperty = $result.PSObject.Properties['notFound']
            if ($null -ne $notFoundProperty) {
                $isNotFound = [bool] $notFoundProperty.Value
            }

            $sha256 = $null
            $secretLocations = @()
            if (-not $isNotFound) {
                if ($null -eq $result.payload) {
                    throw 'APIM policy response was empty.'
                }
                $xml = Get-ApimPolicyResponseXml -Payload $result.payload
                $protected = Protect-ApimPolicyXml -Xml $xml
                $secretLocations = @($protected.SecretLocations)
                $secretCandidateCount += $secretLocations.Count
                $sha256 = Get-ApimPolicySha256 -Xml $protected.Xml
                $paths.Add((Write-RunFile -RunPath $RunPath `
                            -RelativePath $request.RelativePath `
                            -InputObject $protected.Xml -Format Text))
                $filesWritten++
            }

            $indexEntries.Add([ordered]@{
                    scopeType               = $request.ScopeType
                    scope                   = $request.Scope
                    file                    = $request.RelativePath
                    exists                  = -not $isNotFound
                    sha256                  = $sha256
                    hardcodedSecretLocations = $secretLocations
                })
        }

        $index = [ordered]@{
            schemaVersion = '1.0'
            policies      = $indexEntries.ToArray()
        }
        $paths.Add((Write-RunFile -RunPath $RunPath `
                    -RelativePath 'policies/index.json' `
                    -InputObject $index -Depth 100))
        $filesWritten++

        if ($secretCandidateCount -gt 0) {
            Add-RunWarning -RunPath $RunPath -Message (
                'Policy secret candidates were redacted; locations are recorded ' +
                'in the restricted policy index.'
            )
        }

        $stopwatch.Stop()
        Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
            -Status Completed -Items $indexEntries.Count `
            -DurationSec $stopwatch.Elapsed.TotalSeconds
        Write-RunLog -Path $logPath -Level Info -Collector $collectorName `
            -Message (
                'Collected APIM policies with missing scopes indexed and ' +
                'secret candidates redacted.'
            )
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
            -Message 'Policy collector failed; see the restricted run log.'
        Write-RunLog -Path $logPath -Level Error -Collector $collectorName `
            -Message 'APIM policy collection failed.'
        throw
    }
}
