#Requires -Version 7.4
Set-StrictMode -Version Latest

function Get-LabIpv4Range {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Cidr)
    if ($Cidr -cnotmatch '^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})/(0|[1-9][0-9]?)$') {
        throw 'InvalidLabCidr'
    }
    $parts = $Cidr.Split('/')
    [int]$prefix = $parts[1]
    if ($prefix -gt 32) { throw 'InvalidLabCidr' }
    [ulong]$address = 0
    foreach ($octet in $parts[0].Split('.')) {
        if ([int]$octet -gt 255) { throw 'InvalidLabCidr' }
        $address = ($address * 256) + [ulong]$octet
    }
    [ulong]$size = [math]::Pow(2, 32 - $prefix)
    if (($address % $size) -ne 0) { throw 'NonCanonicalLabCidr' }
    return @{ start = $address; end = $address + $size - 1; prefix = $prefix }
}

function Get-LabFoundationParameterSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Text)
    $config = Read-LabJson $Text
    $schema = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) `
        'infra\live-validation-lab\foundation.config.schema.json'
    $schemaValid = Test-Json -Json $Text -SchemaFile $schema -ErrorAction Stop 2>$null
    if (-not $schemaValid) {
        throw 'InvalidFoundationConfiguration'
    }
    if ($config.names.keyVault.Contains('--')) { throw 'InvalidFoundationName' }
    $vnet = Get-LabIpv4Range $config.network.vnetCidr
    $privateRanges = @('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16') |
        ForEach-Object { Get-LabIpv4Range $_ }
    if ($vnet.prefix -lt 16 -or $vnet.prefix -gt 22 -or
        @($privateRanges | Where-Object { $vnet.start -ge $_.start -and $vnet.end -le $_.end }).Count -ne 1) {
        throw 'InvalidLabVnet'
    }
    $subnets = [System.Collections.Generic.List[object]]::new()
    $limits = [ordered]@{ gatewayCidr = 24; apimCidr = 26; workerCidr = 27; privateEndpointCidr = 27 }
    foreach ($name in $limits.Keys) {
        $range = Get-LabIpv4Range $config.network[$name]
        if ($range.start -lt $vnet.start -or $range.end -gt $vnet.end -or $range.prefix -gt $limits[$name]) {
            throw 'InvalidLabSubnet'
        }
        foreach ($other in $subnets) {
            if ($range.start -le $other.end -and $other.start -le $range.end) { throw 'OverlappingLabSubnet' }
        }
        $subnets.Add($range)
    }
    $nonPublic = @(
        '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16',
        '172.16.0.0/12', '192.168.0.0/16', '198.18.0.0/15', '224.0.0.0/4', '240.0.0.0/4'
    ) | ForEach-Object { Get-LabIpv4Range $_ }
    foreach ($name in @('approvedCallerCidrs', 'workerHttpsEgressCidrs')) {
        foreach ($cidr in $config.network[$name]) {
            $range = Get-LabIpv4Range $cidr
            if (@($nonPublic | Where-Object { $range.start -le $_.end -and $_.start -le $range.end }).Count -gt 0) {
                throw 'NonPublicLabInternetRange'
            }
        }
    }
    $parameters = [ordered]@{}
    foreach ($name in @('labId', 'location', 'names', 'publisherEmail', 'publisherName', 'network', 'observability')) {
        $parameters[$name] = @{ value = $config[$name] }
    }
    return [ordered]@{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters = $parameters
    }
}

function New-LabFoundationParameterFile {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)][string] $ConfigPath,
        [Parameter(Mandatory)][string] $OutputPath
    )
    $stream = $null
    try {
        $inputFile = Get-LabPrivatePath $ConfigPath
        $outputFile = Get-LabPrivatePath $OutputPath
        $parameters = Get-LabFoundationParameterSet (Read-LabPrivateText $inputFile)
        $text = ConvertTo-Json $parameters -Depth 20
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($text)
        if (-not $PSCmdlet.ShouldProcess('Private lab parameter file', 'Create new file')) {
            return @{ state = 'Failed'; code = 'LAB_FOUNDATION_PARAMETERS_NOT_WRITTEN' }
        }
        $stream = [System.IO.File]::Open($outputFile, [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
        return @{ state = 'ParametersReady'; code = 'LAB_FOUNDATION_PARAMETERS_READY' }
    }
    catch {
        # Private input, filesystem and parser exception details must never reach a model.
        return @{ state = 'Failed'; code = 'LAB_FOUNDATION_PARAMETERS_FAILED' }
    }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
}
