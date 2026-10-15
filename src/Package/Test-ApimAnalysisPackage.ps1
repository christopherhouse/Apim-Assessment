#Requires -Version 7.4

Set-StrictMode -Version Latest

function Assert-ApimAnalysisScan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Package)

    # This vocabulary is deliberately independent of the builder's mappings.
    $values = @{
        VnetMode = @('Internal', 'External', 'None', 'Unknown')
        RoutingMode = @('HostWide', 'PathBased', 'Unknown')
        WafPosture = @('Prevention', 'Detection', 'Disabled', 'Unknown')
        EdgeAssumption = @('CloudflareAssumed', 'None', 'Unknown')
        Exposure = @('DirectPublic', 'ExternalInUse', 'ExternalUnintended', 'Restricted', 'Internal', 'Platform', 'Unknown')
        CallerAuth = @('Jwt', 'Mtls', 'JwtAndMtls', 'SubscriptionKeyOnly', 'None', 'Unknown')
        UsageBucket = if ($Package.schemaVersion -cin @('1.1', '1.2')) {
            @('Zero', 'VeryLow', 'Low', 'Medium', 'High', 'VeryHigh', 'Extreme', 'Unknown')
        } else { @('Zero', 'Low', 'Medium', 'High', 'Unknown') }
        CostTrend = @('Decreasing', 'Stable', 'Increasing', 'Unknown')
        AssessmentCondition = @(
            'OriginAuthenticationAbsent', 'WafNotPreventing', 'HostWidePublication',
            'DirectGatewayReachable', 'BroadSubnetIngress', 'WeakGatewayTls',
            'UnneededPublicEndpoint', 'LegacyTlsEnabled', 'MinimumApiVersionAbsent',
            'KeyOnlyReachableApi', 'AnonymousReachableApi', 'ActiveAllApiSubscription',
            'PolicyCredentialDetected', 'PlainTextSecretDetected', 'KeyVaultUnhealthy',
            'BackendTlsNotValidated', 'UnapprovedPlainHttp', 'UnsafeCors',
            'SensitiveDiagnosticCapture', 'SubscriptionTracing', 'ManagedIdentityAbsent',
            'ProductionMockOrTrace', 'ProductMissing', 'OwnerTagMissing',
            'NonCurrentRevisionOnline', 'VersioningIncomplete', 'MixedPathVersioning',
            'InheritedControlsDropped', 'ZoneRedundancyAbsent', 'CapacityBelowMinimum',
            'CriticalBackendResilienceAbsent', 'ProbeMisaligned', 'CertificateNearExpiry',
            'LegacyPlatform'
        )
    }
    if ($Package.schemaVersion -ceq '1.2') {
        $values.AssessmentCondition += @('SourcePolicyDrift', 'EnvironmentPolicyDrift')
    }
    $booleanCodes = @(
        'DirectPublic', 'JwtConfigured', 'MtlsConfigured', 'IpFilterConfigured',
        'HostCheckConfigured', 'BaseMissing', 'HardcodedSecret', 'SubscriptionRequired',
        'BackendTlsValidationDisabled', 'BodyLogging', 'SensitiveHeadersLogged',
        'ManagedIdentityConfigured', 'CriticalBackend'
    )
    $countCodes = @('ApiCount', 'OperationCount', 'SubscriptionCount', 'FindingCount')
    $allowedKeys = @(
        'schemaVersion', 'entities', 'facts', 'findings', 'assumptions', 'dataGaps',
        'alias', 'kind', 'factId', 'subjectAlias', 'code', 'value', 'confidence',
        'findingId', 'ruleId', 'severity', 'evaluation', 'priorityBucket', 'factRefs'
    )
    $fieldValues = @{
        schemaVersion = @('1.0', '1.1', '1.2')
        kind = @('Service', 'Api', 'Operation', 'Product', 'Subscription', 'NamedValue', 'Backend', 'Certificate', 'Network', 'Route')
        confidence = @('High', 'Medium', 'Low')
        severity = @('High', 'Medium', 'Low', 'Info')
        evaluation = @('Evaluated', 'NotEvaluated')
        priorityBucket = @('High', 'Medium', 'Low', 'Unknown')
        assumptions = @('CloudflareAssumed', 'OriginAuthenticationUnverified', 'OwnerIntentUnverified', 'TelemetryUnavailable', 'CostUnavailable')
        dataGaps = @('CollectionIncomplete', 'PolicyIncomplete', 'NetworkIncomplete', 'DiagnosticsIncomplete', 'UsageUnavailable', 'CostUnavailable', 'OriginAuthenticationUnknown', 'OwnerIntentUnknown', 'BackendMappingUnavailable', 'ProductClassificationUnavailable', 'DefenderUnavailable', 'RbacUnavailable', 'GitUnavailable')
        code = @($values.Keys) + $booleanCodes + $countCodes
    }
    $fieldPatterns = @{
        alias = '^(?:service|api|operation|product|subscription|named-value|backend|certificate|network|route)-(?=[0-9]*[1-9])[0-9]{3,6}\z'
        subjectAlias = '^(?:service|api|operation|product|subscription|named-value|backend|certificate|network|route)-(?=[0-9]*[1-9])[0-9]{3,6}\z'
        factId = '^fact-(?=[0-9]*[1-9])[0-9]{6}\z'
        factRefs = '^fact-(?=[0-9]*[1-9])[0-9]{6}\z'
        findingId = '^finding-(?=[0-9]*[1-9])[0-9]{6}\z'
        ruleId = '^APIM-(?:NET|SEC|GOV|REL|PERF|POR|COST)-[0-9]{3}\z'
    }
    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push(@{ value = $Package; field = ''; code = '' })
    $work = 0
    while ($stack.Count -gt 0) {
        if (++$work -gt 150000) { throw 'ANALYSIS_SCAN_REJECTED' }
        $frame = $stack.Pop()
        $node = $frame.value
        if ($node -is [System.Collections.IDictionary]) {
            foreach ($key in $node.Keys) {
                if ($allowedKeys -cnotcontains $key) { throw 'ANALYSIS_SCAN_REJECTED' }
                $stack.Push(@{
                        value = $node[$key]; field = $key
                        code = if ($node.Contains('code')) { $node.code } else { '' }
                    })
            }
            if ($node.Contains('code')) {
                $code = $node.code
                if ($values.ContainsKey($code)) {
                    if ($node.value -isnot [string] -or $values[$code] -cnotcontains $node.value) {
                        throw 'ANALYSIS_SCAN_REJECTED'
                    }
                }
                elseif ($code -cin $booleanCodes) {
                    if ($null -ne $node.value -and $node.value -isnot [bool]) {
                        throw 'ANALYSIS_SCAN_REJECTED'
                    }
                }
                elseif ($code -cin $countCodes) {
                    if ($node.value -isnot [long] -and $node.value -isnot [int] -or
                        $node.value -lt 0 -or $node.value -gt 10000) {
                        throw 'ANALYSIS_SCAN_REJECTED'
                    }
                }
                else { throw 'ANALYSIS_SCAN_REJECTED' }
            }
        }
        elseif ($node -is [array]) {
            foreach ($child in $node) {
                $stack.Push(@{ value = $child; field = $frame.field; code = $frame.code })
            }
        }
        elseif ($node -is [string]) {
            if ($node.Length -gt 80 -or $node -match '[^\x20-\x7e]') {
                throw 'ANALYSIS_SCAN_REJECTED'
            }
            # No encoded or normalized alternative is admissible to this closed ASCII contract.
            $normalized = $node.Normalize([Text.NormalizationForm]::FormKC)
            for ($round = 0; $round -lt 3; $round++) {
                $decoded = [Net.WebUtility]::HtmlDecode([Uri]::UnescapeDataString($normalized))
                if ($decoded -cne $normalized) { throw 'ANALYSIS_SCAN_REJECTED' }
            }
            if ($node -match '[\\/<>=@%:&;]' -or
                $node -match '(?i)[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}' -or
                $node -match '[A-Za-z0-9+_/-]{48,}' -or
                ($node.Contains('.') -and $node -cnotin @('1.0', '1.1', '1.2'))) {
                throw 'ANALYSIS_SCAN_REJECTED'
            }
            if ($frame.field -ceq 'value') {
                if (-not $values.ContainsKey($frame.code) -or
                    $values[$frame.code] -cnotcontains $node) {
                    throw 'ANALYSIS_SCAN_REJECTED'
                }
            }
            elseif ($fieldValues.ContainsKey($frame.field)) {
                if ($fieldValues[$frame.field] -cnotcontains $node) {
                    throw 'ANALYSIS_SCAN_REJECTED'
                }
            }
            elseif ($fieldPatterns.ContainsKey($frame.field)) {
                if ($node -cnotmatch $fieldPatterns[$frame.field]) {
                    throw 'ANALYSIS_SCAN_REJECTED'
                }
            }
            else { throw 'ANALYSIS_SCAN_REJECTED' }
        }
        elseif ($null -ne $node -and $node -isnot [bool] -and
            $node -isnot [long] -and $node -isnot [int]) {
            throw 'ANALYSIS_SCAN_REJECTED'
        }
    }
}

function Test-ApimAnalysisAttestation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Json)

    if ([Text.Encoding]::UTF8.GetByteCount($Json) -gt 64KB) {
        throw 'ANALYSIS_ATTESTATION_REJECTED'
    }
    $options = [System.Text.Json.JsonDocumentOptions]::new()
    $options.MaxDepth = 8
    $document = $null
    try {
        $document = [System.Text.Json.JsonDocument]::Parse($Json, $options)
        Assert-ApimAnalysisJsonMember -Element $document.RootElement
    }
    finally { if ($null -ne $document) { $document.Dispose() } }
    $schema = Join-Path (
        Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    ) 'schemas/validation-attestation.schema.json'
    if (-not (Test-Json -Json $Json -SchemaFile $schema -ErrorAction Stop)) {
        throw 'ANALYSIS_ATTESTATION_REJECTED'
    }
}

function Test-ApimAnalysisPackage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $CandidatePath)

    $ErrorActionPreference = 'Stop'
    $VerbosePreference = 'SilentlyContinue'
    try {
        $path = Resolve-ApimAnalysisRoot -Path $CandidatePath
        $bytes = Read-ApimAnalysisSnapshot -Path $path
        $json = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        $null = Test-ApimAnalysisContract -Kind AnalysisPackage -Json $json
        $package = ConvertFrom-Json -InputObject $json -AsHashtable -Depth 32
        Assert-ApimAnalysisScan -Package $package
        $version = Get-ApimAssessmentToolVersion
        $attestation = [ordered]@{
            schemaVersion = '1.0'
            packageSchemaVersion = $package.schemaVersion
            packageSha256 = Get-ApimAnalysisDigest -Bytes $bytes
            builderVersion = $version
            validatorVersion = $version
            status = 'Passed'
            checks = [ordered]@{
                contract = 'Passed'; references = 'Passed'; prohibitedValues = 'Passed'
            }
        }
        Test-ApimAnalysisAttestation -Json (ConvertTo-ApimAnalysisJson -Value $attestation)
        return $attestation
    }
    catch {
        throw [InvalidOperationException]::new('ANALYSIS_VALIDATION_REJECTED')
    }
}
