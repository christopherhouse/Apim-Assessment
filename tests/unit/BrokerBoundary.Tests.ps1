Describe 'Broker OS-stream privacy boundary' {
    BeforeAll {
        $script:boundaryRepository = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    }
    It 'never forwards direct console, native, PowerShell streams or exception canaries' {
        $root = Join-Path $TestDrive 'boundary-host'
        $scripts = Join-Path $root 'scripts'
        $null = [IO.Directory]::CreateDirectory($scripts)
        $null = [IO.Directory]::CreateDirectory((Join-Path $root 'restricted'))
        $null = [IO.Directory]::CreateDirectory((Join-Path $root 'schemas'))
        foreach ($name in @('Start-ApimBroker.ps1', 'Invoke-BrokerWorker.ps1')) {
            Copy-Item -LiteralPath (Join-Path $script:boundaryRepository "scripts/$name") -Destination $scripts
        }
        $module = @'
Set-StrictMode -Version Latest
. '__REPOSITORY__\src\Package\Test-ApimAnalysisContract.ps1'
. '__REPOSITORY__\src\Package\Invoke-ApimBroker.ps1'
. '__REPOSITORY__\src\Package\AnalysisPackage.Common.ps1'
. '__REPOSITORY__\src\Core\Get-Config.ps1'
$analysisSchemaRoot = Join-Path $PSScriptRoot 'schemas'
function Get-ApimBrokerContext {
    param([string] $OperatorConfigPath)
    if ($OperatorConfigPath -cne 'synthetic') { throw 'SYNTHETIC_ADMISSION_REQUIRED' }
    return @{ operator = @{ restrictedRoot = (Join-Path $PSScriptRoot 'restricted') }; runs = @{} }
}
function Invoke-ApimBrokerTool {
    param($Context, $Name, $Arguments)
    [Console]::WriteLine('NEVER_FORWARD_DIRECT_STDOUT')
    [Console]::Error.WriteLine('NEVER_FORWARD_DIRECT_STDERR')
    Write-Warning 'NEVER_FORWARD_WARNING'
    Write-Verbose 'NEVER_FORWARD_VERBOSE' -Verbose
    Write-Debug 'NEVER_FORWARD_DEBUG' -Debug
    Write-Information 'NEVER_FORWARD_INFORMATION' -InformationAction Continue
    Write-Progress -Activity 'NEVER_FORWARD_PROGRESS' -PercentComplete 10
    Write-Error 'NEVER_FORWARD_ERROR' -ErrorAction Continue
    $exe = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
    & $exe -NoProfile -NonInteractive -Command "[Console]::WriteLine('NEVER_FORWARD_NATIVE_STDOUT'); [Console]::Error.WriteLine('NEVER_FORWARD_NATIVE_STDERR')"
    [IO.File]::AppendAllText((Join-Path $PSScriptRoot 'worker-invocations.log'), "$Name`n")
    if ($Name -ceq 'promote_analysis_package') { throw 'NEVER_FORWARD_EXCEPTION' }
    if ($Name -ceq 'run_assessment') { Write-Output 'NEVER_FORWARD_SUCCESS_STREAM' }
    $null = $Context.runs
    return @{ runId = $Arguments.runId; stages = @{ collect = 'Completed'; analyze = 'Completed'; modelSafe = 'NotStarted'; report = 'NotStarted' } }
}
'@
        $module = $module.Replace('__REPOSITORY__', $script:boundaryRepository.Replace("'", "''"))
        if (-not $IsWindows) {
            $module = $module.Replace('\src\Package\', '/src/Package/').Replace('\src\Core\', '/src/Core/')
        }
        [IO.File]::WriteAllText((Join-Path $root 'ApimAssessment.psm1'), $module)
        [IO.File]::WriteAllText((Join-Path $root 'ApimAssessment.psd1'),
            "@{ RootModule = 'ApimAssessment.psm1'; ModuleVersion = '0.1.0'; FunctionsToExport = @() }")
        $process = [Diagnostics.Process]::new()
        $info = [Diagnostics.ProcessStartInfo]::new()
        $info.FileName = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
        foreach ($arg in @('-NoProfile', '-NonInteractive', '-File',
                (Join-Path $scripts 'Start-ApimBroker.ps1'), '-OperatorConfigPath', 'synthetic')) {
            $info.ArgumentList.Add($arg)
        }
        $info.UseShellExecute = $false; $info.RedirectStandardInput = $true
        $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
        $process.StartInfo = $info
        $null = $process.Start()
        try {
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $process.StandardInput.WriteLine('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"synthetic","version":"1.0"}}}')
            $process.StandardInput.WriteLine('{"jsonrpc":"2.0","method":"notifications/initialized"}')
            $id = 2
            foreach ($name in @('get_assessment_status', 'promote_analysis_package', 'run_assessment')) {
                $process.StandardInput.WriteLine((ConvertTo-Json -Depth 10 -Compress -InputObject @{
                            jsonrpc = '2.0'; id = $id; method = 'tools/call'
                            params = @{ name = $name; arguments = @{ runId = 'run-00000000000000000000000000000001' } }
                        }))
                $id++
            }
            $process.StandardInput.Close()
            $process.WaitForExit(60000) | Should -BeTrue
            $wire = $stdout.GetAwaiter().GetResult()
            $wire | Should -Not -Match 'NEVER_FORWARD|restricted|boundary-host|Exception|stderr'
            $stderr.GetAwaiter().GetResult() | Should -BeNullOrEmpty
            $lines = @($wire.Trim() -split '\r?\n' | ForEach-Object { ConvertFrom-Json -InputObject $_ -AsHashtable })
            $lines.Count | Should -Be 4
            $lines[1].result.isError | Should -BeTrue
            $lines[2].result.isError | Should -BeTrue
            $lines[3].result.isError | Should -BeTrue
            foreach ($response in $lines[1..3]) {
                $response.result.content[0].text | Should -Be '{"errorCode":"BROKER_OPERATION_REJECTED"}'
            }
            Get-Content -LiteralPath (Join-Path $root 'worker-invocations.log') |
                Should -Be @('get_assessment_status', 'promote_analysis_package', 'run_assessment')
            @(Get-ChildItem -LiteralPath (Join-Path $root 'restricted') -Force).Count | Should -Be 0
        }
        finally {
            if (-not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
            $process.Dispose()
        }
    }
}
