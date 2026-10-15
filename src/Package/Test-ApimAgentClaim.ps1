#Requires -Version 7.4

Set-StrictMode -Version Latest

$script:ApimClaimEvidence = @{
    HostWidePublication = @{ AssessmentCondition = @('HostWidePublication'); RoutingMode = @('HostWide') }
    DirectGatewayReachability = @{ AssessmentCondition = @('DirectGatewayReachable'); DirectPublic = @($true); Exposure = @('DirectPublic') }
    OriginAuthenticationUnverified = @{ AssessmentCondition = @('OriginAuthenticationAbsent') }
    WeakCallerAuthentication = @{ AssessmentCondition = @('KeyOnlyReachableApi', 'AnonymousReachableApi') }
    BroadSubscriptionScope = @{ AssessmentCondition = @('ActiveAllApiSubscription') }
    SecretHandlingRisk = @{ AssessmentCondition = @('PolicyCredentialDetected', 'PlainTextSecretDetected'); HardcodedSecret = @($true) }
    WeakTlsPosture = @{ AssessmentCondition = @('WeakGatewayTls', 'LegacyTlsEnabled', 'BackendTlsNotValidated', 'UnapprovedPlainHttp'); BackendTlsValidationDisabled = @($true) }
    InsufficientDiagnostics = @{}
    ReliabilityGap = @{ AssessmentCondition = @('ZoneRedundancyAbsent', 'CapacityBelowMinimum', 'CriticalBackendResilienceAbsent', 'ProbeMisaligned', 'CertificateNearExpiry') }
    GovernanceGap = @{ AssessmentCondition = @('ProductMissing', 'OwnerTagMissing', 'NonCurrentRevisionOnline', 'VersioningIncomplete', 'MixedPathVersioning', 'InheritedControlsDropped', 'MinimumApiVersionAbsent', 'LegacyPlatform', 'SourcePolicyDrift', 'EnvironmentPolicyDrift') }
}
$script:ApimClaimRecommendations = @{
    HostWidePublication = @('ConfirmExposure', 'RestrictPublication')
    DirectGatewayReachability = @('ConfirmExposure', 'RestrictPublication')
    OriginAuthenticationUnverified = @('ValidateOriginAuthentication')
    WeakCallerAuthentication = @('EnableCallerAuthentication')
    BroadSubscriptionScope = @('ReviewSubscriptionScope')
    SecretHandlingRisk = @('RemoveHardcodedSecrets')
    WeakTlsPosture = @('ReviewTlsPosture')
    InsufficientDiagnostics = @('EnableDiagnostics')
    ReliabilityGap = @('ImproveReliability')
    GovernanceGap = @('EstablishOwnership', 'ImproveLifecycleGovernance')
    MissingEvidence = @('ResolveDataGaps')
}
$script:ApimExecutiveClaims = @{
    ReduceExposure = @('HostWidePublication', 'DirectGatewayReachability')
    StrengthenAuthentication = @('WeakCallerAuthentication', 'BroadSubscriptionScope')
    ProtectSecrets = @('SecretHandlingRisk')
    ImproveTls = @('WeakTlsPosture')
    ImproveDiagnostics = @('InsufficientDiagnostics')
    ImproveReliability = @('ReliabilityGap')
    ImproveGovernance = @('GovernanceGap')
    ValidateAssumptions = @('OriginAuthenticationUnverified', 'MissingEvidence')
    ResolveDataGaps = @('MissingEvidence')
    ReviewUsage = @('UsageBucket')
    ReviewCost = @('CostTrend')
}

function Test-ApimClaimFact {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string] $Claim,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Fact
    )
    if ($Claim -cin @('UsageBucket', 'CostTrend')) {
        return $Fact.code -ceq $Claim -and $Fact.value -cne 'Unknown'
    }
    if (-not $script:ApimClaimEvidence.ContainsKey($Claim)) { return $false }
    $matrix = $script:ApimClaimEvidence[$Claim]
    return $matrix.ContainsKey($Fact.code) -and $matrix[$Fact.code] -ccontains $Fact.value
}

function Assert-ApimClaimEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Item,
        [Parameter(Mandatory)][string[]] $Claims,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Facts,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Findings
    )
    $rank = @{ Low = 0; Medium = 1; High = 2 }
    $ceiling = 2
    $cited = 0
    foreach ($id in $Item.factRefs) {
        $fact = $Facts[$id]
        $supported = @($Claims | Where-Object { Test-ApimClaimFact -Claim $_ -Fact $fact })
        if ($supported.Count -eq 0) { throw 'AGENT_EVIDENCE_REJECTED' }
        $ceiling = [Math]::Min($ceiling, $rank[$fact.confidence])
        $cited++
    }
    foreach ($id in $Item.findingRefs) {
        $finding = $Findings[$id]
        if ($finding.evaluation -ceq 'NotEvaluated') {
            if ($Claims -cnotcontains 'MissingEvidence') { throw 'AGENT_EVIDENCE_REJECTED' }
            $ceiling = 0
        }
        else {
            $supported = 0
            foreach ($factId in $finding.factRefs) {
                $fact = $Facts[$factId]
                if (@($Claims | Where-Object {
                            Test-ApimClaimFact -Claim $_ -Fact $fact
                        }).Count -gt 0) {
                    $supported++
                    $ceiling = [Math]::Min($ceiling, $rank[$fact.confidence])
                }
            }
            if ($supported -eq 0) { throw 'AGENT_EVIDENCE_REJECTED' }
        }
        $cited++
    }
    if ($cited -gt 0 -and $rank[$Item.confidence] -gt $ceiling) {
        throw 'AGENT_CONFIDENCE_REJECTED'
    }
    return $cited
}

function Test-ApimAgentClaim {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][ValidateSet('ExpertObservations', 'ExecutiveSummary')]
        [string] $Kind,
        [Parameter(Mandatory)][string] $Json,
        [Parameter(Mandatory)][string] $PackageJson,
        [AllowEmptyCollection()][string[]] $ObservationJson = @()
    )
    $parameters = @{ Kind = $Kind; Json = $Json; PackageJson = $PackageJson }
    if ($Kind -ceq 'ExecutiveSummary') { $parameters.ObservationJson = $ObservationJson }
    $null = Test-ApimAnalysisContract @parameters
    $package = ConvertFrom-ApimAnalysisContractJson -Kind AnalysisPackage -Json $PackageJson
    $inputContract = ConvertFrom-ApimAnalysisContractJson -Kind $Kind -Json $Json
    $facts = @{}; $findings = @{}; $observations = @{}
    foreach ($fact in $package.facts) { $facts.Add($fact.factId, $fact) }
    foreach ($finding in $package.findings) { $findings.Add($finding.findingId, $finding) }
    if ($Kind -ceq 'ExpertObservations') {
        foreach ($item in $inputContract.observations) {
            $claim = $item.rationaleCode
            if ($script:ApimClaimRecommendations[$claim] -cnotcontains $item.recommendationCode) {
                throw 'AGENT_RECOMMENDATION_REJECTED'
            }
            $category = switch ($claim) {
                { $_ -cin @('HostWidePublication', 'DirectGatewayReachability', 'OriginAuthenticationUnverified') } { @('Exposure', 'Architecture') }
                { $_ -cin @('ReliabilityGap') } { @('Reliability') }
                GovernanceGap { @('Governance') }
                MissingEvidence { @('Architecture', 'Exposure', 'Security', 'Reliability', 'Governance') }
                default { @('Security') }
            }
            if ($category -cnotcontains $item.category) { throw 'AGENT_CATEGORY_REJECTED' }
            $null = Assert-ApimClaimEvidence -Item $item -Claims @($claim) `
                -Facts $facts -Findings $findings
            if ($claim -ceq 'MissingEvidence' -and $item.confidence -cne 'Low') {
                throw 'AGENT_CONFIDENCE_REJECTED'
            }
        }
        return $true
    }
    foreach ($text in $ObservationJson) {
        $null = Test-ApimAgentClaim -Kind ExpertObservations -Json $text -PackageJson $PackageJson
        $set = ConvertFrom-ApimAnalysisContractJson -Kind ExpertObservations -Json $text
        foreach ($observation in $set.observations) { $observations.Add($observation.observationId, $observation) }
    }
    $rank = @{ Low = 0; Medium = 1; High = 2 }
    $globalCeiling = if ($package.dataGaps.Count -gt 0 -or $package.assumptions.Count -gt 0) { 1 } else { 2 }
    foreach ($section in @('priorities', 'themes', 'decisions', 'roadmap')) {
        foreach ($item in $inputContract[$section]) {
            $claims = $script:ApimExecutiveClaims[$item.code]
            $count = Assert-ApimClaimEvidence -Item $item -Claims $claims -Facts $facts -Findings $findings
            foreach ($id in $item.observationRefs) {
                $observation = $observations[$id]
                if ($claims -cnotcontains $observation.rationaleCode -or
                    $rank[$item.confidence] -gt $rank[$observation.confidence]) {
                    throw 'AGENT_RECONCILIATION_REJECTED'
                }
                $count++
            }
            if ($count -eq 0) { throw 'AGENT_EVIDENCE_REJECTED' }
            $globalCeiling = [Math]::Min($globalCeiling, $rank[$item.confidence])
        }
    }
    $evaluated = @($package.findings | Where-Object evaluation -CEQ Evaluated)
    $high = @($evaluated | Where-Object severity -CEQ High)
    $posture = if ($high.Count -gt 0) { 'ActionRequired' }
    elseif ($evaluated.Count -gt 0) { 'ImprovementRecommended' }
    else { 'InsufficientEvidence' }
    if ($inputContract.posture -cne $posture -or
        $rank[$inputContract.confidence] -gt $globalCeiling -or
        ($posture -ceq 'InsufficientEvidence' -and $inputContract.confidence -cne 'Low')) {
        throw 'AGENT_POSTURE_REJECTED'
    }
    if ($high.Count -gt 0) {
        $topCitations = @($inputContract.priorities | ForEach-Object {
                $_.findingRefs
                foreach ($id in $_.observationRefs) { $observations[$id].findingRefs }
            })
        if (@($high | Where-Object { $topCitations -ccontains $_.findingId }).Count -eq 0) {
            throw 'AGENT_PRIORITY_REJECTED'
        }
    }
    return $true
}
