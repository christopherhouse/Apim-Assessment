#Requires -Version 7.4
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string] $Config = (Join-Path (Join-Path $HOME 'apim-smoke-private') 'smoke.psd1'),

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $Environment,

    [switch] $MicrosoftOwnedTestEnvironment,

    [ValidateRange(1, 64)]
    [int] $ThrottleLimit = 6
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

. (Join-Path $PSScriptRoot 'Format-ApimSmokeConsoleLine.ps1')
$useColor = -not [Console]::IsOutputRedirected -and
    -not (Test-Path Env:NO_COLOR) -and $Host.UI.SupportsVirtualTerminal

if (-not $MicrosoftOwnedTestEnvironment) {
    [Console]::Error.WriteLine('SMOKE_CONFIG_ERROR: acknowledge a Microsoft-owned test environment.')
    exit 1
}

Write-ApimSmokeConsoleLine -Line (Format-ApimSmokeConsoleLine `
        -State Header -Color:$useColor) -Color:$useColor
Write-ApimSmokeConsoleLine -Line (Format-ApimSmokeConsoleLine `
        -State Preparing -Name 'Private configuration' `
        -Color:$useColor) -Color:$useColor -Transient:$useColor
$repoRoot = Split-Path $PSScriptRoot -Parent
try {
    $module = Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') `
        -Force -PassThru -ErrorAction Stop
    $prepared = & $module {
        param($configPath, $environmentName, $repositoryPath)

        Test-ConfigPathLink -Path (
            [System.IO.Path]::GetFullPath($configPath)
        ) -Context 'Smoke configuration'
        if (Test-ConfigPathOverlap -First (
                [System.IO.Path]::GetFullPath($configPath)
            ) -Second $repositoryPath) {
            throw 'Smoke configuration must be outside the repository.'
        }
        $configuration = Get-Config -Path $configPath
        if ((Test-ConfigPathOverlap -First $configuration.Output.Root `
                    -Second $repositoryPath) -or
            (Test-ConfigPathOverlap -First $configuration.Output.ModelSafeRoot `
                    -Second $repositoryPath)) {
            throw 'Smoke output roots must be outside the repository.'
        }
        [pscustomobject]@{
            Config = $configuration
            Target = Get-ApimEnvironmentConfig -Config $configuration `
                -EnvironmentName $environmentName
        }
    } $Config $Environment $repoRoot 2>$null 3>$null 4>$null 5>$null 6>$null
}
catch {
    if ($useColor) { [Console]::Out.WriteLine() }
    [Console]::Error.WriteLine('SMOKE_CONFIG_ERROR: check the private configuration and output locations.')
    exit 1
}

Write-ApimSmokeConsoleLine -Line (Format-ApimSmokeConsoleLine `
        -State Ready -Name 'Private configuration' `
        -Color:$useColor) -Color:$useColor -ReplaceTransient:$useColor
Write-ApimSmokeConsoleLine -Line (Format-ApimSmokeConsoleLine `
        -State Preparing -Name 'Az modules and context' `
        -Color:$useColor) -Color:$useColor -Transient:$useColor
try {
    Import-Module Az.Accounts -ErrorAction Stop -WarningAction SilentlyContinue `
        -InformationAction SilentlyContinue
    Import-Module Az.ResourceGraph -ErrorAction Stop `
        -WarningAction SilentlyContinue -InformationAction SilentlyContinue
    $context = Get-AzContext -ErrorAction Stop 2>$null 3>$null 4>$null 5>$null 6>$null
    $tenantId = & $module {
        param($activeContext, $targetSubscriptionId)
        Test-ApimSmokeContext -Context $activeContext `
            -SubscriptionId $targetSubscriptionId
    } $context $prepared.Target.SubscriptionId
}
catch {
    if ($useColor) { [Console]::Out.WriteLine() }
    [Console]::Error.WriteLine('SMOKE_AUTH_ERROR: verify Az modules and the selected Azure context.')
    exit 2
}

Write-ApimSmokeConsoleLine -Line (Format-ApimSmokeConsoleLine `
        -State Ready -Name 'Az modules and context' `
        -Color:$useColor) -Color:$useColor -ReplaceTransient:$useColor
Write-ApimSmokeConsoleLine -Line (Format-ApimSmokeConsoleLine `
        -State Preparing -Name 'Restricted run' `
        -Color:$useColor) -Color:$useColor -Transient:$useColor
$formatSmokeLine = ${function:Format-ApimSmokeConsoleLine}
$writeSmokeLine = ${function:Write-ApimSmokeConsoleLine}
$onProgress = {
    param($update)

    $parameters = @{
        State = if ($update.Phase -eq 'Running') {
            'Running'
        }
        else {
            $update.Status
        }
        Name = $update.Name
        Index = $update.Index
        Total = $update.Total
        Color = $useColor
    }
    if ($update.FailureCode) {
        $parameters.FailureCode = $update.FailureCode
    }
    $running = $update.Phase -eq 'Running'
    $replace = $useColor -and (
        ($running -and $update.Index -eq 1) -or
        (-not $running -and $update.Status -ne 'Skipped')
    )
    & $writeSmokeLine -Line (& $formatSmokeLine @parameters) `
        -Color:$useColor -Transient:($running -and $useColor) `
        -ReplaceTransient:$replace
}.GetNewClosure()
try {
    $result = & $module {
        param($configuration, $environmentName, $tenantId, $throttle,
            $progressCallback)

        Invoke-ApimSmoke -Config $configuration `
            -EnvironmentName $environmentName -TenantId $tenantId `
            -ThrottleLimit $throttle -OnProgress $progressCallback
    } $prepared.Config $Environment $tenantId $ThrottleLimit $onProgress `
        2>$null 3>$null 4>$null 5>$null 6>$null
}
catch {
    if ($useColor) { [Console]::Out.WriteLine() }
    [Console]::Error.WriteLine('SMOKE_RUN_ERROR: inspect the restricted run folder locally.')
    exit 4
}

try {
    & $module {
        param($runPath, $smokeResult, $targetEnvironment)
        Test-ApimSmokeOutput -RunPath $runPath -Result $smokeResult `
            -Environment $targetEnvironment
    } (Join-Path $prepared.Config.Output.Root $result.RunId) `
        $result $prepared.Target 2>$null 3>$null 4>$null 5>$null 6>$null
}
catch {
    [Console]::Error.WriteLine('SMOKE_OUTPUT_INVALID: inspect the restricted run locally.')
    exit 4
}
[Console]::Out.WriteLine('SMOKE_OUTPUT_VALID: manifest and completed collector files verified.')
Write-ApimSmokeConsoleLine -Line (Format-ApimSmokeConsoleLine `
        -State Summary -SummaryStatus $result.Status `
        -CompletedCount @($result.Checks |
            Where-Object Status -EQ Completed).Count `
        -Total $result.Checks.Count `
        -Color:$useColor) -Color:$useColor
if ($result.Status -ne 'Completed') {
    exit 3
}
