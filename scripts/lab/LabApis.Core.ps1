#Requires -Version 7.4
Set-StrictMode -Version Latest

function Get-LabApiParameterSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Text)
    $config = Read-LabJson $Text
    $schema = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) `
        'infra\live-validation-lab\apis.config.schema.json'
    $schemaValid = Test-Json -Json $Text -SchemaFile $schema -ErrorAction Stop 2>$null
    if (-not $schemaValid) {
        throw 'InvalidApiConfiguration'
    }
    foreach ($name in @('tenantId', 'frontendResourceClientId', 'backendAudienceClientId', 'workerClientId')) {
        if ([guid]$config[$name] -eq [guid]::Empty) { throw 'InvalidApiIdentity' }
    }
    if (@($config.frontendResourceClientId, $config.backendAudienceClientId,
            $config.workerClientId | Select-Object -Unique).Count -ne 3) {
        throw 'ConflictingApiIdentities'
    }
    $privateRanges = @('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16') |
        ForEach-Object { Get-LabIpv4Range $_ }
    $ranges = @{}
    foreach ($name in @('gatewayCidr', 'workerCidr')) {
        $range = Get-LabIpv4Range $config[$name]
        $limit = if ($name -ceq 'gatewayCidr') { 24 } else { 27 }
        if ($range.prefix -lt 16 -or $range.prefix -gt $limit -or
            @($privateRanges | Where-Object { $range.start -ge $_.start -and $range.end -le $_.end }).Count -ne 1) {
            throw 'InvalidApiSourceRange'
        }
        $ranges[$name] = $range
    }
    $gateway = $ranges.gatewayCidr
    $worker = $ranges.workerCidr
    $address = Get-LabIpv4Range "$($config.workerPrivateIp)/32"
    if (($gateway.start -le $worker.end -and $worker.start -le $gateway.end) -or
        $address.start -lt ($worker.start + 4) -or $address.start -ge $worker.end) {
        throw 'InvalidApiSourceAddress'
    }
    $values = [ordered]@{}
    foreach ($name in @('apimName', 'tenantId', 'frontendResourceClientId', 'backendAudienceClientId',
            'workerClientId', 'backendOrigin', 'workerPrivateIp')) {
        $values[$name] = @{ value = $config[$name] }
    }
    foreach ($bound in @('Start', 'End')) {
        [ulong]$number = $gateway[$bound.ToLowerInvariant()]
        $octets = foreach ($shift in @(24, 16, 8, 0)) { ($number -shr $shift) -band 255 }
        $values["gatewayAddress$bound"] = @{ value = $octets -join '.' }
    }
    return [ordered]@{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters = $values
    }
}

function New-LabApiParameterFile {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)][string] $ConfigPath,
        [Parameter(Mandatory)][string] $OutputPath
    )
    $stream = $null
    try {
        $inputFile = Get-LabPrivatePath $ConfigPath
        $outputFile = Get-LabPrivatePath $OutputPath
        $parameters = Get-LabApiParameterSet (Read-LabPrivateText $inputFile)
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json $parameters -Depth 12))
        if (-not $PSCmdlet.ShouldProcess('Private API parameter file', 'Create new file')) {
            return @{ state = 'Failed'; code = 'LAB_API_PARAMETERS_NOT_WRITTEN' }
        }
        $stream = [IO.File]::Open($outputFile, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
        return @{ state = 'ParametersReady'; code = 'LAB_API_PARAMETERS_READY' }
    }
    catch {
        # Private parser/filesystem details must not reach model-visible output.
        return @{ state = 'Failed'; code = 'LAB_API_PARAMETERS_FAILED' }
    }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
}
