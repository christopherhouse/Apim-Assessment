#Requires -Version 7.4
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'LabBootstrap.Core.ps1')

function ConvertFrom-LabAcmeJsonElement {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Text.Json.JsonElement] $Element)
    switch ($Element.ValueKind) {
        Object {
            $value = @{}
            foreach ($property in $Element.EnumerateObject()) {
                $value[$property.Name] = ConvertFrom-LabAcmeJsonElement $property.Value
            }
            return $value
        }
        Array { return ,@($Element.EnumerateArray() | ForEach-Object { ConvertFrom-LabAcmeJsonElement $_ }) }
        String { return $Element.GetString() }
        Number { return $Element.GetDecimal() }
        True { return $true }
        False { return $false }
        Null { return $null }
        default { throw 'LAB_ACME_JSON_INVALID' }
    }
}

function Read-LabAcmeJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Text)
    # Preserve timestamp strings across PowerShell versions so approved digests round-trip exactly.
    $null = Read-LabJson $Text
    $document = [System.Text.Json.JsonDocument]::Parse($Text)
    try { return ConvertFrom-LabAcmeJsonElement $document.RootElement }
    finally { $document.Dispose() }
}

function Assert-LabAcmeShape {
    [CmdletBinding()]
    param(
        [AllowNull()][object] $Value,
        [Parameter(Mandatory)][string[]] $Keys
    )
    Assert-LabCondition ($Value -is [System.Collections.IDictionary])
    Assert-LabCondition ((Get-LabObjectDigest @($Value.Keys | Sort-Object)) -ceq
        (Get-LabObjectDigest @($Keys | Sort-Object)))
}

function Assert-LabAcmeStringMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Value,
        [Parameter(Mandatory)][string[]] $Keys
    )
    foreach ($key in $Keys) { Assert-LabCondition ($Value[$key] -is [string]) }
}

function ConvertTo-LabAcmeTimestamp {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Value)
    Assert-LabCondition ($Value -is [string])
    $timestamp = [DateTimeOffset]::ParseExact($Value, 'O', [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None)
    Assert-LabCondition ($timestamp.Offset -eq [TimeSpan]::Zero)
    return $timestamp
}

function Test-LabAcmePathOverlap {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string] $Left, [Parameter(Mandatory)][string] $Right)
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $separator = [IO.Path]::DirectorySeparatorChar
    $a = [IO.Path]::GetFullPath($Left).TrimEnd($separator)
    $b = [IO.Path]::GetFullPath($Right).TrimEnd($separator)
    return $a.Equals($b, $comparison) -or $a.StartsWith("$b$separator", $comparison) -or
        $b.StartsWith("$a$separator", $comparison)
}

function Assert-LabAcmePrivateAccess {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    $null = Get-LabPrivatePath $Path
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($IsWindows) {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $allowed = @($owner, 'S-1-5-18', 'S-1-5-32-544')
        Assert-LabCondition ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ceq $owner)
        foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            Assert-LabCondition ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
                $rule.IdentityReference.Value -cin $allowed)
        }
    }
    else {
        $mode = [IO.File]::GetUnixFileMode($Path)
        $expected = if ($item.PSIsContainer) { 448 } else { 384 }
        Assert-LabCondition ([int]$mode -eq $expected)
        $start = [Diagnostics.ProcessStartInfo]::new('/usr/bin/stat')
        $start.UseShellExecute = $false
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        if ($IsMacOS) {
            $start.ArgumentList.Add('-f'); $start.ArgumentList.Add('%Su')
        }
        else { $start.ArgumentList.Add('--format=%U'); $start.ArgumentList.Add('--') }
        $start.ArgumentList.Add($Path)
        $process = [Diagnostics.Process]::Start($start)
        try {
            $actualOwner = $process.StandardOutput.ReadToEnd().Trim()
            $null = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            Assert-LabCondition ($process.ExitCode -eq 0 -and $actualOwner -ceq [Environment]::UserName)
        }
        finally { $process.Dispose() }
    }
}

function Get-LabAcmeWindowsSecurity {
    [CmdletBinding()]
    [OutputType([Security.AccessControl.FileSystemSecurity])]
    param([switch] $Directory)
    $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = if ($Directory) { [Security.AccessControl.DirectorySecurity]::new() }
        else { [Security.AccessControl.FileSecurity]::new() }
    $acl.SetOwner($owner)
    $acl.SetAccessRuleProtection($true, $false)
    $inherit = if ($Directory) {
        [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    } else { [Security.AccessControl.InheritanceFlags]::None }
    foreach ($sid in @($owner.Value, 'S-1-5-18', 'S-1-5-32-544')) {
        $identity = [Security.Principal.SecurityIdentifier]::new($sid)
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($identity,
            [Security.AccessControl.FileSystemRights]::FullControl, $inherit,
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow)
        $null = $acl.AddAccessRule($rule)
    }
    return $acl
}

function Initialize-LabAcmePrivateAccess {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    Assert-LabCondition (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)
    if ($IsWindows) {
        $acl = Get-LabAcmeWindowsSecurity -Directory:$item.PSIsContainer
        if ($item.PSIsContainer) { [IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]$item, $acl) }
        else { [IO.FileSystemAclExtensions]::SetAccessControl([IO.FileInfo]$item, $acl) }
    }
    else { [IO.File]::SetUnixFileMode($Path, $(if ($item.PSIsContainer) { 448 } else { 384 })) }
}

function Get-LabAcmePrivateFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Config,
        [Parameter(Mandatory)][string] $Name
    )
    Assert-LabCondition ($Name -cmatch '^[a-z][a-z0-9-]*\.json$')
    return Join-Path $Config.stateDirectory $Name
}

function Read-LabAcmeConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    $file = Get-LabPrivatePath $Path
    Assert-LabCondition ($Path -ceq $file)
    Assert-LabAcmePrivateAccess $file
    $text = Read-LabPrivateText $file
    $config = Read-LabAcmeJson $text
    $schema = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) `
        'infra/live-validation-lab/acme.config.schema.json'
    Assert-LabCondition (Test-Json -Json $text -SchemaFile $schema -ErrorAction Stop)
    foreach ($name in @('tenantId', 'subscriptionId')) {
        Assert-LabCondition ([guid]$config[$name] -ne [guid]::Empty)
    }
    $names = @($config.hostnames.gateway, $config.hostnames.apim, $config.hostnames.backend)
    Assert-LabCondition (@($names | Select-Object -Unique).Count -eq 3)
    foreach ($name in @($names) + @($config.challengeZoneName)) {
        $ip = $null
        Assert-LabCondition (-not [Net.IPAddress]::TryParse($name, [ref]$ip))
    }
    $root = Get-LabPrivatePath $config.stateDirectory
    Assert-LabCondition ($config.stateDirectory -ceq $root -and -not $root.Contains('%'))
    Assert-LabCondition (Test-Path -LiteralPath $root -PathType Container)
    Assert-LabAcmePrivateAccess $root
    if ($IsWindows) {
        Assert-LabCondition ((Get-Acl -LiteralPath $root).AreAccessRulesProtected)
    }
    $config.stateDirectory = $root
    foreach ($visible in $config.modelVisibleRoots) {
        Assert-LabCondition ([IO.Path]::IsPathFullyQualified($visible))
        Assert-LabCondition ($visible -ceq [IO.Path]::GetFullPath($visible))
        Assert-LabCondition (-not (Test-LabAcmePathOverlap $root $visible) -and
            -not (Test-LabAcmePathOverlap $file $visible))
    }
    return $config
}

function Write-LabAcmePrivateJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Value,
        [switch] $CreateNew
    )
    $null = Get-LabPrivatePath $Path
    Assert-LabAcmePrivateAccess ([IO.Path]::GetDirectoryName($Path))
    if (Test-Path -LiteralPath $Path) { Assert-LabAcmePrivateAccess $Path }
    $text = ConvertTo-Json (ConvertTo-LabCanonicalValue $Value) -Depth 40 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    Assert-LabCondition ($bytes.Length -le 1048576)
    if ($CreateNew) {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            if (-not $IsWindows) { [IO.File]::SetUnixFileMode($Path, 384) }
            $stream.Write($bytes)
            $stream.Flush($true)
        }
        finally { $stream.Dispose() }
        Initialize-LabAcmePrivateAccess $Path
        return
    }
    $temporary = Join-Path ([IO.Path]::GetDirectoryName($Path)) ("private-$([guid]::NewGuid().ToString('N')).json")
    try {
        Write-LabAcmePrivateJson -Path $temporary -Value $Value -CreateNew
        [IO.File]::Move($temporary, $Path, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { [IO.File]::Delete($temporary) }
    }
}

function Read-LabAcmePrivateJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    Assert-LabAcmePrivateAccess $Path
    return Read-LabAcmeJson (Read-LabPrivateText $Path)
}

function Open-LabAcmeLock {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Config)
    $path = Join-Path $Config.stateDirectory 'acme.lock'
    $null = Get-LabPrivatePath $path
    if (Test-Path -LiteralPath $path) { Assert-LabAcmePrivateAccess $path }
    $lock = if ($IsWindows) {
        $security = [Security.AccessControl.FileSecurity](Get-LabAcmeWindowsSecurity)
        [IO.FileSystemAclExtensions]::Create([IO.FileInfo]::new($path), [IO.FileMode]::OpenOrCreate,
            [Security.AccessControl.FileSystemRights]::FullControl, [IO.FileShare]::None,
            4096, [IO.FileOptions]::None, $security)
    }
    else {
        [IO.File]::Open($path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    }
    try {
        if (-not $IsWindows) { [IO.File]::SetUnixFileMode($path, 384) }
        return $lock
    }
    catch { $lock.Dispose(); throw }
}

function Get-LabAcmeUtcNow {
    [CmdletBinding()]
    param()
    return [DateTimeOffset]::UtcNow
}

function Get-LabAcmeState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Config)
    $file = Get-LabAcmePrivateFile $Config 'lifecycle.json'
    if (-not (Test-Path -LiteralPath $file)) {
        return @{ schemaVersion = '1.0'; staging = $null; receipt = $null }
    }
    $state = Read-LabAcmePrivateJson $file
    Assert-LabAcmeShape $state @('schemaVersion', 'staging', 'receipt')
    Assert-LabAcmeStringMember $state @('schemaVersion')
    Assert-LabCondition ($state.schemaVersion -ceq '1.0')
    if ($null -ne $state.staging) {
        Assert-LabAcmeShape $state.staging @('configSha256', 'validatedAt', 'notAfter', 'thumbprint')
        Assert-LabAcmeStringMember $state.staging @('configSha256', 'validatedAt', 'notAfter', 'thumbprint')
        Assert-LabCondition ($state.staging.configSha256 -cmatch '^[a-f0-9]{64}$' -and
            $state.staging.thumbprint -cmatch '^[A-F0-9]{40}$')
        $null = ConvertTo-LabAcmeTimestamp $state.staging.validatedAt
        $null = ConvertTo-LabAcmeTimestamp $state.staging.notAfter
    }
    if ($null -ne $state.receipt) {
        Assert-LabAcmeShape $state.receipt @('configSha256', 'thumbprint', 'notAfter', 'secretUri', 'rotationStatus')
        Assert-LabAcmeStringMember $state.receipt @('configSha256', 'thumbprint', 'notAfter', 'secretUri', 'rotationStatus')
        Assert-LabCondition ($state.receipt.configSha256 -cmatch '^[a-f0-9]{64}$' -and
            $state.receipt.thumbprint -cmatch '^[A-F0-9]{40}$' -and
            $state.receipt.secretUri -ceq "https://$($Config.keyVaultName).vault.azure.net/secrets/$($Config.certificateName)" -and
            $state.receipt.rotationStatus -ceq 'PendingConsumerValidation')
        $null = ConvertTo-LabAcmeTimestamp $state.receipt.notAfter
    }
    return $state
}

function Assert-LabAcmeStaging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Config,
        [Parameter(Mandatory)][System.Collections.IDictionary] $State
    )
    $proof = $State.staging
    $now = Get-LabAcmeUtcNow
    Assert-LabCondition ($null -ne $proof -and $proof.configSha256 -ceq (Get-LabObjectDigest $Config))
    $validated = ConvertTo-LabAcmeTimestamp $proof.validatedAt
    Assert-LabCondition ($validated -le $now -and $validated -ge $now.AddDays(-7) -and
        (ConvertTo-LabAcmeTimestamp $proof.notAfter) -gt $now)
}

function Get-LabAcmePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Config,
        [Parameter(Mandatory)][string] $Stage,
        [Parameter(Mandatory)][string] $SnapshotSha256,
        [Parameter(Mandatory)][string] $Action,
        [switch] $Rotate
    )
    $now = Get-LabAcmeUtcNow
    return @{
        schemaVersion = '1.0'; configSha256 = Get-LabObjectDigest $Config
        snapshotSha256 = $SnapshotSha256; stage = $Stage; action = $Action
        rotate = [bool]$Rotate; issuedAt = $now.ToString('O'); expiresAt = $now.AddSeconds(1800).ToString('O')
    }
}

function Assert-LabAcmePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Config,
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Digest,
        [Parameter(Mandatory)][string] $Stage,
        [Parameter(Mandatory)][string] $SnapshotSha256,
        [switch] $Rotate
    )
    Assert-LabCondition ($Digest -cmatch '^[a-f0-9]{64}$')
    $file = Get-LabPrivatePath $Path
    Assert-LabCondition ([IO.Path]::GetDirectoryName($file) -ceq $Config.stateDirectory -and
        [IO.Path]::GetFileName($file) -cmatch '^approval-[a-z0-9-]+\.json$')
    $plan = Read-LabAcmePrivateJson $file
    Assert-LabAcmeShape $plan @('schemaVersion', 'configSha256', 'snapshotSha256', 'stage',
        'action', 'rotate', 'issuedAt', 'expiresAt')
    Assert-LabAcmeStringMember $plan @('schemaVersion', 'configSha256', 'snapshotSha256', 'stage',
        'action', 'issuedAt', 'expiresAt')
    Assert-LabCondition ($plan.schemaVersion -ceq '1.0' -and $plan.stage -ceq $Stage -and
        $plan.rotate -is [bool] -and $plan.rotate -eq [bool]$Rotate -and
        $plan.action -cin @('Issue', 'Import', 'Record', 'NotDue') -and
        (Get-LabObjectDigest $plan) -ceq $Digest -and
        $plan.configSha256 -ceq (Get-LabObjectDigest $Config) -and
        $plan.snapshotSha256 -ceq $SnapshotSha256)
    $issued = ConvertTo-LabAcmeTimestamp $plan.issuedAt
    $expires = ConvertTo-LabAcmeTimestamp $plan.expiresAt
    $now = Get-LabAcmeUtcNow
    Assert-LabCondition ($issued -le $now -and $expires -gt $now -and
        ($expires - $issued).TotalSeconds -eq 1800)
    return $plan
}

function Assert-LabAcmeWriteWindow {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Session)
    Assert-LabCondition ((Get-LabAcmeUtcNow) -lt (ConvertTo-LabAcmeTimestamp $Session.plan.expiresAt))
    Assert-LabAcmeContext $Session
}
