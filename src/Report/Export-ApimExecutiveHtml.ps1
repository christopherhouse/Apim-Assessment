#Requires -Version 7.4

Set-StrictMode -Version Latest

function ConvertTo-ApimHtmlText {
    [CmdletBinding()]
    param([AllowNull()][object] $Value)
    if ($null -eq $Value) { return 'Unknown' }
    $text = [string]$Value
    if ($text.Length -gt 32768) { throw 'HTML_TEXT_REJECTED' }
    return [Net.WebUtility]::HtmlEncode($text)
}

function Get-ApimHtmlAgentContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Context
    )
    if (@($Context.Keys | Where-Object { $_ -cnotin @('packageJson', 'observations', 'executives', 'candidateId') }).Count -gt 0 -or
        $Context.candidateId -cnotmatch '^candidate-[a-f0-9]{32}\z' -or
        $Context.executives.Count -gt 1 -or $Context.observations.Count -gt 2) {
        throw 'HTML_AGENT_CONTEXT_REJECTED'
    }
    $settings = Get-ApimRunSetting -RunPath $RunPath
    $fresh = New-ApimAnalysisPackage -RunPath $RunPath -Config $settings.Config
    $freshPath = Resolve-RunFilePath -RunPath $RunPath -RelativePath "restricted/candidates/$($fresh.candidateId)"
    $priorPath = Resolve-RunFilePath -RunPath $RunPath -RelativePath "restricted/candidates/$($Context.candidateId)"
    $packageBytes = Read-ApimAnalysisSnapshot -Path (Join-Path $freshPath 'analysis-package.json')
    if ((Get-ApimAnalysisDigest -Bytes $packageBytes) -cne (
            Get-ApimAnalysisDigest -Bytes ([Text.Encoding]::UTF8.GetBytes($Context.packageJson))
        )) { throw 'HTML_PACKAGE_STALE' }
    $mapBytes = Read-ApimAnalysisSnapshot -Path (Join-Path $freshPath 'alias-map.json')
    if ((Get-ApimAnalysisDigest -Bytes $mapBytes) -cne (
            Get-ApimAnalysisDigest -Bytes (Read-ApimAnalysisSnapshot -Path (Join-Path $priorPath 'alias-map.json'))
        )) { throw 'HTML_ALIAS_REJECTED' }
    $package = ConvertFrom-ApimAnalysisContractJson -Kind AnalysisPackage -Json $Context.packageJson
    $map = [Text.UTF8Encoding]::new($false, $true).GetString($mapBytes) | ConvertFrom-Json -AsHashtable
    $labels = @{}
    foreach ($row in $map.aliases) {
        $label = switch -CaseSensitive ($row.scope) {
            service { 'API Management service' }
            network { 'Gateway network' }
            default { $row.scope.Substring($row.scope.IndexOf(':') + 1) }
        }
        $labels.Add($row.alias, $label)
    }
    foreach ($entity in $package.entities) {
        if (-not $labels.ContainsKey($entity.alias)) { throw 'HTML_ALIAS_REJECTED' }
    }
    $roles = @{}
    foreach ($json in $Context.observations) {
        $null = Test-ApimAgentClaim -Kind ExpertObservations -Json $json -PackageJson $Context.packageJson
        $set = ConvertFrom-ApimAnalysisContractJson -Kind ExpertObservations -Json $json
        if ($roles.ContainsKey($set.analyst)) { throw 'HTML_AGENT_CONTEXT_REJECTED' }
        $roles.Add($set.analyst, $true)
    }
    $summary = $null
    if ($Context.executives.Count -eq 1) {
        $null = Test-ApimAgentClaim -Kind ExecutiveSummary -Json $Context.executives[0] `
            -PackageJson $Context.packageJson -ObservationJson $Context.observations
        $summary = ConvertFrom-ApimAnalysisContractJson -Kind ExecutiveSummary -Json $Context.executives[0]
    }
    return @{ labels = $labels; package = $package; summary = $summary; context = $Context }
}

function ConvertTo-ApimHtmlProposal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Items,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Agent
    )
    $facts = @{}; $findings = @{}; $observations = @{}
    foreach ($fact in $Agent.package.facts) { $facts.Add($fact.factId, $fact) }
    foreach ($finding in $Agent.package.findings) { $findings.Add($finding.findingId, $finding) }
    foreach ($json in $Agent.context.observations) {
        $set = ConvertFrom-ApimAnalysisContractJson -Kind ExpertObservations -Json $json
        foreach ($observation in $set.observations) { $observations.Add($observation.observationId, $observation) }
    }
    $builder = [Text.StringBuilder]::new()
    foreach ($item in $Items) {
        $aliases = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
        $citedItems = @($item)
        foreach ($id in $item.observationRefs) { $citedItems += $observations[$id] }
        foreach ($cited in $citedItems) {
            foreach ($id in $cited.factRefs) { $null = $aliases.Add($facts[$id].subjectAlias) }
            foreach ($id in $cited.findingRefs) { $null = $aliases.Add($findings[$id].subjectAlias) }
        }
        $labels = @($aliases | ForEach-Object {
                if (-not $Agent.labels.ContainsKey($_)) { throw 'HTML_ALIAS_REJECTED' }
                $Agent.labels[$_]
            })
        $code = [regex]::Replace($item.code, '([a-z])([A-Z])', '$1 $2')
        $references = @($item.findingRefs) + @($item.factRefs) + @($item.observationRefs)
        $null = $builder.Append('<article><h3>' + (ConvertTo-ApimHtmlText $code) +
            '</h3><p>' + (ConvertTo-ApimHtmlText ($labels -join ', ')) +
            '</p><p class="muted">Confidence: ' + (ConvertTo-ApimHtmlText $item.confidence) +
            ' | Citations: ' + (ConvertTo-ApimHtmlText ($references -join ', ')) + '</p></article>')
    }
    return $builder.ToString()
}

function Export-ApimExecutiveHtml {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [System.Collections.IDictionary] $AgentOutputContext,
        [string] $WorkbookPath
    )
    Test-ApimSavedFindingReplay -RunPath $RunPath
    $manifest = Get-RunManifest -RunPath $RunPath
    $models = Get-ApimModelSet -RunPath $RunPath
    $findings = @(Get-ApimFindingSet -RunPath $RunPath)
    $actions = @(Get-ApimActionPlan -Findings $findings)
    $agent = $null
    if ($null -ne $AgentOutputContext) {
        $agent = Get-ApimHtmlAgentContext -RunPath $RunPath -Context $AgentOutputContext
    }
    $evaluated = @($findings | Where-Object evaluation -CEQ Evaluated)
    $high = @($evaluated | Where-Object severity -CEQ High)
    $notEvaluated = @($findings | Where-Object evaluation -CEQ NotEvaluated)
    $posture = if ($high.Count -gt 0) { 'Action required' }
    elseif ($evaluated.Count -gt 0) { 'Improvement recommended' }
    else { 'Insufficient evidence' }
    $mode = if ($null -ne $agent -and $null -ne $agent.summary) {
        'Validated AI synthesis / deterministic evidence'
    } else { 'Deterministic report / no AI synthesis' }
    $slots = @{
        TITLE = ConvertTo-ApimHtmlText "$($manifest.customer) APIM assessment"
        SCOPE = ConvertTo-ApimHtmlText ("Environment: {0} | Assessment anchor: {1} | {2} APIs / {3} operations" -f
            $manifest.environment, $manifest.startedUtc, $models.apis.Count, $models.operations.Count)
        MODE = ConvertTo-ApimHtmlText $mode
        POSTURE = '<h3>' + $posture + '</h3><p>Deterministic rule severity remains authoritative. Unknown evidence is not a pass.</p>'
        KPIS = ''
        TOPOLOGY = ''
        CHART = ''
        RISKS = ''
        ACTIONS = ''
        DECISIONS = ''
        GAPS = ''
        ROADMAP = ''
    }
    foreach ($kpi in @(
            @('APIs assessed', $models.apis.Count), @('High findings', $high.Count),
            @('Evaluated findings', $evaluated.Count), @('Not evaluated', $notEvaluated.Count)
        )) {
        $slots.KPIS += '<div class="kpi"><strong>' + [int]$kpi[1] + '</strong>' +
            (ConvertTo-ApimHtmlText $kpi[0]) + '</div>'
    }
    $waf = ConvertTo-ApimHtmlText "$($models.network.wafState) / $($models.network.wafMode)"
    $vnet = ConvertTo-ApimHtmlText $models.network.virtualNetworkType
    $direct = ConvertTo-ApimHtmlText $models.network.directPublic
    $gateways = $models.network.appGateways.Count
    $slots.TOPOLOGY = @"
<svg viewBox="0 0 900 190" role="img" aria-labelledby="topology-title topology-desc">
<title id="topology-title">Observed assessment topology</title>
<desc id="topology-desc">Edge is assumed. $gateways configured application gateways. APIM VNet mode $vnet. Direct public reachability $direct. WAF posture $waf. No authentication or path reachability is inferred by this diagram.</desc>
<rect x="4" y="32" width="230" height="100" rx="10"/><text x="20" y="64">Edge: assumed</text><text x="20" y="100">Not independently verified</text>
<path d="M234 82 H304 M290 74 L304 82 L290 90"/>
<rect x="304" y="32" width="260" height="100" rx="10"/><text x="320" y="64">App Gateways: $gateways</text><text x="320" y="100">WAF: $waf</text>
<path d="M564 82 H634 M620 74 L634 82 L620 90"/>
<rect x="634" y="32" width="260" height="100" rx="10"/><text x="650" y="64">APIM VNet: $vnet</text><text x="650" y="100">Direct public: $direct</text>
<text x="4" y="174">Conceptual inventory, not proof that every route is reachable or authenticated.</text>
</svg>
"@
    $chart = [Text.StringBuilder]::new()
    $null = $chart.Append('<svg viewBox="0 0 820 310" role="img" aria-labelledby="exposure-title exposure-desc"><title id="exposure-title">API exposure counts</title><desc id="exposure-desc">Unknown API exposure is retained as its own category. Each row shows its exact local inventory count.</desc>')
    $row = 0
    foreach ($category in @('DirectPublic', 'ExternalInUse', 'ExternalUnintended', 'Restricted', 'Internal', 'Platform', 'Unknown')) {
        $count = @($models.apis | Where-Object exposure -CEQ $category).Count
        $width = [int][Math]::Round(480 * $count / [Math]::Max(1, $models.apis.Count))
        $y = 24 + 40 * $row
        $null = $chart.Append("<text x=`"0`" y=`"$y`">$category</text><rect class=`"bar`" x=`"220`" y=`"$($y - 16)`" width=`"$width`" height=`"24`"/><text x=`"740`" y=`"$y`">$count</text>")
        $row++
    }
    $null = $chart.Append('</svg>'); $slots.CHART = $chart.ToString()
    $riskRows = [Text.StringBuilder]::new()
    $null = $riskRows.Append('<div class="table-wrap"><table><caption>Highest-priority deterministic findings</caption><thead><tr><th scope="col">Rule</th><th scope="col">Severity / evaluation</th><th scope="col">Affected scope</th></tr></thead><tbody>')
    foreach ($finding in @($findings | Select-Object -First 5)) {
        $null = $riskRows.Append('<tr><td>' + (ConvertTo-ApimHtmlText $finding.ruleId) +
            '</td><td>' + (ConvertTo-ApimHtmlText "$($finding.severity) / $($finding.evaluation)") +
            '</td><td>' + (ConvertTo-ApimHtmlText $finding.scope) + '</td></tr>')
    }
    $null = $riskRows.Append('</tbody></table></div>')
    $slots.RISKS = $riskRows.ToString()
    foreach ($action in @($actions | Select-Object -First 10)) {
        $slots.ACTIONS += '<article><h3>' + (ConvertTo-ApimHtmlText "$($action.ruleId): $($action.title)") +
            '</h3><p>' + (ConvertTo-ApimHtmlText $action.recommendation) +
            '</p><p class="muted">' + (ConvertTo-ApimHtmlText "$($action.severity) / $($action.evaluation) | Affected: $($action.affectedCount) | Owner: unassigned") +
            '</p></article>'
    }
    $gaps = @($models.Values | ForEach-Object {
            foreach ($model in @($_)) { $model.missingInputs }
        } | Sort-Object -Unique)
    $slots.GAPS = '<p>Edge behavior is assumed, not independently verified. Telemetry and cost collection are unavailable in this slice. Missing usage is Unknown, never zero. Origin authentication and endpoint-owner intent require explicit local attestation.</p><ul>'
    foreach ($gap in $gaps) { $slots.GAPS += '<li>' + (ConvertTo-ApimHtmlText $gap) + '</li>' }
    $slots.GAPS += '</ul><p>NotEvaluated findings: ' + $notEvaluated.Count + '. Review incomplete evidence before accepting posture.</p>'
    $slots.ROADMAP = '<h3>Confirm evidence</h3><p>Resolve missing inputs and validate assumptions before the readout.</p><h3>Assign accountable owners</h3><p>Review the local action workbook and set owners, status and target dates.</p><h3>Validate outcomes</h3><p>Authorized maintainers validate changes separately; rerun the read-only assessment to measure progress.</p>'
    if ($null -ne $agent -and $null -ne $agent.summary) {
        $slots.POSTURE += '<p>Validated synthesis confidence: ' + (ConvertTo-ApimHtmlText $agent.summary.confidence) + '</p>'
        $slots.ACTIONS = (ConvertTo-ApimHtmlProposal -Items $agent.summary.priorities -Agent $agent) + $slots.ACTIONS
        $slots.DECISIONS = (ConvertTo-ApimHtmlProposal -Items $agent.summary.themes -Agent $agent) +
            (ConvertTo-ApimHtmlProposal -Items $agent.summary.decisions -Agent $agent)
        $slots.ROADMAP = (ConvertTo-ApimHtmlProposal -Items $agent.summary.roadmap -Agent $agent) + $slots.ROADMAP
        foreach ($code in @($agent.summary.assumptions) + @($agent.summary.dataGaps)) {
            $slots.GAPS += '<p>' + (ConvertTo-ApimHtmlText $code) + '</p>'
        }
    }
    $templatePath = Join-Path (Split-Path $analysisSchemaRoot -Parent) 'template/ApimExecutiveSummary.html'
    $template = [Text.UTF8Encoding]::new($false, $true).GetString((Read-ApimAnalysisSnapshot -Path $templatePath))
    $html = [regex]::Replace($template, '\{\{([A-Z]+)\}\}', [Text.RegularExpressions.MatchEvaluator]{
            param($Match)
            $key = $Match.Groups[1].Value
            if (-not $slots.ContainsKey($key)) { throw 'HTML_TEMPLATE_REJECTED' }
            return $slots[$key]
        })
    if ([string]::IsNullOrEmpty($WorkbookPath)) {
        $WorkbookPath = Get-ApimReportOutputPath -RunPath $RunPath -Manifest $manifest
    }
    else {
        $relativeWorkbook = [IO.Path]::GetRelativePath([IO.Path]::GetFullPath($RunPath), [IO.Path]::GetFullPath($WorkbookPath))
        if ($relativeWorkbook -cnotmatch '^report[/\\][^/\\]+\.xlsx\z') { throw 'HTML_OUTPUT_REJECTED' }
        $WorkbookPath = Resolve-RunFilePath -RunPath $RunPath -RelativePath $relativeWorkbook
        Test-ConfigPathLink -Path $WorkbookPath -Context 'Paired report'
        if (-not (Test-Path -LiteralPath $WorkbookPath -PathType Leaf)) { throw 'HTML_OUTPUT_REJECTED' }
    }
    $outputPath = [IO.Path]::ChangeExtension($WorkbookPath, '.html')
    if (-not $PSCmdlet.ShouldProcess($outputPath, 'Render local executive HTML')) { return }
    $relative = [IO.Path]::GetRelativePath([IO.Path]::GetFullPath($RunPath), $outputPath)
    $null = Write-RunFile -RunPath $RunPath -RelativePath $relative -InputObject $html -Format Text
    return @{ status = 'Completed' }
}
