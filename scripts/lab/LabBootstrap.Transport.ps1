#Requires -Version 7.4
Set-StrictMode -Version Latest

function Get-LabOwnerContext {
    [CmdletBinding()]
    param()
    $ProgressPreference = 'SilentlyContinue'
    try {
        $context = Get-AzContext -ErrorAction Stop 2>$null 3>$null 4>$null 5>$null 6>$null
        return @{
            tenant = $context.Tenant.Id; subscription = $context.Subscription.Id
            cloud = $context.Environment.Name; accountType = $context.Account.Type
        }
    }
    catch { throw [System.InvalidOperationException]::new('LAB_CONTEXT_INVALID') }
}

function Invoke-LabArmRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'PUT')][string] $Method,
        [Parameter(Mandatory)][string] $Path,
        [AllowNull()][System.Collections.IDictionary] $Body
    )
    $ProgressPreference = 'SilentlyContinue'
    try {
        if ($Path -cnotmatch '^/subscriptions/[0-9a-f-]{36}/' -or
            $Path -match '(?i)listSecrets|listValue|listKeys|/secrets|regenerate|token|://|[\r\n]') {
            throw 'InvalidArmPath'
        }
        $parameters = @{ Path = $Path; Method = $Method; ErrorAction = 'Stop' }
        if ($null -ne $Body) { $parameters.Payload = ConvertTo-Json $Body -Depth 30 -Compress }
        $response = Invoke-AzRestMethod @parameters 2>$null 3>$null 4>$null 5>$null 6>$null
        if ($response.StatusCode -eq 404 -and $Method -ceq 'GET') { return $null }
        if ($response.StatusCode -notin @(200, 201, 204)) { throw 'UnexpectedArmStatus' }
        if ($Method -ceq 'PUT') { return }
        if ([System.Text.Encoding]::UTF8.GetByteCount($response.Content) -gt 2097152) {
            throw 'ArmResponseTooLarge'
        }
        return ConvertFrom-Json -InputObject $response.Content -AsHashtable -Depth 40 -ErrorAction Stop
    }
    catch {
        # Some Az.Accounts versions throw for non-success HTTP status codes.
        $exception = $_.Exception
        if ($Method -ceq 'GET' -and $null -ne $exception.PSObject.Properties['Response'] -and
            $null -ne $exception.Response -and
            $null -ne $exception.Response.PSObject.Properties['StatusCode'] -and
            [int]$exception.Response.StatusCode -eq 404) { return $null }
        throw [System.InvalidOperationException]::new('LAB_ARM_FAILED')
    }
}

function Invoke-LabGhProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [AllowNull()][string] $InputText,
        [ValidateRange(1, 120)][int] $TimeoutSeconds = 60,
        [ValidateRange(128, 4194304)][int] $MaxOutputBytes = 2097152
    )
    $process = [System.Diagnostics.Process]::new()
    $output = [System.IO.MemoryStream]::new()
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $started = $false
    try {
        $tool = Get-Command gh -CommandType Application -ErrorAction Stop
        $start = [System.Diagnostics.ProcessStartInfo]::new($tool.Source)
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardInput = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $null = $start.Environment.Remove('GH_DEBUG')
        $start.Environment['GH_PROMPT_DISABLED'] = '1'
        $start.Environment['GH_PAGER'] = 'cat'
        foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
        $process.StartInfo = $start
        if (-not $process.Start()) { throw 'GhUnavailable' }
        $started = $true
        $buffers = @([byte[]]::new(4096), [byte[]]::new(4096))
        $streams = @($process.StandardOutput.BaseStream, $process.StandardError.BaseStream)
        $tasks = @($streams[0].ReadAsync($buffers[0], 0, 4096),
            $streams[1].ReadAsync($buffers[1], 0, 4096))
        $done = @($false, $false)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$InputText)
        $write = $process.StandardInput.BaseStream.WriteAsync($bytes, 0, $bytes.Length)
        $inputClosed = $false
        $total = 0
        while (-not ($done[0] -and $done[1] -and $process.HasExited)) {
            if ($clock.Elapsed.TotalSeconds -gt $TimeoutSeconds) { throw 'GhTimeout' }
            if (-not $inputClosed -and $write.IsCompleted) {
                $null = $write.GetAwaiter().GetResult()
                $process.StandardInput.Close()
                $inputClosed = $true
            }
            for ($i = 0; $i -lt 2; $i++) {
                if ($done[$i] -or -not $tasks[$i].IsCompleted) { continue }
                $count = $tasks[$i].GetAwaiter().GetResult()
                if ($count -eq 0) { $done[$i] = $true; continue }
                $total += $count
                if ($total -gt $MaxOutputBytes) { throw 'GhOutputLimit' }
                if ($i -eq 0) { $output.Write($buffers[$i], 0, $count) }
                $tasks[$i] = $streams[$i].ReadAsync($buffers[$i], 0, 4096)
            }
            Start-Sleep -Milliseconds 5
        }
        if (-not $inputClosed) { $null = $write.GetAwaiter().GetResult() }
        return @{
            exitCode = $process.ExitCode
            stdout = [System.Text.UTF8Encoding]::new($false, $true).GetString($output.ToArray())
        }
    }
    catch { throw [System.InvalidOperationException]::new('LAB_GITHUB_FAILED') }
    finally {
        if ($started -and -not $process.HasExited) {
            try { $process.Kill($true); $null = $process.WaitForExit(2000) }
            catch { Write-Verbose 'LAB_PROCESS_CLEANUP_FAILED' }
        }
        $process.Dispose()
        $output.Dispose()
    }
}

function Invoke-LabGitHubRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'PUT', 'POST')][string] $Method,
        [Parameter(Mandatory)][string] $Path,
        [AllowNull()][System.Collections.IDictionary] $Body
    )
    try {
        if ($Path -cnotmatch '^repos/[A-Za-z0-9-]+/[A-Za-z0-9._-]+(/|$)' -or
            $Path -match '(?i)secrets|token|://|[\r\n]') { throw 'InvalidGitHubPath' }
        $arguments = @('api', '--hostname', 'github.com', '--include', '--method', $Method,
            '-H', 'Accept: application/vnd.github+json', '-H', 'X-GitHub-Api-Version: 2026-03-10', $Path)
        $inputText = $null
        if ($null -ne $Body) {
            $arguments += @('--input', '-')
            $inputText = ConvertTo-Json $Body -Depth 20 -Compress
        }
        $result = Invoke-LabGhProcess -Arguments $arguments -InputText $inputText
        # Parse --include's HTTP status, never human-readable stderr or error JSON.
        $match = [regex]::Match($result.stdout, '\AHTTP/[0-9.]+\s+([0-9]{3})[^\r\n]*\r?\n')
        if (-not $match.Success) { throw 'MissingGitHubStatus' }
        $status = [int]$match.Groups[1].Value
        if ($status -eq 404 -and $Method -ceq 'GET') { return $null }
        if ($result.exitCode -ne 0 -or $status -notin @(200, 201, 204)) { throw 'GitHubStatusFailed' }
        if ($Method -cne 'GET') { return }
        $parts = [regex]::Split($result.stdout, '\r?\n\r?\n', 2)
        if ($parts.Count -ne 2) { throw 'MissingGitHubBody' }
        return ConvertFrom-Json $parts[1] -AsHashtable -Depth 40 -ErrorAction Stop
    }
    catch { throw [System.InvalidOperationException]::new('LAB_GITHUB_FAILED') }
}
