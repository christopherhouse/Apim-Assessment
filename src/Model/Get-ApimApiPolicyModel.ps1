#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimModelValue {
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
            return $InputObject[$Name]
        }
    }
    else {
        $property = $InputObject.PSObject.Properties[$Name]
        if ($null -ne $property) {
            return $property.Value
        }
    }
    if ($AllowMissing) {
        return $null
    }
    throw "$Context did not contain '$Name'."
}

function Get-ApimModelCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Payload,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context
    )

    $items = @(Get-ApimModelValue -InputObject $Payload -Name value `
            -Context $Context)
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($item in $items) {
        if ($null -eq $item) {
            throw "$Context contained a null resource."
        }
        $name = [string] (Get-ApimModelValue -InputObject $item -Name name `
                -Context $Context)
        if ([string]::IsNullOrWhiteSpace($name) -or
            -not $seen.Add($name)) {
            throw "$Context contained an invalid or duplicate resource name."
        }
    }
    return @($items)
}

function ConvertTo-ApimModelInputMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context
    )

    $result = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($key in $InputObject.Keys) {
        $name = [string] $key
        if ([string]::IsNullOrWhiteSpace($name) -or
            $result.ContainsKey($name)) {
            throw "$Context contained an invalid or duplicate name."
        }
        if ($null -eq $InputObject[$key]) {
            throw "$Context contained a null payload."
        }
        $result.Add($name, $InputObject[$key])
    }
    return ,$result
}

function ConvertTo-ApimNamedResourceMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Payload,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context
    )

    $result = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($item in Get-ApimModelCollection -Payload $Payload `
            -Context $Context) {
        $name = [string] (Get-ApimModelValue -InputObject $item -Name name `
                -Context $Context)
        $result.Add($name, $item)
    }
    return ,$result
}

function Get-ApimModelBoolean {
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
        [string] $Context
    )

    $value = Get-ApimModelValue -InputObject $InputObject -Name $Name `
        -Context $Context
    if ($value -isnot [bool]) {
        throw "$Context field '$Name' was not Boolean."
    }
    return [bool] $value
}

function Get-ApimDiagnosticModelValue {
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

function Get-ApimDiagnosticRiskFact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Diagnostics
    )

    $hasPositiveBody = $false
    $hasUnknownBody = $false
    $hasSensitiveHeader = $false
    $hasUnknownRequestHeader = $false
    $sensitiveNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($name in @(
            'Authorization',
            'Ocp-Apim-Subscription-Key',
            'Cookie'
        )) {
        $null = $sensitiveNames.Add($name)
    }

    foreach ($diagnostic in $Diagnostics) {
        $properties = Get-ApimDiagnosticModelValue `
            -InputObject $diagnostic -Name properties `
            -Context 'APIM diagnostic model resource'
        foreach ($pipelineName in @('frontend', 'backend')) {
            $pipeline = Get-ApimDiagnosticModelValue `
                -InputObject $properties -Name $pipelineName `
                -Context 'APIM diagnostic model properties' -AllowMissing
            foreach ($messageName in @('request', 'response')) {
                $message = if ($null -eq $pipeline) {
                    $null
                }
                else {
                    Get-ApimDiagnosticModelValue -InputObject $pipeline `
                        -Name $messageName `
                        -Context "APIM diagnostic $pipelineName settings" `
                        -AllowMissing
                }
                $bodyBytes = if ($null -eq $message) {
                    $null
                }
                else {
                    Get-ApimDiagnosticModelValue -InputObject $message `
                        -Name bodyBytes `
                        -Context (
                            "APIM diagnostic $pipelineName $messageName settings"
                        ) -AllowMissing
                }
                $bodyByteNumber = 0.0
                if ($null -ne $bodyBytes -and
                    ($bodyBytes -is [bool] -or
                        $bodyBytes -is [string] -or
                        -not [double]::TryParse(
                            [string] $bodyBytes,
                            [System.Globalization.NumberStyles]::Float,
                            [System.Globalization.CultureInfo]::InvariantCulture,
                            [ref] $bodyByteNumber
                        ) -or
                        [double]::IsNaN($bodyByteNumber) -or
                        [double]::IsInfinity($bodyByteNumber) -or
                        $bodyByteNumber -lt 0 -or
                        [math]::Floor($bodyByteNumber) -ne $bodyByteNumber)) {
                    throw 'APIM diagnostic body-byte count was invalid.'
                }
                if ($null -eq $bodyBytes) {
                    $hasUnknownBody = $true
                }
                elseif ($bodyByteNumber -gt 0) {
                    $hasPositiveBody = $true
                }

                if ($messageName -eq 'request') {
                    $headers = if ($null -eq $message) {
                        $null
                    }
                    else {
                        Get-ApimDiagnosticModelValue `
                            -InputObject $message -Name headers `
                            -Context (
                                "APIM diagnostic $pipelineName request settings"
                            ) -AllowMissing
                    }
                    if ($null -ne $headers) {
                        if ($headers -is [string] -or
                            $headers -isnot [System.Collections.IEnumerable]) {
                            throw 'APIM diagnostic request headers were invalid.'
                        }
                        foreach ($header in @($headers)) {
                            if ($header -isnot [string] -or
                                [string]::IsNullOrWhiteSpace($header)) {
                                throw (
                                    'APIM diagnostic request headers were ' +
                                    'invalid.'
                                )
                            }
                            if ($sensitiveNames.Contains([string] $header)) {
                                $hasSensitiveHeader = $true
                            }
                        }
                    }
                    else {
                        $hasUnknownRequestHeader = $true
                    }
                }
            }
        }
    }

    $bodyLogging = if ($hasPositiveBody) {
        $true
    }
    elseif ($Diagnostics.Count -eq 0) {
        $false
    }
    elseif ($hasUnknownBody) {
        $null
    }
    else {
        $false
    }

    $sensitiveHeadersLogged = if ($hasSensitiveHeader) {
        $true
    }
    elseif ($Diagnostics.Count -eq 0) {
        $false
    }
    elseif ($hasUnknownRequestHeader) {
        $null
    }
    else {
        $false
    }

    return [pscustomobject] [ordered]@{
        bodyLogging = $bodyLogging
        sensitiveHeadersLogged = $sensitiveHeadersLogged
    }
}

function Join-ApimOperationPath {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string] $ApiPath,

        [AllowEmptyString()]
        [string] $UrlTemplate
    )

    $segments = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in @($ApiPath, $UrlTemplate)) {
        $trimmed = $candidate.Trim().Trim('/')
        if (-not [string]::IsNullOrEmpty($trimmed)) {
            $segments.Add($trimmed)
        }
    }
    if ($segments.Count -eq 0) {
        return '/'
    }
    return '/' + ($segments -join '/')
}

function Get-ApimPolicyFlagPathKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ApiId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $OperationId,

        [AllowNull()]
        [string] $Product
    )

    $productKey = if ($null -eq $Product) {
        '<none>'
    }
    else {
        $Product
    }
    return "$ApiId`u{001F}$OperationId`u{001F}$productKey"
}

function Get-ApimAggregateRiskValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Records,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    if ($Records.Count -eq 0) {
        return $null
    }
    if (@($Records | Where-Object { $_.$Name -eq $true }).Count -gt 0) {
        return $true
    }
    if (@($Records | Where-Object {
                $_.policyEvaluationStatus -eq 'Partial'
            }).Count -gt 0) {
        return $null
    }
    return $false
}

function Get-ApimPositiveControlStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Operations,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $CoverageProperty
    )

    if ($Operations.Count -eq 0) {
        return 'NA'
    }
    $values = @($Operations | ForEach-Object { $_.$CoverageProperty })
    if (@($values | Where-Object { $_ -eq $true }).Count -eq
        $Operations.Count) {
        return 'Pass'
    }
    if (@($values | Where-Object { $null -eq $_ }).Count -gt 0 -or
        @($Operations | Where-Object {
                $_.policyEvaluationStatus -eq 'Partial'
            }).Count -gt 0) {
        return 'NA'
    }
    return 'Fail'
}

function Get-ApimNegativeControlStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Operations,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RiskProperty
    )

    if ($Operations.Count -eq 0) {
        return 'NA'
    }
    if (@($Operations | Where-Object {
                $_.$RiskProperty -eq $true
            }).Count -gt 0) {
        return 'Fail'
    }
    if (@($Operations | Where-Object {
                $null -eq $_.$RiskProperty -or
                $_.policyEvaluationStatus -eq 'Partial'
            }).Count -gt 0) {
        return 'NA'
    }
    return 'Pass'
}

function Get-ApimApiPolicyModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $ApisPayload,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $OperationsByApi,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $RevisionsByApi,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $TagsByApi,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $ProductsPayload,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ProductApisByProduct,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $PolicyFlags,

        [AllowNull()]
        [System.Collections.IDictionary] $BackendCredentialByApi,

        [AllowNull()]
        [object] $ServiceDiagnosticsPayload,

        [AllowNull()]
        [System.Collections.IDictionary] $DiagnosticsByApi,

        [ValidateNotNullOrEmpty()]
        [string] $OwnerTagPattern = '^(owner|team)[:=-]'
    )

    $apiResources = @(Get-ApimModelCollection -Payload $ApisPayload `
            -Context 'APIM API payload')
    $currentApis = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($api in $apiResources) {
        $properties = Get-ApimModelValue -InputObject $api -Name properties `
            -Context 'APIM API resource'
        if (Get-ApimModelBoolean -InputObject $properties -Name isCurrent `
                -Context 'APIM API properties') {
            $apiName = [string] (Get-ApimModelValue -InputObject $api `
                    -Name name -Context 'APIM API resource')
            $currentApis.Add($apiName, $api)
        }
    }

    $operationsMap = ConvertTo-ApimModelInputMap `
        -InputObject $OperationsByApi -Context 'Operation payload map'
    $revisionsMap = ConvertTo-ApimModelInputMap `
        -InputObject $RevisionsByApi -Context 'Revision payload map'
    $tagsMap = ConvertTo-ApimModelInputMap -InputObject $TagsByApi `
        -Context 'Tag payload map'
    foreach ($mapEntry in @(
            @{ map = $operationsMap; name = 'Operation payload map' }
            @{ map = $revisionsMap; name = 'Revision payload map' }
            @{ map = $tagsMap; name = 'Tag payload map' }
        )) {
        foreach ($name in $mapEntry.map.Keys) {
            if (-not $currentApis.ContainsKey($name)) {
                throw "$($mapEntry.name) contained an unknown API."
            }
        }
        foreach ($apiName in $currentApis.Keys) {
            if (-not $mapEntry.map.ContainsKey($apiName)) {
                throw "$($mapEntry.name) was missing an API."
            }
        }
    }

    $productMap = ConvertTo-ApimNamedResourceMap -Payload $ProductsPayload `
        -Context 'APIM product payload'
    $productApiMap = ConvertTo-ApimModelInputMap `
        -InputObject $ProductApisByProduct `
        -Context 'Product API payload map'
    foreach ($productName in $productApiMap.Keys) {
        if (-not $productMap.ContainsKey($productName)) {
            throw 'Product API payload map contained an unknown product.'
        }
    }
    foreach ($productName in $productMap.Keys) {
        if (-not $productApiMap.ContainsKey($productName)) {
            throw 'Product API payload map was missing a product.'
        }
    }

    $apiProducts = [System.Collections.Generic.Dictionary[
        string,
        System.Collections.Generic.List[string]
    ]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($apiName in $currentApis.Keys) {
        $apiProducts.Add(
            $apiName,
            [System.Collections.Generic.List[string]]::new()
        )
    }
    foreach ($productName in $productMap.Keys) {
        foreach ($apiName in Get-ApimCollectionResourceName `
                -Payload $productApiMap[$productName] `
                -CollectionName 'Product API') {
            if (-not $currentApis.ContainsKey($apiName)) {
                throw 'Product membership referenced an unknown API.'
            }
            $apiProducts[$apiName].Add($productName)
        }
    }
    foreach ($apiName in $apiProducts.Keys) {
        $sorted = $apiProducts[$apiName].ToArray()
        [System.Array]::Sort($sorted, [System.StringComparer]::Ordinal)
        $apiProducts[$apiName].Clear()
        $apiProducts[$apiName].AddRange($sorted)
    }

    $backendMap = $null
    if ($null -ne $BackendCredentialByApi) {
        $backendMap = ConvertTo-ApimModelInputMap `
            -InputObject $BackendCredentialByApi `
            -Context 'Backend credential map'
        foreach ($apiName in $backendMap.Keys) {
            if (-not $currentApis.ContainsKey($apiName) -or
                $backendMap[$apiName] -isnot [bool]) {
                throw 'Backend credential map contained an invalid entry.'
            }
        }
        foreach ($apiName in $currentApis.Keys) {
            if (-not $backendMap.ContainsKey($apiName)) {
                throw 'Backend credential map was missing an API.'
            }
        }
    }

    $serviceDiagnostics = $null
    $serviceDiagnosticFacts = $null
    if ($null -ne $ServiceDiagnosticsPayload) {
        $serviceDiagnostics = @(Get-ApimModelCollection `
                -Payload $ServiceDiagnosticsPayload `
                -Context 'Service diagnostic payload')
        $serviceDiagnosticFacts = Get-ApimDiagnosticRiskFact `
            -Diagnostics $serviceDiagnostics
    }
    $diagnosticMap = $null
    $diagnosticFactMap = $null
    if ($null -ne $DiagnosticsByApi) {
        $diagnosticMap = ConvertTo-ApimModelInputMap `
            -InputObject $DiagnosticsByApi `
            -Context 'API diagnostic payload map'
        $diagnosticFactMap = [System.Collections.Generic.Dictionary[
            string,
            object
        ]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($apiName in $diagnosticMap.Keys) {
            if (-not $currentApis.ContainsKey($apiName)) {
                throw 'API diagnostic payload map contained an unknown API.'
            }
            $apiDiagnostics = @(Get-ApimModelCollection `
                    -Payload $diagnosticMap[$apiName] `
                    -Context "API diagnostic payload for '$apiName'")
            $diagnosticFactMap.Add(
                $apiName,
                [pscustomobject] [ordered]@{
                    count = $apiDiagnostics.Count
                    facts = Get-ApimDiagnosticRiskFact `
                        -Diagnostics $apiDiagnostics
                }
            )
        }
    }

    $flagByPath = [System.Collections.Generic.Dictionary[
        string,
        object
    ]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $flagNames = @(
        'callerAuthJwt',
        'callerAuthMtls',
        'throttling',
        'ipFilter',
        'hostRestriction',
        'corsUnsafe',
        'backendAuth',
        'hardcodedSecret',
        'backendOverride',
        'backendOverrideHttp',
        'mockOrTrace',
        'returnsWithoutBackend',
        'baseMissing'
    )
    foreach ($flagRecord in $PolicyFlags) {
        if ($null -eq $flagRecord) {
            throw 'Policy flag records contained a null entry.'
        }
        $apiId = [string] (Get-ApimModelValue -InputObject $flagRecord `
                -Name apiId -Context 'Policy flag record')
        $operationId = [string] (Get-ApimModelValue -InputObject $flagRecord `
                -Name operationId -Context 'Policy flag record')
        $productValue = Get-ApimModelValue -InputObject $flagRecord `
            -Name product -Context 'Policy flag record' -AllowMissing
        $product = if ($null -eq $productValue) {
            $null
        }
        else {
            [string] $productValue
        }
        $evaluationStatus = [string] (Get-ApimModelValue `
                -InputObject $flagRecord -Name evaluationStatus `
                -Context 'Policy flag record')
        if ($evaluationStatus -notin @('Complete', 'Partial')) {
            throw 'Policy flag record contained an invalid evaluation status.'
        }
        foreach ($flagName in $flagNames) {
            $null = Get-ApimModelBoolean -InputObject $flagRecord `
                -Name $flagName -Context 'Policy flag record'
        }
        $key = Get-ApimPolicyFlagPathKey -ApiId $apiId `
            -OperationId $operationId -Product $product
        if ($flagByPath.ContainsKey($key)) {
            throw 'Policy flag records contained a duplicate product path.'
        }
        $flagByPath.Add($key, $flagRecord)
    }

    $operationRecords = [System.Collections.Generic.List[object]]::new()
    $consumedFlagKeys = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($apiName in @($currentApis.Keys | Sort-Object)) {
        $apiResource = $currentApis[$apiName]
        $apiProperties = Get-ApimModelValue -InputObject $apiResource `
            -Name properties -Context 'APIM API resource'
        $apiPath = [string] (Get-ApimModelValue `
                -InputObject $apiProperties -Name path `
                -Context 'APIM API properties')
        $operations = @(Get-ApimModelCollection `
                -Payload $operationsMap[$apiName] `
                -Context "Operation payload for '$apiName'")
        foreach ($operation in $operations | Sort-Object {
                [string] (Get-ApimModelValue -InputObject $_ -Name name `
                        -Context 'APIM operation')
            }) {
            $operationId = [string] (Get-ApimModelValue `
                    -InputObject $operation -Name name `
                    -Context 'APIM operation')
            $operationProperties = Get-ApimModelValue `
                -InputObject $operation -Name properties `
                -Context 'APIM operation'

            $pathFlags = [System.Collections.Generic.List[object]]::new()
            $expectedProducts = [System.Collections.Generic.List[object]]::new()
            if ($apiProducts[$apiName].Count -eq 0) {
                $expectedProducts.Add($null)
            }
            else {
                foreach ($productName in $apiProducts[$apiName]) {
                    $expectedProducts.Add($productName)
                }
            }
            foreach ($product in $expectedProducts) {
                $key = Get-ApimPolicyFlagPathKey -ApiId $apiName `
                    -OperationId $operationId -Product $product
                if (-not $flagByPath.ContainsKey($key)) {
                    throw 'Policy flag records were missing an operation path.'
                }
                $pathFlags.Add($flagByPath[$key])
                $null = $consumedFlagKeys.Add($key)
            }

            $policyPartial = @($pathFlags | Where-Object {
                    $_.evaluationStatus -eq 'Partial'
                }).Count -gt 0
            $modes = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal
            )
            foreach ($pathFlag in $pathFlags) {
                if ($pathFlag.callerAuthJwt) {
                    $null = $modes.Add('Entra/JWT')
                }
                if ($pathFlag.callerAuthMtls) {
                    $null = $modes.Add('mTLS')
                }
            }
            [string[]] $operationCallerAuthModes = @($modes)
            [System.Array]::Sort(
                $operationCallerAuthModes,
                [System.StringComparer]::Ordinal
            )
            $hasUnauthenticatedPath = @($pathFlags | Where-Object {
                    -not $_.callerAuthJwt -and -not $_.callerAuthMtls
                }).Count -gt 0

            $backendAuth = if ($null -ne $backendMap) {
                @($pathFlags | Where-Object {
                        $_.backendAuth -or [bool] $backendMap[$apiName]
                    }).Count -gt 0
            }
            elseif (@($pathFlags | Where-Object backendAuth).Count -gt 0) {
                $true
            }
            else {
                $null
            }
            $backendAuthAllPaths = if ($null -ne $backendMap) {
                @($pathFlags | Where-Object {
                        $_.backendAuth -or [bool] $backendMap[$apiName]
                    }).Count -eq $pathFlags.Count
            }
            elseif (@($pathFlags | Where-Object backendAuth).Count -eq
                $pathFlags.Count) {
                $true
            }
            else {
                $null
            }

            $missingInputs = [System.Collections.Generic.List[string]]::new()
            $missingInputs.Add('usage')
            if ($null -eq $backendMap -and
                $null -eq $backendAuthAllPaths) {
                $missingInputs.Add('backends')
            }
            if ($policyPartial) {
                $missingInputs.Add('policyFragments')
            }
            [string[]] $sortedMissingInputs = $missingInputs.ToArray()
            [System.Array]::Sort(
                $sortedMissingInputs,
                [System.StringComparer]::Ordinal
            )

            $operationRecords.Add([pscustomobject] [ordered]@{
                    apiId                        = $apiName
                    operationId                  = $operationId
                    method                       = [string] (
                        Get-ApimModelValue -InputObject $operationProperties `
                            -Name method -Context 'Operation properties'
                    )
                    fullPath                     = Join-ApimOperationPath `
                        -ApiPath $apiPath -UrlTemplate ([string] (
                            Get-ApimModelValue `
                                -InputObject $operationProperties `
                                -Name urlTemplate `
                                -Context 'Operation properties'
                        ))
                    hasDescription               = -not [string]::
                        IsNullOrWhiteSpace([string] (
                            Get-ApimModelValue `
                                -InputObject $operationProperties `
                                -Name description `
                                -Context 'Operation properties' `
                                -AllowMissing
                        ))
                    products                     = @($apiProducts[$apiName])
                    policyEvaluationStatus       = if ($policyPartial) {
                        'Partial'
                    }
                    else {
                        'Complete'
                    }
                    callerAuthJwt                = @($pathFlags |
                            Where-Object callerAuthJwt).Count -eq
                        $pathFlags.Count
                    callerAuthMtls               = @($pathFlags |
                            Where-Object callerAuthMtls).Count -eq
                        $pathFlags.Count
                    callerAuthModes              = $operationCallerAuthModes
                    hasUnauthenticatedPolicyPath = $hasUnauthenticatedPath
                    throttling                   = @($pathFlags |
                            Where-Object throttling).Count -gt 0
                    throttlingAllPaths           = @($pathFlags |
                            Where-Object throttling).Count -eq
                        $pathFlags.Count
                    ipFilter                     = @($pathFlags |
                            Where-Object ipFilter).Count -gt 0
                    ipFilterAllPaths             = @($pathFlags |
                            Where-Object ipFilter).Count -eq
                        $pathFlags.Count
                    hostRestriction              = @($pathFlags |
                            Where-Object hostRestriction).Count -gt 0
                    corsUnsafe                   = @($pathFlags |
                            Where-Object corsUnsafe).Count -gt 0
                    backendAuth                  = $backendAuth
                    backendAuthAllPaths          = $backendAuthAllPaths
                    hardcodedSecret              = @($pathFlags |
                            Where-Object hardcodedSecret).Count -gt 0
                    backendOverride              = @($pathFlags |
                            Where-Object backendOverride).Count -gt 0
                    backendOverrideHttp          = @($pathFlags |
                            Where-Object backendOverrideHttp).Count -gt 0
                    mockOrTrace                  = @($pathFlags |
                            Where-Object mockOrTrace).Count -gt 0
                    returnsWithoutBackend        = @($pathFlags |
                            Where-Object returnsWithoutBackend).Count -gt 0
                    baseMissing                  = @($pathFlags |
                            Where-Object baseMissing).Count -gt 0
                    calls90d                     = $null
                    modelStatus                  = 'Partial'
                    missingInputs                = $sortedMissingInputs
                })
        }
    }
    if ($consumedFlagKeys.Count -ne $flagByPath.Count) {
        throw 'Policy flag records referenced an unknown API or operation path.'
    }

    $apiRecords = [System.Collections.Generic.List[object]]::new()
    foreach ($apiName in @($currentApis.Keys | Sort-Object)) {
        $apiResource = $currentApis[$apiName]
        $properties = Get-ApimModelValue -InputObject $apiResource `
            -Name properties -Context 'APIM API resource'
        $apiOperations = @($operationRecords | Where-Object apiId -EQ $apiName)
        $productNames = @($apiProducts[$apiName])

        $subscriptionRequired = Get-ApimModelBoolean `
            -InputObject $properties -Name subscriptionRequired `
            -Context 'APIM API properties'
        if (-not $subscriptionRequired) {
            foreach ($productName in $productNames) {
                $productProperties = Get-ApimModelValue `
                    -InputObject $productMap[$productName] -Name properties `
                    -Context 'APIM product resource'
                if (Get-ApimModelBoolean -InputObject $productProperties `
                        -Name subscriptionRequired `
                        -Context 'APIM product properties') {
                    $subscriptionRequired = $true
                    break
                }
            }
        }

        $callerAuthModes = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($operation in $apiOperations) {
            foreach ($mode in $operation.callerAuthModes) {
                $null = $callerAuthModes.Add($mode)
            }
        }
        $hasWeakPath = @($apiOperations | Where-Object {
                $_.hasUnauthenticatedPolicyPath
            }).Count -gt 0
        $hasPartialPolicy = @($apiOperations | Where-Object {
                $_.policyEvaluationStatus -eq 'Partial'
            }).Count -gt 0
        $hasUncertainAuthPath = @($apiOperations | Where-Object {
                $_.policyEvaluationStatus -eq 'Partial' -and
                $_.hasUnauthenticatedPolicyPath
            }).Count -gt 0
        $callerAuth = if ($apiOperations.Count -eq 0 -or
            $hasUncertainAuthPath) {
            $null
        }
        elseif ($hasWeakPath -and $callerAuthModes.Count -gt 0) {
            'Mixed'
        }
        elseif ($hasWeakPath) {
            if ($subscriptionRequired) {
                'SubscriptionKeyOnly'
            }
            else {
                'None'
            }
        }
        elseif ($callerAuthModes.Count -gt 1) {
            'Mixed'
        }
        else {
            @($callerAuthModes)[0]
        }

        $tags = [System.Collections.Generic.List[string]]::new()
        foreach ($tag in Get-ApimModelCollection -Payload $tagsMap[$apiName] `
                -Context "Tag payload for '$apiName'") {
            $tags.Add([string] (Get-ApimModelValue -InputObject $tag `
                        -Name name -Context 'APIM tag'))
        }
        [string[]] $sortedTags = $tags.ToArray()
        [System.Array]::Sort(
            $sortedTags,
            [System.StringComparer]::Ordinal
        )
        $ownerMatches = @($sortedTags | Where-Object {
                $_ -match $OwnerTagPattern
            })
        $ownerTag = if ($ownerMatches.Count -eq 0) {
            $null
        }
        else {
            $ownerMatches[0]
        }

        $revisions = @(Get-ApimModelCollection `
                -Payload $revisionsMap[$apiName] `
                -Context "Revision payload for '$apiName'")
        $nonCurrentOnlineRevisions = @($revisions | Where-Object {
                $revisionProperties = Get-ApimModelValue -InputObject $_ `
                    -Name properties -Context 'APIM revision'
                (Get-ApimModelBoolean -InputObject $revisionProperties `
                        -Name isOnline -Context 'APIM revision properties') -and
                -not (Get-ApimModelBoolean -InputObject $revisionProperties `
                        -Name isCurrent -Context 'APIM revision properties')
            }).Count

        $serviceUrl = [string] (Get-ApimModelValue `
                -InputObject $properties -Name serviceUrl `
                -Context 'APIM API properties' -AllowMissing)
        $backendHost = $null
        if (-not [string]::IsNullOrWhiteSpace($serviceUrl)) {
            $serviceUri = $null
            if (-not [System.Uri]::TryCreate(
                    $serviceUrl,
                    [System.UriKind]::Absolute,
                    [ref] $serviceUri
                ) -or [string]::IsNullOrWhiteSpace($serviceUri.Host)) {
                throw 'APIM API service URL was invalid.'
            }
            $backendHost = $serviceUri.Host
        }
        if (@($apiOperations | Where-Object backendOverride).Count -gt 0) {
            $backendHost = $null
        }

        $apiVersionSetId = [string] (Get-ApimModelValue `
                -InputObject $properties -Name apiVersionSetId `
                -Context 'APIM API properties' -AllowMissing)
        $versionSet = if ([string]::IsNullOrWhiteSpace($apiVersionSetId)) {
            $null
        }
        else {
            [System.Uri]::UnescapeDataString(
                ($apiVersionSetId.TrimEnd('/') -split '/')[-1]
            )
        }
        $apiVersionValue = Get-ApimModelValue -InputObject $properties `
            -Name apiVersion -Context 'APIM API properties' -AllowMissing
        $apiVersion = if ([string]::IsNullOrWhiteSpace(
                [string] $apiVersionValue
            )) {
            $null
        }
        else {
            [string] $apiVersionValue
        }

        $diagnosticFacts = [pscustomobject] [ordered]@{
            bodyLogging = $null
            sensitiveHeadersLogged = $null
        }
        if ($null -ne $diagnosticMap -and
            $diagnosticMap.ContainsKey($apiName)) {
            if ($diagnosticFactMap[$apiName].count -gt 0) {
                $diagnosticFacts = $diagnosticFactMap[$apiName].facts
            }
            elseif ($null -ne $serviceDiagnosticFacts) {
                $diagnosticFacts = $serviceDiagnosticFacts
            }
        }

        $missingInputs = [System.Collections.Generic.List[string]]::new()
        foreach ($missingInput in @(
                'backends',
                'exposure',
                'findings',
                'git',
                'openApiQuality',
                'usage'
            )) {
            $missingInputs.Add($missingInput)
        }
        if ($null -eq $diagnosticFacts.bodyLogging -or
            $null -eq $diagnosticFacts.sensitiveHeadersLogged) {
            $missingInputs.Add('diagnostics')
        }
        if ($null -eq $backendHost) {
            $missingInputs.Add('backendTarget')
        }
        if ($hasPartialPolicy) {
            $missingInputs.Add('policyFragments')
        }
        [string[]] $sortedMissingInputs = @(
            $missingInputs | Sort-Object -Unique
        )

        $apiRecords.Add([pscustomobject] [ordered]@{
                apiId                     = $apiName
                displayName               = [string] (
                    Get-ApimModelValue -InputObject $properties `
                        -Name displayName -Context 'APIM API properties'
                )
                path                      = [string] (
                    Get-ApimModelValue -InputObject $properties -Name path `
                        -Context 'APIM API properties'
                )
                apiType                   = [string] (
                    Get-ApimModelValue -InputObject $properties `
                        -Name apiType -Context 'APIM API properties'
                )
                protocols                 = @(
                    Get-ApimModelValue -InputObject $properties `
                        -Name protocols -Context 'APIM API properties' |
                        Sort-Object
                )
                backendHost               = $backendHost
                products                  = $productNames
                ownerTag                  = $ownerTag
                tags                      = $sortedTags
                versionSet                = $versionSet
                version                   = $apiVersion
                revisionCount             = $revisions.Count
                nonCurrentOnlineRevisions = $nonCurrentOnlineRevisions
                operationCount            = $apiOperations.Count
                subscriptionRequired      = $subscriptionRequired
                callerAuth                = $callerAuth
                throttling                = Get-ApimAggregateRiskValue `
                    -Records $apiOperations -Name throttling
                ipFilter                  = Get-ApimAggregateRiskValue `
                    -Records $apiOperations -Name ipFilter
                corsUnsafe                = Get-ApimAggregateRiskValue `
                    -Records $apiOperations -Name corsUnsafe
                backendAuth               = if (@($apiOperations |
                            Where-Object backendAuth).Count -gt 0) {
                    $true
                }
                elseif (@($apiOperations | Where-Object {
                            $null -eq $_.backendAuth
                        }).Count -gt 0) {
                    $null
                }
                else {
                    $false
                }
                hardcodedSecret           = Get-ApimAggregateRiskValue `
                    -Records $apiOperations -Name hardcodedSecret
                baseMissing               = Get-ApimAggregateRiskValue `
                    -Records $apiOperations -Name baseMissing
                mockOrTrace               = Get-ApimAggregateRiskValue `
                    -Records $apiOperations -Name mockOrTrace
                backendTlsValidation      = $null
                bodyLogging               = $diagnosticFacts.bodyLogging
                sensitiveHeadersLogged    = $diagnosticFacts.
                    sensitiveHeadersLogged
                reachability              = $null
                exposure                  = $null
                calls90d                  = $null
                callsViaAppGw             = $null
                callsInternal             = $null
                lastCall                  = $null
                p95Ms                     = $null
                backendP95Ms              = $null
                pct5xx                    = $null
                openApiScore              = $null
                inGit                     = $null
                findingIds                = $null
                modelStatus               = 'Partial'
                missingInputs             = $sortedMissingInputs
            })
    }

    $policyMatrix = [System.Collections.Generic.List[object]]::new()
    foreach ($api in $apiRecords) {
        $apiOperations = @($operationRecords |
                Where-Object apiId -EQ $api.apiId)
        $callerAuthStatus = if ($apiOperations.Count -eq 0) {
            'NA'
        }
        elseif (@($apiOperations | Where-Object {
                    -not $_.hasUnauthenticatedPolicyPath
                }).Count -eq $apiOperations.Count) {
            'Pass'
        }
        elseif (@($apiOperations | Where-Object {
                    $_.policyEvaluationStatus -eq 'Partial'
                }).Count -gt 0) {
            'NA'
        }
        else {
            'Fail'
        }
        $backendStatus = Get-ApimPositiveControlStatus `
            -Operations $apiOperations -CoverageProperty backendAuthAllPaths
        $matrixMissingInputs = [System.Collections.Generic.List[string]]::new()
        if ($backendStatus -eq 'NA' -and $null -eq $backendMap) {
            $matrixMissingInputs.Add('backends')
        }
        if (@($apiOperations | Where-Object {
                    $_.policyEvaluationStatus -eq 'Partial'
                }).Count -gt 0) {
            $matrixMissingInputs.Add('policyFragments')
        }
        [string[]] $sortedMatrixMissingInputs = @(
            $matrixMissingInputs | Sort-Object -Unique
        )
        $policyMatrix.Add([pscustomobject] [ordered]@{
                apiId             = $api.apiId
                evaluationStatus  = if ($sortedMatrixMissingInputs.Count -eq
                    0) {
                    'Complete'
                }
                else {
                    'Partial'
                }
                callerAuth        = $callerAuthStatus
                rateLimit         = Get-ApimPositiveControlStatus `
                    -Operations $apiOperations `
                    -CoverageProperty throttlingAllPaths
                ipFilter          = Get-ApimPositiveControlStatus `
                    -Operations $apiOperations `
                    -CoverageProperty ipFilterAllPaths
                corsSafe          = Get-ApimNegativeControlStatus `
                    -Operations $apiOperations -RiskProperty corsUnsafe
                backendAuth       = $backendStatus
                noHardcodedSecret = Get-ApimNegativeControlStatus `
                    -Operations $apiOperations `
                    -RiskProperty hardcodedSecret
                basePresent       = Get-ApimNegativeControlStatus `
                    -Operations $apiOperations -RiskProperty baseMissing
                noMockTrace       = Get-ApimNegativeControlStatus `
                    -Operations $apiOperations -RiskProperty mockOrTrace
                modelStatus       = if ($sortedMatrixMissingInputs.Count -eq
                    0) {
                    'Complete'
                }
                else {
                    'Partial'
                }
                missingInputs     = $sortedMatrixMissingInputs
            })
    }

    return [pscustomobject] [ordered]@{
        apis         = @($apiRecords | Sort-Object apiId)
        operations   = @($operationRecords |
                Sort-Object apiId, operationId)
        policyMatrix = @($policyMatrix | Sort-Object apiId)
    }
}

function Write-ApimApiPolicyModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Model
    )

    $models = [ordered]@{
        apis = @(Get-ApimModelValue -InputObject $Model -Name apis `
                -Context 'API policy model')
        operations = @(Get-ApimModelValue -InputObject $Model `
                -Name operations -Context 'API policy model')
        policyMatrix = @(Get-ApimModelValue -InputObject $Model `
                -Name policyMatrix -Context 'API policy model')
    }

    return Write-ApimModelSet -RunPath $RunPath -Models $models
}
