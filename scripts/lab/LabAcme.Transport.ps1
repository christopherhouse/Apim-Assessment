#Requires -Version 7.4
Set-StrictMode -Version Latest

function Import-LabAcmeModule {
    [CmdletBinding()]
    param([switch] $Client)
    $file = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) `
        'infra/live-validation-lab/acme.dependencies.psd1'
    $pins = Import-PowerShellDataFile $file
    $names = if ($Client) { @('Posh-ACME') } else { @('Az.Accounts', 'Az.Dns', 'Az.KeyVault') }
    foreach ($name in $names) {
        Import-Module -Name $name -RequiredVersion $pins[$name] -Global -ErrorAction Stop
    }
}

function Connect-LabAcmeIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Config)
    foreach ($name in @('MSI_ENDPOINT', 'IDENTITY_ENDPOINT', 'IDENTITY_HEADER', 'MSI_SECRET')) {
        Assert-LabCondition ([string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name)))
    }
    $null = Disable-AzContextAutosave -Scope Process -ErrorAction Stop
    $null = Connect-AzAccount -Identity -Tenant $Config.tenantId -Subscription $Config.subscriptionId `
        -Scope Process -SkipContextPopulation -ErrorAction Stop
    return Get-AzContext -ErrorAction Stop
}

function Assert-LabAcmeContext {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Session)
    $context = Get-AzContext -ErrorAction Stop
    Assert-LabCondition ($context.Environment.Name -ceq 'AzureCloud' -and
        $context.Account.Type -ceq 'ManagedService' -and
        $context.Tenant.Id -ceq $Session.config.tenantId -and
        $context.Subscription.Id -ceq $Session.config.subscriptionId -and
        $context.Account.Id -ceq $Session.context.Account.Id)
}

function Get-LabAcmeArmResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Session,
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][string] $ApiVersion
    )
    Assert-LabAcmeContext $Session
    $response = Invoke-AzRestMethod -Method GET -Path "$($Id)?api-version=$ApiVersion" `
        -DefaultProfile $Session.context -ErrorAction Stop
    Assert-LabCondition ($response.StatusCode -eq 200)
    return Read-LabJson $response.Content
}

function Get-LabAcmeResourceSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Session)
    $config = $Session.config
    $prefix = "/subscriptions/$($config.subscriptionId)/resourceGroups/$($config.labResourceGroup)/providers"
    $vmId = "$prefix/Microsoft.Compute/virtualMachines/$($config.workerVmName)"
    $vaultId = "$prefix/Microsoft.KeyVault/vaults/$($config.keyVaultName)"
    $zoneId = "$prefix/Microsoft.Network/dnsZones/$($config.challengeZoneName)"
    $vm = Get-LabAcmeArmResource $Session $vmId '2024-07-01'
    Assert-LabOwnedResource $vm $vmId 'Microsoft.Compute/virtualMachines' $config
    Assert-LabCondition ($vm.identity.type -cin @('SystemAssigned', 'SystemAssigned, UserAssigned') -and
        $vm.identity.tenantId -ceq $config.tenantId -and
        $vm.identity.principalId -cmatch '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$')
    # The managed identity account ID can be a client ID; bind to the VM using IMDS.
    $identity = Get-LabAcmeInstanceIdentity
    Assert-LabCondition ($identity -ieq $vmId)
    $vault = Get-LabAcmeArmResource $Session $vaultId '2023-07-01'
    Assert-LabOwnedResource $vault $vaultId 'Microsoft.KeyVault/vaults' $config
    Assert-LabCondition ($vault.properties.tenantId -ceq $config.tenantId -and
        $vault.properties.enableRbacAuthorization -eq $true -and
        $vault.properties.vaultUri -ceq "https://$($config.keyVaultName).vault.azure.net/")
    $zone = Get-LabAcmeArmResource $Session $zoneId '2018-05-01'
    Assert-LabOwnedResource $zone $zoneId 'Microsoft.Network/dnsZones' $config -GlobalLocation
    Assert-LabCondition ($zone.properties.zoneType -ceq 'Public' -and @($zone.properties.nameServers).Count -ge 2)
    return @{
        vmId = $vmId; vmPrincipalId = $vm.identity.principalId; vaultId = $vaultId
        zoneId = $zoneId; nameServers = @($zone.properties.nameServers | Sort-Object)
    }
}

function Get-LabAcmeInstanceIdentity {
    [CmdletBinding()]
    param()
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.UseProxy = $false; $handler.AllowAutoRedirect = $false
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(3)
    try {
        $null = $client.DefaultRequestHeaders.Add('Metadata', 'true')
        $text = $client.GetStringAsync(
            'http://169.254.169.254/metadata/instance/compute/resourceId?api-version=2021-02-01&format=text'
        ).GetAwaiter().GetResult()
        Assert-LabCondition ($text.Length -le 1024)
        return $text.Trim()
    }
    finally { $client.Dispose(); $handler.Dispose() }
}

function Resolve-LabAcmePublicName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)][int] $Type)
    Assert-LabCondition ($Name -cmatch '^(?:_acme-challenge\.)?[a-z0-9][a-z0-9.-]{1,252}$' -and $Type -in @(2, 5))
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.UseProxy = $false; $handler.AllowAutoRedirect = $false
    $client = [Net.Http.HttpClient]::new($handler)
    $cancel = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(3))
    $response = $null
    $stream = $null
    try {
        $uri = "https://dns.google/resolve?name=$([uri]::EscapeDataString($Name))&type=$Type&edns_client_subnet=0.0.0.0/0"
        $response = $client.GetAsync($uri, [Net.Http.HttpCompletionOption]::ResponseHeadersRead,
            $cancel.Token).GetAwaiter().GetResult()
        Assert-LabCondition ([int]$response.StatusCode -eq 200 -and
            ($null -eq $response.Content.Headers.ContentLength -or $response.Content.Headers.ContentLength -le 16384))
        $stream = $response.Content.ReadAsStreamAsync($cancel.Token).GetAwaiter().GetResult()
        $buffer = [byte[]]::new(16385)
        $count = 0
        while ($count -lt $buffer.Length) {
            $read = $stream.ReadAsync($buffer, $count, $buffer.Length - $count, $cancel.Token).GetAwaiter().GetResult()
            if ($read -eq 0) { break }
            $count += $read
        }
        Assert-LabCondition ($count -le 16384)
        return ConvertFrom-LabAcmeDnsResponse ([Text.Encoding]::UTF8.GetString($buffer, 0, $count)) $Name $Type
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
        $cancel.Dispose(); $client.Dispose(); $handler.Dispose()
    }
}

function ConvertFrom-LabAcmeDnsResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][int] $Type
    )
    Assert-LabCondition ([Text.Encoding]::UTF8.GetByteCount($Text) -le 16384)
    $result = Read-LabAcmeJson $Text
    Assert-LabCondition ($result.Status -is [decimal] -and $result.Status -eq 0 -and
        $result.TC -is [bool] -and -not $result.TC -and
        $result.CD -is [bool] -and -not $result.CD -and
        $result.Contains('Answer') -and $result.Answer -is [array])
    return @(
        foreach ($answer in $result.Answer) {
            if ($answer.type -eq $Type -and $answer.name.TrimEnd('.') -ieq $Name) {
                Assert-LabCondition ($answer.data -is [string])
                $answer.data.TrimEnd('.').ToLowerInvariant()
            }
        }
    )
}

function Assert-LabAcmeDelegation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Config,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Resources
    )
    $actual = @(Resolve-LabAcmePublicName $Config.challengeZoneName 2 | Sort-Object -Unique)
    $expected = @($Resources.nameServers | ForEach-Object { $_.TrimEnd('.').ToLowerInvariant() } | Sort-Object -Unique)
    Assert-LabCondition ($actual.Count -ge 2 -and
        (Get-LabObjectDigest $actual) -ceq (Get-LabObjectDigest $expected))
    foreach ($role in @('gateway', 'apim', 'backend')) {
        $alias = @(Resolve-LabAcmePublicName "_acme-challenge.$($Config.hostnames[$role])" 5)
        Assert-LabCondition ($alias.Count -eq 1 -and $alias[0] -ceq "$role.$($Config.challengeZoneName)")
    }
}

function Get-LabAcmeVaultCertificate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Session)
    Assert-LabAcmeContext $Session
    # A missing name returns no certificate. Other service/authentication errors are not suppressed.
    $result = Get-AzKeyVaultCertificate -VaultName $Session.config.keyVaultName `
        -Name $Session.config.certificateName -DefaultProfile $Session.context -ErrorAction Stop
    if ($null -eq $result) { return $null }
    Assert-LabCondition ($result.Tags['apimAssessmentLab'] -ceq $Session.config.labId -and
        $result.Tags['acmeConfigSha256'] -ceq (Get-LabObjectDigest $Session.config) -and $result.Enabled -eq $true)
    $expectedPrefix = "https://$($Session.config.keyVaultName).vault.azure.net/certificates/$($Session.config.certificateName)/"
    Assert-LabCondition ($result.Id.StartsWith($expectedPrefix, [StringComparison]::Ordinal) -and
        $result.Thumbprint -cmatch '^[A-Fa-f0-9]{40}$' -and $null -ne $result.Certificate)
    Assert-LabAcmeCertificateName $result.Certificate $Session.config
    return @{
        thumbprint = $result.Thumbprint.ToUpperInvariant()
        notBefore = ([DateTimeOffset]$result.Certificate.NotBefore.ToUniversalTime()).ToString('O')
        notAfter = ([DateTimeOffset]$result.Certificate.NotAfter.ToUniversalTime()).ToString('O')
    }
}

function Import-LabAcmeVaultCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Session,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Candidate
    )
    Assert-LabAcmeWriteWindow $Session
    $null = Import-AzKeyVaultCertificate -VaultName $Session.config.keyVaultName `
        -Name $Session.config.certificateName -FilePath $Candidate.pfxPath -Password $Candidate.password `
        -Tag @{ apimAssessmentLab = $Session.config.labId; acmeConfigSha256 = Get-LabObjectDigest $Session.config } `
        -DefaultProfile $Session.context -ErrorAction Stop
}

function Initialize-LabAcmeProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Config,
        [Parameter(Mandatory)][string] $Stage
    )
    Assert-LabCondition ($Stage -cin @('Staging', 'Production'))
    $profileDirectory = Join-Path $Config.stateDirectory $Stage.ToLowerInvariant()
    $null = Get-LabPrivatePath $profileDirectory
    if (-not (Test-Path -LiteralPath $profileDirectory)) {
        $null = [IO.Directory]::CreateDirectory($profileDirectory)
        Initialize-LabAcmePrivateAccess $profileDirectory
    }
    Assert-LabAcmePrivateAccess $profileDirectory
    foreach ($item in Get-ChildItem -LiteralPath $profileDirectory -Force -Recurse -ErrorAction Stop) {
        Assert-LabAcmePrivateAccess $item.FullName
    }
    Assert-LabAcmeClientCache $profileDirectory $Stage
    $env:POSHACME_HOME = $profileDirectory
    $env:POSHACME_PLUGINS = Join-Path $PSScriptRoot 'acme-plugin'
    Import-LabAcmeModule -Client
    return $profileDirectory
}

function Get-LabAcmeClientCertificate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Session)
    if ($null -eq (Get-PAServer -ErrorAction Stop) -or $null -eq (Get-PAAccount -ErrorAction Stop)) { return $null }
    return Get-PACertificate -Name $Session.config.certificateName -ErrorAction Stop
}

function Invoke-LabAcmeClientIssuance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Session)
    Assert-LabAcmeWriteWindow $Session
    $config = $Session.config
    $server = if ($Session.stage -ceq 'Staging') { 'LE_STAGE' } else { 'LE_PROD' }
    $null = Set-PAServer -DirectoryUrl $server -DisableTelemetry -SkipCertificateCheck:$false -ErrorAction Stop
    $password = [Security.SecureString]::new()
    try {
        foreach ($character in [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(48)).ToCharArray()) {
            $password.AppendChar($character)
        }
        $password.MakeReadOnly()
        $pluginArgs = @{ LabSessionNonce = $Session.nonce }
        $Session.generatedPassword = $password
        return New-PACertificate -Domain @($config.hostnames.gateway, $config.hostnames.apim, $config.hostnames.backend) `
            -Name $config.certificateName -DirectoryUrl $server -CertKeyLength 2048 -AlwaysNewKey `
            -AcceptTOS -Install:$false -Plugin LabAzureDns -PluginArgs $pluginArgs `
            -DnsAlias @("gateway.$($config.challengeZoneName)", "apim.$($config.challengeZoneName)", "backend.$($config.challengeZoneName)") `
            -DnsVariant 'dns-01' -DnsSleep 120 -ValidationTimeout 60 -PfxPassSecure $password -Force -ErrorAction Stop
    }
    catch { $password.Dispose(); $Session.generatedPassword = $null; throw }
}

function Assert-LabAcmeClientCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProfileDirectory,
        [Parameter(Mandatory)][string] $Stage
    )
    $expected = if ($Stage -ceq 'Staging') { 'https://acme-staging-v02.api.letsencrypt.org/directory' }
        else { 'https://acme-v02.api.letsencrypt.org/directory' }
    $current = Join-Path $ProfileDirectory 'current-server.txt'
    if (Test-Path -LiteralPath $current) {
        Assert-LabCondition ((Read-LabPrivateText $current).Trim() -ceq $expected)
    }
    $directories = @(Get-ChildItem -LiteralPath $ProfileDirectory -Directory -Force -ErrorAction Stop)
    foreach ($directory in $directories) {
        $file = Join-Path $directory.FullName 'dir.json'
        Assert-LabCondition (Test-Path -LiteralPath $file -PathType Leaf)
        $server = Read-LabAcmePrivateJson $file
        Assert-LabCondition ($server.location -ceq $expected -and
            $server.SkipCertificateCheck -is [bool] -and -not $server.SkipCertificateCheck -and
            $server.DisableTelemetry -is [bool] -and $server.DisableTelemetry)
    }
    Assert-LabCondition ($directories.Count -le 1 -and
        ((Test-Path -LiteralPath $current) -eq ($directories.Count -eq 1)))
}
