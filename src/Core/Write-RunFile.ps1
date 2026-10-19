#Requires -Version 7.4

Set-StrictMode -Version Latest

$script:ManifestSchemaPath = Join-Path (
    Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
) 'schemas/manifest.schema.json'

function Resolve-RunFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RelativePath
    )

    if ([System.IO.Path]::IsPathFullyQualified($RelativePath)) {
        throw 'Run file path must be relative to the run folder.'
    }

    $resolvedRunPath = [System.IO.Path]::TrimEndingDirectorySeparator(
        [System.IO.Path]::GetFullPath($RunPath)
    )
    $resolvedFilePath = [System.IO.Path]::GetFullPath(
        (Join-Path $resolvedRunPath $RelativePath)
    )
    $runPrefix = "$resolvedRunPath$([System.IO.Path]::DirectorySeparatorChar)"
    $comparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    if (-not $resolvedFilePath.StartsWith(
            $runPrefix,
            $comparison
        )) {
        throw 'Run file path cannot escape the run folder.'
    }

    return $resolvedFilePath
}

function Write-RunFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RelativePath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $InputObject,

        [ValidateSet('Json', 'Text')]
        [string] $Format = 'Json',

        [ValidateRange(2, 100)]
        [int] $Depth = 50
    )

    $filePath = Resolve-RunFilePath -RunPath $RunPath -RelativePath $RelativePath
    $directory = [System.IO.Path]::GetDirectoryName($filePath)
    Test-ConfigPathLink -Path $directory -Context 'Run file path'
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    Test-ConfigPathLink -Path $directory -Context 'Run file path'

    $content = if ($Format -eq 'Json') {
        ConvertTo-Json -InputObject $InputObject -Depth $Depth
    }
    else {
        [string] $InputObject
    }
    if (-not $content.EndsWith("`n") -and
        -not $content.EndsWith("`r")) {
        $content += [Environment]::NewLine
    }

    $temporaryPath = "$filePath.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [System.IO.File]::WriteAllText(
            $temporaryPath,
            $content,
            [System.Text.UTF8Encoding]::new($false)
        )
        Move-Item -LiteralPath $temporaryPath -Destination $filePath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }

    return $filePath
}

function Get-ApimAssessmentToolVersion {
    [CmdletBinding()]
    param()

    $moduleVersion = $ExecutionContext.SessionState.Module.Version
    if ($null -eq $moduleVersion) {
        throw 'ApimAssessment module version is unavailable.'
    }
    return $moduleVersion.ToString()
}

function Get-ApimEnvironmentConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Config,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $EnvironmentName
    )

    $environmentMatches = @($Config.Environments | Where-Object {
            $_.Name -eq $EnvironmentName
        })
    if ($environmentMatches.Count -ne 1) {
        throw "Configuration environment '$EnvironmentName' was not found."
    }
    return $environmentMatches[0]
}

function Test-RunManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Manifest
    )

    if (-not (Test-Path -LiteralPath $script:ManifestSchemaPath -PathType Leaf)) {
        throw 'Manifest schema is unavailable.'
    }

    $json = $Manifest | ConvertTo-Json -Depth 100
    $isValid = $json | Test-Json -SchemaFile $script:ManifestSchemaPath `
        -ErrorAction Stop
    if (-not $isValid) {
        throw 'Run manifest did not satisfy the manifest schema.'
    }
    if ($Manifest.schemaVersion -ceq '1.2') {
        $keys = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::OrdinalIgnoreCase
        )
        $anchor = [datetimeoffset] $Manifest.startedUtc
        foreach ($entry in $Manifest.evidenceWindows) {
            if (-not $keys.Add("$($entry.kind)|$($entry.target)")) {
                throw 'Run evidence windows contain duplicate targets.'
            }
            $length = switch ($entry.kind) {
                Usage { [int] $Manifest.windows.usageDays }
                Security { [int] $Manifest.windows.securityLogDays }
                Metric { [int] $Manifest.windows.metricDays }
                Cost { [int] $Manifest.windows.costMonths }
                Ingestion { [int] $Manifest.windows.usageDays }
                AppGateway { [int] $Manifest.windows.usageDays }
            }
            $retention = @{}
            if ($null -ne $entry.retentionDays) {
                $retention.RetentionDays = [int] $entry.retentionDays
            }
            $expected = Get-ApimEvidenceWindow -EndUtc $anchor -Kind $entry.kind `
                -Length $length @retention
            foreach ($field in @('requestedStartUtc', 'startUtc', 'endUtc')) {
                $actualDate = [datetimeoffset] $entry.$field
                if ($actualDate -ne [datetimeoffset] $expected.$field) {
                    throw 'Run evidence window is not bound to the UTC run anchor.'
                }
            }
            if ($entry.isCapped -ne $expected.isCapped -or
                ($entry.status -ceq 'Completed' -and
                    ($entry.reason -cne 'None' -or $entry.schema -ceq 'None')) -or
                ($entry.status -ceq 'Skipped' -and
                    $entry.reason -cnotin @('Unconfigured', 'OptOut')) -or
                ($entry.kind -cin @('Metric', 'Cost') -and
                    $entry.schema -cne 'NotApplicable')) {
                throw 'Run evidence coverage is inconsistent.'
            }
        }
    }
}

function Save-RunManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Manifest
    )

    Test-RunManifest -Manifest $Manifest
    Write-RunFile -RunPath $RunPath -RelativePath 'manifest.json' `
        -InputObject $Manifest -Depth 100
}

function Get-RunManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath
    )

    $manifestPath = Resolve-RunFilePath -RunPath $RunPath `
        -RelativePath 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Run manifest was not found in '$RunPath'."
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw |
            ConvertFrom-Json -Depth 100 -ErrorAction Stop
    }
    catch {
        throw "Run manifest in '$RunPath' is not valid JSON."
    }
    Test-RunManifest -Manifest $manifest
    return $manifest
}

function New-ApimRun {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Config,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $EnvironmentName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TenantId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Operator,

        [datetimeoffset] $StartedUtc = [datetimeoffset]::UtcNow,

        [string] $RunId,

        [string] $ToolVersion,

        [switch] $IncludeTelemetry
    )

    $environment = Get-ApimEnvironmentConfig -Config $Config `
        -EnvironmentName $EnvironmentName
    if ([string]::IsNullOrWhiteSpace($RunId)) {
        $RunId = '{0}_{1}' -f $StartedUtc.UtcDateTime.ToString('yyyy-MM-dd_HHmm'),
            $EnvironmentName
    }
    if ($RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw 'Run ID contains unsupported path characters.'
    }
    if ([string]::IsNullOrWhiteSpace($ToolVersion)) {
        $ToolVersion = Get-ApimAssessmentToolVersion
    }

    $runPath = Join-Path $Config.Output.Root $RunId
    if (Test-Path -LiteralPath $runPath) {
        throw "Run folder '$RunId' already exists."
    }

    $resourceId = (
        '/subscriptions/{0}/resourceGroups/{1}/providers/' +
        'Microsoft.ApiManagement/service/{2}'
    ) -f
        $environment.SubscriptionId,
        $environment.ApimResourceGroup,
        $environment.ApimName
    $manifest = [ordered]@{
        schemaVersion = '1.1'
        toolVersion   = $ToolVersion
        customer      = $Config.Customer
        environment   = $environment.Name
        runId         = $RunId
        startedUtc    = $StartedUtc.UtcDateTime.ToString('O')
        completedUtc  = $null
        operator      = $Operator
        tenantId      = $TenantId
        subscriptionId = $environment.SubscriptionId
        apim          = [ordered]@{
            resourceId = $resourceId
            apiVersion = '2024-05-01'
        }
        windows       = [ordered]@{
            usageDays      = [int] $Config.Windows.UsageDays
            securityLogDays = [int] $Config.Windows.SecurityLogDays
            costMonths     = [int] $Config.Windows.CostMonths
        }
        edge          = [ordered]@{
            provider = $Config.Edge.Provider
            mode     = $Config.Edge.Mode
        }
        scoring       = [ordered]@{
            severity = [ordered]@{
                high   = [double] $Config.Scoring.Severity.High
                medium = [double] $Config.Scoring.Severity.Medium
                low    = [double] $Config.Scoring.Severity.Low
                info   = [double] $Config.Scoring.Severity.Info
            }
            exposure = [ordered]@{
                directPublic       = [double] $Config.Scoring.Exposure.DirectPublic
                externalInUse      = [double] $Config.Scoring.Exposure.ExternalInUse
                externalUnintended = [double] $Config.Scoring.Exposure.ExternalUnintended
                restricted         = [double] $Config.Scoring.Exposure.Restricted
                internal           = [double] $Config.Scoring.Exposure.Internal
                platform           = [double] $Config.Scoring.Exposure.Platform
                unknown            = [double] $Config.Scoring.Exposure.Unknown
            }
            usage = [ordered]@{
                inUse         = [double] $Config.Scoring.Usage.InUse
                unused        = [double] $Config.Scoring.Usage.Unused
                notApplicable = [double] $Config.Scoring.Usage.NotApplicable
            }
        }
        stages        = [ordered]@{
            collect = 'NotStarted'
            analyze = 'NotStarted'
            report  = 'NotStarted'
        }
        collectors    = @()
        modelSafe     = [ordered]@{
            build         = 'NotStarted'
            validation    = 'NotRun'
            promotion     = 'NotStarted'
            packageSha256 = $null
        }
        warnings      = @()
    }
    if ($IncludeTelemetry) {
        $manifest.schemaVersion = '1.2'
        $manifest.windows.metricDays = [int] $Config.Windows.MetricDays
        $manifest.evidenceWindows = @()
    }
    Test-RunManifest -Manifest $manifest

    if (-not $PSCmdlet.ShouldProcess($runPath, 'Create APIM assessment run')) {
        return
    }
    foreach ($relativeDirectory in @(
            '.', 'raw', 'model', 'restricted', 'report', 'logs'
        )) {
        $directory = if ($relativeDirectory -eq '.') {
            $runPath
        }
        else {
            Join-Path $runPath $relativeDirectory
        }
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    }

    Save-RunManifest -RunPath $runPath -Manifest $manifest | Out-Null
    return [pscustomobject]@{
        RunId        = $RunId
        Path         = $runPath
        ManifestPath = Join-Path $runPath 'manifest.json'
        LogPath      = Join-Path $runPath 'logs/run.log'
        Environment  = $environment
    }
}

function Set-RunStageStatus {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [ValidateSet('collect', 'analyze', 'report')]
        [string] $Stage,

        [Parameter(Mandatory)]
        [ValidateSet('NotStarted', 'InProgress', 'Completed', 'Partial', 'Failed', 'Skipped')]
        [string] $Status
    )

    if (-not $PSCmdlet.ShouldProcess($RunPath, "Set $Stage stage to $Status")) {
        return
    }

    $manifest = Get-RunManifest -RunPath $RunPath
    $manifest.stages.$Stage = $Status
    Save-RunManifest -RunPath $RunPath -Manifest $manifest | Out-Null
}

function Set-RunCollectorStatus {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateSet('NotStarted', 'InProgress', 'Completed', 'Partial', 'Failed', 'Skipped')]
        [string] $Status,

        [ValidateRange(0, [int]::MaxValue)]
        [int] $Items = 0,

        [ValidateRange(0, [int]::MaxValue)]
        [int] $Errors = 0,

        [ValidateRange(0, [double]::MaxValue)]
        [double] $DurationSec = 0,

        [AllowEmptyCollection()]
        [ValidateNotNull()]
        [string[]] $Files
    )

    if (-not $PSCmdlet.ShouldProcess(
            $RunPath,
            "Set $Name collector to $Status"
        )) {
        return
    }

    $manifest = Get-RunManifest -RunPath $RunPath
    $collector = [pscustomobject] [ordered]@{
        name        = $Name
        status      = $Status
        items       = $Items
        errors      = $Errors
        durationSec = [math]::Round($DurationSec, 3)
    }
    if ($PSBoundParameters.ContainsKey('Files')) {
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($file in $Files) {
            if ($file -cnotmatch '^(?!.*(?:^|/)\.\.?(?:/|$))[A-Za-z0-9._~%-]+(?:/[A-Za-z0-9._~%-]+)*$' -or
                -not $seen.Add($file)) {
                throw 'Collector file inventory contains an invalid or duplicate relative path.'
            }
            $null = Resolve-RunFilePath -RunPath $RunPath -RelativePath $file
        }
        $collector | Add-Member -NotePropertyName files -NotePropertyValue @($Files)
    }
    $manifest.collectors = @(
        @(
            @($manifest.collectors | Where-Object { $_.name -ne $Name })
            $collector
        ) | Sort-Object name
    )
    Save-RunManifest -RunPath $RunPath -Manifest $manifest | Out-Null
}

function Add-RunWarning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Message
    )

    $manifest = Get-RunManifest -RunPath $RunPath
    if ($Message -notin @($manifest.warnings)) {
        $manifest.warnings = @($manifest.warnings) + $Message
        Save-RunManifest -RunPath $RunPath -Manifest $manifest | Out-Null
    }
}

function Complete-ApimRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [datetimeoffset] $CompletedUtc = [datetimeoffset]::UtcNow
    )

    $manifest = Get-RunManifest -RunPath $RunPath
    $manifest.completedUtc = $CompletedUtc.UtcDateTime.ToString('O')
    Save-RunManifest -RunPath $RunPath -Manifest $manifest | Out-Null
}
