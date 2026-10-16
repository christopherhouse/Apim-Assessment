#Requires -Version 7.4

Set-StrictMode -Version Latest

$analysisSchemaRoot = Join-Path (
    Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
) 'schemas'
$script:ApimAnalysisSchemaPaths = @{
    AnalysisPackage = Join-Path $analysisSchemaRoot 'analysis-package.schema.json'
    ExpertObservations = Join-Path $analysisSchemaRoot 'expert-observations.schema.json'
    ExecutiveSummary = Join-Path $analysisSchemaRoot 'executive-summary.schema.json'
}

function Assert-ApimAnalysisJsonMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Text.Json.JsonElement] $Element
    )

    if ($Element.ValueKind -eq 'Object') {
        $names = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) {
                throw 'Analysis contract contains duplicate JSON members.'
            }
            Assert-ApimAnalysisJsonMember -Element $property.Value
        }
    }
    elseif ($Element.ValueKind -eq 'Array') {
        foreach ($child in $Element.EnumerateArray()) {
            Assert-ApimAnalysisJsonMember -Element $child
        }
    }
}

function ConvertFrom-ApimAnalysisContractJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('AnalysisPackage', 'ExpertObservations', 'ExecutiveSummary')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Json
    )

    if ($Json.Length -gt 16MB -or
        [System.Text.Encoding]::UTF8.GetByteCount($Json) -gt 16MB) {
        throw 'Analysis contract size limit exceeded.'
    }
    $options = [System.Text.Json.JsonDocumentOptions]::new()
    $options.MaxDepth = 32
    $document = $null
    try {
        $document = [System.Text.Json.JsonDocument]::Parse($Json, $options)
        Assert-ApimAnalysisJsonMember -Element $document.RootElement
        $schemaPath = $script:ApimAnalysisSchemaPaths[$Kind]
        $version = $document.RootElement.GetProperty('schemaVersion').GetString()
        if ($Kind -eq 'AnalysisPackage' -and $version -cin @('1.1', '1.2', '1.3', '1.4', '1.5')) {
            $schemaPath = Join-Path $analysisSchemaRoot "analysis-package.v$version.schema.json"
        }
        $valid = Test-Json -Json $Json -SchemaFile $schemaPath `
            -ErrorAction Stop
        if (-not $valid) { throw 'Analysis contract schema validation failed.' }
        return ConvertFrom-Json -InputObject $Json -AsHashtable -Depth 32 `
            -ErrorAction Stop
    }
    catch {
        throw 'Analysis contract JSON or schema validation failed.'
    }
    finally {
        if ($null -ne $document) { $document.Dispose() }
    }
}

function Assert-ApimAnalysisReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Item,

        [Parameter(Mandatory)]
        [object] $Index,

        [System.Collections.Generic.HashSet[string]] $ObservationIds,

        [switch] $RequireCitation
    )

    $referenceSets = @{
        factRefs = $Index.facts
        findingRefs = $Index.findings
        observationRefs = $ObservationIds
    }
    $count = 0
    foreach ($name in $referenceSets.Keys) {
        if (-not $Item.Contains($name)) { continue }
        foreach ($reference in $Item[$name]) {
            $set = $referenceSets[$name]
            if ($null -eq $set -or -not $set.Contains($reference)) {
                throw 'Analysis contract has an unsupported reference.'
            }
            $count++
        }
    }
    if ($RequireCitation -and $count -eq 0) {
        throw 'Analysis contract requires a supported citation.'
    }
}

function Get-ApimAnalysisPackageIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Package
    )

    $index = [pscustomobject]@{
        entities = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        facts = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        findings = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
    }
    foreach ($entity in $Package.entities) {
        $prefix = if ($entity.kind -ceq 'NamedValue') { 'named-value' }
        else { $entity.kind.ToLowerInvariant() }
        if (-not $entity.alias.StartsWith("$prefix-", [System.StringComparison]::Ordinal) -or
            -not $index.entities.Add($entity.alias)) {
            throw 'Analysis contract has invalid or duplicate entity aliases.'
        }
    }
    foreach ($fact in $Package.facts) {
        if (-not $index.facts.Add($fact.factId) -or
            -not $index.entities.Contains($fact.subjectAlias)) {
            throw 'Analysis contract has invalid fact IDs or subjects.'
        }
        if ($fact.code -ceq 'AssessmentCondition' -and
            $fact.value -cin @('ProductGovernanceWeak', 'ApiDiagnosticsWeak')) {
            $kind = if ($fact.value -ceq 'ProductGovernanceWeak') { 'Product' } else { 'Api' }
            $entity = @($Package.entities | Where-Object alias -CEQ $fact.subjectAlias)
            if ($Package.schemaVersion -cnotin @('1.4', '1.5') -or $entity.Count -ne 1 -or $entity[0].kind -cne $kind) {
                throw 'Analysis contract has an unsupported governance condition binding.'
            }
        }
        if ($fact.code -ceq 'AssessmentCondition' -and $fact.value -cin @(
            'PremiumCapacityReview', 'NormalizedCostIncreasing', 'DiagnosticIngestionGrowth',
            'LogicAppCostIncreasing', 'NonProductionPremium'
            )) {
            $entity = @($Package.entities | Where-Object alias -CEQ $fact.subjectAlias)
            if ($Package.schemaVersion -cne '1.5' -or $entity.Count -ne 1 -or $entity[0].kind -cne 'Service') {
            throw 'Analysis contract has an unsupported cost condition binding.'
            }
        }
    }
    foreach ($finding in $Package.findings) {
        if (-not $index.findings.Add($finding.findingId) -or
            -not $index.entities.Contains($finding.subjectAlias)) {
            throw 'Analysis contract has invalid finding IDs or subjects.'
        }
        Assert-ApimAnalysisReference -Item $finding -Index $index `
            -RequireCitation:($finding.evaluation -ceq 'Evaluated')
        if ($finding.evaluation -ceq 'Evaluated' -and
            $finding.ruleId -clike 'APIM-POR-*') {
            $conditions = @{
                'APIM-POR-001' = 'PortalUnavailable'
                'APIM-POR-002' = 'PortalAuthenticationWeak'
                'APIM-POR-003' = 'ProductVisibilityMismatch'
                'APIM-POR-004' = 'ApiDocumentationWeak'
                'APIM-POR-005' = 'LegacyPortalEnabled'
            }
            $kind = if ($finding.ruleId -ceq 'APIM-POR-004') { 'Api' } else { 'Service' }
            $entity = @($Package.entities | Where-Object alias -CEQ $finding.subjectAlias)
            $conditionFacts = @($Package.facts | Where-Object {
                    $_.factId -cin $finding.factRefs -and
                    $_.subjectAlias -ceq $finding.subjectAlias -and
                    $_.code -ceq 'AssessmentCondition' -and
                    $_.value -ceq $conditions[$finding.ruleId]
                })
            if ($Package.schemaVersion -cnotin @('1.3', '1.4', '1.5') -or
                -not $conditions.ContainsKey($finding.ruleId) -or
                $entity.Count -ne 1 -or $entity[0].kind -cne $kind -or
                $conditionFacts.Count -ne 1) {
                throw 'Analysis contract has an unsupported portal condition binding.'
            }
        }
        if ($finding.evaluation -ceq 'Evaluated' -and
            $finding.ruleId -cin @('APIM-GOV-003', 'APIM-GOV-009')) {
            $condition = if ($finding.ruleId -ceq 'APIM-GOV-003') { 'ProductGovernanceWeak' }
                else { 'ApiDiagnosticsWeak' }
            $conditionFacts = @($Package.facts | Where-Object {
                    $_.factId -cin $finding.factRefs -and
                    $_.subjectAlias -ceq $finding.subjectAlias -and
                    $_.code -ceq 'AssessmentCondition' -and $_.value -ceq $condition
                })
            if ($Package.schemaVersion -cnotin @('1.4', '1.5') -or $conditionFacts.Count -ne 1) {
                throw 'Analysis contract has an unsupported governance condition binding.'
            }
        }
        if ($finding.evaluation -ceq 'Evaluated' -and $finding.ruleId -clike 'APIM-COST-*') {
            $conditions = @{
            'APIM-COST-001' = 'PremiumCapacityReview'
            'APIM-COST-002' = 'NormalizedCostIncreasing'
            'APIM-COST-003' = 'DiagnosticIngestionGrowth'
            'APIM-COST-004' = 'LogicAppCostIncreasing'
            'APIM-COST-005' = 'NonProductionPremium'
            }
            $entity = @($Package.entities | Where-Object alias -CEQ $finding.subjectAlias)
            $conditionFacts = @($Package.facts | Where-Object {
                $_.factId -cin $finding.factRefs -and $_.subjectAlias -ceq $finding.subjectAlias -and
                $_.code -ceq 'AssessmentCondition' -and $_.value -ceq $conditions[$finding.ruleId]
            })
            if ($Package.schemaVersion -cne '1.5' -or -not $conditions.ContainsKey($finding.ruleId) -or
            $entity.Count -ne 1 -or $entity[0].kind -cne 'Service' -or $conditionFacts.Count -ne 1) {
            throw 'Analysis contract has an unsupported cost condition binding.'
            }
        }
        if ($finding.evaluation -ceq 'NotEvaluated' -and
            ($finding.severity -cne 'Info' -or
                $finding.priorityBucket -cne 'Unknown' -or
                $finding.dataGaps.Count -eq 0)) {
            throw 'Analysis contract must preserve missing-evidence qualifications.'
        }
        foreach ($gap in $finding.dataGaps) {
            if ($Package.dataGaps -cnotcontains $gap) {
                throw 'Analysis contract must include finding data gaps.'
            }
        }
    }
    return $index
}

function Assert-ApimExpertObservationSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ObservationSet,

        [Parameter(Mandatory)]
        [object] $Index,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]] $ObservationIds
    )

    $architecture = $ObservationSet.analyst -ceq 'ArchitectureExposure'
    $prefix = if ($architecture) { 'observation-architecture-' }
    else { 'observation-security-' }
    $categories = if ($architecture) {
        @('Architecture', 'Exposure', 'Reliability', 'Governance')
    }
    else { @('Security', 'Exposure') }
    foreach ($observation in $ObservationSet.observations) {
        if (-not $observation.observationId.StartsWith(
                $prefix, [System.StringComparison]::Ordinal
            ) -or $categories -cnotcontains $observation.category -or
            -not $ObservationIds.Add($observation.observationId)) {
            throw 'Analysis contract has invalid or duplicate analyst observations.'
        }
        Assert-ApimAnalysisReference -Item $observation -Index $Index -RequireCitation
    }
}

function Test-ApimAnalysisContract {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('AnalysisPackage', 'ExpertObservations', 'ExecutiveSummary')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Json,

        [AllowEmptyString()]
        [string] $PackageJson,

        [AllowEmptyCollection()]
        [string[]] $ObservationJson = @()
    )

    $ErrorActionPreference = 'Stop'
    if ($Kind -eq 'AnalysisPackage' -and
        ($PSBoundParameters.ContainsKey('PackageJson') -or
            $PSBoundParameters.ContainsKey('ObservationJson'))) {
        throw 'Package validation does not accept external reference context.'
    }
    if ($Kind -ne 'ExecutiveSummary' -and
        $PSBoundParameters.ContainsKey('ObservationJson')) {
        throw 'Only executive validation accepts specialist reference context.'
    }
    $inputContract = ConvertFrom-ApimAnalysisContractJson -Kind $Kind -Json $Json
    if ($Kind -eq 'AnalysisPackage') {
        $null = Get-ApimAnalysisPackageIndex -Package $inputContract
        return $true
    }
    if ([string]::IsNullOrWhiteSpace($PackageJson)) {
        throw 'Analysis contract requires a validated package context.'
    }
    $package = ConvertFrom-ApimAnalysisContractJson -Kind AnalysisPackage -Json $PackageJson
    $index = Get-ApimAnalysisPackageIndex -Package $package
    $observationIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    if ($Kind -eq 'ExpertObservations') {
        Assert-ApimExpertObservationSet -ObservationSet $inputContract `
            -Index $index -ObservationIds $observationIds
        return $true
    }
    $analysts = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($jsonText in $ObservationJson) {
        $observationSet = ConvertFrom-ApimAnalysisContractJson `
            -Kind ExpertObservations -Json $jsonText
        if (-not $analysts.Add($observationSet.analyst)) {
            throw 'Analysis contract has duplicate analyst roles.'
        }
        Assert-ApimExpertObservationSet -ObservationSet $observationSet `
            -Index $index -ObservationIds $observationIds
    }
    $itemIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $sections = [ordered]@{
        priorities = 'priority'
        themes = 'theme'
        decisions = 'decision'
        roadmap = 'roadmap'
    }
    foreach ($section in $sections.Keys) {
        foreach ($item in $inputContract[$section]) {
            if (-not $item.itemId.StartsWith(
                    "$($sections[$section])-", [System.StringComparison]::Ordinal
                ) -or -not $itemIds.Add($item.itemId)) {
                throw 'Analysis contract has invalid or duplicate executive items.'
            }
            Assert-ApimAnalysisReference -Item $item -Index $index `
                -ObservationIds $observationIds -RequireCitation
        }
    }
    foreach ($name in @('assumptions', 'dataGaps')) {
        if ($inputContract[$name].Count -ne $package[$name].Count) {
            throw 'Analysis contract must retain package assumptions and data gaps.'
        }
        foreach ($code in $package[$name]) {
            if ($inputContract[$name] -cnotcontains $code) {
                throw 'Analysis contract must retain package assumptions and data gaps.'
            }
        }
    }
    return $true
}
