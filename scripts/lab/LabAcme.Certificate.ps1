#Requires -Version 7.4
Set-StrictMode -Version Latest

function Assert-LabAcmeCertificateName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Security.Cryptography.X509Certificates.X509Certificate2] $Certificate,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Config
    )
    $extensions = @($Certificate.Extensions | Where-Object { $_.Oid.Value -ceq '2.5.29.17' })
    Assert-LabCondition ($extensions.Count -eq 1)
    $reader = [System.Formats.Asn1.AsnReader]::new(
        [ReadOnlyMemory[byte]]::new($extensions[0].RawData), [System.Formats.Asn1.AsnEncodingRules]::DER)
    $sequence = $reader.ReadSequence()
    $names = @(
        while ($sequence.HasData) {
            $tag = $sequence.PeekTag()
            Assert-LabCondition ($tag.TagClass -eq [System.Formats.Asn1.TagClass]::ContextSpecific -and $tag.TagValue -eq 2)
            $sequence.ReadCharacterString([System.Formats.Asn1.UniversalTagNumber]::IA5String, $tag)
        }
    )
    $reader.ThrowIfNotEmpty()
    $expected = @($Config.hostnames.gateway, $Config.hostnames.apim, $Config.hostnames.backend)
    Assert-LabCondition ($names.Count -eq 3 -and
        (Get-LabObjectDigest @($names | Sort-Object)) -ceq (Get-LabObjectDigest @($expected | Sort-Object)))
}

function Assert-LabAcmeCertificateKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Security.Cryptography.X509Certificates.X509Certificate2] $Certificate)
    Assert-LabCondition ($Certificate.HasPrivateKey)
    $rsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
    if ($null -ne $rsa) {
        try { Assert-LabCondition ($rsa.KeySize -ge 2048) }
        finally { $rsa.Dispose() }
        return
    }
    $ec = [Security.Cryptography.X509Certificates.ECDsaCertificateExtensions]::GetECDsaPrivateKey($Certificate)
    Assert-LabCondition ($null -ne $ec)
    try { Assert-LabCondition ($ec.KeySize -ge 256) }
    finally { $ec.Dispose() }
}

function Get-LabAcmeCandidateFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $ProfileDirectory)
    $full = Get-LabPrivatePath $Path
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    Assert-LabCondition ($full.StartsWith("$ProfileDirectory$([IO.Path]::DirectorySeparatorChar)", $comparison))
    Assert-LabAcmePrivateAccess $full
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    Assert-LabCondition (-not $item.PSIsContainer -and $item.Length -gt 0 -and $item.Length -le 1048576)
    return $full
}

function Assert-LabAcmeCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Session,
        [Parameter(Mandatory)][object] $ClientCertificate
    )
    $profileDirectory = $Session.home
    $certPath = Get-LabAcmeCandidateFile $ClientCertificate.CertFile $profileDirectory
    $keyPath = Get-LabAcmeCandidateFile $ClientCertificate.KeyFile $profileDirectory
    $chainPath = Get-LabAcmeCandidateFile $ClientCertificate.FullChainFile $profileDirectory
    $pfxPath = Get-LabAcmeCandidateFile $ClientCertificate.PfxFullChain $profileDirectory
    Assert-LabCondition ($ClientCertificate.PfxPass -is [Security.SecureString])
    $leaf = $null
    $pfx = $null
    $chain = $null
    $collection = [Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
    $bundle = [Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
    try {
        $leaf = [Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPemFile($certPath, $keyPath)
        Assert-LabAcmeCertificateKey $leaf
        Assert-LabAcmeCertificateName $leaf $Session.config
        $now = Get-LabAcmeUtcNow
        Assert-LabCondition ($leaf.NotBefore.ToUniversalTime() -le $now.UtcDateTime -and
            $leaf.NotAfter.ToUniversalTime() -gt $now.AddDays(1).UtcDateTime)
        $pfx = [Security.Cryptography.X509Certificates.X509Certificate2]::new($pfxPath,
            $ClientCertificate.PfxPass, [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
        Assert-LabCondition ($pfx.Thumbprint -ceq $leaf.Thumbprint)
        Assert-LabAcmeCertificateKey $pfx
        $collection.ImportFromPem([IO.File]::ReadAllText($chainPath))
        Assert-LabCondition ($collection.Count -ge 1 -and $collection.Count -le 16 -and
            @($collection | Where-Object Thumbprint -CEQ $leaf.Thumbprint).Count -eq 1)
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($ClientCertificate.PfxPass)
        $plain = $null
        try {
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringUni($pointer)
            $bundle.Import($pfxPath, $plain,
                [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
        }
        finally {
            $plain = $null
            [Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($pointer)
        }
        Assert-LabCondition ($bundle.Count -eq $collection.Count -and
            (Get-LabObjectDigest @($bundle.Thumbprint | Sort-Object)) -ceq
            (Get-LabObjectDigest @($collection.Thumbprint | Sort-Object)))
        if ($Session.stage -ceq 'Production') {
            $chain = [Security.Cryptography.X509Certificates.X509Chain]::new()
            $chain.ChainPolicy.DisableCertificateDownloads = $true
            $chain.ChainPolicy.RevocationMode = [Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
            $chain.ChainPolicy.VerificationFlags = [Security.Cryptography.X509Certificates.X509VerificationFlags]::NoFlag
            $chain.ChainPolicy.ApplicationPolicy.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.1'))
            $chain.ChainPolicy.ExtraStore.AddRange($collection)
            Assert-LabCondition ($chain.Build($leaf))
        }
        return @{
            thumbprint = $leaf.Thumbprint; notAfter = ([DateTimeOffset]$leaf.NotAfter.ToUniversalTime()).ToString('O')
            notBefore = ([DateTimeOffset]$leaf.NotBefore.ToUniversalTime()).ToString('O')
            pfxPath = $pfxPath; password = $ClientCertificate.PfxPass
            metadata = @{
                thumbprint = $leaf.Thumbprint; notAfter = ([DateTimeOffset]$leaf.NotAfter.ToUniversalTime()).ToString('O')
                notBefore = ([DateTimeOffset]$leaf.NotBefore.ToUniversalTime()).ToString('O')
            }
        }
    }
    finally {
        if ($null -ne $chain) { $chain.Dispose() }
        if ($null -ne $leaf) { $leaf.Dispose() }
        if ($null -ne $pfx) { $pfx.Dispose() }
        foreach ($certificate in $collection) { $certificate.Dispose() }
        foreach ($certificate in $bundle) { $certificate.Dispose() }
    }
}

function Get-LabAcmeIssuanceIntent {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Session)
    $file = Get-LabAcmePrivateFile $Session.config "$($Session.stage.ToLowerInvariant())-issuance.json"
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $intent = Read-LabAcmePrivateJson $file
    Assert-LabAcmeShape $intent @('schemaVersion', 'configSha256', 'stage', 'priorThumbprint', 'issuedAt')
    Assert-LabAcmeStringMember $intent @('schemaVersion', 'configSha256', 'stage', 'priorThumbprint', 'issuedAt')
    Assert-LabCondition ($intent.schemaVersion -ceq '1.0' -and $intent.stage -ceq $Session.stage -and
        $intent.configSha256 -ceq (Get-LabObjectDigest $Session.config) -and
        ($intent.priorThumbprint -ceq '' -or $intent.priorThumbprint -cmatch '^[A-F0-9]{40}$') -and
        (ConvertTo-LabAcmeTimestamp $intent.issuedAt) -le (Get-LabAcmeUtcNow))
    return $intent
}

function Get-LabAcmeCandidate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Session)
    $intent = Get-LabAcmeIssuanceIntent $Session
    if ($null -eq $intent) { return $null }
    $clientCertificate = Get-LabAcmeClientCertificate $Session
    if ($null -eq $clientCertificate) { return $null }
    if ($clientCertificate.Thumbprint -ceq $intent.priorThumbprint) { return $null }
    $candidate = Assert-LabAcmeCandidate $Session $clientCertificate
    Assert-LabCondition ([DateTimeOffset]::Parse($candidate.notBefore) -ge
        ([DateTimeOffset]::Parse($intent.issuedAt)).AddHours(-2))
    return $candidate
}

function Clear-LabAcmeExport {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Session)
    $clientCertificate = Get-LabAcmeClientCertificate $Session
    Assert-LabCondition ($null -ne $clientCertificate)
    # Keep account/order state for renewal; discard only the client's fixed export names.
    foreach ($property in @('PfxFile', 'PfxFullChain')) {
        $path = $clientCertificate.$property
        if (-not [string]::IsNullOrEmpty($path) -and (Test-Path -LiteralPath $path)) {
            $file = Get-LabAcmeCandidateFile $path $Session.home
            [IO.File]::Delete($file)
        }
    }
}
