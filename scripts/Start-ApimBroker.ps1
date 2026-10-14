#Requires -Version 7.4
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'The stdio wire requires exact JSON lines, never host-formatted pipeline output.')]
[CmdletBinding()]
param([Parameter(Mandatory)][string] $OperatorConfigPath)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'ApimAssessment.psd1') `
        -Force *>$null
    $module = Get-Module ApimAssessment
    $context = & $module { param($Path) Get-ApimBrokerContext -OperatorConfigPath $Path } $OperatorConfigPath
}
catch {
    [Console]::Error.WriteLine('BROKER_STARTUP_REJECTED')
    exit 1
}
$initialized = $false
$ready = $false
while ($null -ne ($line = [Console]::ReadLine())) {
    $id = $null
    try {
        $request = & $module { param($Text) ConvertFrom-ApimBrokerJson -Json $Text } $line
        if ($request -isnot [Collections.IDictionary] -or
            $request.jsonrpc -cne '2.0' -or $request.method -isnot [string] -or
            @($request.Keys | Where-Object { $_ -cnotin @('jsonrpc', 'id', 'method', 'params') }).Count -gt 0) {
            throw 'INVALID_REQUEST'
        }
        if ($request.Contains('id')) {
            if ($request.id -isnot [long] -and $request.id -isnot [int] -and
                ($request.id -isnot [string] -or $request.id -cnotmatch '^[A-Za-z0-9_-]{1,64}\z')) { throw 'INVALID_REQUEST' }
            $id = $request.id
        }
        if ($request.method -ceq 'notifications/initialized' -and $initialized -and $null -eq $id) {
            if ($request.Contains('params') -and $request.params.Count -ne 0) { throw 'INVALID_REQUEST' }
            $ready = $true
            continue
        }
        if ($null -eq $id) { continue }
        $result = switch -CaseSensitive ($request.method) {
            initialize {
                if ($initialized -or $request.params.protocolVersion -cne '2025-11-25' -or
                    @($request.params.Keys | Where-Object { $_ -cnotin @('protocolVersion', 'capabilities', 'clientInfo') }).Count -gt 0 -or
                    $request.params.capabilities -isnot [Collections.IDictionary] -or
                    $request.params.clientInfo -isnot [Collections.IDictionary] -or
                    $request.params.clientInfo.name -isnot [string] -or
                    $request.params.clientInfo.version -isnot [string]) { throw 'INVALID_REQUEST' }
                $initialized = $true
                @{ protocolVersion = '2025-11-25'; capabilities = @{ tools = @{ listChanged = $false } }
                    serverInfo = @{ name = 'apim-assessment'; version = $module.Version.ToString() } }
            }
            ping {
                if (-not $initialized -or ($request.Contains('params') -and $request.params.Count -ne 0)) { throw 'INVALID_REQUEST' }
                @{}
            }
            'tools/list' {
                if (-not $ready -or ($request.Contains('params') -and $request.params.Count -ne 0)) { throw 'INVALID_REQUEST' }
                @{ tools = @(& $module { Get-ApimBrokerTool }) }
            }
            'tools/call' {
                if (-not $ready -or
                    $request.params -isnot [Collections.IDictionary] -or
                    $request.params.name -isnot [string] -or
                    $request.params.arguments -isnot [Collections.IDictionary] -or
                    @($request.params.Keys | Where-Object { $_ -cnotin @('name', 'arguments') }).Count -gt 0) { throw 'INVALID_REQUEST' }
                try {
                    $toolResult = & $module {
                        param($Context, $Name, $Arguments)
                        $result = Invoke-ApimBrokerWorker -Context $Context -Name $Name -Arguments $Arguments
                        Assert-ApimBrokerResult -Name $Name -Result $result -Context $Context -Arguments $Arguments
                        return $result
                    } $context $request.params.name $request.params.arguments
                    @{ content = @(@{ type = 'text'; text = (ConvertTo-Json -InputObject $toolResult -Depth 32 -Compress) }); isError = $false }
                }
                catch {
                    @{ content = @(@{ type = 'text'; text = '{"errorCode":"BROKER_OPERATION_REJECTED"}' }); isError = $true }
                }
            }
            default { throw 'METHOD_NOT_FOUND' }
        }
        $response = @{ jsonrpc = '2.0'; id = $id; result = $result }
    }
    catch {
        if ($null -eq $id) {
            $response = @{ jsonrpc = '2.0'; id = $null; error = @{ code = -32600; message = 'BROKER_REQUEST_REJECTED' } }
        }
        else {
            $code = if ($_.Exception.Message -ceq 'METHOD_NOT_FOUND') { -32601 } else { -32602 }
            $response = @{ jsonrpc = '2.0'; id = $id; error = @{ code = $code; message = 'BROKER_REQUEST_REJECTED' } }
        }
    }
    [Console]::WriteLine((ConvertTo-Json -InputObject $response -Depth 40 -Compress))
}
