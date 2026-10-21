#Requires -Version 7.4
Set-StrictMode -Version Latest

function Get-LabWorkerParameterSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Text)
    $config = Read-LabJson $Text
    $schema = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) `
        'infra\live-validation-lab\worker.config.schema.json'
    $schemaValid = Test-Json -Json $Text -SchemaFile $schema -ErrorAction Stop 2>$null
    if (-not $schemaValid) {
        throw 'InvalidWorkerConfiguration'
    }
    $subnet = Get-LabIpv4Range $config.workerCidr
    $address = Get-LabIpv4Range "$($config.workerPrivateIp)/32"
    $private = @('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16') |
        ForEach-Object { Get-LabIpv4Range $_ }
    if ($subnet.prefix -lt 16 -or $subnet.prefix -gt 27 -or
        @($private | Where-Object { $subnet.start -ge $_.start -and $subnet.end -le $_.end }).Count -ne 1 -or
        $address.start -lt ($subnet.start + 4) -or $address.start -ge $subnet.end) {
        throw 'InvalidWorkerAddress'
    }
    $stream = [IO.MemoryStream]::new([Convert]::FromBase64String($config.sshPublicKey.Split(' ')[1]))
    $rsa = [Security.Cryptography.RSA]::Create()
    try {
        $parts = [System.Collections.Generic.List[byte[]]]::new()
        for ($index = 0; $index -lt 3; $index++) {
            $lengthBytes = [byte[]]::new(4)
            if ($stream.Read($lengthBytes, 0, 4) -ne 4) { throw 'InvalidWorkerPublicKey' }
            if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($lengthBytes) }
            $length = [BitConverter]::ToInt32($lengthBytes)
            if ($length -lt 1 -or $length -gt 513) { throw 'InvalidWorkerPublicKey' }
            $part = [byte[]]::new($length)
            if ($stream.Read($part, 0, $length) -ne $length) { throw 'InvalidWorkerPublicKey' }
            $parts.Add($part)
        }
        if ($stream.Position -ne $stream.Length -or [Text.Encoding]::ASCII.GetString($parts[0]) -cne 'ssh-rsa') {
            throw 'InvalidWorkerPublicKey'
        }
        $parameters = [Security.Cryptography.RSAParameters]::new()
        $parameters.Exponent = $parts[1]
        $modulus = $parts[2]
        if ($modulus[0] -eq 0) { $modulus = [byte[]]$modulus[1..($modulus.Length - 1)] }
        $parameters.Modulus = $modulus
        $rsa.ImportParameters($parameters)
        if ($rsa.KeySize -lt 2048 -or $rsa.KeySize -gt 4096) { throw 'InvalidWorkerPublicKey' }
    }
    finally { $rsa.Dispose(); $stream.Dispose() }
    $values = [ordered]@{}
    foreach ($name in @('labId', 'location', 'vnetName', 'workerVmName', 'workerPrivateIp',
            'sshPublicKey', 'vmSize', 'ubuntuImageVersion', 'availabilityZone')) {
        $values[$name] = @{ value = $config[$name] }
    }
    return [ordered]@{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters = $values
    }
}

function New-LabWorkerParameterFile {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)][string] $ConfigPath,
        [Parameter(Mandatory)][string] $OutputPath
    )
    $stream = $null
    try {
        $inputFile = Get-LabPrivatePath $ConfigPath
        $outputFile = Get-LabPrivatePath $OutputPath
        $parameters = Get-LabWorkerParameterSet (Read-LabPrivateText $inputFile)
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json $parameters -Depth 12))
        if (-not $PSCmdlet.ShouldProcess('Private worker parameter file', 'Create new file')) {
            return @{ state = 'Failed'; code = 'LAB_WORKER_PARAMETERS_NOT_WRITTEN' }
        }
        $stream = [IO.File]::Open($outputFile, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
        return @{ state = 'ParametersReady'; code = 'LAB_WORKER_PARAMETERS_READY' }
    }
    catch {
        # Private inputs and parser/filesystem exception text must not reach model-visible output.
        return @{ state = 'Failed'; code = 'LAB_WORKER_PARAMETERS_FAILED' }
    }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
}
