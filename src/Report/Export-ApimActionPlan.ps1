#Requires -Version 7.4

Set-StrictMode -Version Latest

$script:ApimReportTemplatePath = Join-Path (
    Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
) 'template/ApimActionPlan.xlsx'
$script:ApimReportRuleCatalogPath = Join-Path (
    Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
) 'rules'
$script:ApimReportImportExcelVersion = [version] '7.8.10'
$script:ApimReportMaximumRows = 9997

function Import-ApimReportDependency {
    [CmdletBinding()]
    param()

    $available = @(Get-Module -ListAvailable -Name ImportExcel |
            Where-Object Version -EQ $script:ApimReportImportExcelVersion)
    if ($available.Count -eq 0) {
        throw (
            'ImportExcel 7.8.10 is required to render the action-plan ' +
            'workbook.'
        )
    }
    Import-Module ImportExcel `
        -RequiredVersion $script:ApimReportImportExcelVersion `
        -ErrorAction Stop 3>$null
}

function Get-ApimFindingSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath
    )

    $path = Resolve-RunFilePath -RunPath $RunPath `
        -RelativePath 'findings.json'
    Test-ConfigPathLink -Path $path -Context 'Findings file path'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'Required findings were unavailable.'
    }
    try {
        $json = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
    }
    catch {
        throw 'Findings could not be read for report rendering.'
    }
    Test-ApimFindingsJson -Json $json
    try {
        $parsed = ConvertFrom-Json -InputObject $json -Depth 100 `
            -NoEnumerate -ErrorAction Stop
    }
    catch {
        throw 'Findings could not be parsed for report rendering.'
    }
    if ($parsed -isnot [array]) {
        throw 'Findings could not be parsed for report rendering.'
    }
    [object[]] $findings = $parsed
    Assert-ApimFindingKey -Findings $findings
    return $findings
}

function Assert-ApimReportNamePart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value) -or
        $Value -match '[<>:"/\\|?*\x00-\x1F]' -or
        $Value.EndsWith('.') -or $Value.EndsWith(' ') -or
        $Value -in @('.', '..')) {
        throw 'Report filename component contains unsupported characters.'
    }
}

function Get-ApimReportOutputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [object] $Manifest
    )

    Assert-ApimReportNamePart -Value ([string] $Manifest.customer)
    Assert-ApimReportNamePart -Value ([string] $Manifest.environment)
    $date = ([datetimeoffset] $Manifest.startedUtc).ToString('yyyy-MM-dd')
    $baseName = '{0} APIM Assessment - {1} - {2}' -f
        $Manifest.customer, $Manifest.environment, $date
    $reportDirectory = Resolve-RunFilePath -RunPath $RunPath `
        -RelativePath 'report'
    Test-ConfigPathLink -Path $reportDirectory -Context 'Report directory'

    for ($suffix = 1; $suffix -le [int]::MaxValue; $suffix++) {
        $fileName = if ($suffix -eq 1) {
            "$baseName.xlsx"
        }
        else {
            "$baseName-$suffix.xlsx"
        }
        $candidate = Resolve-RunFilePath -RunPath $RunPath `
            -RelativePath (Join-Path 'report' $fileName)
        Test-ConfigPathLink -Path $candidate -Context 'Report file path'
        if (-not (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    throw 'No available report filename could be selected.'
}

function ConvertTo-ApimReportCellValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [datetime] -or $Value -is [datetimeoffset]) {
        return ([datetimeoffset] $Value).ToString('O')
    }
    if ($Value -is [System.Collections.IDictionary] -or
        $Value -is [pscustomobject]) {
        return ConvertTo-Json -InputObject $Value -Depth 100 -Compress `
            -ErrorAction Stop
    }
    if ($Value -is [System.Collections.IEnumerable] -and
        $Value -isnot [string]) {
        [object[]] $items = @($Value)
        if (@($items | Where-Object {
                    $_ -is [System.Collections.IDictionary] -or
                    $_ -is [pscustomobject]
                }).Count -gt 0) {
            return ConvertTo-Json -InputObject $items -Depth 100 -Compress `
                -ErrorAction Stop
        }
        return @($items | ForEach-Object { [string] $_ }) -join '; '
    }
    return $Value
}

function Get-ApimReportTableMapping {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet(
            'tblActions',
            'tblFindings',
            'tblApis',
            'tblPolicy',
            'tblSubs',
            'tblExposure',
            'tblRun',
            'tblRules',
            'tblWeights',
            'tblComparison', 'tblComparisonGaps', 'tblComparisonPillars',
            'tblComparisonKpis', 'tblResolvedTracking', 'tblUnassessedTracking'
        )]
        [string] $TableName
    )

    switch ($TableName) {
        tblActions {
            return [ordered]@{
                'Rule ID' = 'ruleId'
                Title = 'title'
                Pillar = 'pillar'
                Severity = 'severity'
                Evaluation = 'evaluation'
                'Affected Count' = 'affectedCount'
                'Finding Count' = 'findingCount'
                Priority = 'maxPriorityScore'
                'Top Affected Scopes' = 'topAffectedScopes'
                Recommendation = 'recommendation'
                Effort = 'effort'
                Owner = 'owner'
                Status = 'status'
                'Target Date' = 'targetDate'
                Notes = 'notes'
            }
        }
        tblFindings {
            return [ordered]@{
                'Finding Key' = 'findingKey'
                'Rule ID' = 'ruleId'
                Title = 'title'
                Pillar = 'pillar'
                MCSB = 'mcsb'
                Severity = 'severity'
                Scope = 'scope'
                Resource = 'resource'
                Exposure = 'exposure'
                Usage = 'usage'
                Priority = 'priorityScore'
                Evidence = 'evidence'
                'Evidence Text' = 'evidenceText'
                Recommendation = 'recommendation'
                Effort = 'effort'
                'Source Files' = 'sourceFiles'
                Evaluation = 'evaluation'
                Owner = 'owner'
                Status = 'status'
                'Target Date' = 'targetDate'
                Notes = 'notes'
            }
        }
        tblApis {
            return [ordered]@{
                'API ID' = 'apiId'
                'Display Name' = 'displayName'
                Path = 'path'
                'API Type' = 'apiType'
                Protocols = 'protocols'
                'Backend Host' = 'backendHost'
                Products = 'products'
                'Owner Tag' = 'ownerTag'
                Tags = 'tags'
                'Version Set' = 'versionSet'
                Version = 'version'
                'Revision Count' = 'revisionCount'
                'Non-current Online Revisions' = 'nonCurrentOnlineRevisions'
                'Operation Count' = 'operationCount'
                'Subscription Required' = 'subscriptionRequired'
                'Caller Auth' = 'callerAuth'
                Throttling = 'throttling'
                'IP Filter' = 'ipFilter'
                'Unsafe CORS' = 'corsUnsafe'
                'Backend Auth' = 'backendAuth'
                'Hard-coded Secret' = 'hardcodedSecret'
                'Base Missing' = 'baseMissing'
                'Mock or Trace' = 'mockOrTrace'
                'Backend TLS Validation' = 'backendTlsValidation'
                'Body Logging' = 'bodyLogging'
                'Sensitive Headers Logged' = 'sensitiveHeadersLogged'
                Reachability = 'reachability'
                Exposure = 'exposure'
                'Calls 90d' = 'calls90d'
                'Calls via App Gateway' = 'callsViaAppGw'
                'Calls Internal' = 'callsInternal'
                'Last Call' = 'lastCall'
                'P95 ms' = 'p95Ms'
                'Backend P95 ms' = 'backendP95Ms'
                '5xx Percent' = 'pct5xx'
                'OpenAPI Score' = 'openApiScore'
                'In Git' = 'inGit'
                'Finding IDs' = 'findingIds'
                'Model Status' = 'modelStatus'
                'Missing Inputs' = 'missingInputs'
            }
        }
        tblPolicy {
            return [ordered]@{
                'API ID' = 'apiId'
                'Evaluation Status' = 'evaluationStatus'
                'Caller Auth' = 'callerAuth'
                'Rate Limit' = 'rateLimit'
                'IP Filter' = 'ipFilter'
                'CORS Safe' = 'corsSafe'
                'Backend Auth' = 'backendAuth'
                'No Hard-coded Secret' = 'noHardcodedSecret'
                'Base Present' = 'basePresent'
                'No Mock or Trace' = 'noMockTrace'
                'Model Status' = 'modelStatus'
                'Missing Inputs' = 'missingInputs'
            }
        }
        tblSubs {
            return [ordered]@{
                'Subscription ID' = 'subscriptionId'
                'Display Name' = 'displayName'
                'Scope Type' = 'scopeType'
                'Scope Target' = 'scopeTarget'
                State = 'state'
                'Owner Type' = 'ownerType'
                'Created Date' = 'createdDate'
                'Expiration Date' = 'expirationDate'
                'Allow Tracing' = 'allowTracing'
                'Calls 90d' = 'calls90d'
                'Last Used' = 'lastUsed'
                'Built-in Master' = 'isBuiltInMaster'
                Flags = 'flags'
                'Model Status' = 'modelStatus'
                'Missing Inputs' = 'missingInputs'
            }
        }
        tblExposure {
            return [ordered]@{
                'Route Key' = 'routeKey'
                Gateway = 'gateway'
                Listener = 'listener'
                'Listener Host' = 'listenerHost'
                'Backend Host' = 'backendHost'
                'Frontend Type' = 'frontendType'
                'Rule Type' = 'ruleType'
                Pattern = 'pattern'
                'WAF State' = 'wafState'
                'WAF Mode' = 'wafMode'
                Edge = 'edge'
                'API ID' = 'apiId'
                Reachability = 'reachability'
                Restriction = 'restriction'
                Exposure = 'exposure'
                'Calls via App Gateway' = 'callsViaAppGw'
                'Calls Internal' = 'callsInternal'
                Confidence = 'confidence'
                'Base Missing Bypass' = 'baseMissingBypass'
                'Restricted Operations' = 'restrictedOperations'
                'Model Status' = 'modelStatus'
                'Missing Inputs' = 'missingInputs'
            }
        }
        { $_ -cin @('tblComparison', 'tblComparisonGaps') } {
            return [ordered]@{
                'Finding Key' = 'findingKey'; 'Rule ID' = 'ruleId'; Pillar = 'pillar'
                Change = 'change'; 'Previous Severity' = 'previousSeverity'
                'Current Severity' = 'currentSeverity'; 'Severity Changed' = 'severityChanged'
                Reason = 'reason'
            }
        }
        tblComparisonPillars {
            return [ordered]@{
                Pillar = 'pillar'; New = 'new'; Resolved = 'resolved'
                Persisting = 'persisting'; 'Not Reassessed' = 'notReassessed'
            }
        }
        tblComparisonKpis {
            return [ordered]@{
                Metric = 'metric'; Baseline = 'baseline'; Current = 'current'
                Delta = 'delta'; Reason = 'reason'
            }
        }
        { $_ -cin @('tblResolvedTracking', 'tblUnassessedTracking') } {
            return [ordered]@{
                Kind = 'kind'; Key = 'key'; 'Rule ID' = 'ruleId'; Change = 'change'
                Owner = 'owner'; Status = 'status'; 'Target Date' = 'targetDate'; Notes = 'notes'
            }
        }
        tblRun {
            return [ordered]@{
                Section = 'section'
                Name = 'name'
                Status = 'status'
                Items = 'items'
                Errors = 'errors'
                'Duration Sec' = 'durationSec'
                'Started UTC' = 'startedUtc'
                'Completed UTC' = 'completedUtc'
                Window = 'window'
                Value = 'value'
            }
        }
        tblRules {
            return [ordered]@{
                'Rule ID' = 'ruleId'
                Title = 'title'
                Pillar = 'pillar'
                MCSB = 'mcsb'
                Severity = 'severity'
                Scope = 'scope'
                Requires = 'requires'
                Recommendation = 'recommendation'
                Effort = 'effort'
                Enabled = 'enabled'
            }
        }
        tblWeights {
            return [ordered]@{
                Dimension = 'dimension'
                Value = 'value'
                Weight = 'weight'
            }
        }
    }
}

function ConvertTo-ApimReportRunRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Section,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [AllowNull()]
        [object] $Status,

        [AllowNull()]
        [object] $Items,

        [AllowNull()]
        [object] $Errors,

        [AllowNull()]
        [object] $DurationSec,

        [AllowNull()]
        [object] $StartedUtc,

        [AllowNull()]
        [object] $CompletedUtc,

        [AllowNull()]
        [object] $Window,

        [AllowNull()]
        [object] $Value
    )

    return [pscustomobject][ordered]@{
        section = $Section
        name = $Name
        status = $Status
        items = $Items
        errors = $Errors
        durationSec = $DurationSec
        startedUtc = $StartedUtc
        completedUtc = $CompletedUtc
        window = $Window
        value = $Value
    }
}

function ConvertTo-ApimReportRunRowSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Manifest
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    $rows.Add((ConvertTo-ApimReportRunRow -Section Run -Name Assessment `
            -StartedUtc $Manifest.startedUtc `
            -CompletedUtc $Manifest.completedUtc -Value $Manifest.runId))
    foreach ($entry in @(
            @{ Section = 'Scope'; Name = 'Customer'; Value = $Manifest.customer }
            @{
                Section = 'Scope'
                Name = 'Environment'
                Value = $Manifest.environment
            }
            @{ Section = 'Scope'; Name = 'Operator'; Value = $Manifest.operator }
            @{
                Section = 'Scope'
                Name = 'Tenant ID'
                Value = $Manifest.tenantId
            }
            @{
                Section = 'Scope'
                Name = 'Subscription ID'
                Value = $Manifest.subscriptionId
            }
            @{
                Section = 'Scope'
                Name = 'APIM Resource ID'
                Value = $Manifest.apim.resourceId
            }
            @{
                Section = 'Version'
                Name = 'Manifest Schema'
                Value = $Manifest.schemaVersion
            }
            @{
                Section = 'Version'
                Name = 'Tool'
                Value = $Manifest.toolVersion
            }
            @{
                Section = 'Version'
                Name = 'APIM API'
                Value = $Manifest.apim.apiVersion
            }
        )) {
        $rows.Add((ConvertTo-ApimReportRunRow -Section $entry.Section `
                -Name $entry.Name -Value $entry.Value))
    }
    foreach ($stage in @('collect', 'analyze', 'report')) {
        $rows.Add((ConvertTo-ApimReportRunRow -Section Stage `
                -Name ([cultureinfo]::InvariantCulture.TextInfo.ToTitleCase(
                    $stage
                )) -Status $Manifest.stages.$stage))
    }
    foreach ($collector in @($Manifest.collectors | Sort-Object name)) {
        $rows.Add((ConvertTo-ApimReportRunRow -Section Collector `
                -Name $collector.name -Status $collector.status `
                -Items $collector.items -Errors $collector.errors `
                -DurationSec $collector.durationSec))
    }
    foreach ($window in @(
            @{
                Name = 'Usage'
                Window = "$($Manifest.windows.usageDays) days"
                Value = $Manifest.windows.usageDays
            }
            @{
                Name = 'Security Logs'
                Window = "$($Manifest.windows.securityLogDays) days"
                Value = $Manifest.windows.securityLogDays
            }
            @{
                Name = 'Cost'
                Window = "$($Manifest.windows.costMonths) months"
                Value = $Manifest.windows.costMonths
            }
        )) {
        $rows.Add((ConvertTo-ApimReportRunRow -Section Window -Name $window.Name `
                -Window $window.Window -Value $window.Value))
    }
    foreach ($entry in @(
            @{
                Section = 'Edge'
                Name = 'Provider'
                Value = $Manifest.edge.provider
            }
            @{
                Section = 'Edge'
                Name = 'Mode'
                Value = $Manifest.edge.mode
            }
            @{
                Section = 'Model Safe'
                Name = 'Build'
                Status = $Manifest.modelSafe.build
            }
            @{
                Section = 'Model Safe'
                Name = 'Validation'
                Status = $Manifest.modelSafe.validation
            }
            @{
                Section = 'Model Safe'
                Name = 'Promotion'
                Status = $Manifest.modelSafe.promotion
            }
            @{
                Section = 'Model Safe'
                Name = 'Package SHA-256'
                Value = $Manifest.modelSafe.packageSha256
            }
        )) {
        $status = if ($entry.ContainsKey('Status')) {
            $entry.Status
        }
        else {
            $null
        }
        $value = if ($entry.ContainsKey('Value')) {
            $entry.Value
        }
        else {
            $null
        }
        $rows.Add((ConvertTo-ApimReportRunRow -Section $entry.Section `
                -Name $entry.Name -Status $status -Value $value))
    }
    for ($index = 0; $index -lt @($Manifest.warnings).Count; $index++) {
        $rows.Add((ConvertTo-ApimReportRunRow -Section Warning `
                -Name ('Warning {0}' -f ($index + 1)) `
                -Value $Manifest.warnings[$index]))
    }
    return $rows.ToArray()
}

function ConvertTo-ApimReportRuleRowSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object[]] $Rules
    )

    [object[]] $sorted = @($Rules)
    [Array]::Sort($sorted, [System.Collections.Generic.Comparer[object]]::Create(
            [System.Comparison[object]] {
                param($left, $right)
                return [string]::CompareOrdinal($left.Id, $right.Id)
            }
        ))
    return @($sorted | ForEach-Object {
            [pscustomobject][ordered]@{
                ruleId = $_.Id
                title = $_.Title
                pillar = $_.Pillar
                mcsb = $_.Mcsb
                severity = $_.Severity
                scope = @(Resolve-ApimRuleScope -Scope $_.Scope)
                requires = @($_.Requires)
                recommendation = $_.Recommendation
                effort = $_.Effort
                enabled = $_.Enabled
            }
        })
}

function ConvertTo-ApimReportWeightRowSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Manifest
    )

    return @(
        [pscustomobject]@{
            dimension = 'Severity'; value = 'High'
            weight = $Manifest.scoring.severity.high
        }
        [pscustomobject]@{
            dimension = 'Severity'; value = 'Medium'
            weight = $Manifest.scoring.severity.medium
        }
        [pscustomobject]@{
            dimension = 'Severity'; value = 'Low'
            weight = $Manifest.scoring.severity.low
        }
        [pscustomobject]@{
            dimension = 'Severity'; value = 'Info'
            weight = $Manifest.scoring.severity.info
        }
        [pscustomobject]@{
            dimension = 'Exposure'; value = 'DirectPublic'
            weight = $Manifest.scoring.exposure.directPublic
        }
        [pscustomobject]@{
            dimension = 'Exposure'; value = 'ExternalInUse'
            weight = $Manifest.scoring.exposure.externalInUse
        }
        [pscustomobject]@{
            dimension = 'Exposure'; value = 'ExternalUnintended'
            weight = $Manifest.scoring.exposure.externalUnintended
        }
        [pscustomobject]@{
            dimension = 'Exposure'; value = 'Restricted'
            weight = $Manifest.scoring.exposure.restricted
        }
        [pscustomobject]@{
            dimension = 'Exposure'; value = 'Internal'
            weight = $Manifest.scoring.exposure.internal
        }
        [pscustomobject]@{
            dimension = 'Exposure'; value = 'Platform'
            weight = $Manifest.scoring.exposure.platform
        }
        [pscustomobject]@{
            dimension = 'Exposure'; value = 'Unknown'
            weight = $Manifest.scoring.exposure.unknown
        }
        [pscustomobject]@{
            dimension = 'Usage'; value = 'InUse'
            weight = $Manifest.scoring.usage.inUse
        }
        [pscustomobject]@{
            dimension = 'Usage'; value = 'Unused'
            weight = $Manifest.scoring.usage.unused
        }
        [pscustomobject]@{
            dimension = 'Usage'; value = 'NotApplicable'
            weight = $Manifest.scoring.usage.notApplicable
        }
    )
}

function ConvertTo-ApimReportRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Records,

        [Parameter(Mandatory)]
        [System.Collections.Specialized.OrderedDictionary] $Mapping
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $Records) {
        $row = [ordered]@{}
        foreach ($header in $Mapping.Keys) {
            $propertyName = $Mapping[$header]
            if ($null -eq $propertyName) {
                $value = $null
            }
            elseif ($record -is [System.Collections.IDictionary]) {
                if (-not $record.Contains($propertyName)) {
                    throw "Report source record was missing '$propertyName'."
                }
                $value = $record[$propertyName]
            }
            elseif ($null -eq $record.PSObject.Properties[$propertyName]) {
                throw "Report source record was missing '$propertyName'."
            }
            else {
                $value = $record.$propertyName
            }
            $row[$header] = ConvertTo-ApimReportCellValue -Value $value
        }
        $rows.Add([pscustomobject] $row)
    }
    return $rows.ToArray()
}

function Assert-ApimReportRowCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int] $Count,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TableName
    )

    if ($Count -gt $script:ApimReportMaximumRows) {
        throw (
            "Report table '$TableName' exceeds the 9,997-row template limit."
        )
    }
}

function Write-ApimReportTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Package,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WorksheetName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TableName,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Rows,

        [Parameter(Mandatory)]
        [System.Collections.Specialized.OrderedDictionary] $Mapping
    )

    Assert-ApimReportRowCount -Count $Rows.Count -TableName $TableName
    $worksheet = $Package.Workbook.Worksheets[$WorksheetName]
    if ($null -eq $worksheet) {
        throw "Report template worksheet '$WorksheetName' was unavailable."
    }
    $table = $worksheet.Tables[$TableName]
    if ($null -eq $table) {
        throw "Report template table '$TableName' was unavailable."
    }
    [string[]] $actualHeaders = @($table.Columns.Name)
    [string[]] $expectedHeaders = @($Mapping.Keys)
    if ($actualHeaders.Count -ne $expectedHeaders.Count) {
        throw "Report template table '$TableName' has invalid headers."
    }
    for ($index = 0; $index -lt $actualHeaders.Count; $index++) {
        if ($actualHeaders[$index] -cne $expectedHeaders[$index]) {
            throw "Report template table '$TableName' has invalid headers."
        }
    }

    $startRow = $table.Address.Start.Row
    $startColumn = $table.Address.Start.Column
    $endColumn = $table.Address.End.Column
    $dataRowCount = [math]::Max(1, $Rows.Count)
    $worksheet.Cells[
        ($startRow + 1),
        $startColumn,
        ($startRow + $dataRowCount),
        $endColumn
    ].Clear()

    for ($rowIndex = 0; $rowIndex -lt $Rows.Count; $rowIndex++) {
        for ($columnIndex = 0;
            $columnIndex -lt $expectedHeaders.Count;
            $columnIndex++) {
            $header = $expectedHeaders[$columnIndex]
            $worksheet.Cells[
                ($startRow + 1 + $rowIndex),
                ($startColumn + $columnIndex)
            ].Value = $Rows[$rowIndex].$header
        }
    }
    $tableAddress = $worksheet.Cells[
        $startRow,
        $startColumn,
        ($startRow + $dataRowCount),
        $endColumn
    ].Address
    $table.TableXml.DocumentElement.SetAttribute('ref', $tableAddress)
    $namespace = [System.Xml.XmlNamespaceManager]::new(
        $table.TableXml.NameTable
    )
    $namespace.AddNamespace(
        'd',
        'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
    )
    $autoFilter = $table.TableXml.SelectSingleNode(
        '/d:table/d:autoFilter',
        $namespace
    )
    if ($null -ne $autoFilter) {
        $autoFilter.SetAttribute('ref', $tableAddress)
    }
}

function Write-ApimReportSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Package,

        [Parameter(Mandatory)]
        [object] $Manifest,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Findings,

        [Parameter(Mandatory)]
        [object] $Network
    )

    $summary = $Package.Workbook.Worksheets['Summary']
    if ($null -eq $summary) {
        throw "Report template worksheet 'Summary' was unavailable."
    }
    $notEvaluated = @($Findings | Where-Object {
            $_.evaluation -eq 'NotEvaluated'
        }).Count
    $summary.Cells[4, 1].Value = (
        'ASSUMPTIONS AND DATA GAPS - Edge: {0}/{1}; windows: usage {2}d, ' +
        'security {3}d, cost {4}m; NotEvaluated findings: {5}; manifest ' +
        'warnings: {6}; Usage, Cost, and Environment Drift remain deferred ' +
        'in this report slice.'
    ) -f
        $Manifest.edge.provider,
        $Manifest.edge.mode,
        $Manifest.windows.usageDays,
        $Manifest.windows.securityLogDays,
        $Manifest.windows.costMonths,
        $notEvaluated,
        @($Manifest.warnings).Count

    $exposure = $Package.Workbook.Worksheets['Exposure Map']
    if ($null -eq $exposure -or
        $exposure.Cells[1, 24].Text -cne 'Network Summary') {
        throw 'Report template network summary was unavailable.'
    }
    $networkValues = @(
        $Network.virtualNetworkType,
        $(if ($null -eq $Network.publicNetworkAccess) {
                'Unknown'
            }
            else {
                $Network.publicNetworkAccess
            }),
        $Network.nsgEvaluation,
        $(if ($null -eq $Network.directPublic) {
                'Unknown'
            }
            else {
                [string] $Network.directPublic
            }),
        $Network.appGatewayTlsPolicy,
        $Network.appGatewayProbeAlignment,
        "$($Network.wafState) / $($Network.wafMode)",
        $Network.modelStatus
    )
    for ($index = 0; $index -lt $networkValues.Count; $index++) {
        $exposure.Cells[($index + 3), 25].Value = $networkValues[$index]
    }
}

function Write-ApimReportPriorityFormula {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Package,

        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int] $ActionCount,

        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int] $FindingCount
    )

    $findingTable = $Package.Workbook.Worksheets[
        'Finding Details'
    ].Tables['tblFindings']
    $actionTable = $Package.Workbook.Worksheets[
        'Action Plan'
    ].Tables['tblActions']
    if ($null -eq $findingTable -or $null -eq $actionTable) {
        throw 'Report template priority tables were unavailable.'
    }
    $findingPriorityColumn = [Array]::IndexOf(
        [string[]] @($findingTable.Columns.Name),
        'Priority'
    )
    $actionPriorityColumn = [Array]::IndexOf(
        [string[]] @($actionTable.Columns.Name),
        'Priority'
    )
    if ($findingPriorityColumn -lt 0 -or $actionPriorityColumn -lt 0) {
        throw 'Report template priority columns were unavailable.'
    }

    $findingFormula = (
        'ROUND(' +
        'SUMIFS(tblWeights[Weight],tblWeights[Dimension],"Severity",' +
        'tblWeights[Value],[@Severity])*' +
        'SUMIFS(tblWeights[Weight],tblWeights[Dimension],"Exposure",' +
        'tblWeights[Value],[@Exposure])*' +
        'IF([@Usage]="",1,SUMIFS(tblWeights[Weight],' +
        'tblWeights[Dimension],"Usage",tblWeights[Value],[@Usage])),1)'
    )
    for ($index = 0; $index -lt $FindingCount; $index++) {
        $findingTable.WorkSheet.Cells[
            ($findingTable.Address.Start.Row + 1 + $index),
            ($findingTable.Address.Start.Column + $findingPriorityColumn)
        ].Formula = $findingFormula
    }
    for ($index = 0; $index -lt $ActionCount; $index++) {
        $actionTable.WorkSheet.Cells[
            ($actionTable.Address.Start.Row + 1 + $index),
            ($actionTable.Address.Start.Column + $actionPriorityColumn)
        ].Formula = (
            'MAXIFS(tblFindings[Priority],tblFindings[Rule ID],' +
            '[@[Rule ID]])'
        )
    }
}

function Export-ApimActionPlan {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [ValidateNotNullOrEmpty()]
        [string] $TemplatePath = $script:ApimReportTemplatePath,

        [string] $PreviousReport
    )

    Import-ApimReportDependency
    $manifest = Get-RunManifest -RunPath $RunPath
    $models = Get-ApimModelSet -RunPath $RunPath
    [object[]] $findings = @(Get-ApimFindingSet -RunPath $RunPath)
    [object[]] $actions = @(Get-ApimActionPlan -Findings $findings)
    $comparison = Get-ApimSavedComparison -RunPath $RunPath
    $trackingArguments = @{
        RunPath = $RunPath; Manifest = $manifest; Models = $models
        Actions = $actions; Findings = $findings; Comparison = $comparison
    }
    if ($PSBoundParameters.ContainsKey('PreviousReport')) {
        $trackingArguments.PreviousReport = $PreviousReport
    }
    $tracking = Merge-ApimPriorTracking @trackingArguments
    Test-ConfigPathLink -Path $script:ApimReportRuleCatalogPath `
        -Context 'Rule catalog path'
    [object[]] $rules = @(Get-ApimRuleCatalog `
            -CatalogPath $script:ApimReportRuleCatalogPath)
    [object[]] $runRows = @(ConvertTo-ApimReportRunRowSet `
            -Manifest $manifest)
    $settingsPath = Resolve-RunFilePath -RunPath $RunPath -RelativePath 'restricted/run-settings.json'
    Test-ConfigPathLink -Path $settingsPath -Context 'Report settings'
    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        $snapshot = Get-ApimComparisonSnapshot -RunPath $RunPath
        $runRows += ConvertTo-ApimReportRunRow -Section Lifecycle -Name 'Snapshot SHA256' `
            -Value $snapshot.identity.sha256
    }
    [object[]] $ruleRows = @(ConvertTo-ApimReportRuleRowSet -Rules $rules)
    [object[]] $weightRows = @(ConvertTo-ApimReportWeightRowSet `
            -Manifest $manifest)

    $resolvedTemplate = [System.IO.Path]::GetFullPath($TemplatePath)
    Test-ConfigPathLink -Path $resolvedTemplate -Context 'Report template path'
    if (-not (Test-Path -LiteralPath $resolvedTemplate -PathType Leaf)) {
        throw 'Report template was unavailable.'
    }
    $outputPath = Get-ApimReportOutputPath -RunPath $RunPath `
        -Manifest $manifest
    if (-not $PSCmdlet.ShouldProcess($outputPath, 'Render APIM action plan')) {
        return
    }

    $outputDirectory = [System.IO.Path]::GetDirectoryName($outputPath)
    Test-ConfigPathLink -Path $outputDirectory -Context 'Report directory'
    [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
    Test-ConfigPathLink -Path $outputDirectory -Context 'Report directory'
    $temporaryPath = "$outputPath.$([guid]::NewGuid().ToString('N')).tmp.xlsx"
    $package = $null
    try {
        Copy-Item -LiteralPath $resolvedTemplate `
            -Destination $temporaryPath -ErrorAction Stop
        $package = Open-ExcelPackage -Path $temporaryPath
        foreach ($definition in @(
                @{
                    Worksheet = 'Action Plan'
                    Table = 'tblActions'
                    Records = $tracking.actions
                }
                @{
                    Worksheet = 'Finding Details'
                    Table = 'tblFindings'
                    Records = $tracking.findings
                }
                @{
                    Worksheet = 'API Inventory'
                    Table = 'tblApis'
                    Records = @($models.apis)
                }
                @{
                    Worksheet = 'Effective Policy Matrix'
                    Table = 'tblPolicy'
                    Records = @($models.policyMatrix)
                }
                @{
                    Worksheet = 'Subscriptions'
                    Table = 'tblSubs'
                    Records = @($models.subscriptions)
                }
                @{
                    Worksheet = 'Exposure Map'
                    Table = 'tblExposure'
                    Records = @($models.exposure)
                }
                @{
                    Worksheet = 'Run Info'
                    Table = 'tblRun'
                    Records = $runRows
                }
                @{
                    Worksheet = 'Method & Rules'
                    Table = 'tblRules'
                    Records = $ruleRows
                }
                @{
                    Worksheet = 'Method & Rules'
                    Table = 'tblWeights'
                    Records = $weightRows
                }
                @{ Worksheet = 'Resolved Since Last Run'; Table = 'tblResolvedTracking'; Records = $tracking.resolved }
                @{ Worksheet = 'Not Reassessed'; Table = 'tblUnassessedTracking'; Records = $tracking.notReassessed }
                @{ Worksheet = 'Run Comparison'; Table = 'tblComparison'; Records = @(if ($null -ne $comparison) { $comparison.changes }) }
                @{ Worksheet = 'Comparison Gaps'; Table = 'tblComparisonGaps'; Records = @(if ($null -ne $comparison) { $comparison.gaps }) }
                @{ Worksheet = 'Comparison Pillars'; Table = 'tblComparisonPillars'; Records = @(if ($null -ne $comparison) { $comparison.pillars }) }
                @{ Worksheet = 'Comparison KPIs'; Table = 'tblComparisonKpis'; Records = @(if ($null -ne $comparison) { $comparison.kpis }) }
            )) {
            $mapping = Get-ApimReportTableMapping `
                -TableName $definition.Table
            [object[]] $rows = @(ConvertTo-ApimReportRow `
                    -Records $definition.Records -Mapping $mapping)
            Write-ApimReportTable -Package $package `
                -WorksheetName $definition.Worksheet `
                -TableName $definition.Table -Rows $rows -Mapping $mapping
        }
        Write-ApimReportPriorityFormula -Package $package `
            -ActionCount $actions.Count -FindingCount $findings.Count
        Write-ApimReportSummary -Package $package -Manifest $manifest `
            -Findings $findings -Network $models.network
        $package.Workbook.CalcMode = 'Automatic'
        $package.Workbook.FullCalcOnLoad = $true
        Close-ExcelPackage -ExcelPackage $package
        $package = $null
        [System.IO.File]::Move($temporaryPath, $outputPath, $false)
    }
    catch {
        if ($null -ne $package) {
            $package.Dispose()
        }
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
        throw
    }
    return $outputPath
}
