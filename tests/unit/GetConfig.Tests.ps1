BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:sampleConfigPath = Join-Path $repoRoot 'config/sample.psd1'
    $script:module = Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') `
        -Force -PassThru

    function Get-SyntheticConfigFile {
        param(
            [string] $RestrictedRoot = (Join-Path $TestDrive 'restricted'),
            [string] $ModelSafeRoot = (Join-Path $TestDrive 'analysis'),
            [scriptblock] $Transform
        )

        $content = Get-Content -LiteralPath $script:sampleConfigPath -Raw
        $escapedRestrictedRoot = $RestrictedRoot.Replace("'", "''")
        $escapedModelSafeRoot = $ModelSafeRoot.Replace("'", "''")
        $content = $content.Replace(
            "'<absolute-external-restricted-path>'",
            "'$escapedRestrictedRoot'"
        ).Replace(
            "'<absolute-external-analysis-path>'",
            "'$escapedModelSafeRoot'"
        )
        if ($null -ne $Transform) {
            $content = & $Transform $content
        }

        $path = Join-Path $TestDrive "$([guid]::NewGuid()).psd1"
        Set-Content -LiteralPath $path -Value $content -NoNewline
        return $path
    }
}

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-Config' {
    It 'loads a complete synthetic configuration and normalizes output roots' {
        $path = Get-SyntheticConfigFile

        $config = & $script:module {
            param($ConfigPath)
            Get-Config -Path $ConfigPath
        } $path

        $config.Customer | Should -Be 'Example'
        $config.Environments.Count | Should -Be 1
        $config.RuleExceptions.ApprovedPlainHttpBackendIds.Count |
            Should -Be 0
        $config.RuleExceptions.ApprovedPlainHttpOperationKeys.Count |
            Should -Be 0
        [System.IO.Path]::IsPathFullyQualified($config.Output.Root) |
            Should -BeTrue
        [System.IO.Path]::IsPathFullyQualified($config.Output.ModelSafeRoot) |
            Should -BeTrue
    }

    It 'fails clearly when a required top-level key is missing' {
        $path = Get-SyntheticConfigFile -Transform {
            param($Content)
            $Content -replace "(?m)^\s*Customer\s*=.*\r?\n", ''
        }

        {
            & $script:module {
                param($ConfigPath)
                Get-Config -Path $ConfigPath
            } $path
        } | Should -Throw "*root.Customer*required*"
    }

    It 'fails clearly when a nested value has the wrong type' {
        $path = Get-SyntheticConfigFile -Transform {
            param($Content)
            $Content.Replace('UsageDays = 90', "UsageDays = 'ninety'")
        }

        {
            & $script:module {
                param($ConfigPath)
                Get-Config -Path $ConfigPath
            } $path
        } | Should -Throw "*Windows.UsageDays*numeric*"
    }

    It 'rejects non-finite numeric settings' {
        {
            & $script:module {
                Test-ConfigNumber -Value ([double]::NaN) `
                    -Context 'Thresholds.Error5xxPct'
            }
        } | Should -Throw "*Thresholds.Error5xxPct*finite number*"
    }

    It 'accepts an omitted optional rule-exception map as no exemptions' {
        $path = Get-SyntheticConfigFile -Transform {
            param($Content)
            $Content -replace (
                "(?ms)^\s*RuleExceptions\s*=\s*@\{.*?^\s*\}\r?\n",
                ''
            )
        }

        {
            & $script:module {
                param($ConfigPath)
                Get-Config -Path $ConfigPath
            } $path
        } | Should -Not -Throw
    }

    It 'accepts valid exact plain-HTTP exception targets' {
        $path = Get-SyntheticConfigFile -Transform {
            param($Content)
            $Content.Replace(
                'ApprovedPlainHttpBackendIds = @()',
                "ApprovedPlainHttpBackendIds = @('status-backend')"
            ).Replace(
                'ApprovedPlainHttpOperationKeys = @()',
                "ApprovedPlainHttpOperationKeys = @('orders-v1/get-orders')"
            )
        }

        $config = & $script:module {
            param($ConfigPath)
            Get-Config -Path $ConfigPath
        } $path
        $config.RuleExceptions.ApprovedPlainHttpBackendIds |
            Should -Be @('status-backend')
        $config.RuleExceptions.ApprovedPlainHttpOperationKeys |
            Should -Be @('orders-v1/get-orders')
    }

    It 'rejects duplicate or malformed plain-HTTP exception keys' `
        -TestCases @(
            @{
                Field = 'ApprovedPlainHttpOperationKeys'
                Value = "@('orders-v1/get-orders', 'ORDERS-V1/GET-ORDERS')"
                Expected = '*duplicate value*'
            }
            @{
                Field = 'ApprovedPlainHttpOperationKeys'
                Value = "@('orders-v1')"
                Expected = '*invalid target key*'
            }
            @{
                Field = 'ApprovedPlainHttpBackendIds'
                Value = "@('status/backend')"
                Expected = '*invalid target key*'
            }
            @{
                Field = 'ApprovedPlainHttpBackendIds'
                Value = "'status-backend'"
                Expected = '*array of strings*'
            }
        ) {
            param($Field, $Value, $Expected)

            $needle = "$Field = @()"
            $replacement = "$Field = $Value"
            $path = Get-SyntheticConfigFile -Transform {
                param($Content)
                $Content.Replace($needle, $replacement)
            }

            {
                & $script:module {
                    param($ConfigPath)
                    Get-Config -Path $ConfigPath
                } $path
            } | Should -Throw $Expected
        }

    It 'rejects duplicate environment names case-insensitively' {
        $path = Get-SyntheticConfigFile -Transform {
            param($Content)
            $match = [regex]::Match(
                $Content,
                '(?ms)    Environments = @\(\r?\n(?<environment>.*?)(?=\r?\n    \)\r?\n    Edge)'
            )
            $environment = $match.Groups['environment']
            $Content.Insert(
                $environment.Index + $environment.Length,
                "`n$($environment.Value)"
            )
        }

        {
            & $script:module {
                param($ConfigPath)
                Get-Config -Path $ConfigPath
            } $path
        } | Should -Throw "*duplicate name 'Prod'*"
    }

    It 'rejects relative output paths' {
        $path = Get-SyntheticConfigFile -RestrictedRoot 'runs'

        {
            & $script:module {
                param($ConfigPath)
                Get-Config -Path $ConfigPath
            } $path
        } | Should -Throw "*Output.Root*absolute path*"
    }

    It 'rejects overlapping restricted and model-safe roots' {
        $restrictedRoot = Join-Path $TestDrive 'restricted'
        $path = Get-SyntheticConfigFile -RestrictedRoot $restrictedRoot `
            -ModelSafeRoot (Join-Path $restrictedRoot 'analysis')

        {
            & $script:module {
                param($ConfigPath)
                Get-Config -Path $ConfigPath
            } $path
        } | Should -Throw '*output roots cannot overlap*'
    }

    It 'requires Copilot-visible paths for agent-assisted validation' {
        $path = Get-SyntheticConfigFile

        {
            & $script:module {
                param($ConfigPath)
                Get-Config -Path $ConfigPath -AgentAssisted
            } $path
        } | Should -Throw '*requires at least one Copilot-visible path*'
    }

    It 'rejects a restricted root visible to Copilot' {
        $visibleRoot = Join-Path $TestDrive 'copilot-workspace'
        $path = Get-SyntheticConfigFile `
            -RestrictedRoot (Join-Path $visibleRoot 'runs') `
            -ModelSafeRoot (Join-Path $TestDrive 'analysis')

        {
            & $script:module {
                param($ConfigPath, $VisibleRoot)
                Get-Config -Path $ConfigPath -AgentAssisted `
                    -CopilotVisiblePath $VisibleRoot
            } $path $visibleRoot
        } | Should -Throw '*Output.Root*outside every Copilot-visible path*'
    }

    It 'accepts agent-assisted validation when the restricted root is isolated' {
        $path = Get-SyntheticConfigFile
        $visibleRoot = Join-Path $TestDrive 'copilot-workspace'

        {
            & $script:module {
                param($ConfigPath, $VisibleRoot)
                Get-Config -Path $ConfigPath -AgentAssisted `
                    -CopilotVisiblePath $VisibleRoot
            } $path $visibleRoot
        } | Should -Not -Throw
    }

    It 'rejects an existing symbolic link in an output path' -Skip:$IsWindows {
        $target = Join-Path $TestDrive 'restricted-target'
        $link = Join-Path $TestDrive 'restricted-link'
        New-Item -ItemType Directory -Path $target | Out-Null
        New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null
        $path = Get-SyntheticConfigFile -RestrictedRoot $link

        {
            & $script:module {
                param($ConfigPath)
                Get-Config -Path $ConfigPath
            } $path
        } | Should -Throw '*symbolic link or junction*'
    }
}
