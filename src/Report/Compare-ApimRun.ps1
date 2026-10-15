#Requires -Version 7.4

Set-StrictMode -Version Latest

function Test-ApimLifecycleJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Json,
        [Parameter(Mandatory)]
        [ValidateSet('comparison', 'comparison-binding', 'tracking')]
        [string] $Contract
    )

    $schema = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) `
        "schemas/$Contract.schema.json"
    if ([Text.Encoding]::UTF8.GetByteCount($Json) -gt 64MB) {
        throw 'Lifecycle contract exceeds the supported size.'
    }
    $options = [Text.Json.JsonDocumentOptions]::new()
    $options.MaxDepth = 32
    $document = [Text.Json.JsonDocument]::Parse($Json, $options)
    try { Assert-ApimAnalysisJsonMember -Element $document.RootElement }
    finally { $document.Dispose() }
    if (-not (Test-Json -Json $Json -SchemaFile $schema -ErrorAction Stop)) {
        throw 'Lifecycle contract rejected.'
    }
}

function Get-ApimLifecycleDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Value)

    $map = ConvertFrom-Json -InputObject (
        ConvertTo-Json -InputObject @{ value = $Value } -Depth 100 -WarningAction Stop
    ) -Depth 100 -AsHashtable
    return Get-ApimConfigDigest -Config $map
}

function Get-ApimLifecycleFindingDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Findings)

    $map = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($finding in $Findings) { $map.Add($finding.findingKey, $finding) }
    return Get-ApimLifecycleDigest -Value $map
}

function Get-ApimComparisonSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $RunPath)

    $context = Get-ApimRunSetting -RunPath $RunPath
    if ($context.Manifest.stages.analyze -cne 'Completed') {
        throw 'Comparison requires completed analysis.'
    }
    $models = Get-ApimModelSet -RunPath $RunPath
    $findings = @(Get-ApimFindingSet -RunPath $RunPath)
    $settings = @{}
    foreach ($key in $context.Settings.Keys) {
        if ($key -cnotin @('runId', 'toolVersion')) {
            $settings[$key] = $context.Settings[$key]
        }
    }
    $settingsDigest = Get-ApimLifecycleDigest -Value @{
        settings = $settings; scoring = $context.Manifest.scoring
        windows = $context.Manifest.windows; edge = $context.Manifest.edge
    }
    $modelDigests = @{}
    foreach ($name in $models.Keys) {
        $modelDigests[$name] = @(
            $models[$name] | ForEach-Object { Get-ApimLifecycleDigest -Value $_ } |
                Sort-Object -CaseSensitive
        )
    }
    $digest = Get-ApimLifecycleDigest -Value @{
        models = $modelDigests; findings = Get-ApimLifecycleFindingDigest -Findings $findings
        settings = $settingsDigest; resource = $context.Manifest.apim.resourceId
        environment = $context.Manifest.environment; runId = $context.Manifest.runId
        startedUtc = $context.Manifest.startedUtc; version = $context.Manifest.toolVersion
    }
    $rules = @(Get-ApimRuleCatalog -CatalogPath $script:ApimReportRuleCatalogPath)
    $replayed = @(Invoke-ApimRuleEngine -Rules $rules -Models $models `
            -Manifest $context.Manifest -Config $context.Config)
    return @{
        manifest = $context.Manifest; models = $models; findings = $findings
        settingsDigest = $settingsDigest
        replayMatches = (Get-ApimLifecycleFindingDigest -Findings $replayed) -ceq (
            Get-ApimLifecycleFindingDigest -Findings $findings
        )
        identity = [ordered]@{
            runId = $context.Manifest.runId; toolVersion = $context.Manifest.toolVersion
            startedUtc = $context.Manifest.startedUtc; sha256 = $digest
        }
    }
}

function Test-ApimRuleReassessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RuleId,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Models,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Findings
    )

    if (@($Findings | Where-Object {
                $_.ruleId -ceq $RuleId -and $_.evaluation -cne 'Evaluated'
            }).Count -gt 0) { return $false }
    $rules = @(Get-ApimRuleCatalog -CatalogPath $script:ApimReportRuleCatalogPath |
            Where-Object Id -CEQ $RuleId)
    if ($rules.Count -ne 1 -or -not $rules[0].Enabled) { return $false }
    foreach ($required in $rules[0].Requires) {
        $name = [IO.Path]::GetFileNameWithoutExtension($required)
        if (-not $Models.Contains($name)) { return $false }
        foreach ($record in @($Models[$name])) {
            if ($record.modelStatus -cne 'Complete') { return $false }
        }
    }
    return $true
}

function Get-ApimComparisonKpi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Snapshot,
        [Parameter(Mandatory)][string] $Metric
    )

    switch ($Metric) {
        ReachableApis {
            if (@($Snapshot.models.apis | Where-Object {
                        $_.reachability -cnotin @('Reachable', 'NotRoutable')
                    }).Count -gt 0) { return $null }
            return @($Snapshot.models.apis | Where-Object reachability -CEQ 'Reachable' |
                    Select-Object -ExpandProperty apiId -Unique).Count
        }
        ActiveAllApiSubscriptions {
            return @($Snapshot.models.subscriptions | Where-Object {
                    $_.scopeType -ceq 'AllApis' -and $_.state -ieq 'active'
                } | Select-Object -ExpandProperty subscriptionId -Unique).Count
        }
        default { return $null }
    }
}

function Get-ApimRunComparison {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Baseline,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Current
    )

    if ($Baseline.manifest.apim.resourceId -ine $Current.manifest.apim.resourceId -or
        $Baseline.manifest.environment -cne $Current.manifest.environment -or
        $Baseline.manifest.tenantId -ine $Current.manifest.tenantId -or
        $Baseline.manifest.customer -cne $Current.manifest.customer) {
        throw 'Comparison scope is incompatible.'
    }
    $before = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $after = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($finding in $Baseline.findings) { $before.Add($finding.findingKey, $finding) }
    foreach ($finding in $Current.findings) { $after.Add($finding.findingKey, $finding) }
    $keys = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach ($key in @($before.Keys) + @($after.Keys)) { $null = $keys.Add($key) }
    $changes = [Collections.Generic.List[object]]::new()
    $gaps = [Collections.Generic.List[object]]::new()
    foreach ($key in $keys) {
        $old = if ($before.ContainsKey($key)) { $before[$key] } else { $null }
        $new = if ($after.ContainsKey($key)) { $after[$key] } else { $null }
        $finding = if ($null -ne $new) { $new } else { $old }
        $reason = 'ComparableSnapshots'
        if (($null -ne $old -and $old.evaluation -cne 'Evaluated') -or
            ($null -ne $new -and $new.evaluation -cne 'Evaluated')) {
            $reason = 'EvidenceIncomplete'
        }
        elseif ($null -eq $old -or $null -eq $new) {
            $other = if ($null -eq $new) { $Current } else { $Baseline }
            if ($Baseline.settingsDigest -cne $Current.settingsDigest) {
                $reason = 'SettingsChanged'
            }
            elseif (-not $Baseline.replayMatches) {
                $reason = 'HistoricalReplayMismatch'
            }
            elseif (-not (Test-ApimRuleReassessment -RuleId $finding.ruleId `
                        -Models $other.models -Findings $other.findings)) {
                $reason = 'EvidenceIncomplete'
            }
        }
        $change = if ($reason -cne 'ComparableSnapshots') { 'NotReassessed' }
        elseif ($null -eq $old) { 'New' }
        elseif ($null -eq $new) { 'Resolved' }
        else { 'Persisting' }
        $row = [ordered]@{
            findingKey = $key; ruleId = $finding.ruleId; pillar = $finding.pillar
            change = $change
            previousSeverity = if ($null -ne $old) { $old.severity } else { $null }
            currentSeverity = if ($null -ne $new) { $new.severity } else { $null }
            severityChanged = $change -ceq 'Persisting' -and $old.severity -cne $new.severity
            reason = $reason
        }
        if ($change -ceq 'NotReassessed') { $gaps.Add($row) } else { $changes.Add($row) }
    }
    $pillars = @(
        foreach ($pillar in @('Security', 'Reliability', 'OperationalExcellence', 'CostOptimization', 'PerformanceEfficiency')) {
            [ordered]@{
                pillar = $pillar
                new = @($changes | Where-Object { $_.pillar -ceq $pillar -and $_.change -ceq 'New' }).Count
                resolved = @($changes | Where-Object { $_.pillar -ceq $pillar -and $_.change -ceq 'Resolved' }).Count
                persisting = @($changes | Where-Object { $_.pillar -ceq $pillar -and $_.change -ceq 'Persisting' }).Count
                notReassessed = @($gaps | Where-Object pillar -CEQ $pillar).Count
            }
        }
    )
    $kpis = @(
        foreach ($metric in @('ReachableApis', 'UnusedApis', 'ActiveAllApiSubscriptions', 'MonthlyCost')) {
            $a = Get-ApimComparisonKpi -Snapshot $Baseline -Metric $metric
            $b = Get-ApimComparisonKpi -Snapshot $Current -Metric $metric
            $reason = if ($metric -ceq 'UnusedApis') { 'UsageUnavailable' }
            elseif ($metric -ceq 'MonthlyCost') { 'CostUnavailable' }
            elseif ($null -eq $a -or $null -eq $b) { 'EvidenceIncomplete' }
            else { 'Available' }
            [ordered]@{
                metric = $metric; baseline = $a; current = $b
                delta = if ($reason -ceq 'Available') { $b - $a } else { $null }
                reason = $reason
            }
        }
    )
    $result = [ordered]@{
        schemaVersion = '1.0'; baseline = $Baseline.identity; current = $Current.identity
        changes = $changes.ToArray(); gaps = $gaps.ToArray(); pillars = $pillars; kpis = $kpis
    }
    Test-ApimLifecycleJson -Json (ConvertTo-Json $result -Depth 100) -Contract comparison
    return $result
}

function Get-ApimSavedComparison {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $RunPath)

    $path = Resolve-RunFilePath -RunPath $RunPath -RelativePath 'diff.json'
    $bindingPath = Resolve-RunFilePath -RunPath $RunPath -RelativePath 'restricted/comparison-binding.json'
    Test-ConfigPathLink -Path $path -Context Comparison
    Test-ConfigPathLink -Path $bindingPath -Context 'Comparison binding'
    if (-not (Test-Path -LiteralPath $path) -and -not (Test-Path -LiteralPath $bindingPath)) { return $null }
    $json = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
    $bindingJson = Get-Content -LiteralPath $bindingPath -Raw -ErrorAction Stop
    Test-ApimLifecycleJson -Json $json -Contract comparison
    Test-ApimLifecycleJson -Json $bindingJson -Contract comparison-binding
    $comparison = ConvertFrom-Json -InputObject $json -Depth 100 -AsHashtable
    $binding = ConvertFrom-Json -InputObject $bindingJson -AsHashtable
    if ((Get-ApimLifecycleDigest -Value $comparison) -cne $binding.diffSha256 -or
        (Get-ApimComparisonSnapshot -RunPath $RunPath).identity.sha256 -cne $comparison.current.sha256) {
        throw 'Comparison is stale or modified.'
    }
    return $comparison
}

function Compare-ApimRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Baseline,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Current
    )

    try {
        if (Test-ConfigPathOverlap -First ([IO.Path]::GetFullPath($Baseline)) `
                -Second ([IO.Path]::GetFullPath($Current))) {
            throw 'Baseline and current runs must be disjoint.'
        }
        Test-ApimSavedFindingReplay -RunPath $Current
        $comparison = Get-ApimRunComparison `
            -Baseline (Get-ApimComparisonSnapshot -RunPath $Baseline) `
            -Current (Get-ApimComparisonSnapshot -RunPath $Current)
        $null = Write-RunFile -RunPath $Current -RelativePath 'diff.json' -InputObject $comparison -Depth 100
        $null = Write-RunFile -RunPath $Current -RelativePath 'restricted/comparison-binding.json' `
            -InputObject @{ schemaVersion = '1.0'; diffSha256 = Get-ApimLifecycleDigest -Value $comparison }
        return Invoke-ApimReport -RunFolder $Current
    }
    catch {
        return [pscustomobject]@{ Status = 'Failed'; ExitCode = 4; ErrorCode = 'COMPARISON_FAILED' }
    }
}
