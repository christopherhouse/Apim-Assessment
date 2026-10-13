#Requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $Config,

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

if (-not $MicrosoftOwnedTestEnvironment) {
    [Console]::Error.WriteLine('SMOKE_CONFIG_ERROR: acknowledge a Microsoft-owned test environment.')
    exit 1
}

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
    [Console]::Error.WriteLine('SMOKE_CONFIG_ERROR: check the private configuration and output locations.')
    exit 1
}

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
    [Console]::Error.WriteLine('SMOKE_AUTH_ERROR: verify Az modules and the selected Azure context.')
    exit 2
}

try {
    $result = & $module {
        param($configuration, $environmentName, $tenantId, $throttle)

        Invoke-ApimSmoke -Config $configuration `
            -EnvironmentName $environmentName -TenantId $tenantId `
            -ThrottleLimit $throttle
    } $prepared.Config $Environment $tenantId $ThrottleLimit `
        2>$null 3>$null 4>$null 5>$null 6>$null

    foreach ($check in $result.Checks) {
        [Console]::Out.WriteLine("$($check.Name): $($check.Status)")
    }
    [Console]::Out.WriteLine("Collection smoke: $($result.Status)")
    if ($result.Status -ne 'Completed') {
        exit 3
    }
}
catch {
    [Console]::Error.WriteLine('SMOKE_RUN_ERROR: inspect the restricted run folder locally.')
    exit 4
}
