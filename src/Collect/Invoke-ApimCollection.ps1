#Requires -Version 7.4

Set-StrictMode -Version Latest

function ConvertTo-ApimCanonicalValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value
    )

    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        [string[]] $keys = @($Value.Keys)
        [array]::Sort($keys, [StringComparer]::Ordinal)
        foreach ($key in $keys) {
            $result[$key] = ConvertTo-ApimCanonicalValue -Value $Value[$key]
        }
        return $result
    }
    if ($Value -is [datetime] -or $Value -is [datetimeoffset]) {
        return ([datetimeoffset] $Value).ToUniversalTime().ToString('O')
    }
    if ($null -ne $Value -and $Value.PSObject.BaseObject -is [pscustomobject]) {
        $map = @{}
        foreach ($property in $Value.PSObject.Properties) {
            $map[$property.Name] = $property.Value
        }
        return ConvertTo-ApimCanonicalValue -Value $map
    }
    if ($Value -is [array]) {
        $items = @(
            foreach ($item in $Value) {
                ConvertTo-ApimCanonicalValue -Value $item
            }
        )
        return ,$items
    }
    return $Value
}

function Get-ApimConfigDigest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Config
    )

    $json = ConvertTo-Json -InputObject (
        ConvertTo-ApimCanonicalValue -Value $Config
    ) -Depth 100 -Compress -WarningAction Stop
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    return [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($bytes)
    ).ToLowerInvariant()
}

function Remove-ApimCollectorOutput {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [ValidateSet('Service', 'Apis', 'Products', 'Subscriptions',
            'SecurityAssets', 'Diagnostics', 'Policies', 'Network', 'Identity', 'Portal', 'OpenApi', 'Organization',
            'LogAnalytics', 'Metrics', 'Cost', 'LogicApps')]
        [string] $Name
    )

    $owned = @{
        Service = @('raw/service.json')
        Apis = @('raw/apis.json', 'raw/operations', 'raw/apiRevisions', 'raw/apiTags')
        Products = @('raw/products.json', 'raw/productApis', 'raw/productGroups')
        Subscriptions = @('raw/subscriptions.json')
        SecurityAssets = @('raw/namedValues.json', 'raw/backends.json', 'raw/certificates.json')
        Diagnostics = @('raw/loggers.json', 'raw/diagnostics.json', 'raw/apiDiagnostics')
        Policies = @('policies')
        Network = @('raw/network')
        Identity = @('raw/identityProviders.json', 'raw/authorizationServers.json',
            'raw/openidConnectProviders.json', 'raw/authorizationProviders.json')
        Portal = @('raw/portal')
        OpenApi = @('raw/openapi')
        Organization = @((Get-ApimOrganizationEndpoint).File)
        LogAnalytics = @('logs/workspaces.json', 'logs/usageByApi.json', 'logs/usageByRoute.json',
            'logs/usageMonthly.json', 'logs/tls.json', 'logs/noSubscriptionCalls.json', 'cost/laIngestion.json',
            'logs/appgwByListener.json', 'logs/appgwNonEdge.json', 'logs/directNonAppGw.json',
            'logs/headersLogged.json')
        Metrics = @('metrics/apim.json', 'metrics/appgw.json')
        Cost = @('cost/daily.json')
        LogicApps = @('cost/logicApps.json')
    }
    $paths = @(
        foreach ($relative in $owned[$Name]) {
            $path = Resolve-RunFilePath -RunPath $RunPath -RelativePath $relative
            Test-ConfigPathLink -Path $path -Context 'Collector output'
            if (Test-Path -LiteralPath $path) {
                if (Test-Path -LiteralPath $path -PathType Container) {
                    foreach ($child in Get-ChildItem -LiteralPath $path -Recurse `
                            -Force -ErrorAction Stop) {
                        Test-ConfigPathLink -Path $child.FullName `
                            -Context 'Collector output'
                    }
                }
                $path
            }
        }
    )
    foreach ($path in $paths) {
        if ($PSCmdlet.ShouldProcess($path, 'Remove invalidated collector output')) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
        }
    }
}

function Get-ApimTelemetryCollectorRegistry {
    [CmdletBinding()]
    param()

    @(
        [pscustomobject]@{ Name = 'LogAnalytics'; Function = 'Invoke-ApimLogCollector'; Requires = @(); Throttled = $false }
        [pscustomobject]@{ Name = 'Metrics'; Function = 'Invoke-ApimMetricsCollector'; Requires = @(); Throttled = $false }
        [pscustomobject]@{ Name = 'Cost'; Function = 'Invoke-ApimCostCollector'; Requires = @(); Throttled = $false }
        [pscustomobject]@{ Name = 'LogicApps'; Function = 'Invoke-ApimLogicAppCollector'; Requires = @(); Throttled = $false }
    )
}

function Invoke-ApimCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Config,

        [Parameter(Mandatory)]
        [string] $EnvironmentName,

        [Parameter(Mandatory)]
        [string] $TenantId,

        [string] $ResumeRunPath,

        [ValidateRange(1, 64)]
        [int] $ThrottleLimit = 6,

        [switch] $SkipGit,

        [switch] $IncludeTelemetry,

        [switch] $SkipLogs,

        [switch] $SkipCost
    )

    Test-ApimCountOnlyPrivacy -Config $Config
    if ($ResumeRunPath) {
        Test-ConfigPathLink -Path $ResumeRunPath -Context 'Resume run'
        Test-ConfigPathLink -Path (Join-Path $ResumeRunPath 'manifest.json') -Context 'Resume manifest'
        $IncludeTelemetry = (Get-RunManifest -RunPath $ResumeRunPath).schemaVersion -ceq '1.2'
    }
    if (-not $IncludeTelemetry -and ($SkipLogs -or $SkipCost)) {
        throw 'Telemetry opt-outs cannot change legacy run settings.'
    }
    $checks = @(Get-ApimCollectorRegistry)
    if ($IncludeTelemetry) { $checks += @(Get-ApimTelemetryCollectorRegistry) }
    foreach ($check in $checks) {
        if ($null -eq (Get-Command -Name $check.Function `
                    -CommandType Function -ErrorAction SilentlyContinue)) {
            throw 'A registered collection check is unavailable.'
        }
    }
    $environment = Get-ApimEnvironmentConfig -Config $Config `
        -EnvironmentName $EnvironmentName
    $digest = Get-ApimConfigDigest -Config $Config
    if ($SkipGit) {
        $digest = Get-ApimConfigDigest -Config @{ config = $Config; skipGit = $true }
    }
    if ($IncludeTelemetry) {
        $digest = Get-ApimConfigDigest -Config @{
            config = $Config; skipGit = [bool] $SkipGit
            skipLogs = [bool] $SkipLogs; skipCost = [bool] $SkipCost
        }
    }
    if ($ResumeRunPath) {
        Test-ConfigPathLink -Path $ResumeRunPath -Context 'Resume run'
        Test-ConfigPathLink -Path (Join-Path $ResumeRunPath 'manifest.json') `
            -Context 'Resume manifest'
        $manifest = Get-RunManifest -RunPath $ResumeRunPath
        $expectedPath = Join-Path $Config.Output.Root $manifest.runId
        if ([IO.Path]::GetFullPath($ResumeRunPath) -ne
            [IO.Path]::GetFullPath($expectedPath) -or
            $manifest.schemaVersion -cnotin @('1.1', '1.2') -or
            $manifest.customer -cne $Config.Customer -or
            $manifest.environment -cne $environment.Name -or
            $manifest.subscriptionId -cne $environment.SubscriptionId -or
            $manifest.tenantId -cne $TenantId -or
            $manifest.toolVersion -cne (Get-ApimAssessmentToolVersion)) {
            throw 'Resume identity is incompatible.'
        }
        $context = Read-ApimSmokeOutputJson -RunPath $ResumeRunPath `
            -RelativePath 'restricted/collection-context.json'
        $savedSettings = Get-ApimRunSetting -RunPath $ResumeRunPath
        $expectedSettings = Get-ApimRunSettingSnapshot -RunPath $ResumeRunPath `
            -Config $Config -Environment $environment -SkipLogs:$SkipLogs -SkipCost:$SkipCost `
            -IncludeObservedRoutes:($savedSettings.Settings.schemaVersion -ceq '1.2')
        if (@($context.PSObject.Properties.Name).Count -ne 2 -or
            $context.schemaVersion -cne '1.0' -or
            $context.configSha256 -cne $digest -or
            (Get-ApimConfigDigest -Config $savedSettings.Settings) -cne
            (Get-ApimConfigDigest -Config $expectedSettings) -or
            @($manifest.collectors.name | Sort-Object -Unique).Count -ne
            @($manifest.collectors).Count -or
            @($manifest.collectors | Where-Object {
                    $_.name -cnotin (@($checks.Name) + @('Git'))
                }).Count -gt 0) {
            throw 'Resume context is incompatible.'
        }
        $run = [pscustomobject]@{
            Path = $ResumeRunPath
            RunId = $manifest.runId
        }
    }
    else {
        $run = New-ApimRun -Config $Config -EnvironmentName $EnvironmentName `
            -TenantId $TenantId -Operator LocalOperator -IncludeTelemetry:$IncludeTelemetry -RunId (
                '{0}_{1}' -f [datetimeoffset]::UtcNow.ToString('yyyy-MM-dd_HHmmss'),
                [guid]::NewGuid().ToString('N').Substring(0, 8)
            )
        $null = Write-RunFile -RunPath $run.Path `
            -RelativePath 'restricted/collection-context.json' -InputObject (
                [ordered]@{ schemaVersion = '1.0'; configSha256 = $digest }
            )
        Save-ApimRunSetting -RunPath $run.Path -Config $Config `
            -Environment $environment -SkipLogs:$SkipLogs -SkipCost:$SkipCost `
            -IncludeObservedRoutes:$IncludeTelemetry
    }

    $statuses = @{}
    $changed = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    Set-RunStageStatus -RunPath $run.Path -Stage collect -Status InProgress
    foreach ($check in $checks) {
        $records = @((Get-RunManifest -RunPath $run.Path).collectors |
                Where-Object name -CEQ $check.Name)
        $telemetryCheck = $check.Name -cin @('LogAnalytics', 'Metrics', 'Cost', 'LogicApps')
        $reuse = $ResumeRunPath -and $records.Count -eq 1 -and
            ($records[0].status -ceq 'Completed' -or
                ($telemetryCheck -and $records[0].status -ceq 'Skipped')) -and
            @($check.Requires | Where-Object { $changed.Contains($_) }).Count -eq 0
        if ($reuse) {
            try {
                Test-ApimCollectorOutput -RunPath $run.Path `
                    -Environment $environment -Collector $records[0] `
                    -CompletePolicyInventory
            }
            catch {
                $reuse = $false
                Add-RunWarning -RunPath $run.Path -Message (
                    "$($check.Name) saved output failed validation; recollection required."
                )
            }
        }
        if ($reuse) {
            $statuses[$check.Name] = $records[0].status
            continue
        }
        $null = $changed.Add($check.Name)
        foreach ($stage in @('analyze', 'report')) {
            Set-RunStageStatus -RunPath $run.Path -Stage $stage -Status NotStarted
        }
        $manifest = Get-RunManifest -RunPath $run.Path
        $manifest.modelSafe.build = 'NotStarted'
        $manifest.modelSafe.validation = 'NotRun'
        $manifest.modelSafe.promotion = 'NotStarted'
        $manifest.modelSafe.packageSha256 = $null
        $null = Save-RunManifest -RunPath $run.Path -Manifest $manifest
        if (@($check.Requires | Where-Object {
                    $statuses[$_] -cne 'Completed'
                }).Count -gt 0) {
            Set-RunCollectorStatus -RunPath $run.Path -Name $check.Name `
                -Status Skipped
            Add-RunWarning -RunPath $run.Path `
                -Message "$($check.Name) skipped after a prerequisite failure."
            $statuses[$check.Name] = 'Skipped'
            continue
        }

        $arguments = @{ RunPath = $run.Path; Environment = $environment }
        if ($check.Throttled) { $arguments.ThrottleLimit = $ThrottleLimit }
        Set-RunCollectorStatus -RunPath $run.Path -Name $check.Name `
            -Status InProgress
        try {
            Remove-ApimCollectorOutput -RunPath $run.Path -Name $check.Name
            $null = & $check.Function @arguments
            $records = @((Get-RunManifest -RunPath $run.Path).collectors |
                    Where-Object name -CEQ $check.Name)
            if ($records.Count -ne 1 -or
                ($records[0].status -cne 'Completed' -and
                    -not ($telemetryCheck -and $records[0].status -cin @('Partial', 'Skipped')))) {
                throw 'Collector did not report completion.'
            }
            Test-ApimCollectorOutput -RunPath $run.Path `
                -Environment $environment -Collector $records[0] `
                -CompletePolicyInventory
            $statuses[$check.Name] = $records[0].status
        }
        catch {
            $records = @((Get-RunManifest -RunPath $run.Path).collectors |
                    Where-Object name -CEQ $check.Name)
            $status = if ($records.Count -eq 1 -and
                $records[0].status -cin @('Failed', 'Partial')) {
                $records[0].status
            }
            else { 'Failed' }
            if ($records.Count -ne 1 -or
                $records[0].status -cnotin @('Failed', 'Partial')) {
                Set-RunCollectorStatus -RunPath $run.Path -Name $check.Name `
                    -Status $status -Errors 1
            }
            Add-RunWarning -RunPath $run.Path `
                -Message "$($check.Name) collection failed; inspect the restricted run locally."
            $statuses[$check.Name] = $status
        }
    }
    $gitStatus = Invoke-ApimOptionalGitCollection -RunPath $run.Path `
        -Environment $environment -Resume:([bool] $ResumeRunPath) -SkipGit:$SkipGit
    $status = if (@($checks | Where-Object {
                $statuses[$_.Name] -cne 'Completed' -and
                -not ($_.Name -cin @('LogAnalytics', 'Cost', 'LogicApps') -and $statuses[$_.Name] -ceq 'Skipped')
            }).Count -or
        $gitStatus -cnotin @('Completed', 'Skipped')) {
        'Partial'
    }
    else { 'Completed' }
    Set-RunStageStatus -RunPath $run.Path -Stage collect -Status $status
    Complete-ApimRun -RunPath $run.Path
    return [pscustomobject]@{
        RunId = $run.RunId
        Status = $status
        ExitCode = if ($status -eq 'Completed') { 0 } else { 3 }
        Checks = @(
            foreach ($check in $checks) {
                [pscustomobject]@{
                    Name = $check.Name
                    Status = $statuses[$check.Name]
                    Reused = -not $changed.Contains($check.Name)
                }
            }
        )
    }
}

function Invoke-ApimOptionalGitCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Environment,
        [switch] $Resume,
        [switch] $SkipGit
    )

    if ($SkipGit -or [string]::IsNullOrWhiteSpace($Environment.GitRepoPath)) {
        Set-RunCollectorStatus -RunPath $RunPath -Name Git -Status Skipped
        return 'Skipped'
    }
    try {
        $current = Get-ApimGitPolicySnapshot -Environment $Environment
        $manifest = Get-RunManifest -RunPath $RunPath
        $prior = @($manifest.collectors | Where-Object name -CEQ Git)
        if ($Resume -and $prior.Count -eq 1 -and $prior[0].status -ceq 'Completed') {
            $saved = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath 'git/policyHashes.json'
            Test-ApimGitPolicySnapshot -Snapshot $saved
            if ($prior[0].items -eq @($saved.policies).Count -and
                (Get-ApimLifecycleDigest -Value $current) -ceq (Get-ApimLifecycleDigest -Value $saved)) {
                return 'Completed'
            }
        }
        foreach ($stage in @('analyze', 'report')) {
            Set-RunStageStatus -RunPath $RunPath -Stage $stage -Status NotStarted
        }
        $manifest = Get-RunManifest -RunPath $RunPath
        $manifest.modelSafe.build = 'NotStarted'
        $manifest.modelSafe.validation = 'NotRun'
        $manifest.modelSafe.promotion = 'NotStarted'
        $manifest.modelSafe.packageSha256 = $null
        $null = Save-RunManifest -RunPath $RunPath -Manifest $manifest
        $null = Invoke-ApimGitCollector -RunPath $RunPath -Environment $Environment
        $saved = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath 'git/policyHashes.json'
        Test-ApimGitPolicySnapshot -Snapshot $saved
        if ($saved.commitSha -cne $current.commitSha) { throw 'Git changed during collection.' }
        return 'Completed'
    }
    catch {
        Set-RunCollectorStatus -RunPath $RunPath -Name Git -Status Failed -Errors 1
        foreach ($stage in @('analyze', 'report')) {
            Set-RunStageStatus -RunPath $RunPath -Stage $stage -Status NotStarted
        }
        $manifest = Get-RunManifest -RunPath $RunPath
        $manifest.modelSafe.build = 'NotStarted'
        $manifest.modelSafe.validation = 'NotRun'
        $manifest.modelSafe.promotion = 'NotStarted'
        $manifest.modelSafe.packageSha256 = $null
        $null = Save-RunManifest -RunPath $RunPath -Manifest $manifest
        Add-RunWarning -RunPath $RunPath -Message 'Git collection failed; inspect restricted configuration locally.'
        return 'Failed'
    }
}
