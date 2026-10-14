$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixtureRoot = Join-Path $repoRoot 'tests/fixtures/synthetic-reference/raw'
$scoring = (Import-PowerShellDataFile (
        Join-Path $repoRoot 'config/sample.psd1'
    )).Scoring
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'APIM diagnostics collector' {
    InModuleScope ApimAssessment -Parameters @{
        FixtureRoot = $fixtureRoot
        Scoring = $scoring
    } {
        param($FixtureRoot, $Scoring)

        $script:diagnosticsFixtureRoot = $FixtureRoot
        $script:diagnosticsScoring = $Scoring

        BeforeAll {
            function ConvertTo-DiagnosticsCompactJson {
                param(
                    [Parameter(Mandatory)]
                    [string] $Json
                )

                return [System.Text.Json.Nodes.JsonNode]::Parse(
                    $Json
                ).ToJsonString()
            }

            function Get-SyntheticDiagnosticResource {
                param(
                    [Parameter(Mandatory)]
                    [object] $Expected
                )

                $convertMessage = {
                    param($Message)
                    if ($null -eq $Message) {
                        return $null
                    }
                    [pscustomobject]@{
                        headers = @($Message.headers)
                        body = [pscustomobject]@{
                            bytes = $Message.bodyBytes
                            sample = 'must-never-persist'
                        }
                        unknownField = 'drop-me'
                    }
                }
                $convertPipeline = {
                    param($Pipeline)
                    if ($null -eq $Pipeline) {
                        return $null
                    }
                    [pscustomobject]@{
                        request = & $convertMessage $Pipeline.request
                        response = & $convertMessage $Pipeline.response
                    }
                }
                [pscustomobject]@{
                    name = $Expected.name
                    properties = [pscustomobject]@{
                        loggerId = $Expected.properties.loggerId
                        alwaysLog = $Expected.properties.alwaysLog
                        sampling = $Expected.properties.sampling
                        verbosity = $Expected.properties.verbosity
                        logClientIp = $Expected.properties.logClientIp
                        httpCorrelationProtocol = (
                            $Expected.properties.httpCorrelationProtocol
                        )
                        frontend = & $convertPipeline `
                            $Expected.properties.frontend
                        backend = & $convertPipeline `
                            $Expected.properties.backend
                        dataMasking = [pscustomobject]@{
                            headers = @('must-never-persist')
                        }
                        unknownField = 'drop-me'
                    }
                }
            }
        }

        BeforeEach {
            $script:environment = @{
                Name = 'Prod'
                SubscriptionId = '00000000-0000-0000-0000-000000000001'
                ApimResourceGroup = 'rg-synthetic-prod'
                ApimName = 'apim-synthetic-prod'
            }
            $config = @{
                Customer = 'Synthetic Customer'
                Environments = @($script:environment)
                Windows = @{
                    UsageDays = 90; SecurityLogDays = 30; CostMonths = 6
                }
                Edge = @{
                    Provider = 'SyntheticEdge'; Mode = 'AssumedReachable'
                }
                Scoring = $script:diagnosticsScoring
                Output = @{
                    Root = Join-Path $TestDrive (
                        [guid]::NewGuid().ToString('N')
                    )
                }
            }
            $script:run = New-ApimRun -Config $config -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000010' `
                -Operator 'synthetic.operator@example.invalid' `
                -RunId '2026-10-13_2330_Prod'
            $apiPayload = Get-Content -LiteralPath (
                Join-Path $script:diagnosticsFixtureRoot 'apis.json'
            ) -Raw | ConvertFrom-Json -Depth 100
            Write-RunFile -RunPath $script:run.Path `
                -RelativePath 'raw/apis.json' -InputObject $apiPayload `
                -Depth 50 | Out-Null
            $script:rootUris = @()
            $script:parallelRequests = @()
            $script:parallelThrottle = $null

            Mock Invoke-ApimArm {
                $script:rootUris += $Uri
                if ($Uri -match '/loggers\?') {
                    return [pscustomobject]@{
                        value = @(
                            [pscustomobject]@{
                                name = 'event-hub'
                                properties = [pscustomobject]@{
                                    loggerType = 'azureEventHub'
                                    resourceId = (
                                        '/subscriptions/00000000-0000-0000-' +
                                        '0000-000000000001/resourceGroups/' +
                                        'rg-synthetic-observability/providers/' +
                                        'Microsoft.EventHub/namespaces/' +
                                        'evh-synthetic'
                                    )
                                    isBuffered = $false
                                    credentials = [pscustomobject]@{
                                        connectionString = (
                                            'must-never-persist'
                                        )
                                    }
                                    description = 'must-never-persist'
                                }
                            }
                            [pscustomobject]@{
                                name = 'application-insights'
                                properties = [pscustomobject]@{
                                    loggerType = 'applicationInsights'
                                    resourceId = (
                                        '/subscriptions/00000000-0000-0000-' +
                                        '0000-000000000001/resourceGroups/' +
                                        'rg-synthetic-observability/providers/' +
                                        'Microsoft.Insights/components/' +
                                        'appi-synthetic'
                                    )
                                    isBuffered = $true
                                    credentials = [pscustomobject]@{
                                        instrumentationKey = (
                                            'must-never-persist'
                                        )
                                    }
                                }
                            }
                        )
                    }
                }
                if ($Uri -match '/diagnostics\?') {
                    $expected = Get-Content -LiteralPath (
                        Join-Path $script:diagnosticsFixtureRoot `
                            'diagnostics.json'
                    ) -Raw | ConvertFrom-Json -Depth 100
                    return [pscustomobject]@{
                        value = @(
                            Get-SyntheticDiagnosticResource `
                                -Expected $expected.value[0]
                        )
                    }
                }
                throw 'Unexpected synthetic root URI.'
            }
            Mock Invoke-ApimParallelArmRequest {
                $script:parallelRequests = @($Requests)
                $script:parallelThrottle = $ThrottleLimit
                @(
                    foreach ($request in $Requests | Sort-Object Index) {
                        $file = Split-Path $request.RelativePath -Leaf
                        $expected = Get-Content -LiteralPath (
                            Join-Path $script:diagnosticsFixtureRoot (
                                "apiDiagnostics/$file"
                            )
                        ) -Raw | ConvertFrom-Json -Depth 100
                        [pscustomobject]@{
                            index = $request.Index
                            relativePath = $request.RelativePath
                            success = $true
                            payload = [pscustomobject]@{
                                value = @(
                                    foreach ($diagnostic in $expected.value) {
                                        Get-SyntheticDiagnosticResource `
                                            -Expected $diagnostic
                                    }
                                )
                            }
                        }
                    }
                )
            }
        }

        It 'writes deterministic allowlisted service and API diagnostic files' {
            $paths = @(Invoke-ApimDiagnosticsCollector `
                    -RunPath $script:run.Path -Environment $script:environment `
                    -ThrottleLimit 2)

            $paths.Count | Should -Be 4
            $script:parallelThrottle | Should -Be 2
            $script:parallelRequests.Count | Should -Be 2
            $script:rootUris | Should -Be @(
                '/subscriptions/00000000-0000-0000-0000-000000000001/' +
                'resourceGroups/rg-synthetic-prod/providers/' +
                'Microsoft.ApiManagement/service/apim-synthetic-prod/' +
                'loggers?api-version=2024-05-01'
                '/subscriptions/00000000-0000-0000-0000-000000000001/' +
                'resourceGroups/rg-synthetic-prod/providers/' +
                'Microsoft.ApiManagement/service/apim-synthetic-prod/' +
                'diagnostics?api-version=2024-05-01'
            )
            $script:parallelRequests[0].Uri | Should -Be (
                '/subscriptions/00000000-0000-0000-0000-000000000001/' +
                'resourceGroups/rg-synthetic-prod/providers/' +
                'Microsoft.ApiManagement/service/apim-synthetic-prod/' +
                'apis/orders-v1/diagnostics?api-version=2024-05-01'
            )

            foreach ($relativePath in @(
                    'loggers.json',
                    'diagnostics.json',
                    'apiDiagnostics/orders-v1.json',
                    'apiDiagnostics/status-v1.json'
                )) {
                $actual = Get-Content -LiteralPath (
                    Join-Path $script:run.Path "raw/$relativePath"
                ) -Raw
                $expected = Get-Content -LiteralPath (
                    Join-Path $script:diagnosticsFixtureRoot $relativePath
                ) -Raw
                ConvertTo-DiagnosticsCompactJson $actual |
                    Should -Be (ConvertTo-DiagnosticsCompactJson $expected)
            }

            $persisted = @(
                foreach ($path in $paths) {
                    Get-Content -LiteralPath $path -Raw
                }
            ) -join "`n"
            $persisted | Should -Not -Match (
                '(?i)must-never-persist|connectionString|' +
                'instrumentationKey|description|sample|dataMasking'
            )
            $collector = (Get-RunManifest -RunPath $script:run.Path).collectors |
                Where-Object name -EQ Diagnostics
            $collector.status | Should -Be 'Completed'
            $collector.items | Should -Be 5
            $collector.errors | Should -Be 0
        }

        It 'preserves missing diagnostic settings as null and known empty headers as arrays' {
            $resource = [pscustomobject]@{
                name = 'synthetic'
                properties = [pscustomobject]@{
                    frontend = [pscustomobject]@{
                        request = [pscustomobject]@{
                            headers = @()
                        }
                    }
                }
            }
            $actual = ConvertTo-ApimCollectedDiagnostic -Resource $resource

            $actual.properties.loggerId | Should -BeNullOrEmpty
            $actual.properties.sampling | Should -BeNullOrEmpty
            ($actual.properties.frontend.request.headers -is [array]) |
                Should -BeTrue
            $actual.properties.frontend.request.headers.Count | Should -Be 0
            $actual.properties.frontend.request.bodyBytes |
                Should -BeNullOrEmpty
            $actual.properties.frontend.response | Should -BeNullOrEmpty
            $actual.properties.backend | Should -BeNullOrEmpty
        }

        It 'retains sanitized root evidence and records Partial on API child failure' {
            Mock Invoke-ApimParallelArmRequest {
                $exception = [System.InvalidOperationException]::new(
                    'One or more parallel ARM requests failed.'
                )
                $exception.Data['FailureCount'] = 2
                throw $exception
            }

            {
                Invoke-ApimDiagnosticsCollector -RunPath $script:run.Path `
                    -Environment $script:environment
            } | Should -Throw '*parallel ARM requests failed*'
            Test-Path -LiteralPath (
                Join-Path $script:run.Path 'raw/loggers.json'
            ) | Should -BeTrue
            Test-Path -LiteralPath (
                Join-Path $script:run.Path 'raw/diagnostics.json'
            ) | Should -BeTrue
            Test-Path -LiteralPath (
                Join-Path $script:run.Path `
                    'raw/apiDiagnostics/orders-v1.json'
            ) | Should -BeFalse
            $collector = (Get-RunManifest -RunPath $script:run.Path).collectors |
                Where-Object name -EQ Diagnostics
            $collector.status | Should -Be 'Partial'
            $collector.errors | Should -Be 2
        }

        It 'fails before writing when root diagnostic metadata is malformed' {
            Mock Invoke-ApimArm {
                if ($Uri -match '/loggers\?') {
                    return [pscustomobject]@{ value = @() }
                }
                [pscustomobject]@{
                    value = @(
                        [pscustomobject]@{
                            name = 'invalid'
                            properties = [pscustomobject]@{
                                sampling = [pscustomobject]@{
                                    percentage = 101
                                }
                            }
                        }
                    )
                }
            }

            {
                Invoke-ApimDiagnosticsCollector -RunPath $script:run.Path `
                    -Environment $script:environment
            } | Should -Throw
            Test-Path -LiteralPath (
                Join-Path $script:run.Path 'raw/loggers.json'
            ) | Should -BeFalse
            Test-Path -LiteralPath (
                Join-Path $script:run.Path 'raw/diagnostics.json'
            ) | Should -BeFalse
            $collector = (Get-RunManifest -RunPath $script:run.Path).collectors |
                Where-Object name -EQ Diagnostics
            $collector.status | Should -Be 'Failed'
        }
    }
}
