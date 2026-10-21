BeforeAll {
    $script:acmeRepo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:acmeSource = Join-Path $script:acmeRepo 'scripts\lab'
    foreach ($name in @('Core', 'Transport', 'Dns', 'Certificate', 'Workflow', 'Process')) {
        . (Join-Path $script:acmeSource "LabAcme.$name.ps1")
    }
    $script:acmeSample = [IO.File]::ReadAllText(
        (Join-Path $script:acmeRepo 'infra\live-validation-lab\acme.sample.json'))
    $script:acmeNow = [DateTimeOffset]'2026-10-21T12:00:00Z'

    function Get-SyntheticAcmeConfig {
        $directory = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = [IO.Directory]::CreateDirectory($directory)
        Initialize-LabAcmePrivateAccess $directory
        $config = Read-LabJson $script:acmeSample
        $config.stateDirectory = $directory
        $config.modelVisibleRoots = @($script:acmeRepo)
        return $config
    }

    function Write-SyntheticAcmeConfig {
        param([System.Collections.IDictionary] $Config)
        $path = Join-Path $Config.stateDirectory 'config.json'
        Write-LabAcmePrivateJson $path $Config
        return $path
    }

    function Write-SyntheticAcmeStaging {
        param([System.Collections.IDictionary] $Config)
        $state = Get-LabAcmeState $Config
        $state.staging = @{
            configSha256 = Get-LabObjectDigest $Config; validatedAt = $script:acmeNow.ToString('O')
            notAfter = $script:acmeNow.AddDays(30).ToString('O'); thumbprint = 'B' * 40
        }
        Write-LabAcmePrivateJson (Get-LabAcmePrivateFile $Config 'lifecycle.json') $state
    }

    function Get-SyntheticAcmeCertificate {
        param([System.Collections.IDictionary] $Config, [string[]] $Names, [int] $Bits = 2048,
            [int] $ValidDays = 90)
        $profileDirectory = Join-Path $Config.stateDirectory 'staging'
        $null = [IO.Directory]::CreateDirectory($profileDirectory)
        Initialize-LabAcmePrivateAccess $profileDirectory
        $key = [Security.Cryptography.RSA]::Create($Bits)
        $certificate = $null
        $password = [Security.SecureString]::new()
        foreach ($character in 'SYNTHETIC-EXPORT-PASSWORD'.ToCharArray()) { $password.AppendChar($character) }
        $password.MakeReadOnly()
        try {
            $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=synthetic.example',
                $key, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $san = [Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
            foreach ($name in $Names) { $san.AddDnsName($name) }
            $request.CertificateExtensions.Add($san.Build())
            $start = [DateTimeOffset]::UtcNow.AddDays(-2)
            $end = [DateTimeOffset]::UtcNow.AddDays($ValidDays)
            $certificate = $request.CreateSelfSigned($start, $end)
            $certPath = Join-Path $profileDirectory 'cert.cer'
            $keyPath = Join-Path $profileDirectory 'cert.key'
            $chainPath = Join-Path $profileDirectory 'fullchain.cer'
            $pfxPath = Join-Path $profileDirectory 'cert-fullchain.pfx'
            [IO.File]::WriteAllText($certPath, $certificate.ExportCertificatePem())
            [IO.File]::WriteAllText($keyPath, $key.ExportPkcs8PrivateKeyPem())
            [IO.File]::WriteAllText($chainPath, $certificate.ExportCertificatePem())
            [IO.File]::WriteAllBytes($pfxPath, $certificate.Export(
                    [Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $password))
            foreach ($file in @($certPath, $keyPath, $chainPath, $pfxPath)) {
                Initialize-LabAcmePrivateAccess $file
            }
            return [pscustomobject]@{
                CertFile = $certPath; KeyFile = $keyPath; FullChainFile = $chainPath
                PfxFile = $pfxPath; PfxFullChain = $pfxPath; PfxPass = $password
                Thumbprint = $certificate.Thumbprint
            }
        }
        finally {
            if ($null -ne $certificate) { $certificate.Dispose() }
            $key.Dispose()
        }
    }

    # These declarations prevent Pester from discovering/importing any installed Az module.
    function Get-AzContext { [CmdletBinding()] param() throw 'SYNTHETIC_UNMOCKED_CALL' }
    function Get-AzDnsRecordSet {
        [CmdletBinding()]
        param($Name, $RecordType, $ZoneName, $ResourceGroupName, $DefaultProfile)
        $null = $Name, $RecordType, $ZoneName, $ResourceGroupName, $DefaultProfile
        throw 'SYNTHETIC_UNMOCKED_CALL'
    }
    function New-AzDnsRecordConfig {
        [CmdletBinding(SupportsShouldProcess)]
        param($Value)
        $null = $Value
        if ($PSCmdlet.ShouldProcess('synthetic', 'construct')) { throw 'SYNTHETIC_UNMOCKED_CALL' }
    }
    function New-AzDnsRecordSet {
        [CmdletBinding(SupportsShouldProcess)]
        param($Name, $RecordType, $ZoneName, $ResourceGroupName, $Ttl, $DnsRecords, $Metadata, $DefaultProfile)
        $null = $Name, $RecordType, $ZoneName, $ResourceGroupName, $Ttl, $DnsRecords, $Metadata, $DefaultProfile
        if ($PSCmdlet.ShouldProcess('synthetic', 'create')) { throw 'SYNTHETIC_UNMOCKED_CALL' }
    }
    function Add-AzDnsRecordConfig {
        [CmdletBinding()]
        param($RecordSet, $Value)
        $null = $RecordSet, $Value
        throw 'SYNTHETIC_UNMOCKED_CALL'
    }
    function Remove-AzDnsRecordConfig {
        [CmdletBinding(SupportsShouldProcess)]
        param($RecordSet, $Value)
        $null = $RecordSet, $Value
        if ($PSCmdlet.ShouldProcess('synthetic', 'remove')) { throw 'SYNTHETIC_UNMOCKED_CALL' }
    }
    function Set-AzDnsRecordSet {
        [CmdletBinding(SupportsShouldProcess)]
        param($RecordSet, $DefaultProfile)
        $null = $RecordSet, $DefaultProfile
        if ($PSCmdlet.ShouldProcess('synthetic', 'update')) { throw 'SYNTHETIC_UNMOCKED_CALL' }
    }
    function Get-PAServer { [CmdletBinding()] param() throw 'SYNTHETIC_UNMOCKED_CALL' }
    function Get-PAAccount { [CmdletBinding()] param() throw 'SYNTHETIC_UNMOCKED_CALL' }
    function Get-PACertificate {
        [CmdletBinding()]
        param($Name)
        $null = $Name
        throw 'SYNTHETIC_UNMOCKED_CALL'
    }
    function Set-PAServer {
        [CmdletBinding(SupportsShouldProcess)]
        param($DirectoryUrl, [switch] $DisableTelemetry, [switch] $SkipCertificateCheck)
        $null = $DirectoryUrl, $DisableTelemetry, $SkipCertificateCheck
        if ($PSCmdlet.ShouldProcess('synthetic', 'configure')) { throw 'SYNTHETIC_UNMOCKED_CALL' }
    }
    function New-PACertificate {
        [CmdletBinding(SupportsShouldProcess)]
        param($Domain, $Name, $DirectoryUrl, $CertKeyLength, [switch] $AlwaysNewKey, [switch] $AcceptTOS,
            [switch] $Install, $Plugin, $PluginArgs, $DnsAlias, $DnsVariant, $DnsSleep, $ValidationTimeout,
            [Security.SecureString] $PfxPassSecure, [switch] $Force)
        $null = $Domain, $Name, $DirectoryUrl, $CertKeyLength, $AlwaysNewKey, $AcceptTOS, $Install,
            $Plugin, $PluginArgs, $DnsAlias, $DnsVariant, $DnsSleep, $ValidationTimeout, $PfxPassSecure, $Force
        if ($PSCmdlet.ShouldProcess('synthetic', 'issue')) { throw 'SYNTHETIC_UNMOCKED_CALL' }
    }
}

Describe 'Closed private ACME input and approval state' {
    BeforeEach {
        $script:acmeConfig = Get-SyntheticAcmeConfig
        Mock Get-LabAcmeUtcNow { $script:acmeNow }
    }

    It 'accepts a private closed synthetic configuration and excludes all declared visible roots' {
        $path = Write-SyntheticAcmeConfig $script:acmeConfig
        (Read-LabAcmeConfig $path).schemaVersion | Should -BeExactly '1.0'
        foreach ($root in @($script:acmeConfig.stateDirectory, (Split-Path $script:acmeConfig.stateDirectory -Parent))) {
            $script:acmeConfig.modelVisibleRoots = @($root)
            $path = Write-SyntheticAcmeConfig $script:acmeConfig
            { Read-LabAcmeConfig $path } | Should -Throw
        }
    }

    It 'rejects unknown, duplicate, missing, noncanonical, wildcard and overlapping-hostname input' {
        foreach ($mutation in @(
                { param($c) $c['unknown'] = 'SYNTHETIC_PRIVATE_CANARY' },
                { param($c) $c.Remove('workerVmName') },
                { param($c) $c.schemaVersion = '2.0' },
                { param($c) $c.tenantId = '00000000-0000-0000-0000-000000000000' },
                { param($c) $c.hostnames.gateway = '*.synthetic.example' },
                { param($c) $c.hostnames.apim = $c.hostnames.gateway },
                { param($c) $c.hostnames.apim = '192.0.2.10' },
                { param($c) $c.hostnames.apim = 'UPPER.synthetic.example' }
            )) {
            $config = Get-SyntheticAcmeConfig
            & $mutation $config
            $path = Write-SyntheticAcmeConfig $config
            { Read-LabAcmeConfig $path } | Should -Throw
        }
        { Read-LabJson '{"schemaVersion":"1.0","SchemaVersion":"1.0"}' } | Should -Throw
    }

    It 'refuses checkout paths, relative paths and linked private paths' {
        { Read-LabAcmeConfig 'relative.json' } | Should -Throw
        { Get-LabPrivatePath (Join-Path $script:acmeRepo 'artifacts\synthetic-acme.json') } | Should -Throw
        $link = Join-Path $TestDrive 'synthetic-acme-link'
        $linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
        $null = New-Item -ItemType $linkType -Path $link -Target $script:acmeConfig.stateDirectory -ErrorAction Stop
        try { { Get-LabPrivatePath (Join-Path $link 'state.json') } | Should -Throw }
        finally { Remove-Item -LiteralPath $link -Force }
    }

    It 'requires private permissions and an exclusive owner lock' {
        $path = Write-SyntheticAcmeConfig $script:acmeConfig
        { Assert-LabAcmePrivateAccess $path } | Should -Not -Throw
        $lock = Open-LabAcmeLock $script:acmeConfig
        try { { Open-LabAcmeLock $script:acmeConfig } | Should -Throw }
        finally { $lock.Dispose() }
        if (-not $IsWindows) {
            [IO.File]::SetUnixFileMode($path, 420)
            { Read-LabAcmeConfig $path } | Should -Throw
        }
        else {
            $acl = [Security.AccessControl.FileSecurity]::new()
            $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
            $acl.SetOwner($owner)
            $acl.SetAccessRuleProtection($true, $false)
            $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($owner, 'FullControl', 'Allow'))
            $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
                    [Security.Principal.SecurityIdentifier]::new('S-1-1-0'), 'Read', 'Allow'))
            [IO.FileSystemAclExtensions]::SetAccessControl([IO.FileInfo]::new($path), $acl)
            { Read-LabAcmeConfig $path } | Should -Throw
        }
    }

    It 'binds a new thirty-minute plan to exact configuration, snapshot, stage, digest and rotation' {
        $plan = Get-LabAcmePlan $script:acmeConfig Production ('a' * 64) Issue -Rotate
        $path = Join-Path $script:acmeConfig.stateDirectory 'approval-rotation.json'
        Write-LabAcmePrivateJson $path $plan -CreateNew
        $digest = Get-LabObjectDigest $plan
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() | Should -BeExactly $digest
        (Assert-LabAcmePlan $script:acmeConfig $path $digest Production ('a' * 64) -Rotate).action |
            Should -BeExactly 'Issue'
        { Assert-LabAcmePlan $script:acmeConfig $path $digest Production ('b' * 64) -Rotate } | Should -Throw
        { Assert-LabAcmePlan $script:acmeConfig $path $digest Staging ('a' * 64) -Rotate } | Should -Throw
        { Assert-LabAcmePlan $script:acmeConfig $path $digest Production ('a' * 64) } | Should -Throw
        { Assert-LabAcmePlan $script:acmeConfig $path ('b' * 64) Production ('a' * 64) -Rotate } | Should -Throw
        { Write-LabAcmePrivateJson $path $plan -CreateNew } | Should -Throw
        Mock Get-LabAcmeUtcNow { $script:acmeNow.AddSeconds(1800) }
        { Assert-LabAcmePlan $script:acmeConfig $path $digest Production ('a' * 64) -Rotate } | Should -Throw
    }

    It 'requires recent, unexpired configuration-bound staging proof before production' {
        $state = Get-LabAcmeState $script:acmeConfig
        { Assert-LabAcmeStaging $script:acmeConfig $state } | Should -Throw
        $state.staging = @{
            configSha256 = Get-LabObjectDigest $script:acmeConfig; validatedAt = $script:acmeNow.ToString('O')
            notAfter = $script:acmeNow.AddDays(30).ToString('O'); thumbprint = 'A' * 40
        }
        { Assert-LabAcmeStaging $script:acmeConfig $state } | Should -Not -Throw
        foreach ($mutation in @(
                { param($s) $s.configSha256 = 'b' * 64 },
                { param($s) $s.validatedAt = $script:acmeNow.AddDays(-8).ToString('O') },
                { param($s) $s.validatedAt = $script:acmeNow.AddMinutes(1).ToString('O') },
                { param($s) $s.notAfter = $script:acmeNow.ToString('O') }
            )) {
            $proof = Read-LabJson ($state | ConvertTo-Json)
            & $mutation $proof.staging
            { Assert-LabAcmeStaging $script:acmeConfig $proof } | Should -Throw
        }
    }

    It 'rejects unknown lifecycle and journal fields rather than silently dropping them' {
        Write-LabAcmePrivateJson (Get-LabAcmePrivateFile $script:acmeConfig 'lifecycle.json') @{
            schemaVersion = '1.0'; staging = $null; receipt = $null; extra = $true
        }
        { Get-LabAcmeState $script:acmeConfig } | Should -Throw
        $journal = Get-LabAcmeDnsJournal $script:acmeConfig
        $journal.entries = @(@{ name = 'unapproved'; value = 'a' * 43 })
        Save-LabAcmeDnsJournal $script:acmeConfig $journal
        { Get-LabAcmeDnsJournal $script:acmeConfig } | Should -Throw
    }

    It 'rejects coerced member types and noncanonical timestamps in private lifecycle/approval records' {
        foreach ($value in @(21, '2026-10-21', '2026-10-21T07:00:00.0000000-05:00', @('2026-10-21'))) {
            { ConvertTo-LabAcmeTimestamp $value } | Should -Throw
        }
        $plan = Get-LabAcmePlan $script:acmeConfig Staging ('a' * 64) Issue
        $plan.stage = @('Staging')
        $path = Join-Path $script:acmeConfig.stateDirectory 'approval-wrong-type.json'
        Write-LabAcmePrivateJson $path $plan
        { Assert-LabAcmePlan $script:acmeConfig $path (Get-LabObjectDigest $plan) Staging ('a' * 64) } |
            Should -Throw
    }

    It 'rejects cached alternate ACME endpoints, TLS bypass and telemetry before importing the client' {
        Mock Import-LabAcmeModule {}
        $profileDirectory = Initialize-LabAcmeProfile $script:acmeConfig Staging
        $serverDirectory = Join-Path $profileDirectory 'LE_STAGE'
        $null = [IO.Directory]::CreateDirectory($serverDirectory)
        Initialize-LabAcmePrivateAccess $serverDirectory
        $server = @{
            location = 'https://acme-staging-v02.api.letsencrypt.org/directory'
            SkipCertificateCheck = $false; DisableTelemetry = $true
        }
        $serverFile = Join-Path $serverDirectory 'dir.json'
        Write-LabAcmePrivateJson $serverFile $server
        $current = Join-Path $profileDirectory 'current-server.txt'
        [IO.File]::WriteAllText($current, $server.location)
        Initialize-LabAcmePrivateAccess $current
        { Initialize-LabAcmeProfile $script:acmeConfig Staging } | Should -Not -Throw
        foreach ($mutation in @(
                { param($s) $s.location = 'https://unapproved.invalid/directory' },
                { param($s) $s.SkipCertificateCheck = $true },
                { param($s) $s.DisableTelemetry = $false }
            )) {
            $invalid = $server.Clone()
            & $mutation $invalid
            Write-LabAcmePrivateJson $serverFile $invalid
            { Initialize-LabAcmeProfile $script:acmeConfig Staging } | Should -Throw
        }
        Should -Invoke Import-LabAcmeModule -Times 2 -Exactly
        $env:POSHACME_HOME = $null
        $env:POSHACME_PLUGINS = $null
    }
}

Describe 'Pinned ACME client adapter without account, certificate or module access' {
    BeforeEach {
        $script:acmeConfig = Get-SyntheticAcmeConfig
        Mock Get-PAServer { $null }
        Mock Get-PAAccount { $null }
        Mock Get-PACertificate { $null }
    }

    It 'treats an uninitialized isolated profile as no certificate without calling account/certificate cmdlets' {
        (Get-LabAcmeClientCertificate @{ config = $script:acmeConfig }) | Should -BeNullOrEmpty
        Should -Invoke Get-PAAccount -Times 0
        Should -Invoke Get-PACertificate -Times 0
        Mock Get-PAServer { @{ location = 'synthetic' } }
        (Get-LabAcmeClientCertificate @{ config = $script:acmeConfig }) | Should -BeNullOrEmpty
        Should -Invoke Get-PAAccount -Times 1 -Exactly
        Should -Invoke Get-PACertificate -Times 0
    }

    It 'passes fixed SANs, aliases, a fresh key, private password and only an opaque plugin nonce' {
        Mock Assert-LabAcmeWriteWindow {}
        Mock Set-PAServer {}
        Mock New-PACertificate { [pscustomobject]@{ Thumbprint = 'A' * 40 } }
        $session = @{ config = $script:acmeConfig; stage = 'Production'; nonce = 'synthetic-nonce'; generatedPassword = $null }
        try {
            (Invoke-LabAcmeClientIssuance $session).Thumbprint | Should -BeExactly ('A' * 40)
            Should -Invoke Set-PAServer -Times 1 -Exactly -ParameterFilter {
                $DirectoryUrl -ceq 'LE_PROD' -and $DisableTelemetry -and -not $SkipCertificateCheck
            }
            Should -Invoke New-PACertificate -Times 1 -Exactly -ParameterFilter {
                $DirectoryUrl -ceq 'LE_PROD' -and $CertKeyLength -eq 2048 -and
                $AlwaysNewKey -and $Force -and $AcceptTOS -and -not $Install -and
                $Plugin -ceq 'LabAzureDns' -and $DnsVariant -ceq 'dns-01' -and
                $PluginArgs.Count -eq 1 -and $PluginArgs.LabSessionNonce -ceq 'synthetic-nonce' -and
                $PfxPassSecure.Length -ge 48 -and $Domain.Count -eq 3 -and $DnsAlias.Count -eq 3 -and
                $Domain[0] -ceq 'gateway.synthetic.example' -and $Domain[1] -ceq 'apim.synthetic.example' -and
                $Domain[2] -ceq 'backend.synthetic.example' -and
                $DnsAlias[0] -ceq 'gateway.acme.synthetic.example' -and
                $DnsAlias[1] -ceq 'apim.acme.synthetic.example' -and $DnsAlias[2] -ceq 'backend.acme.synthetic.example'
            }
        }
        finally { if ($null -ne $session.generatedPassword) { $session.generatedPassword.Dispose() } }
    }
}

Describe 'Scoped identity, public delegation and owned TXT concurrency' {
    BeforeEach {
        $script:acmeConfig = Get-SyntheticAcmeConfig
        $script:acmeSession = @{
            config = $script:acmeConfig
            context = [pscustomobject]@{
                Account = @{ Id = 'synthetic-identity'; Type = 'ManagedService' }
                Tenant = @{ Id = $script:acmeConfig.tenantId }
                Subscription = @{ Id = $script:acmeConfig.subscriptionId }
                Environment = @{ Name = 'AzureCloud' }
            }
            plan = @{ expiresAt = $script:acmeNow.AddMinutes(30).ToString('O') }
        }
        Mock Get-LabAcmeUtcNow { $script:acmeNow }
        Mock Get-AzContext { $script:acmeSession.context }
        Mock Start-Sleep {}
    }

    It 'rejects user, other-cloud, wrong-tenant and changed managed-identity context' {
        { Assert-LabAcmeContext $script:acmeSession } | Should -Not -Throw
        foreach ($mutation in @(
                { param($c) $c.Account.Type = 'User' },
                { param($c) $c.Environment.Name = 'AzureChinaCloud' },
                { param($c) $c.Tenant.Id = '33333333-3333-4333-8333-333333333333' },
                { param($c) $c.Subscription.Id = '33333333-3333-4333-8333-333333333333' },
                { param($c) $c.Account.Id = 'other-identity' }
            )) {
            $script:wrongContext = Read-LabJson ($script:acmeSession.context | ConvertTo-Json -Depth 8)
            & $mutation $script:wrongContext
            Mock Get-AzContext { $script:wrongContext }
            { Assert-LabAcmeContext $script:acmeSession } | Should -Throw
        }
    }

    It 'requires the exact public NS set and all three direct challenge CNAME aliases' {
        Mock Resolve-LabAcmePublicName {
            param($Name, $Type)
            if ($Type -eq 2) { return @('ns1.synthetic.example', 'ns2.synthetic.example') }
            return $Name.Replace('_acme-challenge.', '').Replace('.synthetic.example', '.acme.synthetic.example')
        }
        $resources = @{ nameServers = @('ns1.synthetic.example.', 'ns2.synthetic.example.') }
        { Assert-LabAcmeDelegation $script:acmeConfig $resources } | Should -Not -Throw
        Mock Resolve-LabAcmePublicName { 'wrong.synthetic.example' } -ParameterFilter { $Type -eq 5 }
        { Assert-LabAcmeDelegation $script:acmeConfig $resources } | Should -Throw
        Mock Resolve-LabAcmePublicName { @('ns1.synthetic.example', 'wrong.synthetic.example') } -ParameterFilter { $Type -eq 2 }
        { Assert-LabAcmeDelegation $script:acmeConfig $resources } | Should -Throw
    }

    It 'rejects truncated, disabled-validation, failed, oversized and duplicate public DNS responses' {
        $text = '{"Status":0,"TC":false,"CD":false,"Answer":[{"name":"acme.synthetic.example.","type":2,"data":"NS1.SYNTHETIC.EXAMPLE."}]}'
        @(ConvertFrom-LabAcmeDnsResponse $text 'acme.synthetic.example' 2)[0] |
            Should -BeExactly 'ns1.synthetic.example'
        foreach ($invalid in @(
                $text.Replace('"TC":false', '"TC":true'),
                $text.Replace('"CD":false', '"CD":true'),
                $text.Replace('"Status":0', '"Status":3'),
                $text.Replace('"Status":0', '"Status":"0"'),
                $text.Replace('"Status":0', '"Status":0,"status":0'),
                ($text + (' ' * 16385))
            )) {
            { ConvertFrom-LabAcmeDnsResponse $invalid 'acme.synthetic.example' 2 } | Should -Throw
        }
        @(ConvertFrom-LabAcmeDnsResponse $text 'other.synthetic.example' 2).Count | Should -Be 0
    }

    It 'binds fresh owned VM, vault and public zone metadata to the executing VM' {
        Mock Get-LabAcmeArmResource {
            param($Session, $Id)
            $type = if ($Id -like '*/virtualMachines/*') { 'Microsoft.Compute/virtualMachines' }
                elseif ($Id -like '*/vaults/*') { 'Microsoft.KeyVault/vaults' } else { 'Microsoft.Network/dnsZones' }
            $resource = @{
                id = $Id; type = $type; location = $Session.config.location
                tags = @{ apimAssessmentLab = $Session.config.labId }
            }
            if ($type -ceq 'Microsoft.Compute/virtualMachines') {
                $resource.identity = @{
                    type = 'SystemAssigned'; tenantId = $Session.config.tenantId
                    principalId = '33333333-3333-4333-8333-333333333333'
                }
            }
            elseif ($type -ceq 'Microsoft.KeyVault/vaults') {
                $resource.properties = @{
                    tenantId = $Session.config.tenantId; enableRbacAuthorization = $true
                    vaultUri = "https://$($Session.config.keyVaultName).vault.azure.net/"
                }
            }
            else {
                $resource.location = 'global'
                $resource.properties = @{ zoneType = 'Public'; nameServers = @('ns1.synthetic.example', 'ns2.synthetic.example') }
            }
            return $resource
        }
        $script:expectedVmId = "/subscriptions/$($script:acmeConfig.subscriptionId)/resourceGroups/$($script:acmeConfig.labResourceGroup)/providers/Microsoft.Compute/virtualMachines/$($script:acmeConfig.workerVmName)"
        Mock Get-LabAcmeInstanceIdentity { $script:expectedVmId }
        (Get-LabAcmeResourceSet $script:acmeSession).vmId | Should -BeExactly $script:expectedVmId
        Mock Get-LabAcmeInstanceIdentity { 'SYNTHETIC_OTHER_VM' }
        { Get-LabAcmeResourceSet $script:acmeSession } | Should -Throw
        Mock Get-LabAcmeInstanceIdentity { $script:expectedVmId }
        Mock Get-LabAcmeArmResource {
            param($Id)
            return @{ id = $Id; type = 'Microsoft.Network/dnsZones'; location = 'global'; tags = @{} }
        } -ParameterFilter { $Id -like '*/dnsZones/*' }
        { Get-LabAcmeResourceSet $script:acmeSession } | Should -Throw
    }

    It 'creates only an owned TXT record at the exact alias without record-set overwrite' {
        Mock Get-AzDnsRecordSet { $null }
        Mock New-AzDnsRecordConfig { param($Value) [pscustomobject]@{ Value = @($Value) } }
        Mock New-AzDnsRecordSet {}
        Invoke-LabAcmeDnsTxt $script:acmeSession Add "gateway.$($script:acmeConfig.challengeZoneName)" ('a' * 43)
        Should -Invoke New-AzDnsRecordSet -Times 1 -Exactly -ParameterFilter {
            $Name -ceq 'gateway' -and $RecordType -ceq 'TXT' -and $Ttl -eq 60 -and
            $ZoneName -ceq $script:acmeConfig.challengeZoneName -and
            $ResourceGroupName -ceq $script:acmeConfig.labResourceGroup -and
            $Metadata.apimAssessmentLab -ceq $script:acmeConfig.labId -and
            ($DnsRecords.Value -join '') -ceq ('a' * 43)
        }
    }

    It 'preserves unrelated TXT values and removes only journaled values using conditional record updates' {
        $script:dnsRecord = [pscustomobject]@{
            Name = 'gateway'; ZoneName = $script:acmeConfig.challengeZoneName
            Metadata = @{ apimAssessmentLab = $script:acmeConfig.labId }
            Records = @([pscustomobject]@{ Value = @('unrelated-txt') })
            ETag = 'synthetic-etag'
        }
        Mock Get-AzDnsRecordSet { $script:dnsRecord }
        Mock Add-AzDnsRecordConfig {
            param($RecordSet, $Value)
            $RecordSet.Records += [pscustomobject]@{ Value = @($Value) }
            return $RecordSet
        }
        Mock Remove-AzDnsRecordConfig {
            param($RecordSet, $Value)
            $RecordSet.Records = @($RecordSet.Records | Where-Object { ($_.Value -join '') -cne $Value })
            return $RecordSet
        }
        Mock Set-AzDnsRecordSet {}
        $name = "gateway.$($script:acmeConfig.challengeZoneName)"
        Invoke-LabAcmeDnsTxt $script:acmeSession Add $name ('a' * 43)
        @((Get-LabAcmeDnsJournal $script:acmeConfig).entries).Count | Should -Be 1
        ($script:dnsRecord.Records.Value -join ',') | Should -Match 'unrelated-txt'
        Invoke-LabAcmeDnsTxt $script:acmeSession Remove $name ('a' * 43)
        $script:dnsRecord.Records.Count | Should -Be 1
        ($script:dnsRecord.Records[0].Value -join '') | Should -BeExactly 'unrelated-txt'
        @((Get-LabAcmeDnsJournal $script:acmeConfig).entries).Count | Should -Be 0
        Should -Invoke Set-AzDnsRecordSet -Times 2 -Exactly -ParameterFilter { $RecordSet.ETag -ceq 'synthetic-etag' }
        Should -Invoke Get-AzDnsRecordSet -Times 2 -Exactly -ParameterFilter {
            $Name -ceq 'gateway' -and $RecordType -ceq 'TXT' -and
            $ZoneName -ceq $script:acmeConfig.challengeZoneName -and
            $ResourceGroupName -ceq $script:acmeConfig.labResourceGroup
        }
    }

    It 'never claims or removes an identical preexisting value and refuses out-of-zone names' {
        Mock Get-AzDnsRecordSet {
            [pscustomobject]@{
                Name = 'gateway'; ZoneName = $script:acmeConfig.challengeZoneName
                Metadata = @{ apimAssessmentLab = $script:acmeConfig.labId }
                Records = @([pscustomobject]@{ Value = @('a' * 43) })
            }
        }
        Mock Set-AzDnsRecordSet {}
        Invoke-LabAcmeDnsTxt $script:acmeSession Add "gateway.$($script:acmeConfig.challengeZoneName)" ('a' * 43)
        Invoke-LabAcmeDnsTxt $script:acmeSession Remove "gateway.$($script:acmeConfig.challengeZoneName)" ('a' * 43)
        @((Get-LabAcmeDnsJournal $script:acmeConfig).entries).Count | Should -Be 0
        Should -Invoke Set-AzDnsRecordSet -Times 0
        { Invoke-LabAcmeDnsTxt $script:acmeSession Add 'arbitrary.synthetic.example' ('a' * 43) } | Should -Throw
    }

    It 're-reads after ETag conflicts, bounds retries and retains owned cleanup intent on failure' {
        $script:dnsRecord = [pscustomobject]@{
            Name = 'gateway'; ZoneName = $script:acmeConfig.challengeZoneName
            Metadata = @{ apimAssessmentLab = $script:acmeConfig.labId }; Records = @(); ETag = 'synthetic'
        }
        Mock Get-AzDnsRecordSet { $script:dnsRecord }
        Mock Add-AzDnsRecordConfig { param($RecordSet) return $RecordSet }
        Mock Set-AzDnsRecordSet {
            $exception = [Exception]::new('SYNTHETIC_PRIVATE_CANARY')
            $exception | Add-Member NoteProperty Response ([pscustomobject]@{ StatusCode = 412 })
            throw $exception
        }
        { Invoke-LabAcmeDnsTxt $script:acmeSession Add "gateway.$($script:acmeConfig.challengeZoneName)" ('a' * 43) } |
            Should -Throw
        Should -Invoke Get-AzDnsRecordSet -Times 3 -Exactly
        Should -Invoke Set-AzDnsRecordSet -Times 3 -Exactly
        Should -Invoke Start-Sleep -Times 2 -Exactly
        @((Get-LabAcmeDnsJournal $script:acmeConfig).entries).Count | Should -Be 1
    }

    It 'fails closed before any DNS write when an approval expires' {
        $script:acmeSession.plan.expiresAt = $script:acmeNow.ToString('O')
        Mock Get-AzDnsRecordSet { throw 'UNREACHABLE' }
        { Invoke-LabAcmeDnsTxt $script:acmeSession Add "gateway.$($script:acmeConfig.challengeZoneName)" ('a' * 43) } |
            Should -Throw
        Should -Invoke Get-AzDnsRecordSet -Times 0
    }
}

Describe 'Custom plugin callback across isolated module scopes' {
    It 'binds an opaque nonce to exact owned TXT changes without serializing the Azure context into plugin arguments' {
        $config = Get-SyntheticAcmeConfig
        $context = [pscustomobject]@{
            Account = @{ Id = 'synthetic'; Type = 'ManagedService' }
            Tenant = @{ Id = $config.tenantId }; Subscription = @{ Id = $config.subscriptionId }
            Environment = @{ Name = 'AzureCloud' }
        }
        $shared = @{
            context = $context; writes = 0
            record = [pscustomobject]@{
                Name = 'gateway'; ZoneName = $config.challengeZoneName; ETag = 'synthetic'
                Metadata = @{ apimAssessmentLab = $config.labId }
                Records = @([pscustomobject]@{ Value = @('unrelated-txt') })
            }
        }
        $adapter = New-Module -Name SyntheticAcmeDnsAdapter -ArgumentList $shared -ScriptBlock {
            param($State)
            $script:state = $State
            function Get-AzContext { $script:state.context }
            function Get-AzDnsRecordSet {
                [CmdletBinding()]
                param($Name, $RecordType, $ZoneName, $ResourceGroupName, $DefaultProfile)
                $null = $Name, $RecordType, $ZoneName, $ResourceGroupName, $DefaultProfile
                return $script:state.record
            }
            function Add-AzDnsRecordConfig {
                [CmdletBinding()]
                param($RecordSet, $Value)
                $RecordSet.Records += [pscustomobject]@{ Value = @($Value) }
                return $RecordSet
            }
            function Remove-AzDnsRecordConfig {
                [CmdletBinding(SupportsShouldProcess)]
                param($RecordSet, $Value)
                if (-not $PSCmdlet.ShouldProcess('synthetic', 'remove')) { throw 'SYNTHETIC_DECLINED' }
                $RecordSet.Records = @($RecordSet.Records | Where-Object { ($_.Value -join '') -cne $Value })
                return $RecordSet
            }
            function Set-AzDnsRecordSet {
                [CmdletBinding(SupportsShouldProcess)]
                param($RecordSet, $DefaultProfile)
                $null = $DefaultProfile
                if (-not $PSCmdlet.ShouldProcess('synthetic', 'update')) { throw 'SYNTHETIC_DECLINED' }
                $script:state.record = $RecordSet
                $script:state.writes++
            }
            Export-ModuleMember -Function Get-AzContext, Get-AzDnsRecordSet, Add-AzDnsRecordConfig,
                Remove-AzDnsRecordConfig, Set-AzDnsRecordSet
        }
        $plugin = New-Module -Name SyntheticAcmePlugin -ArgumentList (
            Join-Path $script:acmeSource 'acme-plugin\LabAzureDns.ps1'
        ) -ScriptBlock {
            param($Path)
            . $Path
            Export-ModuleMember -Function Add-DnsTxt, Remove-DnsTxt, Save-DnsTxt, Get-CurrentPluginType
        }
        $session = @{
            config = $config; context = $context; nonce = 'synthetic-nonce'
            plan = @{ expiresAt = [DateTimeOffset]::UtcNow.AddMinutes(30).ToString('O') }
        }
        try {
            Import-Module $adapter -Global
            Register-LabAcmeDnsDispatch $session
            (& $plugin { Get-CurrentPluginType }) | Should -BeExactly 'dns-01'
            $name = "gateway.$($config.challengeZoneName)"
            { & $plugin { param($n) Add-DnsTxt $n ('a' * 43) -LabSessionNonce 'wrong-nonce' } $name } |
                Should -Throw
            & $plugin { param($n) Add-DnsTxt $n ('a' * 43) -LabSessionNonce 'synthetic-nonce' } $name
            $shared.writes | Should -Be 1
            & $plugin { param($n) Remove-DnsTxt $n ('a' * 43) -LabSessionNonce 'synthetic-nonce' } $name
            $shared.writes | Should -Be 2
            ($shared.record.Records[0].Value -join '') | Should -BeExactly 'unrelated-txt'
            @((Get-LabAcmeDnsJournal $config).entries).Count | Should -Be 0
        }
        finally {
            [AppDomain]::CurrentDomain.SetData('ApimAssessment.LabAcme.DnsDispatch', $null)
            Remove-Module -ModuleInfo $adapter -Force
        }
    }
}

Describe 'Real synthetic certificate material validation' {
    BeforeEach {
        $script:acmeConfig = Get-SyntheticAcmeConfig
        $script:acmeNames = @($script:acmeConfig.hostnames.gateway, $script:acmeConfig.hostnames.apim,
            $script:acmeConfig.hostnames.backend)
    }

    It 'validates staging SANs, dates, RSA private key and matching full-chain PFX without changing trust' {
        $client = Get-SyntheticAcmeCertificate $script:acmeConfig $script:acmeNames
        try {
            $session = @{ config = $script:acmeConfig; stage = 'Staging'; home = (Split-Path $client.CertFile -Parent) }
            (Assert-LabAcmeCandidate $session $client).thumbprint | Should -BeExactly $client.Thumbprint
            $session.stage = 'Production'
            { Assert-LabAcmeCandidate $session $client } | Should -Throw
        }
        finally { $client.PfxPass.Dispose() }
    }

    It 'rejects extra SANs, weak keys and expired certificates' -ForEach @(
        @{ Kind = 'extra-san' }, @{ Kind = 'weak-key' }, @{ Kind = 'expired' }
    ) {
        $names = if ($Kind -ceq 'extra-san') { $script:acmeNames + @('extra.synthetic.example') } else { $script:acmeNames }
        $bits = if ($Kind -ceq 'weak-key') { 1024 } else { 2048 }
        $days = if ($Kind -ceq 'expired') { -1 } else { 90 }
        $client = Get-SyntheticAcmeCertificate $script:acmeConfig $names $bits $days
        try {
            $session = @{ config = $script:acmeConfig; stage = 'Staging'; home = (Split-Path $client.CertFile -Parent) }
            { Assert-LabAcmeCandidate $session $client } | Should -Throw
        }
        finally { $client.PfxPass.Dispose() }
    }

    It 'rejects a mismatched private key and material outside the isolated profile' {
        $client = Get-SyntheticAcmeCertificate $script:acmeConfig $script:acmeNames
        $otherKey = [Security.Cryptography.RSA]::Create(2048)
        try {
            $session = @{ config = $script:acmeConfig; stage = 'Staging'; home = (Split-Path $client.CertFile -Parent) }
            [IO.File]::WriteAllText($client.KeyFile, $otherKey.ExportPkcs8PrivateKeyPem())
            { Assert-LabAcmeCandidate $session $client } | Should -Throw
            $client.KeyFile = Join-Path $script:acmeConfig.stateDirectory 'outside.key'
            { Assert-LabAcmeCandidate $session $client } | Should -Throw
        }
        finally { $otherKey.Dispose(); $client.PfxPass.Dispose() }
    }
}

Describe 'Approved staged issuance, renewal, import and recovery workflow' {
    BeforeEach {
        $script:acmeConfig = Get-SyntheticAcmeConfig
        $script:acmeArgs = @{
            ConfigPath = Write-SyntheticAcmeConfig $script:acmeConfig
            OwnerAuthorized = $true; MicrosoftOwnedTestEnvironment = $true; AcceptPublicDnsQueries = $true
            AcceptAcmeTerms = $true; AcceptCertificateTransparency = $true; Stage = 'Staging'
            PlanPath = Join-Path $script:acmeConfig.stateDirectory 'approval-synthetic.json'
        }
        $script:acmeVault = $null
        $script:acmeClient = $null
        $script:acmeCandidate = @{
            thumbprint = 'A' * 40; notBefore = $script:acmeNow.AddMinutes(-1).ToString('O')
            notAfter = $script:acmeNow.AddDays(90).ToString('O')
            pfxPath = 'SYNTHETIC_PRIVATE_CANARY'; password = $null
            metadata = @{
                thumbprint = 'A' * 40; notBefore = $script:acmeNow.AddMinutes(-1).ToString('O')
                notAfter = $script:acmeNow.AddDays(90).ToString('O')
            }
        }
        Mock Get-LabAcmeUtcNow { $script:acmeNow }
        Mock Import-LabAcmeModule {}
        Mock Connect-LabAcmeIdentity { @{ Account = @{ Id = 'synthetic' } } }
        Mock Assert-LabAcmeContext {}
        Mock Get-LabAcmeResourceSet { @{ vmId = 'synthetic'; nameServers = @('ns1', 'ns2') } }
        Mock Assert-LabAcmeDelegation {}
        Mock Initialize-LabAcmeProfile {
            param($Config, $Stage)
            $directory = Join-Path $Config.stateDirectory $Stage.ToLowerInvariant()
            $null = [IO.Directory]::CreateDirectory($directory)
            Initialize-LabAcmePrivateAccess $directory
            return $directory
        }
        Mock Get-LabAcmeVaultCertificate { $script:acmeVault }
        Mock Get-LabAcmeClientCertificate { $script:acmeClient }
        Mock Invoke-LabAcmeClientIssuance {
            $script:acmeClient = [pscustomobject]@{ Thumbprint = $script:acmeCandidate.thumbprint }
            return $script:acmeClient
        }
        Mock Assert-LabAcmeCandidate { $script:acmeCandidate }
        Mock Register-LabAcmeDnsDispatch {}
        Mock Clear-LabAcmeDnsJournal {}
        Mock Clear-LabAcmeExport {}
        Mock Import-LabAcmeVaultCertificate { $script:acmeVault = $script:acmeCandidate.metadata.Clone() }
        Mock Start-Sleep {}
    }

    It 'checks health without importing a client profile or attempting certificate operations' {
        (Invoke-LabAcmeWorkflow @script:acmeArgs) | Should -Be 23
        $script:acmeVault = $script:acmeCandidate.metadata.Clone()
        (Invoke-LabAcmeWorkflow @script:acmeArgs) | Should -Be 20
        $script:acmeVault.notAfter = $script:acmeNow.AddDays(30).ToString('O')
        (Invoke-LabAcmeWorkflow @script:acmeArgs) | Should -Be 21
        $script:acmeVault.notAfter = $script:acmeNow.AddDays(7).ToString('O')
        (Invoke-LabAcmeWorkflow @script:acmeArgs) | Should -Be 22
        Should -Invoke Initialize-LabAcmeProfile -Times 0
        Should -Invoke Invoke-LabAcmeClientIssuance -Times 0
        Should -Invoke Import-LabAcmeVaultCertificate -Times 0
    }

    It 'refuses missing owner/public-query acknowledgements before authentication' {
        foreach ($name in @('OwnerAuthorized', 'MicrosoftOwnedTestEnvironment', 'AcceptPublicDnsQueries')) {
            $argsCopy = $script:acmeArgs.Clone()
            $argsCopy[$name] = $false
            (Invoke-LabAcmeWorkflow @argsCopy) | Should -Be 90
        }
        Should -Invoke Connect-LabAcmeIdentity -Times 0
    }

    It 'fails closed before public DNS or issuance when approved identity lacks ownership metadata reads' {
        Mock Get-LabAcmeResourceSet { throw 'SYNTHETIC_METADATA_READ_FORBIDDEN' }
        (Invoke-LabAcmeWorkflow @script:acmeArgs -Mode Preview) | Should -Be 90
        Should -Invoke Assert-LabAcmeDelegation -Times 0
        Should -Invoke Invoke-LabAcmeClientIssuance -Times 0
        Should -Invoke Import-LabAcmeVaultCertificate -Times 0
    }

    It 'records staging proof without importing staging material into Key Vault' {
        (Invoke-LabAcmeWorkflow @script:acmeArgs -Mode Preview) | Should -Be 27
        $plan = Read-LabAcmePrivateJson $script:acmeArgs.PlanPath
        $result = Invoke-LabAcmeWorkflow @script:acmeArgs -Mode Apply -ApprovedPlanSha256 (Get-LabObjectDigest $plan)
        if ($result -eq 90) { throw $Error[0] }
        $result | Should -Be 24
        $state = Get-LabAcmeState $script:acmeConfig
        $state.staging.configSha256 | Should -BeExactly (Get-LabObjectDigest $script:acmeConfig)
        $state.receipt | Should -BeNullOrEmpty
        Should -Invoke Invoke-LabAcmeClientIssuance -Times 1 -Exactly
        Should -Invoke Import-LabAcmeVaultCertificate -Times 0
    }

    It 'requires successful staging and explicit production terms/CT approvals' {
        $script:acmeArgs.Stage = 'Production'
        (Invoke-LabAcmeWorkflow @script:acmeArgs -Mode Preview) | Should -Be 90
        $state = Get-LabAcmeState $script:acmeConfig
        $state.staging = @{
            configSha256 = Get-LabObjectDigest $script:acmeConfig; validatedAt = $script:acmeNow.ToString('O')
            notAfter = $script:acmeNow.AddDays(30).ToString('O'); thumbprint = 'B' * 40
        }
        Write-LabAcmePrivateJson (Get-LabAcmePrivateFile $script:acmeConfig 'lifecycle.json') $state
        (Invoke-LabAcmeWorkflow @script:acmeArgs -Mode Preview) | Should -Be 27
        $plan = Read-LabAcmePrivateJson $script:acmeArgs.PlanPath
        foreach ($name in @('AcceptAcmeTerms', 'AcceptCertificateTransparency')) {
            $argsCopy = $script:acmeArgs.Clone(); $argsCopy[$name] = $false
            (Invoke-LabAcmeWorkflow @argsCopy -Mode Apply -ApprovedPlanSha256 (Get-LabObjectDigest $plan)) |
                Should -Be 90
        }
        $result = Invoke-LabAcmeWorkflow @script:acmeArgs -Mode Apply -ApprovedPlanSha256 (Get-LabObjectDigest $plan)
        if ($result -eq 90) { throw $Error[0] }
        $result | Should -Be 25
        $receipt = (Get-LabAcmeState $script:acmeConfig).receipt
        $receipt.rotationStatus | Should -BeExactly 'PendingConsumerValidation'
        $receipt.secretUri | Should -BeExactly 'https://kv-synthetic-lab.vault.azure.net/secrets/lab-tls'
        Should -Invoke Import-LabAcmeVaultCertificate -Times 1 -Exactly
    }

    It 'fails on plan state drift and does not silently reissue or import' {
        (Invoke-LabAcmeWorkflow @script:acmeArgs -Mode Preview) | Should -Be 27
        $plan = Read-LabAcmePrivateJson $script:acmeArgs.PlanPath
        $script:acmeVault = $script:acmeCandidate.metadata.Clone()
        (Invoke-LabAcmeWorkflow @script:acmeArgs -Mode Apply -ApprovedPlanSha256 (Get-LabObjectDigest $plan)) |
            Should -Be 90
        Should -Invoke Invoke-LabAcmeClientIssuance -Times 0
        Should -Invoke Import-LabAcmeVaultCertificate -Times 0
    }

    It 'resumes completed issuance after a failure without issuing another certificate' {
        Mock Clear-LabAcmeDnsJournal {
            if ($null -ne $script:acmeClient) { throw 'SYNTHETIC_PRIVATE_CANARY' }
        }
        (Invoke-LabAcmeWorkflow @script:acmeArgs -Mode Preview) | Should -Be 27
        $plan = Read-LabAcmePrivateJson $script:acmeArgs.PlanPath
        (Invoke-LabAcmeWorkflow @script:acmeArgs -Mode Apply -ApprovedPlanSha256 (Get-LabObjectDigest $plan)) |
            Should -Be 90
        Mock Clear-LabAcmeDnsJournal {}
        $script:acmeArgs.PlanPath = Join-Path $script:acmeConfig.stateDirectory 'approval-resume.json'
        (Invoke-LabAcmeWorkflow @script:acmeArgs -Mode Preview) | Should -Be 27
        $plan = Read-LabAcmePrivateJson $script:acmeArgs.PlanPath
        $plan.action | Should -BeExactly 'Record'
        (Invoke-LabAcmeWorkflow @script:acmeArgs -Mode Apply -ApprovedPlanSha256 (Get-LabObjectDigest $plan)) |
            Should -Be 24
        (Get-LabAcmeState $script:acmeConfig).staging.thumbprint | Should -BeExactly ('A' * 40)
        Should -Invoke Invoke-LabAcmeClientIssuance -Times 1 -Exactly
    }

    It 'does not issue for a healthy production certificate unless rotation is explicitly approved' {
        $script:acmeArgs.Stage = 'Production'
        Write-SyntheticAcmeStaging $script:acmeConfig
        $script:acmeVault = $script:acmeCandidate.metadata.Clone()
        (Invoke-LabAcmeWorkflow @script:acmeArgs -Mode Preview) | Should -Be 27
        $plan = Read-LabAcmePrivateJson $script:acmeArgs.PlanPath
        $plan.action | Should -BeExactly 'NotDue'
        (Invoke-LabAcmeWorkflow @script:acmeArgs -Mode Apply -ApprovedPlanSha256 (Get-LabObjectDigest $plan)) |
            Should -Be 26
        Should -Invoke Invoke-LabAcmeClientIssuance -Times 0
        Should -Invoke Import-LabAcmeVaultCertificate -Times 0
        $script:acmeVault.thumbprint = 'B' * 40
        $script:acmeVault.notAfter = $script:acmeNow.AddDays(45).ToString('O')
        $script:acmeArgs.Rotate = $true
        $script:acmeArgs.PlanPath = Join-Path $script:acmeConfig.stateDirectory 'approval-rotation.json'
        (Invoke-LabAcmeWorkflow @script:acmeArgs -Mode Preview) | Should -Be 27
        $plan = Read-LabAcmePrivateJson $script:acmeArgs.PlanPath
        $plan.action | Should -BeExactly 'Issue'
        $plan.rotate | Should -BeTrue
        $withoutRotation = $script:acmeArgs.Clone(); $withoutRotation.Remove('Rotate')
        (Invoke-LabAcmeWorkflow @withoutRotation -Mode Apply -ApprovedPlanSha256 (Get-LabObjectDigest $plan)) |
            Should -Be 90
        (Invoke-LabAcmeWorkflow @script:acmeArgs -Mode Apply -ApprovedPlanSha256 (Get-LabObjectDigest $plan)) |
            Should -Be 25
        Should -Invoke Invoke-LabAcmeClientIssuance -Times 1 -Exactly
        Should -Invoke Import-LabAcmeVaultCertificate -Times 1 -Exactly
    }

    It 'renews production within thirty days and resumes a completed import without another issuance/version' {
        $script:acmeArgs.Stage = 'Production'
        Write-SyntheticAcmeStaging $script:acmeConfig
        $script:acmeVault = @{
            thumbprint = 'B' * 40; notAfter = $script:acmeNow.AddDays(29).ToString('O')
            notBefore = $script:acmeNow.AddDays(-60).ToString('O')
        }
        (Invoke-LabAcmeWorkflow @script:acmeArgs -Mode Preview) | Should -Be 27
        $plan = Read-LabAcmePrivateJson $script:acmeArgs.PlanPath
        $plan.action | Should -BeExactly 'Issue'
        Mock Import-LabAcmeVaultCertificate {
            $script:acmeVault = $script:acmeCandidate.metadata.Clone()
            $script:readbackUnavailable = $true
            # Simulate a successfully imported version followed by process death before readback/receipt.
            throw 'SYNTHETIC_PRIVATE_CANARY'
        }
        Mock Get-LabAcmeVaultCertificate {
            if ($script:readbackUnavailable) { throw 'SYNTHETIC_PRIVATE_CANARY' }
            return $script:acmeVault
        }
        $script:readbackUnavailable = $false
        (Invoke-LabAcmeWorkflow @script:acmeArgs -Mode Apply -ApprovedPlanSha256 (Get-LabObjectDigest $plan)) |
            Should -Be 90
        # Complete the known service operation, then allow metadata readback in a newly approved run.
        $script:acmeVault = $script:acmeCandidate.metadata.Clone()
        Mock Get-LabAcmeVaultCertificate { $script:acmeVault }
        $script:acmeArgs.PlanPath = Join-Path $script:acmeConfig.stateDirectory 'approval-import-resume.json'
        (Invoke-LabAcmeWorkflow @script:acmeArgs -Mode Preview) | Should -Be 27
        $plan = Read-LabAcmePrivateJson $script:acmeArgs.PlanPath
        $plan.action | Should -BeExactly 'Record'
        (Invoke-LabAcmeWorkflow @script:acmeArgs -Mode Apply -ApprovedPlanSha256 (Get-LabObjectDigest $plan)) |
            Should -Be 25
        Should -Invoke Invoke-LabAcmeClientIssuance -Times 1 -Exactly
        Should -Invoke Import-LabAcmeVaultCertificate -Times 1 -Exactly
    }

    It 'uses readback after a lost import response instead of creating a duplicate version' {
        $session = @{ config = $script:acmeConfig; plan = @{ expiresAt = $script:acmeNow.AddMinutes(30).ToString('O') } }
        Mock Import-LabAcmeVaultCertificate {
            $script:acmeVault = $script:acmeCandidate.metadata.Clone()
            throw 'SYNTHETIC_PRIVATE_CANARY'
        }
        (Complete-LabAcmeImport $session $script:acmeCandidate $null).thumbprint | Should -BeExactly ('A' * 40)
        Should -Invoke Import-LabAcmeVaultCertificate -Times 1 -Exactly
    }

    It 'rejects rollback and refuses an expired write window' {
        $session = @{ config = $script:acmeConfig; plan = @{ expiresAt = $script:acmeNow.AddMinutes(30).ToString('O') } }
        $script:acmeVault = @{
            thumbprint = 'B' * 40; notAfter = $script:acmeNow.AddDays(120).ToString('O')
            notBefore = $script:acmeNow.AddDays(-1).ToString('O')
        }
        { Complete-LabAcmeImport $session $script:acmeCandidate $script:acmeVault } | Should -Throw
        $session.plan.expiresAt = $script:acmeNow.ToString('O')
        { Complete-LabAcmeImport $session $script:acmeCandidate $script:acmeVault } | Should -Throw
        Should -Invoke Import-LabAcmeVaultCertificate -Times 0
    }
}

Describe 'Bounded process and public status-only output' {
    BeforeAll { $script:processCounter = 0 }

    It 'discards Console stdout/stderr and all PowerShell streams before accepting a closed exit status' {
        $worker = Join-Path $TestDrive 'synthetic-streams.ps1'
        [IO.File]::WriteAllText($worker, @'
[Console]::Out.WriteLine('SYNTHETIC_PRIVATE_CANARY')
[Console]::Error.WriteLine('SYNTHETIC_PRIVATE_CANARY')
Write-Output 'SYNTHETIC_PRIVATE_CANARY'
Write-Warning 'SYNTHETIC_PRIVATE_CANARY'
Write-Verbose 'SYNTHETIC_PRIVATE_CANARY' -Verbose
Write-Debug 'SYNTHETIC_PRIVATE_CANARY' -Debug
Write-Information 'SYNTHETIC_PRIVATE_CANARY' -InformationAction Continue
Write-Error 'SYNTHETIC_PRIVATE_CANARY'
exit 24
'@)
        $result = @(Invoke-LabAcmeWorkerProcess $worker @() *>&1)
        $result.Count | Should -Be 1
        $result[0] | Should -Be 24
    }

    It 'fails closed on output floods, unexpected exit codes and child timeouts' -ForEach @(
        @{ Body = "[Console]::Out.Write(('SYNTHETIC_PRIVATE_CANARY' * 1000)); exit 24"; Limit = 128; Timeout = 20 }
        @{ Body = 'exit 99'; Limit = 4096; Timeout = 20 }
        @{ Body = 'Start-Sleep -Seconds 30; exit 24'; Limit = 4096; Timeout = 1 }
    ) {
        $worker = Join-Path $TestDrive 'synthetic-failure.ps1'
        [IO.File]::WriteAllText($worker, $Body)
        $result = @(Invoke-LabAcmeWorkerProcess $worker @() -MaxOutputBytes $Limit -TimeoutSeconds $Timeout *>&1)
        $result.Count | Should -Be 1
        $result[0] | Should -Be 90
    }

    It 'emits one fixed failure with no input paths or exception details from the real public CLI' {
        $entry = Join-Path $script:acmeSource 'Invoke-LabAcme.ps1'
        $output = @(& pwsh -NoProfile -File $entry -ConfigPath 'SYNTHETIC_PRIVATE_CANARY' *>&1)
        $LASTEXITCODE | Should -Be 1
        ($output -join "`n").Trim() | Should -BeExactly 'LAB_ACME_INCOMPLETE'
    }
}
