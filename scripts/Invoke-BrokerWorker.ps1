#Requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $RequestPath,
    [Parameter(Mandatory)][string] $ResponsePath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$response = @{ success = $false }
try {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'ApimAssessment.psd1') -Force
    $request = Get-Content -LiteralPath $RequestPath -Raw |
        ConvertFrom-Json -AsHashtable -Depth 64
    $module = Get-Module ApimAssessment
    & $module {
        param($Request, $Response)
        $Response.result = Invoke-ApimBrokerTool -Context $Request.context `
            -Name $Request.name -Arguments $Request.arguments `
            2>$null 3>$null 4>$null 5>$null 6>$null
        $Response.runs = $Request.context.runs
        $Response.success = $true
    } $request $response
}
catch {
    $response = @{ success = $false }
}
[IO.File]::WriteAllText($ResponsePath, (ConvertTo-Json -InputObject $response -Depth 64 -Compress),
    [Text.UTF8Encoding]::new($false))
