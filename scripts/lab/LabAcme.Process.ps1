#Requires -Version 7.4
Set-StrictMode -Version Latest

function Invoke-LabAcmeWorkerProcess {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][string] $WorkerPath,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Arguments,
        [int] $TimeoutSeconds = 900,
        [int] $MaxOutputBytes = 1048576
    )
    $process = [Diagnostics.Process]::new()
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $started = $false
    $cleanupFailed = $false
    try {
        $binary = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
        if ($IsWindows) { $start = [Diagnostics.ProcessStartInfo]::new($binary) }
        else {
            $start = [Diagnostics.ProcessStartInfo]::new('/bin/sh')
            foreach ($argument in @('-c', 'umask 077; exec "$@"', 'lab-acme', $binary)) {
                $start.ArgumentList.Add($argument)
            }
        }
        $start.UseShellExecute = $false; $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
        $start.RedirectStandardInput = $true
        foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $WorkerPath) + $Arguments) {
            $start.ArgumentList.Add($argument)
        }
        $process.StartInfo = $start
        Assert-LabCondition ($process.Start())
        $started = $true
        $process.StandardInput.Close()
        $buffers = @([byte[]]::new(4096), [byte[]]::new(4096))
        $streams = @($process.StandardOutput.BaseStream, $process.StandardError.BaseStream)
        $tasks = @($streams[0].ReadAsync($buffers[0], 0, 4096), $streams[1].ReadAsync($buffers[1], 0, 4096))
        $done = @($false, $false)
        $total = 0
        while (-not ($done[0] -and $done[1] -and $process.HasExited)) {
            Assert-LabCondition ($clock.Elapsed.TotalSeconds -le $TimeoutSeconds)
            for ($index = 0; $index -lt 2; $index++) {
                if ($done[$index] -or -not $tasks[$index].IsCompleted) { continue }
                $count = $tasks[$index].GetAwaiter().GetResult()
                if ($count -eq 0) { $done[$index] = $true; continue }
                $total += $count
                Assert-LabCondition ($total -le $MaxOutputBytes)
                $tasks[$index] = $streams[$index].ReadAsync($buffers[$index], 0, 4096)
            }
            Start-Sleep -Milliseconds 5
        }
        Assert-LabCondition ($process.ExitCode -in @(20, 21, 22, 23, 24, 25, 26, 27, 90))
        return $process.ExitCode
    }
    catch { return 90 }
    finally {
        if ($started -and -not $process.HasExited) {
            try { $process.Kill($true); $null = $process.WaitForExit(2000) }
            catch { $cleanupFailed = $true }
        }
        $process.Dispose()
        if ($cleanupFailed) { throw [InvalidOperationException]::new('LAB_ACME_PROCESS_CLEANUP_FAILED') }
    }
}
