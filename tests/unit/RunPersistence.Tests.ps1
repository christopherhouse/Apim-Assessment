BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:manifestSchemaPath = Join-Path $repoRoot 'schemas/manifest.schema.json'
    $script:module = Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') `
        -Force -PassThru
}

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Run persistence and manifest lifecycle' {
    BeforeEach {
        $script:restrictedRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:run = & $script:module {
            param($RestrictedRoot)
            $config = @{
                Customer = 'Synthetic Customer'
                Environments = @(
                    @{
                        Name              = 'Prod'
                        SubscriptionId    = '00000000-0000-0000-0000-000000000001'
                        ApimResourceGroup = 'rg-synthetic-prod'
                        ApimName          = 'apim-synthetic-prod'
                    }
                )
                Windows = @{
                    UsageDays = 90; SecurityLogDays = 30; CostMonths = 6
                }
                Edge = @{ Provider = 'SyntheticEdge'; Mode = 'AssumedReachable' }
                Scoring = @{
                    Severity = @{ High = 3; Medium = 2; Low = 1; Info = 0.5 }
                    Exposure = @{
                        DirectPublic = 2.5
                        ExternalInUse = 2
                        ExternalUnintended = 2
                        Restricted = 1.5
                        Internal = 1
                        Platform = 1.5
                        Unknown = 1.5
                    }
                    Usage = @{
                        InUse = 1.5
                        Unused = 1
                        NotApplicable = 1
                    }
                }
                Output = @{ Root = $RestrictedRoot }
            }
            New-ApimRun -Config $config -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000010' `
                -Operator 'synthetic.operator@example.invalid' `
                -StartedUtc ([datetimeoffset] '2026-10-12T23:00:00Z') `
                -RunId '2026-10-12_2300_Prod'
        } $script:restrictedRoot
    }

    It 'creates the required run folders and a schema-valid manifest' {
        foreach ($relativePath in @(
                'manifest.json', 'raw', 'model', 'restricted', 'report', 'logs'
            )) {
            Test-Path -LiteralPath (Join-Path $script:run.Path $relativePath) |
                Should -BeTrue
        }

        $manifestJson = Get-Content -LiteralPath $script:run.ManifestPath -Raw
        ($manifestJson | Test-Json -SchemaFile $script:manifestSchemaPath) |
            Should -BeTrue
        $manifest = $manifestJson | ConvertFrom-Json
        $manifest.runId | Should -Be '2026-10-12_2300_Prod'
        $manifest.apim.resourceId | Should -Be (
            '/subscriptions/00000000-0000-0000-0000-000000000001/' +
            'resourceGroups/rg-synthetic-prod/providers/' +
            'Microsoft.ApiManagement/service/apim-synthetic-prod'
        )
        $manifest.stages.collect | Should -Be 'NotStarted'
        $manifest.schemaVersion | Should -Be '1.1'
        $manifest.scoring.severity.high | Should -Be 3
        $manifest.scoring.exposure.directPublic | Should -Be 2.5
        $manifest.scoring.usage.inUse | Should -Be 1.5
        $manifest.collectors.Count | Should -Be 0
        $manifest.completedUtc | Should -BeNullOrEmpty
    }

    It 'writes nested JSON atomically without a UTF-8 BOM' {
        $path = & $script:module {
            param($RunPath)
            Write-RunFile -RunPath $RunPath -RelativePath 'raw/example.json' `
                -InputObject ([ordered]@{ value = 'synthetic' })
        } $script:run.Path

        (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).value |
            Should -Be 'synthetic'
        [System.IO.File]::ReadAllBytes($path)[0] | Should -Not -Be 0xEF
        Get-ChildItem -LiteralPath (Split-Path $path -Parent) -Filter '*.tmp' |
            Should -BeNullOrEmpty
    }

    It 'does not append a second newline to text that already has one' {
        $path = & $script:module {
            param($RunPath)
            Write-RunFile -RunPath $RunPath -RelativePath 'policies/example.xml' `
                -InputObject "<policies />`n" -Format Text
        } $script:run.Path

        Get-Content -LiteralPath $path -Raw | Should -Be "<policies />`n"
    }

    It 'rejects paths that escape the run folder' {
        {
            & $script:module {
                param($RunPath)
                Write-RunFile -RunPath $RunPath -RelativePath '../outside.json' `
                    -InputObject @{ value = 'synthetic' }
            } $script:run.Path
        } | Should -Throw '*cannot escape*'
    }

    It 'uses case-sensitive containment on case-sensitive platforms' -Skip:$IsWindows {
        {
            & $script:module {
                param($RunPath)
                Write-RunFile -RunPath $RunPath `
                    -RelativePath '../2026-10-12_2300_prod/outside.json' `
                    -InputObject @{ value = 'synthetic' }
            } $script:run.Path
        } | Should -Throw '*cannot escape*'
    }

    It 'tracks stage, collector, warning, and completion updates' {
        & $script:module {
            param($RunPath)
            Set-RunStageStatus -RunPath $RunPath -Stage collect -Status InProgress
            Set-RunCollectorStatus -RunPath $RunPath -Name Service `
                -Status Completed -Items 1 -DurationSec 1.2345
            Add-RunWarning -RunPath $RunPath -Message 'Synthetic warning.'
            Add-RunWarning -RunPath $RunPath -Message 'Synthetic warning.'
            Complete-ApimRun -RunPath $RunPath `
                -CompletedUtc ([datetimeoffset] '2026-10-12T23:05:00Z')
        } $script:run.Path

        $manifestJson = Get-Content -LiteralPath $script:run.ManifestPath -Raw
        ($manifestJson | Test-Json -SchemaFile $script:manifestSchemaPath) |
            Should -BeTrue
        $manifest = $manifestJson | ConvertFrom-Json
        $manifest.stages.collect | Should -Be 'InProgress'
        $manifest.collectors.Count | Should -Be 1
        $manifest.collectors[0].status | Should -Be 'Completed'
        $manifest.collectors[0].durationSec | Should -Be 1.234
        $manifest.warnings | Should -Be @('Synthetic warning.')
        $manifest.completedUtc.ToUniversalTime().ToString('O') |
            Should -Be '2026-10-12T23:05:00.0000000Z'
    }

    It 'refuses to overwrite an existing run folder' {
        {
            & $script:module {
                param($RestrictedRoot)
                $config = @{
                    Customer = 'Synthetic Customer'
                    Environments = @(
                        @{
                            Name = 'Prod'
                            SubscriptionId = '00000000-0000-0000-0000-000000000001'
                            ApimResourceGroup = 'rg-synthetic-prod'
                            ApimName = 'apim-synthetic-prod'
                        }
                    )
                    Windows = @{
                        UsageDays = 90; SecurityLogDays = 30; CostMonths = 6
                    }
                    Edge = @{
                        Provider = 'SyntheticEdge'; Mode = 'AssumedReachable'
                    }
                    Scoring = @{
                        Severity = @{
                            High = 3; Medium = 2; Low = 1; Info = 0.5
                        }
                        Exposure = @{
                            DirectPublic = 2.5
                            ExternalInUse = 2
                            ExternalUnintended = 2
                            Restricted = 1.5
                            Internal = 1
                            Platform = 1.5
                            Unknown = 1.5
                        }
                        Usage = @{
                            InUse = 1.5
                            Unused = 1
                            NotApplicable = 1
                        }
                    }
                    Output = @{ Root = $RestrictedRoot }
                }
                New-ApimRun -Config $config -EnvironmentName Prod `
                    -TenantId '00000000-0000-0000-0000-000000000010' `
                    -Operator 'synthetic.operator@example.invalid' `
                    -RunId '2026-10-12_2300_Prod'
            } $script:restrictedRoot
        } | Should -Throw '*already exists*'
    }

    It 'validates manifest inputs before creating a run folder' {
        $invalidRunId = '2026-10-12_2301_Prod'
        {
            & $script:module {
                param($RestrictedRoot, $RunId)
                $config = @{
                    Customer = 'Synthetic Customer'
                    Environments = @(
                        @{
                            Name = 'Prod'
                            SubscriptionId = '00000000-0000-0000-0000-000000000001'
                            ApimResourceGroup = 'rg-synthetic-prod'
                            ApimName = 'apim-synthetic-prod'
                        }
                    )
                    Windows = @{
                        UsageDays = 90; SecurityLogDays = 30; CostMonths = 6
                    }
                    Edge = @{
                        Provider = 'SyntheticEdge'; Mode = 'AssumedReachable'
                    }
                    Scoring = @{
                        Severity = @{
                            High = 3; Medium = 2; Low = 1; Info = 0.5
                        }
                        Exposure = @{
                            DirectPublic = 2.5
                            ExternalInUse = 2
                            ExternalUnintended = 2
                            Restricted = 1.5
                            Internal = 1
                            Platform = 1.5
                            Unknown = 1.5
                        }
                        Usage = @{
                            InUse = 1.5
                            Unused = 1
                            NotApplicable = 1
                        }
                    }
                    Output = @{ Root = $RestrictedRoot }
                }
                New-ApimRun -Config $config -EnvironmentName Prod `
                    -TenantId 'not-a-guid' `
                    -Operator 'synthetic.operator@example.invalid' `
                    -RunId $RunId
            } $script:restrictedRoot $invalidRunId
        } | Should -Throw
        Test-Path -LiteralPath (
            Join-Path $script:restrictedRoot $invalidRunId
        ) | Should -BeFalse
    }

    It 'rejects an invalid manifest before replacing the persisted manifest' {
        $before = Get-Content -LiteralPath $script:run.ManifestPath -Raw
        {
            & $script:module {
                param($RunPath)
                Save-RunManifest -RunPath $RunPath -Manifest @{
                    schemaVersion = '1.0'
                }
            } $script:run.Path
        } | Should -Throw
        Get-Content -LiteralPath $script:run.ManifestPath -Raw |
            Should -Be $before
    }
}
