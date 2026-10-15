#Requires -Version 7.4

Set-StrictMode -Version Latest

$script:ApimAnalysisConditions = [ordered]@{
    'APIM-NET-001' = 'OriginAuthenticationAbsent'
    'APIM-NET-002' = 'WafNotPreventing'
    'APIM-NET-004' = 'HostWidePublication'
    'APIM-NET-006' = 'DirectGatewayReachable'
    'APIM-NET-007' = 'BroadSubnetIngress'
    'APIM-NET-008' = 'WeakGatewayTls'
    'APIM-NET-009' = 'UnneededPublicEndpoint'
    'APIM-SEC-001' = 'LegacyTlsEnabled'
    'APIM-SEC-002' = 'MinimumApiVersionAbsent'
    'APIM-SEC-003' = 'KeyOnlyReachableApi'
    'APIM-SEC-004' = 'AnonymousReachableApi'
    'APIM-SEC-005' = 'ActiveAllApiSubscription'
    'APIM-SEC-007' = 'PolicyCredentialDetected'
    'APIM-SEC-008' = 'PlainTextSecretDetected'
    'APIM-SEC-009' = 'KeyVaultUnhealthy'
    'APIM-SEC-010' = 'BackendTlsNotValidated'
    'APIM-SEC-011' = 'UnapprovedPlainHttp'
    'APIM-SEC-012' = 'UnsafeCors'
    'APIM-SEC-014' = 'SensitiveDiagnosticCapture'
    'APIM-SEC-015' = 'SubscriptionTracing'
    'APIM-SEC-019' = 'ManagedIdentityAbsent'
    'APIM-SEC-020' = 'ProductionMockOrTrace'
    'APIM-GOV-001' = 'ProductMissing'
    'APIM-GOV-002' = 'OwnerTagMissing'
    'APIM-GOV-003' = 'ProductGovernanceWeak'
    'APIM-GOV-005' = 'NonCurrentRevisionOnline'
    'APIM-GOV-006' = 'VersioningIncomplete'
    'APIM-GOV-007' = 'SourcePolicyDrift'
    'APIM-GOV-008' = 'MixedPathVersioning'
    'APIM-GOV-009' = 'ApiDiagnosticsWeak'
    'APIM-GOV-010' = 'InheritedControlsDropped'
    'APIM-GOV-011' = 'EnvironmentPolicyDrift'
    'APIM-REL-001' = 'ZoneRedundancyAbsent'
    'APIM-REL-002' = 'CapacityBelowMinimum'
    'APIM-REL-003' = 'CriticalBackendResilienceAbsent'
    'APIM-REL-004' = 'ProbeMisaligned'
    'APIM-REL-005' = 'CertificateNearExpiry'
    'APIM-REL-006' = 'LegacyPlatform'
    'APIM-POR-001' = 'PortalUnavailable'
    'APIM-POR-002' = 'PortalAuthenticationWeak'
    'APIM-POR-003' = 'ProductVisibilityMismatch'
    'APIM-POR-004' = 'ApiDocumentationWeak'
    'APIM-POR-005' = 'LegacyPortalEnabled'
}

function Get-ApimAnalysisUsageBand {
    [CmdletBinding()]
    param(
        [AllowNull()][object] $Calls,
        [Parameter(Mandatory)][double[]] $Thresholds
    )

    if ($null -eq $Calls) { return 'Unknown' }
    if ($Calls -eq 0) { return 'Zero' }
    $bands = @('VeryLow', 'Low', 'Medium', 'High', 'VeryHigh', 'Extreme')
    for ($i = 5; $i -ge 0; $i--) {
        if ($Calls -ge $Thresholds[$i]) { return $bands[$i] }
    }
    throw 'ANALYSIS_BUILD_REJECTED'
}

function Get-ApimAnalysisGap {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Inputs)

    $codes = foreach ($inputName in $Inputs) {
        switch -Regex -CaseSensitive ($inputName) {
            'usage' { 'UsageUnavailable'; break }
            'cost' { 'CostUnavailable'; break }
            'edgeOrigin' { 'OriginAuthenticationUnknown'; break }
            'auxiliaryRoutes' { 'OwnerIntentUnknown'; break }
            'policy|Policy' { 'PolicyIncomplete'; break }
            'network' { 'NetworkIncomplete'; break }
            'diagnostic|Diagnostic' { 'DiagnosticsIncomplete'; break }
            'ownerIntent|criticalIntent|governance' { 'OwnerIntentUnknown'; break }
            'externalIntent' { 'ProductClassificationUnavailable'; break }
            'backend|Backend' { 'BackendMappingUnavailable'; break }
            'git' { 'GitUnavailable'; break }
            default { 'CollectionIncomplete' }
        }
    }
    return @($codes | Sort-Object -Unique -CaseSensitive)
}

function Assert-ApimAnalysisIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Identity)

    # Identifiers may remain restricted, but credential-like or encoded identifiers may not.
    if ($Identity.Length -gt 2048 -or
        $Identity -match '[^\x20-\x7e]|[<>=?%\\]' -or
        $Identity -match '(?i)bearer|password|accountkey|sharedaccess|private.key|sig=|eyJ[A-Za-z0-9_-]+\.' -or
        $Identity -match '[A-Za-z0-9+_/-]{64,}') {
        throw 'ANALYSIS_BUILD_REJECTED'
    }
}

function New-ApimAnalysisPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Config
    )

    $ErrorActionPreference = 'Stop'
    $VerbosePreference = 'SilentlyContinue'
    $stage = $null
    try {
        $root = Resolve-ApimAnalysisRoot -Path $RunPath
        foreach ($relative in @('manifest.json', 'findings.json') +
            @($script:ApimModelSchemaPaths.Keys | Where-Object {
                    $_ -cnotin @('drift', 'portal', 'openApiQuality', 'products', 'diagnosticCoverage')
                } |
                ForEach-Object { "model/$_.json" })) {
            $null = Read-ApimAnalysisSnapshot -Path (
                Resolve-RunFilePath -RunPath $root -RelativePath $relative
            )
        }
        $manifest = Get-RunManifest -RunPath $root
        $models = Get-ApimModelSet -RunPath $root
        $saved = @(Get-ApimFindingSet -RunPath $root)
        $thresholds = $Config.AnalysisPackage.UsageBuckets
        if ($Config.AnalysisPackage.UsageMode -cne 'Bucketed' -or
            $Config.AnalysisPackage.CostMode -cne 'RelativeOnly' -or
            $thresholds.Count -ne 6 -or $thresholds[0] -ne 0) {
            throw 'ANALYSIS_BUILD_REJECTED'
        }
        for ($i = 0; $i -lt 6; $i++) {
            Test-ConfigNumber -Value $thresholds[$i] -Context 'Usage band'
            if ($i -gt 0 -and $thresholds[$i] -le $thresholds[$i - 1]) {
                throw 'ANALYSIS_BUILD_REJECTED'
            }
        }
        foreach ($group in @('Severity', 'Exposure', 'Usage')) {
            foreach ($weight in $Config.Scoring[$group].Keys) {
                if ($Config.Scoring[$group][$weight] -ne $manifest.scoring.$group.$weight) {
                    throw 'ANALYSIS_BUILD_REJECTED'
                }
            }
        }
        $rules = @(Get-ApimRuleCatalog -CatalogPath (
                Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'rules'
            ))
        $replayed = @(Invoke-ApimRuleEngine -Rules $rules -Models $models `
                -Manifest $manifest -Config $Config)
        $savedIndex = [System.Collections.Generic.Dictionary[string, object]]::new(
            [StringComparer]::Ordinal
        )
        foreach ($finding in $saved) { $savedIndex.Add($finding.findingKey, $finding) }
        if ($saved.Count -ne $replayed.Count) { throw 'ANALYSIS_BUILD_REJECTED' }
        foreach ($finding in $replayed) {
            if (-not $savedIndex.ContainsKey($finding.findingKey)) {
                throw 'ANALYSIS_BUILD_REJECTED'
            }
            $prior = $savedIndex[$finding.findingKey]
            foreach ($field in @('severity', 'evaluation', 'priorityScore', 'exposure', 'usage')) {
                if ($prior.$field -cne $finding[$field]) { throw 'ANALYSIS_BUILD_REJECTED' }
            }
        }

        $subjects = [System.Collections.Generic.Dictionary[string, object]]::new(
            [StringComparer]::Ordinal
        )
        $subjects.Add('service', @{ kind = 'Service'; model = $models.service })
        $subjects.Add('network', @{ kind = 'Network'; model = $models.network })
        foreach ($entry in @(
                @('apis', 'Api', 'api', 'apiId'),
                @('operations', 'Operation', 'operation', 'operationId'),
                @('subscriptions', 'Subscription', 'subscription', 'subscriptionId'),
                @('namedValues', 'NamedValue', 'named-value', 'namedValueId'),
                @('backends', 'Backend', 'backend', 'backendId'),
                @('certificates', 'Certificate', 'certificate', 'certificateId'),
                @('exposure', 'Route', 'route', 'routeKey')
            )) {
            foreach ($row in $models[$entry[0]]) {
                $id = [string] $row.($entry[3])
                if ($entry[1] -eq 'Operation') { $id = "$($row.apiId)/$id" }
                $key = "$($entry[2]):$id"
                Assert-ApimAnalysisIdentity -Identity $key
                $subjects.Add($key, @{ kind = $entry[1]; model = $row })
            }
        }
        foreach ($route in @($models.network.auxiliaryRoutes)) {
            if ($null -eq $route) { continue }
            $key = "route:$($route.routeKey)"
            Assert-ApimAnalysisIdentity -Identity $key
            $subjects.Add($key, @{ kind = 'Route'; model = $route })
        }
        foreach ($row in @($models.operations) + @($models.exposure) + @($models.policyMatrix)) {
            if (-not $subjects.ContainsKey("api:$($row.apiId)")) {
                throw 'ANALYSIS_BUILD_REJECTED'
            }
        }
        foreach ($subscription in $models.subscriptions) {
            if ($subscription.scopeType -ceq 'Api' -and
                -not $subjects.ContainsKey("api:$($subscription.scopeTarget)")) {
                throw 'ANALYSIS_BUILD_REJECTED'
            }
        }
        if ($models.Contains('products')) {
            foreach ($product in @($models.products | Where-Object productFound -EQ $true)) {
                $key = "product:$($product.productId)"
                Assert-ApimAnalysisIdentity -Identity $key
                $subjects.Add($key, @{ kind = 'Product'; model = $product })
            }
        }
        foreach ($product in @($models.apis.products) + @(
                $models.subscriptions | Where-Object scopeType -CEQ Product |
                    ForEach-Object { $_.scopeTarget }
            )) {
            $key = "product:$product"
            Assert-ApimAnalysisIdentity -Identity $key
            if (-not $subjects.ContainsKey($key)) {
                $subjects.Add($key, @{
                        kind = 'Product'
                        model = [pscustomobject]@{ modelStatus = 'Complete'; missingInputs = @() }
                    })
            }
        }
        [string[]] $keys = @($subjects.Keys)
        [Array]::Sort($keys, [StringComparer]::Ordinal)
        $counters = @{}
        $entities = [System.Collections.Generic.List[object]]::new()
        $aliases = [System.Collections.Generic.List[object]]::new()
        foreach ($key in $keys) {
            $subject = $subjects[$key]
            $kind = $subject.kind
            if (-not $counters.ContainsKey($kind)) { $counters[$kind] = 0 }
            $counters[$kind]++
            $prefix = if ($kind -ceq 'NamedValue') { 'named-value' } else {
                $kind.ToLowerInvariant()
            }
            $alias = '{0}-{1:d3}' -f $prefix, $counters[$kind]
            $subject.alias = $alias
            $entities.Add([ordered]@{ alias = $alias; kind = $kind })
            $aliases.Add([ordered]@{ alias = $alias; scope = $key })
        }
        $facts = [System.Collections.Generic.List[object]]::new()
        $pending = [System.Collections.Generic.List[object]]::new()
        $allGaps = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $null = $allGaps.Add('CostUnavailable')
        $assumptions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $null = $assumptions.Add('CostUnavailable')
        if ($models.Contains('diagnosticCoverage')) {
            foreach ($row in $models.diagnosticCoverage) {
                foreach ($gap in @(Get-ApimAnalysisGap -Inputs @($row.missingInputs))) {
                    $null = $allGaps.Add($gap)
                }
            }
        }
        foreach ($key in $keys) {
            $subject = $subjects[$key]
            $row = $subject.model
            $confidence = if ($row.PSObject.Properties['modelStatus'] -and
                $row.modelStatus -ceq 'Partial') { 'Medium' } else { 'High' }
            if ($row.PSObject.Properties['missingInputs']) {
                foreach ($gap in @(Get-ApimAnalysisGap -Inputs @($row.missingInputs))) {
                    $null = $allGaps.Add($gap)
                }
            }
            $values = [ordered]@{}
            switch -CaseSensitive ($subject.kind) {
                Service {
                    $values.ApiCount = @($models.apis).Count
                    $values.OperationCount = @($models.operations).Count
                    $values.SubscriptionCount = @($models.subscriptions).Count
                    $values.FindingCount = $replayed.Count
                    $values.CostTrend = 'Unknown'
                }
                Network {
                    $values.VnetMode = $row.virtualNetworkType
                    $values.DirectPublic = $row.directPublic
                    $values.WafPosture = if ($row.wafState -ceq 'Disabled') {
                        'Disabled'
                    } elseif ($row.wafState -ceq 'Enabled') { $row.wafMode } else { 'Unknown' }
                    if ($null -eq $row.edgeOriginAssessment -or
                        $row.edgeOriginAssessment.originAuthentication -ceq 'Unknown') {
                        $null = $allGaps.Add('OriginAuthenticationUnknown')
                        $null = $assumptions.Add('OriginAuthenticationUnverified')
                    }
                    if ($null -eq $row.auxiliaryRoutes -or
                        @($row.auxiliaryRoutes | Where-Object ownerNeed -CEQ Unknown).Count -gt 0) {
                        $null = $allGaps.Add('OwnerIntentUnknown')
                        $null = $assumptions.Add('OwnerIntentUnverified')
                    }
                }
                Api {
                    $auth = @{
                        'Entra/JWT' = 'Jwt'; mTLS = 'Mtls'; Both = 'JwtAndMtls'
                        SubscriptionKeyOnly = 'SubscriptionKeyOnly'; None = 'None'; Unknown = 'Unknown'
                    }
                    $values.CallerAuth = if ($null -eq $row.callerAuth -or
                        $row.callerAuth -ceq 'Mixed') { 'Unknown' } else {
                        if (-not $auth.ContainsKey($row.callerAuth)) { throw 'ANALYSIS_BUILD_REJECTED' }
                        $auth[$row.callerAuth]
                    }
                    $values.Exposure = $row.exposure
                    $values.UsageBucket = Get-ApimAnalysisUsageBand -Calls $row.calls90d `
                        -Thresholds $thresholds
                    $values.BaseMissing = $row.baseMissing
                    $values.HardcodedSecret = $row.hardcodedSecret
                    $values.SubscriptionRequired = $row.subscriptionRequired
                    $values.BodyLogging = $row.bodyLogging
                    $values.SensitiveHeadersLogged = $row.sensitiveHeadersLogged
                }
                Operation {
                    $values.BaseMissing = $row.baseMissing
                    $values.HardcodedSecret = $row.hardcodedSecret
                    $values.JwtConfigured = $row.callerAuthJwt
                    $values.MtlsConfigured = $row.callerAuthMtls
                }
                Subscription {
                    $values.UsageBucket = Get-ApimAnalysisUsageBand -Calls $row.calls90d `
                        -Thresholds $thresholds
                }
                Route {
                    if ($row.PSObject.Properties['ruleType']) {
                        $values.RoutingMode = if ($row.ruleType -ceq 'Basic') {
                            'HostWide'
                        } elseif ($row.ruleType -ceq 'PathBasedRouting') {
                            'PathBased'
                        } else { 'Unknown' }
                        $values.Exposure = $row.exposure
                        $values.EdgeAssumption = if ($row.edge -ceq 'Cloudflare-Assumed') {
                            $null = $assumptions.Add('CloudflareAssumed')
                            'CloudflareAssumed'
                        } else { 'None' }
                        $confidence = $row.confidence
                    }
                }
            }
            foreach ($code in $values.Keys) {
                $facts.Add([ordered]@{
                        factId = 'fact-{0:d6}' -f ($facts.Count + 1)
                        subjectAlias = $subject.alias
                        code = $code
                        value = $values[$code]
                        confidence = $confidence
                    })
            }
        }
        if ($allGaps.Contains('UsageUnavailable')) {
            $null = $assumptions.Add('TelemetryUnavailable')
        }
        $maximum = 1.0
        foreach ($group in @('Severity', 'Exposure', 'Usage')) {
            $maximum *= ($Config.Scoring[$group].Values | Measure-Object -Maximum).Maximum
        }
        foreach ($finding in $replayed) {
            if (-not $script:ApimAnalysisConditions.Contains($finding.ruleId)) {
                throw 'ANALYSIS_BUILD_REJECTED'
            }
            $portalFinding = $finding.ruleId -cin @(
                'APIM-POR-001', 'APIM-POR-002', 'APIM-POR-003', 'APIM-POR-005'
            ) -and $finding.scope -ceq 'portal'
            $subjectKey = if ($finding.scope -ceq 'missing-input' -or $portalFinding) { 'service' } else {
                $finding.scope
            }
            if (-not $subjects.ContainsKey($subjectKey)) { throw 'ANALYSIS_BUILD_REJECTED' }
            $subject = $subjects[$subjectKey]
            $refs = @()
            $gaps = @()
            $bucket = 'Unknown'
            if ($finding.evaluation -ceq 'Evaluated') {
                $factId = 'fact-{0:d6}' -f ($facts.Count + 1)
                $confidenceModel = if ($portalFinding) { $models.portal }
                elseif ($finding.ruleId -ceq 'APIM-GOV-009') {
                    @($models.diagnosticCoverage | Where-Object apiId -CEQ $subject.model.apiId)[0]
                }
                else { $subject.model }
                $facts.Add([ordered]@{
                        factId = $factId
                        subjectAlias = $subject.alias
                        code = 'AssessmentCondition'
                        value = $script:ApimAnalysisConditions[$finding.ruleId]
                        confidence = if ($confidenceModel.PSObject.Properties['modelStatus'] -and
                            $confidenceModel.modelStatus -ceq 'Partial') { 'Medium' } else { 'High' }
                    })
                $refs = @($factId)
                $ratio = $finding.priorityScore / $maximum
                $bucket = if ($ratio -ge (2.0 / 3)) { 'High' } elseif (
                    $ratio -ge (1.0 / 3)) { 'Medium' } else { 'Low' }
            }
            else {
                $gaps = @(Get-ApimAnalysisGap -Inputs $finding.evidence.missingInputs)
                foreach ($gap in $gaps) { $null = $allGaps.Add($gap) }
            }
            $pending.Add([ordered]@{
                    findingId = 'finding-{0:d6}' -f ($pending.Count + 1)
                    ruleId = $finding.ruleId
                    subjectAlias = $subject.alias
                    severity = $finding.severity
                    evaluation = $finding.evaluation
                    priorityBucket = $bucket
                    factRefs = $refs
                    dataGaps = $gaps
                })
        }
        $package = [ordered]@{
            schemaVersion = if (@($replayed | Where-Object {
                        $_.ruleId -cin @('APIM-GOV-003', 'APIM-GOV-009') -and $_.evaluation -ceq 'Evaluated'
                    }).Count -gt 0) { '1.4' }
            elseif (@($replayed | Where-Object {
                        $_.ruleId -clike 'APIM-POR-*' -and $_.evaluation -ceq 'Evaluated'
                    }).Count -gt 0) { '1.3' }
            elseif (@($replayed | Where-Object {
                        $_.ruleId -cin @('APIM-GOV-007', 'APIM-GOV-011') -and
                        $_.evaluation -ceq 'Evaluated'
                    }).Count -gt 0) { '1.2' } else { '1.1' }
            entities = $entities.ToArray()
            facts = $facts.ToArray()
            findings = $pending.ToArray()
            assumptions = @($assumptions | Sort-Object -CaseSensitive)
            dataGaps = @($allGaps | Sort-Object -CaseSensitive)
        }
        $json = ConvertTo-ApimAnalysisJson -Value $package
        $null = Test-ApimAnalysisContract -Kind AnalysisPackage -Json $json
        $aliasJson = ConvertTo-ApimAnalysisJson -Value ([ordered]@{
                schemaVersion = '1.0'; aliases = $aliases.ToArray()
            })
        if (-not $PSCmdlet.ShouldProcess('Restricted candidate', 'Create package snapshot')) {
            return
        }
        $parent = Resolve-RunFilePath -RunPath $root -RelativePath 'restricted/candidates'
        Test-ConfigPathLink -Path $parent -Context 'Candidate parent'
        $null = [IO.Directory]::CreateDirectory($parent)
        $id = 'candidate-' + [guid]::NewGuid().ToString('N')
        $stage = Join-Path $parent $id
        $null = [IO.Directory]::CreateDirectory($stage)
        Test-ConfigPathLink -Path $stage -Context 'Candidate snapshot'
        $encoding = [Text.UTF8Encoding]::new($false, $true)
        [IO.File]::WriteAllText((Join-Path $stage 'analysis-package.json'), $json, $encoding)
        [IO.File]::WriteAllText((Join-Path $stage 'alias-map.json'), $aliasJson, $encoding)
        $stage = $null
        return [pscustomobject]@{ status = 'Built'; candidateId = $id }
    }
    catch {
        throw [InvalidOperationException]::new('ANALYSIS_BUILD_REJECTED')
    }
    finally {
        if ($null -ne $stage -and [IO.Directory]::Exists($stage)) {
            try {
                Test-ConfigPathLink -Path $stage -Context 'Owned candidate cleanup'
                [IO.Directory]::Delete($stage, $true)
            }
            catch { throw [InvalidOperationException]::new('ANALYSIS_BUILD_REJECTED') }
        }
    }
}
