#Requires -Version 7.4
[CmdletBinding()]
param(
    [string] $ConfigPath,
    [string] $OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try {
    . (Join-Path $PSScriptRoot 'LabBootstrap.Core.ps1')
    . (Join-Path $PSScriptRoot 'LabFoundation.Core.ps1')
    . (Join-Path $PSScriptRoot 'LabWorker.Core.ps1')
    $result = New-LabWorkerParameterFile $ConfigPath $OutputPath -Confirm:$false
    Write-Output $result.code
    if ($result.state -ceq 'ParametersReady') { exit 0 }
    exit 1
}
catch {
    Write-Output 'LAB_WORKER_PARAMETERS_FAILED'
    exit 1
}
