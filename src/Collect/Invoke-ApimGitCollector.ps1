#Requires -Version 7.4

Set-StrictMode -Version Latest

$script:GitPolicyHashesSchemaPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) `
    'schemas/git-policy-hashes.schema.json'

function Invoke-ApimGitRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Repository,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [int] $MaximumBytes = 8388608
    )

    # Only internal callers supply arguments. Never invoke a shell, hooks or a
    # working-tree filter. Read both pipes concurrently, with finite memory/time.
    $process = [System.Diagnostics.Process]::new()
    $started = $false
    $output = [System.IO.MemoryStream]::new()
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $start = [System.Diagnostics.ProcessStartInfo]::new()
        $start.FileName = 'git'
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        foreach ($key in @($start.Environment.Keys)) {
            if ($key.StartsWith('GIT_', [StringComparison]::OrdinalIgnoreCase)) {
                $null = $start.Environment.Remove($key)
            }
        }
        $start.Environment['GIT_CONFIG_NOSYSTEM'] = '1'
        $start.Environment['GIT_CONFIG_GLOBAL'] = if ($IsWindows) { 'NUL' } else { '/dev/null' }
        $start.Environment['GIT_NO_LAZY_FETCH'] = '1'
        $start.Environment['GIT_NO_REPLACE_OBJECTS'] = '1'
        $start.Environment['GIT_TERMINAL_PROMPT'] = '0'
        $start.Environment['GIT_OPTIONAL_LOCKS'] = '0'
        foreach ($argument in @(
                '--no-pager', '--no-replace-objects',
                '-c', 'protocol.allow=never', '-c', 'core.fsmonitor=false',
                '-c', 'core.hooksPath=', '-C', $Repository
            ) + $Arguments) {
            $start.ArgumentList.Add($argument)
        }
        $process.StartInfo = $start
        $null = $process.Start()
        $started = $true
        $outBuffer = [byte[]]::new(8192)
        $errBuffer = [byte[]]::new(4096)
        $outTask = $process.StandardOutput.BaseStream.ReadAsync($outBuffer, 0, $outBuffer.Length)
        $errTask = $process.StandardError.BaseStream.ReadAsync($errBuffer, 0, $errBuffer.Length)
        $outDone = $false
        $errDone = $false
        $errBytes = 0
        while (-not ($outDone -and $errDone -and $process.HasExited)) {
            if ($timer.Elapsed.TotalSeconds -gt 15) { throw 'Git read rejected.' }
            if (-not $outDone -and $outTask.IsCompleted) {
                $count = $outTask.GetAwaiter().GetResult()
                if ($count -eq 0) { $outDone = $true }
                else {
                    if ($output.Length + $count -gt $MaximumBytes) { throw 'Git read rejected.' }
                    $output.Write($outBuffer, 0, $count)
                    $outTask = $process.StandardOutput.BaseStream.ReadAsync($outBuffer, 0, $outBuffer.Length)
                }
            }
            if (-not $errDone -and $errTask.IsCompleted) {
                $count = $errTask.GetAwaiter().GetResult()
                $errBytes += $count
                if ($errBytes -gt 65536) { throw 'Git read rejected.' }
                if ($count -eq 0) { $errDone = $true }
                else {
                    $errTask = $process.StandardError.BaseStream.ReadAsync($errBuffer, 0, $errBuffer.Length)
                }
            }
            Start-Sleep -Milliseconds 2
        }
        if ($process.ExitCode -ne 0) { throw 'Git read rejected.' }
        return [System.Text.UTF8Encoding]::new($false, $true).GetString($output.ToArray())
    }
    catch { throw 'Git read rejected.' }
    finally {
        if ($started -and -not $process.HasExited) { $process.Kill($true) }
        $process.Dispose()
        $output.Dispose()
    }
}

function Test-ApimGitPolicySnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object] $Snapshot)

    try {
        $json = ConvertTo-Json -InputObject $Snapshot -Depth 10 -ErrorAction Stop
        if (-not (Test-Json -Json $json -SchemaFile $script:GitPolicyHashesSchemaPath `
                    -ErrorAction Stop)) {
            throw 'Git policy snapshot rejected.'
        }
        $coverage = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $previous = $null
        foreach ($scopeType in $Snapshot.scopeTypes) {
            if ($null -ne $previous -and [string]::CompareOrdinal($previous, $scopeType) -ge 0) {
                throw 'Git policy snapshot rejected.'
            }
            $null = $coverage.Add($scopeType)
            $previous = $scopeType
        }
        $previous = $null
        foreach ($policy in $Snapshot.policies) {
            $key = $policy.scopeType + '|' + $policy.scope
            if (-not $coverage.Contains($policy.scopeType) -or
                ($null -ne $previous -and [string]::CompareOrdinal($previous, $key) -ge 0)) {
                throw 'Git policy snapshot rejected.'
            }
            $previous = $key
        }
    }
    catch { throw 'Git policy snapshot rejected.' }
}

function Get-ApimGitPolicyMappingConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [System.Collections.IDictionary] $Environment)

    # Pure configuration validation: no filesystem, repository or process reads.
    try {
        $mappings = @(
            @{ ScopeType = 'Global'; Pattern = 'policy\.xml' }
            @{ ScopeType = 'Product'; Pattern = 'products/(?<product>[^/]+)/policy\.xml' }
            @{ ScopeType = 'Api'; Pattern = 'apis/(?<api>[^/]+)/policy\.xml' }
            @{ ScopeType = 'Operation'; Pattern = 'apis/(?<api>[^/]+)/operations/(?<operation>[^/]+)/policy\.xml' }
        )
        if ($Environment.Contains('GitPolicyMappings')) {
            $mappings = @($Environment['GitPolicyMappings'])
        }
        if ($mappings.Count -lt 1 -or $mappings.Count -gt 32) {
            throw 'Git policy mappings rejected.'
        }
        $compiled = [System.Collections.Generic.List[object]]::new()
        $coverage = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
        $patterns = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($mapping in $mappings) {
            if ($mapping -isnot [System.Collections.IDictionary] -or $mapping.Count -ne 2 -or
                -not $mapping.Contains('ScopeType') -or -not $mapping.Contains('Pattern') -or
                $mapping['ScopeType'] -cnotin @('Global', 'Product', 'Api', 'Operation', 'Fragment') -or
                $mapping['Pattern'] -isnot [string] -or $mapping['Pattern'].Length -lt 1 -or
                $mapping['Pattern'].Length -gt 1024 -or -not $patterns.Add($mapping['Pattern'])) {
                throw 'Git policy mappings rejected.'
            }
            # Wrapper anchoring cannot be bypassed by a configured alternation.
            $regex = [regex]::new('\A(?:' + $mapping['Pattern'] + ')\z',
                [System.Text.RegularExpressions.RegexOptions]::CultureInvariant,
                [TimeSpan]::FromMilliseconds(100))
            $required = @(switch -CaseSensitive ($mapping['ScopeType']) {
                'Global' { @() }
                'Api' { 'api' }
                'Product' { 'product' }
                'Operation' { 'api'; 'operation' }
                'Fragment' { 'fragment' }
            })
            foreach ($capture in $required) {
                if ($capture -cnotin $regex.GetGroupNames()) { throw 'Git policy mappings rejected.' }
            }
            $compiled.Add(@{ ScopeType = $mapping['ScopeType']; Regex = $regex; Captures = @($required) })
            $null = $coverage.Add($mapping['ScopeType'])
        }
        return [pscustomobject]@{
            Mappings = $compiled.ToArray()
            ScopeTypes = @($coverage)
        }
    }
    catch { throw 'Git policy mappings rejected.' }
}

function Get-ApimGitPolicySnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [System.Collections.IDictionary] $Environment)

    try {
        $repo = $Environment['GitRepoPath']
        $root = $Environment['GitPolicyRoot']
        if ($repo -isnot [string] -or -not [System.IO.Path]::IsPathFullyQualified($repo) -or
            $root -isnot [string] -or $root.Length -lt 1 -or $root.Length -gt 1024 -or
            [System.IO.Path]::IsPathRooted($root) -or $root -match '[\\:\x00-\x1f\x7f]' -or
            @($root.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) {
            throw 'Git policy collection failed.'
        }
        # Deliberately support ordinary local clones, not .git indirection files,
        # linked worktrees or bare repositories. Reject physical link ancestors.
        foreach ($path in @($repo, (Join-Path $repo '.git'))) {
            $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if (-not $item.PSIsContainer) { throw 'Git policy collection failed.' }
            while ($null -ne $item) {
                if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                    throw 'Git policy collection failed.'
                }
                $item = $item.Parent
            }
        }
        $mappingConfiguration = Get-ApimGitPolicyMappingConfiguration -Environment $Environment
        $compiled = $mappingConfiguration.Mappings
        $coverage = $mappingConfiguration.ScopeTypes
        # Pin HEAD exactly once. All subsequent reads use object IDs, never HEAD
        # or filesystem XML: dirty and untracked working-tree files are ignored.
        $commit = (Invoke-ApimGitRead -Repository $repo `
                -Arguments @('rev-parse', '--verify', 'HEAD^{commit}') -MaximumBytes 128).Trim()
        if ($commit -cnotmatch '\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z') {
            throw 'Git policy collection failed.'
        }
        $tree = Invoke-ApimGitRead -Repository $repo -Arguments @('ls-tree', '-r', '-t', '-z', $commit)
        $policies = [System.Collections.Generic.SortedDictionary[string, object]]::new([StringComparer]::Ordinal)
        $rootFound = $false
        $totalBytes = 0
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($entry in $tree.Split([char] 0, [StringSplitOptions]::RemoveEmptyEntries)) {
            if ($timer.Elapsed.TotalSeconds -gt 60) { throw 'Git policy collection failed.' }
            if ($entry -cnotmatch '\A([0-7]{6}) (blob|tree|commit) ([0-9a-f]{40}|[0-9a-f]{64})\t(.+)\z') {
                throw 'Git policy collection failed.'
            }
            $mode, $kind, $objectId, $path = $Matches[1], $Matches[2], $Matches[3], $Matches[4]
            $inside = $path.StartsWith($root + '/', [StringComparison]::Ordinal)
            $ancestor = $root.StartsWith($path + '/', [StringComparison]::Ordinal)
            if (-not ($inside -or $ancestor -or $path -ceq $root)) { continue }
            if ($mode -notin @('040000', '100644', '100755') -or
                $path.Contains('\') -or
                @($path.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) {
                throw 'Git policy collection failed.'
            }
            if ($path -ceq $root) {
                if ($kind -cne 'tree') { throw 'Git policy collection failed.' }
                $rootFound = $true
            }
            if ($kind -eq 'tree' -or -not $inside -or
                -not $path.EndsWith('.xml', [StringComparison]::OrdinalIgnoreCase)) { continue }
            $relative = $path.Substring($root.Length + 1)
            $found = @(
                foreach ($mapping in $compiled) {
                    $match = $mapping.Regex.Match($relative)
                    if ($match.Success) { @{ Mapping = $mapping; Match = $match } }
                }
            )
            if ($found.Count -ne 1) { throw 'Git policy collection failed.' }
            $mapping = $found[0].Mapping
            $segments = @(
                foreach ($capture in $mapping.Captures) {
                    $group = $found[0].Match.Groups[$capture]
                    if ($group.Captures.Count -ne 1 -or
                        $group.Value -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,255}\z') {
                        throw 'Git policy collection failed.'
                    }
                    $group.Value
                }
            )
            $scope = if ($mapping.ScopeType -ceq 'Global') { 'global' } else { $segments -join '|' }
            $key = $mapping.ScopeType + '|' + $scope
            if ($policies.ContainsKey($key) -or $policies.Count -ge 4096) {
                throw 'Git policy collection failed.'
            }
            $xml = Invoke-ApimGitRead -Repository $repo `
                -Arguments @('cat-file', 'blob', $objectId) -MaximumBytes 1048576
            $totalBytes += [System.Text.Encoding]::UTF8.GetByteCount($xml)
            if ($totalBytes -gt 16777216) { throw 'Git policy collection failed.' }
            if ($xml.StartsWith([string][char]0xfeff, [StringComparison]::Ordinal)) {
                $xml = $xml.Substring(1)
            }
            $protected = Protect-ApimPolicyXml -Xml $xml
            $policies.Add($key, [pscustomobject][ordered]@{
                    scopeType = $mapping.ScopeType
                    scope = $scope
                    sha256 = Get-ApimPolicySha256 -Xml $protected.Xml
                })
        }
        if (-not $rootFound) { throw 'Git policy collection failed.' }
        $snapshot = [pscustomobject][ordered]@{
            schemaVersion = '1.0'
            commitSha = $commit
            scopeTypes = @($coverage)
            policies = @($policies.Values)
        }
        Test-ApimGitPolicySnapshot -Snapshot $snapshot
        return $snapshot
    }
    catch { throw 'Git policy collection failed.' }
}

function Invoke-ApimGitCollector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RunPath,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Environment
    )

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Set-RunCollectorStatus -RunPath $RunPath -Name Git -Status InProgress
        $snapshot = Get-ApimGitPolicySnapshot -Environment $Environment
        Test-ApimGitPolicySnapshot -Snapshot $snapshot
        $path = Write-RunFile -RunPath $RunPath -RelativePath 'git/policyHashes.json' `
            -InputObject $snapshot
        Set-RunCollectorStatus -RunPath $RunPath -Name Git -Status Completed `
            -Items $snapshot.policies.Count -DurationSec $timer.Elapsed.TotalSeconds
        Write-RunLog -Path (Join-Path $RunPath 'logs/run.log') -Level Info `
            -Collector Git -Message 'Committed Git policy hashes collected.'
        return $path
    }
    catch {
        # Never leave stale success-shaped evidence after a failed retry.
        try {
            $path = Resolve-RunFilePath -RunPath $RunPath -RelativePath 'git/policyHashes.json'
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            }
            Set-RunCollectorStatus -RunPath $RunPath -Name Git -Status Failed `
                -Errors 1 -DurationSec $timer.Elapsed.TotalSeconds
            Write-RunLog -Path (Join-Path $RunPath 'logs/run.log') -Level Error `
                -Collector Git -Message 'Git policy collection failed.'
        }
        catch { # Persistence failures must not expose filesystem or source values.
            throw 'Git policy collection failed.'
        }
        throw 'Git policy collection failed.'
    }
}
