#Requires -Version 7.4
Set-StrictMode -Version Latest

function Get-LabAcmeHealth {
    [CmdletBinding()]
    [OutputType([int])]
    param([AllowNull()][object] $Certificate)
    if ($null -eq $Certificate) { return 23 }
    $now = Get-LabAcmeUtcNow
    Assert-LabCondition ([DateTimeOffset]::Parse($Certificate.notBefore) -le $now)
    $expiry = [DateTimeOffset]::Parse($Certificate.notAfter)
    if ($expiry -le $now.AddDays(7)) { return 22 }
    if ($expiry -le $now.AddDays(30)) { return 21 }
    return 20
}

function Get-LabAcmeSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Session,
        [switch] $Rotate
    )
    $state = Get-LabAcmeState $Session.config
    $journal = Get-LabAcmeDnsJournal $Session.config
    $intent = Get-LabAcmeIssuanceIntent $Session
    $vault = Get-LabAcmeVaultCertificate $Session
    $candidate = Get-LabAcmeCandidate $Session
    $client = Get-LabAcmeClientCertificate $Session
    $prior = if ($null -eq $client) { '' } else { $client.Thumbprint }
    Assert-LabCondition ($prior -ceq '' -or $prior -cmatch '^[A-F0-9]{40}$')
    $action = 'Issue'
    if ($null -ne $candidate) {
        if ($null -ne $vault -and $vault.thumbprint -ceq $candidate.thumbprint) { $action = 'Record' }
        elseif ($Session.stage -ceq 'Staging') { $action = 'Record' }
        else {
            Assert-LabCondition ($null -eq $vault -or
                [DateTimeOffset]::Parse($candidate.notAfter) -gt [DateTimeOffset]::Parse($vault.notAfter))
            $action = 'Import'
        }
    }
    elseif ($Session.stage -ceq 'Production' -and -not $Rotate -and (Get-LabAcmeHealth $vault) -eq 20) {
        $action = 'NotDue'
    }
    $metadata = if ($null -eq $candidate) { $null } else { $candidate.metadata }
    $value = @{
        resources = $Session.resources; state = $state; journal = $journal
        intent = $intent; vault = $vault; candidate = $metadata; priorThumbprint = $prior
        action = $action; stage = $Session.stage; rotate = [bool]$Rotate
    }
    return @{
        sha256 = Get-LabObjectDigest $value; action = $action; state = $state
        vault = $vault; candidate = $candidate; priorThumbprint = $prior
    }
}

function Complete-LabAcmeImport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Session,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Candidate,
        [AllowNull()][object] $Baseline
    )
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        Assert-LabAcmeWriteWindow $Session
        $current = Get-LabAcmeVaultCertificate $Session
        if ($null -ne $current -and $current.thumbprint -ceq $Candidate.thumbprint) { return $current }
        Assert-LabCondition ((Get-LabObjectDigest $current) -ceq (Get-LabObjectDigest $Baseline))
        Assert-LabCondition ($null -eq $current -or
            [DateTimeOffset]::Parse($Candidate.notAfter) -gt [DateTimeOffset]::Parse($current.notAfter))
        try {
            Import-LabAcmeVaultCertificate $Session $Candidate
            $current = Get-LabAcmeVaultCertificate $Session
            Assert-LabCondition ($null -ne $current -and $current.thumbprint -ceq $Candidate.thumbprint -and
                $current.notAfter -ceq $Candidate.notAfter)
            return $current
        }
        catch {
            $failure = $_
            # A successful import can lose its response; read metadata before attempting another version.
            $current = Get-LabAcmeVaultCertificate $Session
            if ($null -ne $current -and $current.thumbprint -ceq $Candidate.thumbprint -and
                $current.notAfter -ceq $Candidate.notAfter) { return $current }
            if ($attempt -eq 2 -or (Get-LabAcmeServiceStatus $failure) -notin @(429, 500, 502, 503, 504)) {
                throw $failure
            }
            Start-Sleep -Seconds ($attempt + 1)
        }
    }
}

function Invoke-LabAcmeWorkflow {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [string] $ConfigPath,
        [string] $Mode = 'Check',
        [string] $Stage = 'Staging',
        [string] $PlanPath,
        [string] $ApprovedPlanSha256,
        [switch] $OwnerAuthorized,
        [switch] $MicrosoftOwnedTestEnvironment,
        [switch] $AcceptPublicDnsQueries,
        [switch] $AcceptAcmeTerms,
        [switch] $AcceptCertificateTransparency,
        [switch] $Rotate
    )
    $lock = $null
    $session = $null
    try {
        Assert-LabCondition ($OwnerAuthorized -and $MicrosoftOwnedTestEnvironment -and $AcceptPublicDnsQueries -and
            $Mode -cin @('Check', 'Preview', 'Apply') -and $Stage -cin @('Staging', 'Production') -and
            (-not $Rotate -or $Stage -ceq 'Production'))
        if ($Mode -ceq 'Apply') {
            Assert-LabCondition ($AcceptAcmeTerms -and ($Stage -ceq 'Staging' -or $AcceptCertificateTransparency))
        }
        $config = Read-LabAcmeConfig $ConfigPath
        $lock = Open-LabAcmeLock $config
        Import-LabAcmeModule
        $context = Connect-LabAcmeIdentity $config
        $session = @{
            config = $config; context = $context; stage = $Stage; plan = $null
            nonce = [guid]::NewGuid().ToString('N'); generatedPassword = $null
        }
        Assert-LabAcmeContext $session
        $session.resources = Get-LabAcmeResourceSet $session
        if ($Mode -ceq 'Check') {
            return Get-LabAcmeHealth (Get-LabAcmeVaultCertificate $session)
        }
        Assert-LabAcmeDelegation $config $session.resources
        if ($Stage -ceq 'Production') { Assert-LabAcmeStaging $config (Get-LabAcmeState $config) }
        $session.home = Initialize-LabAcmeProfile $config $Stage
        $snapshot = Get-LabAcmeSnapshot $session -Rotate:$Rotate
        if ($Mode -ceq 'Preview') {
            $file = Get-LabPrivatePath $PlanPath
            Assert-LabCondition ([IO.Path]::GetDirectoryName($file) -ceq $config.stateDirectory -and
                [IO.Path]::GetFileName($file) -cmatch '^approval-[a-z0-9-]+\.json$')
            $plan = Get-LabAcmePlan $config $Stage $snapshot.sha256 $snapshot.action -Rotate:$Rotate
            Write-LabAcmePrivateJson $file $plan -CreateNew
            return 27
        }
        $session.plan = Assert-LabAcmePlan $config $PlanPath $ApprovedPlanSha256 $Stage $snapshot.sha256 -Rotate:$Rotate
        Assert-LabCondition ($session.plan.action -ceq $snapshot.action)
        Assert-LabAcmeWriteWindow $session
        if ($snapshot.action -ceq 'NotDue') { return 26 }
        Register-LabAcmeDnsDispatch $session
        Clear-LabAcmeDnsJournal $session
        $candidate = $snapshot.candidate
        if ($snapshot.action -ceq 'Issue') {
            $intent = @{
                schemaVersion = '1.0'; configSha256 = Get-LabObjectDigest $config; stage = $Stage
                priorThumbprint = $snapshot.priorThumbprint; issuedAt = (Get-LabAcmeUtcNow).ToString('O')
            }
            Write-LabAcmePrivateJson (Get-LabAcmePrivateFile $config "$($Stage.ToLowerInvariant())-issuance.json") $intent
            $issued = Invoke-LabAcmeClientIssuance $session
            Assert-LabCondition ($null -ne $issued)
            # Posh-ACME writes under the pre-protected home with the child's private umask.
            foreach ($item in Get-ChildItem -LiteralPath $session.home -Recurse -Force -ErrorAction Stop) {
                Initialize-LabAcmePrivateAccess $item.FullName
                Assert-LabAcmePrivateAccess $item.FullName
            }
            $candidate = Assert-LabAcmeCandidate $session $issued
            Assert-LabCondition ($candidate.thumbprint -cne $snapshot.priorThumbprint)
        }
        Assert-LabCondition ($null -ne $candidate)
        Clear-LabAcmeDnsJournal $session
        Assert-LabAcmeWriteWindow $session
        if ($Stage -ceq 'Staging') {
            $snapshot.state.staging = @{
                configSha256 = Get-LabObjectDigest $config; validatedAt = (Get-LabAcmeUtcNow).ToString('O')
                notAfter = $candidate.notAfter; thumbprint = $candidate.thumbprint
            }
            Write-LabAcmePrivateJson (Get-LabAcmePrivateFile $config 'lifecycle.json') $snapshot.state
            $code = 24
        }
        else {
            $null = Complete-LabAcmeImport $session $candidate $snapshot.vault
            $snapshot.state.receipt = @{
                configSha256 = Get-LabObjectDigest $config; thumbprint = $candidate.thumbprint
                notAfter = $candidate.notAfter
                secretUri = "https://$($config.keyVaultName).vault.azure.net/secrets/$($config.certificateName)"
                rotationStatus = 'PendingConsumerValidation'
            }
            Write-LabAcmePrivateJson (Get-LabAcmePrivateFile $config 'lifecycle.json') $snapshot.state
            $code = 25
        }
        $intentFile = Get-LabAcmePrivateFile $config "$($Stage.ToLowerInvariant())-issuance.json"
        if (Test-Path -LiteralPath $intentFile) {
            Assert-LabAcmePrivateAccess $intentFile
            [IO.File]::Delete($intentFile)
        }
        Clear-LabAcmeExport $session
        return $code
    }
    catch { return 90 }
    finally {
        if ($null -ne $session -and $null -ne $session.generatedPassword) { $session.generatedPassword.Dispose() }
        if ($null -ne $lock) { $lock.Dispose() }
        [AppDomain]::CurrentDomain.SetData('ApimAssessment.LabAcme.DnsDispatch', $null)
    }
}
