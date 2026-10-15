#Requires -Version 7.4

Set-StrictMode -Version Latest

$script:ApimFindingsSchemaPath = Join-Path (
    Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
) 'schemas/findings.schema.json'
$script:ApimRuleScopes = @{
    Service = $null
    Api = 'apis'
    Product = 'products'
    Operation = 'operations'
    Subscription = 'subscriptions'
    NamedValue = 'namedValues'
    Backend = 'backends'
    Certificate = 'certificates'
    Route = 'exposure'
    Network = 'network'
    Portal = 'portal'
}

function Resolve-ApimRuleScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Scope
    )

    if ($null -eq $Scope -or
        ($Scope -is [array] -and $Scope.Count -eq 0)) {
        throw 'Rule definition has an invalid contract.'
    }
    [object[]] $candidates = if ($Scope -is [string]) {
        @($Scope)
    }
    elseif ($Scope -is [array]) {
        @($Scope)
    }
    else {
        throw 'Rule definition has an invalid contract.'
    }
    $scopes = [System.Collections.Generic.List[string]]::new()
    $unique = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($candidate in $candidates) {
        if ($candidate -isnot [string] -or
            $candidate -cnotin @($script:ApimRuleScopes.Keys) -or
            -not $unique.Add([string] $candidate)) {
            throw 'Rule definition has an invalid contract.'
        }
        $scopes.Add([string] $candidate)
    }
    return $scopes.ToArray()
}

function Assert-ApimRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Rule
    )

    foreach ($key in @(
            'Id', 'Title', 'Pillar', 'Mcsb', 'Severity', 'Scope', 'Requires',
            'Test', 'Evidence', 'EvidenceText', 'Recommendation', 'Effort',
            'References', 'SourceFiles', 'Enabled'
        )) {
        if (-not $Rule.Contains($key)) {
            throw "Rule definition is missing '$key'."
        }
    }
    if ($Rule.Id -isnot [string] -or
        $Rule.Id -cnotmatch '^APIM-[A-Z]+-[0-9]{3}$' -or
        $Rule.Title -isnot [string] -or
        [string]::IsNullOrWhiteSpace($Rule.Title) -or
        $Rule.Mcsb -isnot [string] -or
        [string]::IsNullOrWhiteSpace($Rule.Mcsb) -or
        $Rule.Recommendation -isnot [string] -or
        [string]::IsNullOrWhiteSpace($Rule.Recommendation) -or
        $Rule.Pillar -cnotin @(
            'Security', 'Reliability', 'OperationalExcellence',
            'CostOptimization', 'PerformanceEfficiency'
        ) -or
        $Rule.Severity -cnotin @('High', 'Medium', 'Low', 'Info') -or
        $Rule.Effort -cnotin @('S', 'M', 'L') -or
        $Rule.Test -isnot [scriptblock] -or
        $Rule.Evidence -isnot [scriptblock] -or
        $Rule.EvidenceText -isnot [scriptblock] -or
        ($Rule.Contains('Applies') -and $null -ne $Rule.Applies -and
            $Rule.Applies -isnot [scriptblock]) -or
        ($Rule.Contains('DataGaps') -and $null -ne $Rule.DataGaps -and
            $Rule.DataGaps -isnot [scriptblock]) -or
        $Rule.Enabled -isnot [bool] -or
        $Rule.Requires -isnot [array] -or
        ($Rule.Contains('OptionalRequires') -and $Rule.OptionalRequires -isnot [array]) -or
        $Rule.SourceFiles -isnot [array] -or
        $Rule.SourceFiles.Count -eq 0 -or
        $Rule.References -isnot [array]) {
        throw 'Rule definition has an invalid contract.'
    }
    $scopes = @(Resolve-ApimRuleScope -Scope $Rule.Scope)
    if ($Rule.Contains('TargetField') -and
        ($scopes.Count -ne 1 -or $scopes[0] -cne 'Route' -or
            $Rule.TargetField -cne 'auxiliaryRoutes')) {
        throw 'Rule definition has an invalid contract.'
    }
    $optionalInputs = @(if ($Rule.Contains('OptionalRequires')) { $Rule.OptionalRequires })
    $inputNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($required in @($Rule.Requires) + $optionalInputs) {
        if ($required -isnot [string] -or
            $required -cnotmatch '^model/([A-Za-z]+)\.json$' -or
            @($script:ApimModelSchemaPaths.Keys) -cnotcontains $Matches[1]) {
            throw 'Rule requires an unsupported model input.'
        }
        if (-not $inputNames.Add($required)) { throw 'Rule contains duplicate model inputs.' }
    }
    foreach ($file in $Rule.SourceFiles) {
        if ($file -isnot [string] -or
            $file -cnotmatch '^(raw|model)/[A-Za-z0-9._/-]+$' -or
            $file.Contains('..')) {
            throw 'Rule source file is invalid.'
        }
    }
    foreach ($reference in $Rule.References) {
        if ($reference -isnot [string] -or
            [string]::IsNullOrWhiteSpace($reference)) {
            throw 'Rule reference is invalid.'
        }
    }
}

function Get-ApimRuleCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $CatalogPath
    )

    $files = @(Get-ChildItem -LiteralPath $CatalogPath -File `
            -Filter '*.rules.ps1' -ErrorAction Stop | Sort-Object Name)
    if ($files.Count -eq 0) {
        throw 'Rule catalog has no implemented definitions.'
    }
    $rules = [System.Collections.Generic.List[object]]::new()
    $ids = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($file in $files) {
        foreach ($rule in @(& $file.FullName)) {
            if ($rule -isnot [System.Collections.IDictionary]) {
                throw 'Rule catalog returned a non-rule value.'
            }
            Assert-ApimRule -Rule $rule
            if (-not $ids.Add($rule.Id)) {
                throw 'Rule catalog contains a duplicate rule ID.'
            }
            $rules.Add($rule)
        }
    }
    if ($rules.Count -eq 0) {
        throw 'Rule catalog has no implemented definitions.'
    }
    return $rules.ToArray()
}

function Get-ApimRuleTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Rule,

        [Parameter(Mandatory)]
        [string] $Scope,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Models,

        [Parameter(Mandatory)]
        [object] $Manifest
    )

    if ($Scope -eq 'Service') {
        return $Manifest.apim
    }
    $name = if ($Rule.Contains('TargetField')) {
        'network'
    }
    else {
        $script:ApimRuleScopes[$Scope]
    }
    if (-not $Models.Contains($name) -or $null -eq $Models[$name]) {
        throw "Rule target model '$name' was unavailable."
    }
    if ($Rule.Contains('TargetField')) {
        return $Models[$name].auxiliaryRoutes
    }
    return $Models[$name]
}

function Get-ApimRuleScopeKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Scope,

        [Parameter(Mandatory)]
        [object] $Target
    )

    switch ($Scope) {
        Service { return 'service' }
        Network { return 'network' }
        Portal { return 'portal' }
        Api { return "api:$($Target.apiId)" }
        Product { return "product:$($Target.productId)" }
        Operation {
            return "operation:$($Target.apiId)/$($Target.operationId)"
        }
        Subscription { return "subscription:$($Target.subscriptionId)" }
        NamedValue { return "named-value:$($Target.namedValueId)" }
        Backend { return "backend:$($Target.backendId)" }
        Certificate { return "certificate:$($Target.certificateId)" }
        Route { return "route:$($Target.routeKey)" }
    }
    throw 'Rule scope is unsupported.'
}

function Get-ApimRulePriority {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Severity,

        [Parameter(Mandatory)]
        [string] $Exposure,

        [AllowNull()]
        [object] $Usage,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Config
    )

    $weights = @(
        $Config.Scoring.Severity[$Severity],
        $Config.Scoring.Exposure[$Exposure],
        $(if ($null -eq $Usage) { 1.0 } else {
                $Config.Scoring.Usage[$Usage]
            })
    )
    foreach ($weight in $weights) {
        if ($null -eq $weight -or $weight -isnot [valuetype] -or
            [double]::IsNaN([double] $weight) -or
            [double]::IsInfinity([double] $weight) -or
            [double] $weight -le 0) {
            throw 'Rule scoring weight was invalid or unavailable.'
        }
    }
    return [math]::Round(
        [double] $weights[0] * [double] $weights[1] *
        [double] $weights[2], 1, [MidpointRounding]::AwayFromZero
    )
}

function Test-ApimFindingsJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Json
    )

    if (-not (Test-Path -LiteralPath $script:ApimFindingsSchemaPath -PathType Leaf)) {
        throw 'Findings schema was unavailable.'
    }
    try {
        $valid = Test-Json -Json $Json -SchemaFile $script:ApimFindingsSchemaPath `
            -ErrorAction Stop
    }
    catch {
        throw 'Findings failed schema validation.'
    }
    if (-not $valid) {
        throw 'Findings failed schema validation.'
    }
}

function Assert-ApimFindingKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Findings
    )

    $keys = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($finding in $Findings) {
        if ($null -eq $finding -or
            $finding.findingKey -cne (
                "$($finding.ruleId)|$($finding.resource)|$($finding.scope)"
            ) -or -not $keys.Add([string] $finding.findingKey)) {
            throw 'Findings contain an invalid or duplicate finding key.'
        }
    }
}

function Invoke-ApimRuleEngine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary[]] $Rules,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Models,

        [Parameter(Mandatory)]
        [object] $Manifest,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Config,

        [string[]] $UnavailableInputs = @()
    )

    Test-RunManifest -Manifest $Manifest
    $resource = ([string] $Manifest.apim.resourceId).Split('/')[-1]
    $ids = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $validated = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $findings = [System.Collections.Generic.List[object]]::new()
    $ctx = [pscustomobject]@{
        Config = $Config
        Models = $Models
        Manifest = $Manifest
    }
    foreach ($unavailable in $UnavailableInputs) {
        if ($unavailable -cnotmatch '^model/([A-Za-z]+)\.json$' -or
            @($script:ApimModelSchemaPaths.Keys) -cnotcontains $Matches[1]) {
            throw 'Unavailable rule input was unsupported.'
        }
    }
    $ctx.Models = [ordered]@{}
    foreach ($name in $Models.Keys) {
        if ("model/$name.json" -cnotin $UnavailableInputs) { $ctx.Models[$name] = $Models[$name] }
    }
    foreach ($rule in $Rules) {
        Assert-ApimRule -Rule $rule
        if (-not $ids.Add($rule.Id)) {
            throw 'Rule catalog contains a duplicate rule ID.'
        }
        if (-not $rule.Enabled) {
            continue
        }
        $ruleScopes = @(Resolve-ApimRuleScope -Scope $rule.Scope)
        $missing = [System.Collections.Generic.List[string]]::new()
        $optionalInputs = @(if ($rule.Contains('OptionalRequires')) { $rule.OptionalRequires })
        foreach ($required in @($rule.Requires) + $optionalInputs) {
            $name = $required.Substring(6, $required.Length - 11)
            if ($required -cin $UnavailableInputs -or
                -not $Models.Contains($name) -or $null -eq $Models[$name]) {
                if ($required -cin $rule.Requires -and -not $missing.Contains($required)) {
                    $missing.Add($required)
                }
                continue
            }
            if ($validated.Add($name)) {
                try {
                    $json = ConvertTo-Json -InputObject $Models[$name] `
                        -Depth 100 -ErrorAction Stop
                }
                catch {
                    throw "Rule input '$name' could not be serialized."
                }
                Test-ApimModelJson -Name $name -Json $json
            }
        }
        foreach ($ruleScope in $ruleScopes) {
            $targetModel = if ($rule.Contains('TargetField')) {
                'network'
            }
            else {
                $script:ApimRuleScopes[$ruleScope]
            }
            if ($null -ne $targetModel) {
                $targetPath = "model/$targetModel.json"
                if ($targetPath -cnotin $rule.Requires) {
                    throw 'Rule definition must require its target model.'
                }
            }
            $sourceFiles = @($rule.SourceFiles) + @($optionalInputs | Where-Object {
                    $name = $_.Substring(6, $_.Length - 11)
                    $_ -cnotin $UnavailableInputs -and $Models.Contains($name) -and $null -ne $Models[$name]
                })
        }
        if ($missing.Count -eq 0 -and $rule.Contains('DataGaps') -and
            $null -ne $rule.DataGaps) {
            foreach ($gap in @(& $rule.DataGaps $ctx)) {
                if ($gap -isnot [string] -or
                    $gap -cnotmatch '^(model/[A-Za-z]+\.json)#[A-Za-z][A-Za-z0-9]*$' -or
                    $Matches[1] -cnotin $rule.Requires) {
                    throw 'Rule data gap referenced an undeclared model field.'
                }
                if (-not $missing.Contains($gap)) {
                    $missing.Add($gap)
                }
            }
        }

        if ($missing.Count -gt 0) {
            $missingFiles = @($missing.ToArray() | Sort-Object -Unique)
            $scope = 'missing-input'
            $exposure = 'Unknown'
            $usage = $null
            $severity = 'Info'
            $findings.Add([ordered]@{
                    findingKey = "$($rule.Id)|$resource|$scope"
                    ruleId = $rule.Id
                    title = $rule.Title
                    pillar = $rule.Pillar
                    mcsb = $rule.Mcsb
                    severity = $severity
                    scope = $scope
                    resource = $resource
                    exposure = $exposure
                    usage = $usage
                    priorityScore = Get-ApimRulePriority -Severity $severity `
                        -Exposure $exposure -Usage $usage -Config $Config
                    evidence = [ordered]@{ missingInputs = $missingFiles }
                    evidenceText = 'Required assessment evidence was unavailable.'
                    recommendation = $rule.Recommendation
                    effort = $rule.Effort
                    sourceFiles = @($sourceFiles | Select-Object -Unique)
                    status = 'Open'
                    evaluation = 'NotEvaluated'
                })
            continue
        }

        foreach ($ruleScope in $ruleScopes) {
            foreach ($target in @(Get-ApimRuleTarget -Rule $rule `
                        -Scope $ruleScope -Models $Models `
                        -Manifest $Manifest)) {
                if ($rule.Contains('Applies') -and $null -ne $rule.Applies) {
                    $applies = & $rule.Applies $target $ctx
                    if ($applies -isnot [bool]) {
                        throw 'Rule Applies must return a Boolean.'
                    }
                    if (-not $applies) {
                        continue
                    }
                }
                $test = & $rule.Test $target $ctx
                if ($test -isnot [bool]) {
                    throw 'Rule Test must return a Boolean.'
                }
                if (-not $test) {
                    continue
                }
                $evidence = & $rule.Evidence $target $ctx
                $evidenceText = & $rule.EvidenceText $target $ctx
                if ($evidence -isnot [System.Collections.IDictionary] -or
                    $evidenceText -isnot [string]) {
                    throw 'Rule evidence has an invalid contract.'
                }
                $scope = Get-ApimRuleScopeKey -Scope $ruleScope `
                    -Target $target
                $exposure = if ($ruleScope -in @('Service', 'Network', 'Portal')) {
                    'Platform'
                }
                elseif ($null -ne $target.PSObject.Properties['exposure'] -and
                    $null -ne $target.exposure) {
                    [string] $target.exposure
                }
                else {
                    'Unknown'
                }
                $usage = if ($ruleScope -in @('Service', 'Network', 'Portal')) {
                    'NotApplicable'
                }
                elseif ($null -ne $target.PSObject.Properties['calls90d'] -and
                    $null -ne $target.calls90d) {
                    if ($target.calls90d -gt 0) { 'InUse' } else { 'Unused' }
                }
                else {
                    $null
                }
                $findings.Add([ordered]@{
                        findingKey = "$($rule.Id)|$resource|$scope"
                        ruleId = $rule.Id
                        title = $rule.Title
                        pillar = $rule.Pillar
                        mcsb = $rule.Mcsb
                        severity = $rule.Severity
                        scope = $scope
                        resource = $resource
                        exposure = $exposure
                        usage = $usage
                        priorityScore = Get-ApimRulePriority `
                            -Severity $rule.Severity -Exposure $exposure `
                            -Usage $usage -Config $Config
                        evidence = $evidence
                        evidenceText = $evidenceText
                        recommendation = $rule.Recommendation
                        effort = $rule.Effort
                        sourceFiles = @($sourceFiles | Select-Object -Unique)
                        status = 'Open'
                        evaluation = 'Evaluated'
                    })
            }
        }
    }
    [object[]] $sorted = $findings.ToArray()
    [Array]::Sort($sorted, [System.Collections.Generic.Comparer[object]]::Create(
            [System.Comparison[object]] {
                param($a, $b)
                $byPriority = $b.priorityScore.CompareTo($a.priorityScore)
                if ($byPriority -ne 0) { return $byPriority }
                $byRule = [string]::CompareOrdinal($a.ruleId, $b.ruleId)
                if ($byRule -ne 0) { return $byRule }
                return [string]::CompareOrdinal($a.scope, $b.scope)
            }
        ))
    Assert-ApimFindingKey -Findings $sorted
    $json = ConvertTo-Json -InputObject $sorted -Depth 100 -ErrorAction Stop
    Test-ApimFindingsJson -Json $json
    return $sorted
}

function Write-ApimFindingSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Findings
    )

    $json = ConvertTo-Json -InputObject $Findings -Depth 100 `
        -ErrorAction Stop
    Test-ApimFindingsJson -Json $json
    Assert-ApimFindingKey -Findings $Findings
    $path = Resolve-RunFilePath -RunPath $RunPath `
        -RelativePath 'findings.json'
    Test-ConfigPathLink -Path $path -Context 'Findings file path'
    return Write-RunFile -RunPath $RunPath -RelativePath 'findings.json' `
        -InputObject $json -Format Text
}
