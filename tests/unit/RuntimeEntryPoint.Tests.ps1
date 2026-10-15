$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Bounded operational capabilities and exit mapping' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)
        $script:entryRepoRoot = $RepoRoot

        BeforeAll {
            function Get-AzContext { throw 'Synthetic Azure context stub.' }
        }
        BeforeEach {
            $script:entryConfig = Import-PowerShellDataFile (
                Join-Path $script:entryRepoRoot 'config/sample.psd1'
            )
            $script:entryConfig.Output.Root = Join-Path $TestDrive 'synthetic-runs'
            Mock Get-Config { $script:entryConfig }
            Mock Import-Module {} -ParameterFilter { $Name -in @('Az.Accounts', 'Az.ResourceGraph') }
            Mock Get-AzContext {
                [pscustomobject]@{
                    Subscription = [pscustomobject]@{
                        Id = '00000000-0000-0000-0000-000000000001'
                    }
                    Tenant = [pscustomobject]@{
                        Id = '00000000-0000-0000-0000-000000000010'
                    }
                }
            }
            Mock Invoke-ApimCollection {
                [pscustomobject]@{ RunId = 'synthetic-run'; Status = 'Completed'; ExitCode = 0 }
            }
            Mock Invoke-ApimAnalyze {
                [pscustomobject]@{ Status = 'Completed'; ExitCode = 0 }
            }
            Mock Invoke-ApimReport {
                [pscustomobject]@{ Status = 'Completed'; ExitCode = 0 }
            }
        }

        It 'returns exit 0 after executing the implemented stages' {
            $result = Invoke-ApimAssessment -Config 'synthetic-config' -Environment Prod
            $result.ExitCode | Should -Be 0
            Should -Invoke Invoke-ApimCollection -Times 1 -Exactly
            Should -Invoke Invoke-ApimAnalyze -Times 1 -Exactly
            Should -Invoke Invoke-ApimReport -Times 1 -Exactly
        }

        It 'honors the collection-only stage and passes resume and throttling' {
            $result = Invoke-ApimAssessment -Config 'synthetic-config' -Environment Prod `
                -Stage Collect -Resume 'synthetic-resume' -ThrottleLimit 3
            $result.ExitCode | Should -Be 0
            Should -Invoke Invoke-ApimCollection -Times 1 -Exactly -ParameterFilter {
                $ResumeRunPath -eq 'synthetic-resume' -and $ThrottleLimit -eq 3
            }
            Should -Invoke Invoke-ApimAnalyze -Times 0 -Exactly
        }

        It 'accepts explicit exclusions without adding unavailable collectors' {
            $result = Invoke-ApimAssessment -Config 'synthetic-config' -Environment Prod `
                -SkipCost -SkipLogs -SkipGit
            $result.ExitCode | Should -Be 0
            Should -Invoke Invoke-ApimCollection -Times 1 -Exactly -ParameterFilter { $SkipGit }
        }

        It 'requires configured Git for an explicit inclusion before authentication' {
            $result = Invoke-ApimAssessment -Config 'synthetic-config' -Environment Prod `
                -SkipGit:$false
            $result.ExitCode | Should -Be 1
            Should -Invoke Get-AzContext -Times 0 -Exactly
            Should -Invoke Invoke-ApimCollection -Times 0 -Exactly
        }

        It 'rejects unavailable capability requests before config or auth' `
            -TestCases @(
                @{ Option = 'SkipCost'; Value = $false }
                @{ Option = 'SkipLogs'; Value = $false }
            ) {
            param($Option, $Value)
            $arguments = @{ Config = 'synthetic-config'; Environment = 'Prod' }
            $arguments[$Option] = $Value
            $result = Invoke-ApimAssessment @arguments
            $result.ExitCode | Should -Be 1
            Should -Invoke Get-Config -Times 0 -Exactly
            Should -Invoke Get-AzContext -Times 0 -Exactly
        }

        It 'maps config rejection to exit 1 and context rejection to exit 2' {
            Mock Get-Config { throw 'synthetic-private-config-canary' }
            (Invoke-ApimCollect -Config 'synthetic-config' -Environment Prod).ExitCode |
                Should -Be 1
            Mock Get-Config { $script:entryConfig }
            Mock Get-AzContext { throw 'synthetic-private-context-canary' }
            $result = Invoke-ApimCollect -Config 'synthetic-config' -Environment Prod
            $result.ExitCode | Should -Be 2
            (ConvertTo-Json -InputObject $result) | Should -Not -Match 'canary|context-canary'
        }

        It 'forwards explicitly supplied tracking only to reporting and rejects collection-only use' {
            $result = Invoke-ApimAssessment -Config 'synthetic-config' -Environment Prod `
                -PreviousReport 'synthetic-prior.xlsx'
            $result.ExitCode | Should -Be 0
            Should -Invoke Invoke-ApimReport -Times 1 -Exactly -ParameterFilter {
                $PreviousReport -ceq 'synthetic-prior.xlsx'
            }
            (Invoke-ApimAssessment -Config 'synthetic-config' -Environment Prod `
                    -Stage Collect -PreviousReport 'synthetic-prior.xlsx').ExitCode | Should -Be 1
            Should -Invoke Invoke-ApimCollection -Times 1 -Exactly
        }

        It 'returns exit 3 for collection-only failures and exit 4 for failed downstream analysis' {
            Mock Invoke-ApimCollection {
                [pscustomobject]@{ RunId = 'synthetic-run'; Status = 'Partial'; ExitCode = 3 }
            }
            (Invoke-ApimAssessment -Config 'synthetic-config' -Environment Prod `
                    -Stage Collect).ExitCode | Should -Be 3
            Mock Invoke-ApimAnalyze { [pscustomobject]@{ Status = 'Failed'; ExitCode = 4 } }
            (Invoke-ApimAssessment -Config 'synthetic-config' -Environment Prod).ExitCode |
                Should -Be 4
            Should -Invoke Invoke-ApimReport -Times 0 -Exactly
        }

        It 'retains collection exit 3 when downstream stages succeed' {
            Mock Invoke-ApimCollection {
                [pscustomobject]@{ RunId = 'synthetic-run'; Status = 'Partial'; ExitCode = 3 }
            }
            (Invoke-ApimAssessment -Config 'synthetic-config' -Environment Prod).ExitCode |
                Should -Be 3
            Should -Invoke Invoke-ApimReport -Times 1 -Exactly
        }

        It 'maps report and runtime-state failures to exit 4' {
            Mock Invoke-ApimReport { [pscustomobject]@{ Status = 'Failed'; ExitCode = 4 } }
            (Invoke-ApimAssessment -Config 'synthetic-config' -Environment Prod).ExitCode |
                Should -Be 4
            Mock Invoke-ApimCollection { throw 'synthetic-private-state-canary' }
            $result = Invoke-ApimCollect -Config 'synthetic-config' -Environment Prod
            $result.ExitCode | Should -Be 4
            (ConvertTo-Json -InputObject $result) | Should -Not -Match 'canary'
        }
    }
}

Describe 'CLI status-only process boundary' {
    BeforeAll {
        $script:cliRepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $script:pwshExecutable = (Get-Process -Id $PID).Path
    }

    It 'prints a bounded outcome whose exit code matches the process (<Code>)' `
        -TestCases @(0..4 | ForEach-Object { @{ Code = $_ } }) {
        param($Code)
        $root = Join-Path $TestDrive "cli-$Code"
        $null = New-Item -ItemType Directory -Path $root
        Copy-Item -LiteralPath (Join-Path $script:cliRepoRoot 'Invoke-ApimAssessment.ps1') `
            -Destination $root
        Set-Content -LiteralPath (Join-Path $root 'ApimAssessment.psd1') -Value @'
@{ RootModule = 'ApimAssessment.psm1'; ModuleVersion = '0.1.0'; FunctionsToExport = @('Invoke-ApimAssessment') }
'@
        $status = if ($Code -eq 0) { 'Completed' } elseif ($Code -eq 3) { 'Partial' } else { 'Failed' }
        Set-Content -LiteralPath (Join-Path $root 'ApimAssessment.psm1') -Value @"
function Invoke-ApimAssessment {
    param([string] `$Config, [string] `$Environment)
    Write-Warning 'synthetic-private-warning-canary'
    Write-Information 'synthetic-private-information-canary' -InformationAction Continue
    Write-Verbose 'synthetic-private-verbose-canary' -Verbose
    Write-Debug 'synthetic-private-debug-canary' -Debug
    [pscustomobject]@{ Status = '$status'; ExitCode = $Code }
}
Export-ModuleMember -Function Invoke-ApimAssessment
"@
        $output = & $script:pwshExecutable -NoProfile -File (
            Join-Path $root 'Invoke-ApimAssessment.ps1'
        ) -Config 'synthetic-config' -Environment 'Synthetic' 2>&1
        $LASTEXITCODE | Should -Be $Code
        ($output -join "`n") | Should -Be "ASSESSMENT_$($status.ToUpperInvariant()) EXIT_$Code"
    }

    It 'returns a bounded failure for nonexistent offline run paths' {
        foreach ($scriptName in @('Invoke-ApimAnalyze.ps1', 'Invoke-ApimReport.ps1')) {
            $output = & $script:pwshExecutable -NoProfile -File (
                Join-Path $script:cliRepoRoot $scriptName
            ) -RunFolder (Join-Path $TestDrive 'nonexistent-synthetic-run') 2>&1
            $LASTEXITCODE | Should -Be 4
            ($output -join "`n") | Should -Not -Match 'nonexistent|Exception|TestDrive'
            ($output -join "`n") | Should -Match '^.*_FAILED EXIT_4$'
        }

    }

    It 'keeps comparison errors status-only across the process boundary' {
        $output = & $script:pwshExecutable -NoProfile -File (
            Join-Path $script:cliRepoRoot 'Compare-ApimRun.ps1'
        ) -Baseline (Join-Path $TestDrive 'baseline-canary') `
            -Current (Join-Path $TestDrive 'current-canary') 2>&1
        $LASTEXITCODE | Should -Be 4
        ($output -join "`n") | Should -Be 'COMPARISON_FAILED EXIT_4'
    }
}
