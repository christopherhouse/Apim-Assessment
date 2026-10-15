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
    It 'accepts explicit governance intent through the configuration entry point' {
        $path = Get-SyntheticConfigFile -Transform {
            param($Content)
            $Content.Replace('Privacy = @{',
                "Governance = @{ Products = @(@{ ProductId = 'partner'; HasOwner = `$true; IsExternal = `$true }); CriticalApiIds = @('orders-v1') }`nPrivacy = @{")
        }
        $actual = & $script:module { param($Path) Get-Config -Path $Path } $path
        $actual.Governance.Products[0].HasOwner | Should -BeTrue
        $actual.Governance.CriticalApiIds | Should -Be @('orders-v1')
    }

    It 'rejects invalid governance intent (<Kind>)' -ForEach @(
        @{ Kind = 'unknown section field'; Value = @{ Extra = $true } }
        @{ Kind = 'null targets'; Value = @{ CriticalApiIds = $null } }
        @{ Kind = 'scalar targets'; Value = @{ CriticalApiIds = 'orders-v1' } }
        @{ Kind = 'unsafe targets'; Value = @{ CriticalApiIds = @('../orders') } }
        @{ Kind = 'duplicate targets'; Value = @{ CriticalApiIds = @('orders', 'ORDERS') } }
        @{ Kind = 'missing owner'; Value = @{ Products = @(@{ ProductId = 'partner'; IsExternal = $true }) } }
        @{ Kind = 'unknown product field'; Value = @{ Products = @(@{ ProductId = 'partner'; HasOwner = $true; IsExternal = $true; Extra = 1 }) } }
        @{ Kind = 'nonboolean owner'; Value = @{ Products = @(@{ ProductId = 'partner'; HasOwner = 'true'; IsExternal = $true }) } }
        @{ Kind = 'duplicate products'; Value = @{ Products = @(
            @{ ProductId = 'partner'; HasOwner = $true; IsExternal = $true },
            @{ ProductId = 'PARTNER'; HasOwner = $false; IsExternal = $false }
        ) } }
    ) {
        { & $script:module { param($Value) Test-ConfigGovernance -Value $Value } $Value } |
            Should -Throw
    }

    It 'rejects identity storage rather than silently returning user identities' {
        $path = Get-SyntheticConfigFile -Transform {
            param($Content)
            $Content.Replace('StoreUserIdentities = $false', 'StoreUserIdentities = $true')
        }
        { & $script:module { param($Path) Get-Config -Path $Path } $path } |
            Should -Throw '*aggregate counts only*'
    }

    It 'validates optional integer OpenAPI quality penalties without changing legacy defaults' {
        $path = Get-SyntheticConfigFile -Transform {
            param($Content)
            $Content.Replace('Privacy = @{',
                "OpenApiQuality = @{ ErrorPenalty = 12; WarningPenalty = 0 }`nPrivacy = @{")
        }
        $actual = & $script:module { param($Path) Get-Config -Path $Path } $path
        $actual.OpenApiQuality.ErrorPenalty | Should -Be 12
        $actual.OpenApiQuality.WarningPenalty | Should -Be 0
        foreach ($value in @(
                @{ ErrorPenalty = -1; WarningPenalty = 2 },
                @{ ErrorPenalty = 1.5; WarningPenalty = 2 },
                @{ ErrorPenalty = '10'; WarningPenalty = 2 },
                @{ ErrorPenalty = 101; WarningPenalty = 2 },
                @{ ErrorPenalty = 10 },
                @{ ErrorPenalty = 10; WarningPenalty = 2; Extra = 1 }
            )) {
            { & $script:module { param($Value)
                    Test-ConfigOpenApiQuality -Value $Value
                } $value } | Should -Throw
        }
    }

    It 'accepts explicit portal visibility and rejects malformed intent' {
        & $script:module {
            Test-ConfigPortalProductVisibility -Value @(
                @{ ProductId = 'private'; IsPublic = $false; IntendedGroupIds = @('partners') }
            )
        }
        foreach ($entry in @(
                @{ ProductId = 'private'; IsPublic = 'false'; IntendedGroupIds = @() },
                @{ ProductId = 'private'; IsPublic = $false; IntendedGroupIds = @('partners', 'PARTNERS') },
                @{ ProductId = 'private'; IsPublic = $false; IntendedGroupIds = @(); Unexpected = $true },
                @{ ProductId = '../private'; IsPublic = $false; IntendedGroupIds = @() }
            )) {
            { & $script:module { param($Entry)
                    Test-ConfigPortalProductVisibility -Value @($Entry)
                } $entry } | Should -Throw
        }
        { & $script:module {
                Test-ConfigPortalProductVisibility -Value @(
                    @{ ProductId = 'private'; IsPublic = $false; IntendedGroupIds = @() },
                    @{ ProductId = 'PRIVATE'; IsPublic = $true; IntendedGroupIds = @() }
                )
            } } | Should -Throw '*duplicate product*'
    }

    It 'rejects unsafe Git path or mapping configuration before any repository read (<Kind>)' `
        -TestCases @(
            @{ Kind = 'relative repository' }, @{ Kind = 'escaping policy root' },
            @{ Kind = 'missing mapping capture' }
        ) {
        param($Kind)
        $mutation = $Kind
        $path = Get-SyntheticConfigFile -Transform {
            param($Content)
            switch ($mutation) {
                'relative repository' { $Content.Replace("GitRepoPath              = ''",
                        "GitRepoPath              = 'relative-repository'") }
                'escaping policy root' { $Content.Replace("'apim/policies'", "'../policies'") }
                'missing mapping capture' { $Content.Replace("GitPolicyRoot            = 'apim/policies'",
                        "GitPolicyRoot = 'apim/policies'`nGitPolicyMappings = @(@{ ScopeType = 'Fragment'; Pattern = 'fragments/[^/]+\.xml' })") }
            }
        }
        { & $script:module { param($ConfigPath) Get-Config -Path $ConfigPath } $path } |
            Should -Throw
    }

    It 'loads a complete synthetic configuration and normalizes output roots' {
        $path = Get-SyntheticConfigFile

        $config = & $script:module {
            param($ConfigPath)
            Get-Config -Path $ConfigPath
        } $path

        $config.Customer | Should -Be 'Example'
        $config.Environments.Count | Should -Be 1
        $config.RuleTargets.CriticalBackendIds.Count | Should -Be 0
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

    It 'accepts an omitted optional rule-target map as no declared targets' {
        $path = Get-SyntheticConfigFile -Transform {
            param($Content)
            $Content -replace (
                "(?ms)^\s*RuleTargets\s*=\s*@\{.*?^\s*\}\r?\n",
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

    It 'accepts valid critical backend targets' {
        $path = Get-SyntheticConfigFile -Transform {
            param($Content)
            $Content.Replace(
                'CriticalBackendIds = @()',
                "CriticalBackendIds = @('orders-backend', 'status-backend')"
            )
        }

        $config = & $script:module {
            param($ConfigPath)
            Get-Config -Path $ConfigPath
        } $path
        $config.RuleTargets.CriticalBackendIds |
            Should -Be @('orders-backend', 'status-backend')
    }

    It 'rejects duplicate or malformed critical backend targets' `
        -TestCases @(
            @{
                Value = "@('status-backend', 'STATUS-BACKEND')"
                Expected = '*duplicate value*'
            }
            @{
                Value = "@('status/backend')"
                Expected = '*invalid target key*'
            }
            @{
                Value = "'status-backend'"
                Expected = '*array of strings*'
            }
        ) {
            param($Value, $Expected)

            $replacement = "CriticalBackendIds = $Value"
            $path = Get-SyntheticConfigFile -Transform {
                param($Content)
                $Content.Replace('CriticalBackendIds = @()',
                    $replacement)
            }
            {
                & $script:module {
                    param($ConfigPath)
                    Get-Config -Path $ConfigPath
                } $path
            } | Should -Throw $Expected
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
