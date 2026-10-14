#Requires -Version 7.4

Set-StrictMode -Version Latest

function Test-ApimRuntimeCapability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Options
    )

    foreach ($name in @('SkipCost', 'SkipLogs', 'SkipGit')) {
        if (@($Options.Keys) -ccontains $name -and -not $Options[$name]) {
            throw 'CAPABILITY_UNAVAILABLE'
        }
    }
    if (@($Options.Keys) -ccontains 'PreviousReport') {
        throw 'CAPABILITY_UNAVAILABLE'
    }
}

function Set-ApimStageFailure {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [ValidateSet('analyze', 'report')]
        [string] $Stage
    )

    if (-not $PSCmdlet.ShouldProcess($RunPath, "Record $Stage failure")) {
        return $false
    }
    try {
        Test-ConfigPathLink -Path $RunPath -Context 'Failed run'
        Test-ConfigPathLink -Path (Join-Path $RunPath 'manifest.json') `
            -Context 'Failed run manifest'
        Set-RunStageStatus -RunPath $RunPath -Stage $Stage -Status Failed
        Add-RunWarning -RunPath $RunPath `
            -Message "$Stage failed; inspect saved inputs locally."
        return $true
    }
    catch {
        return $false
    }
}

function Invoke-ApimCollect {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Config,

        [Parameter(Mandatory)]
        [string] $Environment,

        [string] $Resume,

        [ValidateRange(1, 64)]
        [int] $ThrottleLimit = 6,

        [switch] $SkipCost,
        [switch] $SkipLogs,
        [switch] $SkipGit
    )

    try {
        Test-ApimRuntimeCapability -Options $PSBoundParameters
        $settings = Get-Config -Path $Config
        $target = Get-ApimEnvironmentConfig -Config $settings `
            -EnvironmentName $Environment
        if ($settings.Edge.Provider -cne 'Cloudflare' -or
            $settings.Edge.Mode -cne 'AssumedReachable' -or
            @($settings.AnalysisPackage.UsageBuckets).Count -ne 6) {
            throw 'CAPABILITY_UNAVAILABLE'
        }
    }
    catch {
        return [pscustomobject]@{
            RunId = $null; Status = 'Failed'; ExitCode = 1
            ErrorCode = 'CONFIG_OR_CAPABILITY_ERROR'
        }
    }
    try {
        Import-Module Az.Accounts -ErrorAction Stop 3>$null 4>$null 5>$null 6>$null
        Import-Module Az.ResourceGraph -ErrorAction Stop 3>$null 4>$null 5>$null 6>$null
        $context = Get-AzContext -ErrorAction Stop
        $tenantId = Test-ApimSmokeContext -Context $context `
            -SubscriptionId $target.SubscriptionId
    }
    catch {
        return [pscustomobject]@{
            RunId = $null; Status = 'Failed'; ExitCode = 2; ErrorCode = 'AUTH_ERROR'
        }
    }
    try {
        return Invoke-ApimCollection -Config $settings `
            -EnvironmentName $Environment -TenantId $tenantId `
            -ResumeRunPath $Resume -ThrottleLimit $ThrottleLimit
    }
    catch {
        return [pscustomobject]@{
            RunId = $null; Status = 'Failed'; ExitCode = 4; ErrorCode = 'COLLECTION_STATE_FAILED'
        }
    }
}

function Invoke-ApimAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Config,

        [Parameter(Mandatory)]
        [string] $Environment,

        [ValidateSet('All', 'Collect')]
        [string] $Stage = 'All',

        [string] $Resume,

        [ValidateRange(1, 64)]
        [int] $ThrottleLimit = 6,

        [switch] $SkipCost,
        [switch] $SkipLogs,
        [switch] $SkipGit,

        [string] $PreviousReport
    )

    try {
        Test-ApimRuntimeCapability -Options $PSBoundParameters
    }
    catch {
        return [pscustomobject]@{
            RunId = $null; Status = 'Failed'; ExitCode = 1; ErrorCode = 'CAPABILITY_UNAVAILABLE'
        }
    }
    $collection = Invoke-ApimCollect -Config $Config -Environment $Environment `
        -Resume $Resume -ThrottleLimit $ThrottleLimit
    if ($collection.ExitCode -notin @(0, 3) -or $Stage -eq 'Collect') {
        return $collection
    }
    try {
        $settings = Get-Config -Path $Config
        $runPath = Join-Path $settings.Output.Root $collection.RunId
        $analysis = Invoke-ApimAnalyze -RunFolder $runPath
        if ($analysis.ExitCode -ne 0) {
            return [pscustomobject]@{
                RunId = $collection.RunId; Status = 'Failed'
                ExitCode = 4; ErrorCode = 'ANALYSIS_FAILED'
            }
        }
        $report = Invoke-ApimReport -RunFolder $runPath
        if ($report.ExitCode -ne 0) {
            return [pscustomobject]@{
                RunId = $collection.RunId; Status = 'Failed'
                ExitCode = 4; ErrorCode = 'REPORT_FAILED'
            }
        }
        return [pscustomobject]@{
            RunId = $collection.RunId; Status = $collection.Status
            ExitCode = $collection.ExitCode; ErrorCode = $null
        }
    }
    catch {
        return [pscustomobject]@{
            RunId = $collection.RunId; Status = 'Failed'
            ExitCode = 4; ErrorCode = 'RUN_STATE_FAILED'
        }
    }
}
