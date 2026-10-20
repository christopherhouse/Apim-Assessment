#Requires -Version 7.4
[CmdletBinding()]
param(
    [string] $ConfigPath,
    [string] $OutputPath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    . (Join-Path $PSScriptRoot 'LabBootstrap.Core.ps1')
    . (Join-Path $PSScriptRoot 'LabFoundation.Core.ps1')
    $result = New-LabFoundationParameterFile -ConfigPath $ConfigPath -OutputPath $OutputPath `
        2>$null 3>$null 4>$null 5>$null 6>$null
    [Console]::Out.WriteLine($result.code)
    if ($result.state -ceq 'ParametersReady') { exit 0 }
    exit 1
}
catch {
    [Console]::Out.WriteLine('LAB_FOUNDATION_PARAMETERS_FAILED')
    exit 1
}
