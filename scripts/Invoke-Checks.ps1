#Requires -Version 7.4
[CmdletBinding()]
param(
    [string] $TestPath = 'tests',
    [string] $OutputDirectory = 'artifacts'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$dependencies = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'DevDependencies.psd1')
foreach ($name in $dependencies.Keys) {
    if ($name -in @('KustoLanguage', 'Bicep')) { continue }
    if ($name -eq 'ImportExcel') {
        Import-Module -Name $name -RequiredVersion $dependencies[$name] `
            -ErrorAction Stop 3>$null
    }
    else {
        Import-Module -Name $name -RequiredVersion $dependencies[$name] `
            -ErrorAction Stop
    }
}

$lintTargets = @(
    'ApimAssessment.psd1', 'ApimAssessment.psm1', 'config/sample.psd1',
    'Invoke-ApimCollect.ps1', 'Invoke-ApimAnalyze.ps1',
    'Invoke-ApimReport.ps1', 'Invoke-ApimAssessment.ps1',
    'Compare-ApimRun.ps1',
    'scripts', 'src', 'rules', 'tests'
)
$diagnostics = @(
    foreach ($target in $lintTargets) {
        Invoke-ScriptAnalyzer -Path (Join-Path $repoRoot $target) -Recurse `
            -Severity Error, Warning
    }
)
if ($diagnostics.Count -gt 0) {
    $diagnostics | Format-Table ScriptName, Line, RuleName, Message -AutoSize |
        Out-String | Write-Output
    throw "PSScriptAnalyzer reported $($diagnostics.Count) error(s) or warning(s)."
}

if (-not [System.IO.Path]::IsPathRooted($TestPath)) {
    $TestPath = Join-Path $repoRoot $TestPath
}
if (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot $OutputDirectory
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$configuration = New-PesterConfiguration
$configuration.Run.Path = $TestPath
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'
$configuration.TestResult.Enabled = $true
$configuration.TestResult.OutputPath = Join-Path $OutputDirectory 'TestResults.xml'
$configuration.TestResult.OutputFormat = 'NUnitXml'
$result = Invoke-Pester -Configuration $configuration

if ($result.Result -ne 'Passed') {
    throw "Pester did not pass: $($result.Result); $($result.FailedCount) failed test(s)."
}
