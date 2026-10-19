$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Aggregate-only Log Analytics collection' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:logCollectorRepository = $Repository

        BeforeAll {
            $script:logQueryTransport = (Get-Command Invoke-ApimLogQuery).ScriptBlock
            $script:workspaceSettingReader = (Get-Command Get-ApimWorkspaceSetting).ScriptBlock
            function Invoke-AzOperationalInsightsQuery {
                param($WorkspaceId, $Query)
                throw "Unexpected query invocation for synthetic workspace $WorkspaceId ($($Query.Length) characters)."
            }
            function Get-SyntheticLogRow {
                param([string] $Query)
                if ($Query -match '\|\s*summarize calls=count\(\)\s*$') {
                    return [pscustomobject]@{ calls = '10' }
                }
                if ($Query -match 'headersObserved=') {
                    return [pscustomobject]@{
                        calls = 10; headersObserved = 8; xForwardedForCalls = 5; cfConnectingIpCalls = 2
                        RequestHeaders = 'SYNTHETIC_DROP_SENTINEL'
                    }
                }
                if ($Query -match 'by gatewayId=') {
                    $row = [ordered]@{
                        gatewayId = ('/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/' +
                            'rg-example-prod/providers/Microsoft.Network/applicationGateways/agw-example-prod')
                        listener = 'listener-public'; rule = 'rule-basic-apim'; host = 'api.synthetic.invalid'
                        calls = 10; clientCount = 2; ClientIp = 'SYNTHETIC_DROP_SENTINEL'
                    }
                    if ($Query -match 'clientClass=') { $row.clientClass = 'NonEdge' }
                    return [pscustomobject] $row
                }
                if ($Query -match 'summarize calls=count\(\) by apiId=(?:ApiId|apiId_s)\s*$') {
                    return [pscustomobject]@{ apiId = 'orders'; calls = 1; CallerIpAddress = 'SYNTHETIC_DROP_SENTINEL' }
                }
                if ($Query -match 'gb=sum') {
                    return [pscustomobject]@{
                        dataType = 'ApiManagementGatewayLogs'; day = '2026-10-14T00:00:00Z'
                        gb = '0.5'; unknown = 'SYNTHETIC_DROP_SENTINEL'
                    }
                }
                if ($Query -match 'month=') {
                    return [pscustomobject]@{ apiId = 'orders'; month = '2026-10-01T00:00:00Z'; calls = '10' }
                }
                if ($Query -match 'tlsVersion=') {
                    return [pscustomobject]@{ apiId = 'orders'; tlsVersion = '1.2'; calls = '10' }
                }
                if ($Query -match '\| where isempty|and isempty') {
                    return [pscustomobject]@{ apiId = 'orders'; calls = '2' }
                }
                $row = [ordered]@{
                    apiId = 'orders'; operationId = 'get'; productId = 'partner'; calls = '10'
                    error4xx = '3'; error5xx = '1'; unauthorized = '2'
                    subscriptionCount = '4'; totalTimeP50 = '12.5'; totalTimeP95 = '40'
                    backendTimeP95 = ''; lastCall = '2026-10-14T10:00:00Z'
                    CallerIpAddress = 'SYNTHETIC_DROP_SENTINEL'
                    ApimSubscriptionId = 'SYNTHETIC_DROP_SENTINEL'
                    Body = 'SYNTHETIC_DROP_SENTINEL'
                }
                if ($Query -match 'extend route=') { $row.route = 'ViaAppGw' }
                return [pscustomobject] $row
            }
        }

        BeforeEach {
            $script:logConfig = Import-PowerShellDataFile (
                Join-Path $script:logCollectorRepository 'config/sample.psd1'
            )
            $script:logConfig.Output.Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $script:logWorkspaceResource = (
                '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/' +
                'rg-synthetic/providers/Microsoft.OperationalInsights/workspaces/la-synthetic'
            )
            $script:logRun = New-ApimRun -Config $script:logConfig -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000010' -Operator Synthetic `
                -RunId synthetic-logs -IncludeTelemetry -StartedUtc '2026-10-15T22:00:00Z'
            Save-ApimRunSetting -RunPath $script:logRun.Path -Config $script:logConfig `
                -Environment $script:logConfig.Environments[0]
            Mock Get-ApimWorkspaceSetting {
                [pscustomobject]@{
                    workspaceId = $WorkspaceId; resourceId = $script:logWorkspaceResource
                    retentionDays = 90
                    tables = @{ ApiManagementGatewayLogs = 30; Usage = 14 }
                }
            }
            Mock Invoke-ApimLogQuery { Get-SyntheticLogRow -Query $Query }
            Mock Invoke-ApimArm { throw 'Unexpected ARM access.' }
        }

        It 'writes only projected aggregates and records separate effective log windows' {
            Invoke-ApimLogCollector -RunPath $script:logRun.Path -Environment $script:logConfig.Environments[0]
            $manifest = Get-RunManifest -RunPath $script:logRun.Path
            $record = @($manifest.collectors | Where-Object name -CEQ LogAnalytics)[0]
            $record.status | Should -BeExactly Completed
            $record.files.Count | Should -Be 7
            $usage = @($manifest.evidenceWindows | Where-Object kind -CEQ Usage)[0]
            $usage.schema | Should -BeExactly ResourceSpecific
            $usage.retentionDays | Should -Be 30
            $usage.isCapped | Should -BeTrue
            @($manifest.evidenceWindows | Where-Object kind -CEQ Security)[0].isCapped | Should -BeFalse
            @($manifest.evidenceWindows | Where-Object kind -CEQ Ingestion)[0].retentionDays | Should -Be 14
            foreach ($file in $record.files) {
                Get-Content -LiteralPath (Join-Path $script:logRun.Path $file) -Raw |
                    Should -Not -Match 'SYNTHETIC_DROP_SENTINEL|CallerIpAddress|ApimSubscriptionId|"Body"'
            }
            $api = Read-ApimNetworkCollectorJson -RunPath $script:logRun.Path -RelativePath logs/usageByApi.json
            $api.workspaces[0].rows[0].calls | Should -Be 10
            $api.workspaces[0].rows[0].backendTimeP95 | Should -BeNullOrEmpty
            Should -Invoke Invoke-ApimLogQuery -Exactly -Times 7
            Should -Invoke Invoke-ApimArm -Exactly -Times 0
        }

        It 'falls back to legacy only when resource-specific has no APIM rows' {
            Mock Get-ApimWorkspaceSetting {
                [pscustomobject]@{
                    workspaceId = $WorkspaceId; resourceId = $script:logWorkspaceResource; retentionDays = 90
                    tables = @{ ApiManagementGatewayLogs = 30; AzureDiagnostics = 60; Usage = 90 }
                }
            }
            Mock Invoke-ApimLogQuery {
                if ($Query -match '^ApiManagementGatewayLogs' -and
                    $Query -match '\|\s*summarize calls=count\(\)\s*$') {
                    return [pscustomobject]@{ calls = '0' }
                }
                Get-SyntheticLogRow -Query $Query
            }
            Invoke-ApimLogCollector -RunPath $script:logRun.Path -Environment $script:logConfig.Environments[0]
            $usage = @((Get-RunManifest -RunPath $script:logRun.Path).evidenceWindows |
                    Where-Object kind -CEQ Usage)[0]
            $usage.schema | Should -BeExactly Legacy
            $usage.retentionDays | Should -Be 60
            $usage.status | Should -BeExactly Completed
        }

        It 'qualifies mixed schemas instead of silently claiming complete usage' {
            Mock Get-ApimWorkspaceSetting {
                [pscustomobject]@{
                    workspaceId = $WorkspaceId; resourceId = $script:logWorkspaceResource; retentionDays = 90
                    tables = @{ ApiManagementGatewayLogs = 30; AzureDiagnostics = 30; Usage = 90 }
                }
            }
            Invoke-ApimLogCollector -RunPath $script:logRun.Path -Environment $script:logConfig.Environments[0]
            $usage = @((Get-RunManifest -RunPath $script:logRun.Path).evidenceWindows |
                    Where-Object kind -CEQ Usage)[0]
            $usage.schema | Should -BeExactly Mixed
            $usage.status | Should -BeExactly Partial
            $usage.reason | Should -BeExactly Conflicting
        }

        It 'does not treat absent APIM telemetry as proof of zero requests' {
            Mock Invoke-ApimLogQuery {
                if ($Query -match '\|\s*summarize calls=count\(\)\s*$') {
                    return [pscustomobject]@{ calls = '0' }
                }
                Get-SyntheticLogRow -Query $Query
            }
            Invoke-ApimLogCollector -RunPath $script:logRun.Path -Environment $script:logConfig.Environments[0]
            $usage = @((Get-RunManifest -RunPath $script:logRun.Path).evidenceWindows |
                    Where-Object kind -CEQ Usage)[0]
            $usage.schema | Should -BeExactly None
            $usage.status | Should -BeExactly Failed
            $api = Read-ApimNetworkCollectorJson -RunPath $script:logRun.Path -RelativePath logs/usageByApi.json
            $api.workspaces[0].status | Should -BeExactly Failed
            $api.workspaces[0].rows.Count | Should -Be 0
        }

        It 'isolates failed queries while retaining independent ingestion evidence' {
            Mock Invoke-ApimLogQuery {
                if ($Query -match 'backendTimeP95=') { throw 'Synthetic query denial.' }
                Get-SyntheticLogRow -Query $Query
            }
            Invoke-ApimLogCollector -RunPath $script:logRun.Path -Environment $script:logConfig.Environments[0]
            $manifest = Get-RunManifest -RunPath $script:logRun.Path
            @($manifest.evidenceWindows | Where-Object kind -CEQ Usage)[0].status | Should -BeExactly Partial
            @($manifest.evidenceWindows | Where-Object kind -CEQ Ingestion)[0].status | Should -BeExactly Completed
            @($manifest.collectors | Where-Object name -CEQ LogAnalytics)[0].status | Should -BeExactly Partial
        }

        It 'makes configured log opt-out effective before metadata or query access' {
            Save-ApimRunSetting -RunPath $script:logRun.Path -Config $script:logConfig `
                -Environment $script:logConfig.Environments[0] -SkipLogs
            Invoke-ApimLogCollector -RunPath $script:logRun.Path -Environment $script:logConfig.Environments[0]
            $manifest = Get-RunManifest -RunPath $script:logRun.Path
            @($manifest.evidenceWindows | Where-Object reason -CEQ OptOut).Count | Should -Be 3
            @($manifest.collectors | Where-Object name -CEQ LogAnalytics)[0].status | Should -BeExactly Skipped
            Should -Invoke Get-ApimWorkspaceSetting -Exactly -Times 0
            Should -Invoke Invoke-ApimLogQuery -Exactly -Times 0
        }

        It 'rejects duplicate aggregate keys and out-of-window last calls' {
            $window = Get-ApimEvidenceWindow -EndUtc '2026-10-15T22:00:00Z' -Kind Usage -Length 30
            $row = ConvertTo-ApimLogAggregate -Kind usageByApi -Row (
                Get-SyntheticLogRow -Query 'usageByApi'
            )
            { Test-ApimLogAggregate -Rows @($row, $row) -Window $window } | Should -Throw '*duplicate keys*'
            $row.lastCall = '2026-10-16T00:00:00Z'
            { Test-ApimLogAggregate -Rows @($row) -Window $window } | Should -Throw '*outside*'
        }

        It 'does not accept partial query responses as valid aggregates' {
            Mock Invoke-AzOperationalInsightsQuery {
                [pscustomobject]@{ Results = @([pscustomobject]@{ calls = '0' }); Error = @{ code = 'PartialError' } }
            }
            { & $script:logQueryTransport -WorkspaceId '00000000-0000-0000-0000-000000000002' `
                    -Query 'synthetic query' } | Should -Throw '*incomplete or invalid*'
        }

        It 'replays closed log evidence and rejects unknown fields and retention tampering' {
            Invoke-ApimLogCollector -RunPath $script:logRun.Path -Environment $script:logConfig.Environments[0]
            $record = @((Get-RunManifest -RunPath $script:logRun.Path).collectors |
                    Where-Object name -CEQ LogAnalytics)[0]
            Test-ApimLogSavedOutput -RunPath $script:logRun.Path -Collector $record | Should -Be $record.items
            $payload = Read-ApimLogEvidence -RunPath $script:logRun.Path -Kind usageMonthly
            $payload.workspaces[0].rows[0] | Add-Member secret 'SYNTHETIC_DISALLOWED_FIELD'
            $null = Write-RunFile -RunPath $script:logRun.Path -RelativePath logs/usageMonthly.json -InputObject $payload
            { Test-ApimLogSavedOutput -RunPath $script:logRun.Path -Collector $record } | Should -Throw
            Invoke-ApimLogCollector -RunPath $script:logRun.Path -Environment $script:logConfig.Environments[0]
            $metadata = Read-ApimLogEvidence -RunPath $script:logRun.Path -Kind workspaces
            $metadata.workspaces[0].tables[0].retentionDays = 60
            $null = Write-RunFile -RunPath $script:logRun.Path -RelativePath logs/workspaces.json -InputObject $metadata
            { Test-ApimLogSavedOutput -RunPath $script:logRun.Path -Collector $record } |
                Should -Throw '*schema and retention*'
        }

        It 'resolves only configured workspace metadata through query and guarded GETs with inherited retention' {
            Mock Invoke-ApimResourceGraphQuery {
                [pscustomobject]@{ id = $script:logWorkspaceResource }
            }
            Mock Invoke-ApimArm {
                if ($Uri -match '/tables\?') {
                    return [pscustomobject]@{
                        value = @(
                            [pscustomobject]@{ name = 'ApiManagementGatewayLogs'; properties = @{ retentionInDays = 30 } },
                            [pscustomobject]@{ name = 'Usage'; properties = @{ retentionInDays = -1 } },
                            [pscustomobject]@{ name = 'UnrelatedTable'; properties = @{ retentionInDays = 60 } }
                        )
                    }
                }
                [pscustomobject]@{
                    properties = @{
                        customerId = '00000000-0000-0000-0000-000000000002'
                        retentionInDays = 90
                        unknown = 'SYNTHETIC_DROP_SENTINEL'
                    }
                }
            }
            $result = & $script:workspaceSettingReader `
                -WorkspaceId '00000000-0000-0000-0000-000000000002' `
                -SubscriptionId $script:logConfig.Environments[0].SubscriptionId `
                -LogPath (Join-Path $script:logRun.Path logs/run.log)
            $result.tables.ApiManagementGatewayLogs | Should -Be 30
            $result.tables.Usage | Should -Be 90
            $result.tables.ContainsKey('UnrelatedTable') | Should -BeFalse
            Should -Invoke Invoke-ApimArm -Exactly -Times 2 -ParameterFilter {
                $Uri -match '/Microsoft.OperationalInsights/workspaces/' -and $Method -in @($null, '', 'GET')
            }
        }

        It 'rejects workspace metadata identity conflicts instead of querying another workspace' {
            Mock Invoke-ApimResourceGraphQuery { [pscustomobject]@{ id = $script:logWorkspaceResource } }
            Mock Invoke-ApimArm {
                [pscustomobject]@{ properties = @{ customerId = '00000000-0000-0000-0000-000000000099' } }
            }
            { & $script:workspaceSettingReader -WorkspaceId '00000000-0000-0000-0000-000000000002' `
                    -SubscriptionId $script:logConfig.Environments[0].SubscriptionId `
                    -LogPath (Join-Path $script:logRun.Path logs/run.log) } |
                Should -Throw '*does not match*'
            Should -Invoke Invoke-ApimArm -Exactly -Times 1
        }

        It 'excludes cost ingestion on SkipCost without disabling ordinary usage queries' {
            Save-ApimRunSetting -RunPath $script:logRun.Path -Config $script:logConfig `
                -Environment $script:logConfig.Environments[0] -SkipCost
            Invoke-ApimLogCollector -RunPath $script:logRun.Path -Environment $script:logConfig.Environments[0]
            $manifest = Get-RunManifest -RunPath $script:logRun.Path
            $record = @($manifest.collectors | Where-Object name -CEQ LogAnalytics)[0]
            $record.status | Should -BeExactly Completed
            $record.files.Count | Should -Be 6
            @($manifest.evidenceWindows | Where-Object kind -CEQ Ingestion)[0].reason | Should -BeExactly OptOut
            Test-Path -LiteralPath (Join-Path $script:logRun.Path cost/laIngestion.json) | Should -BeFalse
            Test-ApimLogSavedOutput -RunPath $script:logRun.Path -Collector $record | Should -Be $record.items
            Should -Invoke Invoke-ApimLogQuery -Exactly -Times 6
        }

        It 'collects scoped route aggregates with independent gateway retention and closed replay' {
            $script:logConfig.Edge.TrustedEdgeRanges = @('192.0.2.0/24')
            $script:logConfig.Network.AppGwSubnetCidrs = @('10.0.0.0/24')
            Save-ApimRunSetting -RunPath $script:logRun.Path -Config $script:logConfig `
                -Environment $script:logConfig.Environments[0] -IncludeObservedRoutes
            Mock Get-ApimWorkspaceSetting {
                [pscustomobject]@{
                    workspaceId = $WorkspaceId; resourceId = $script:logWorkspaceResource; retentionDays = 90
                    tables = @{ ApiManagementGatewayLogs = 30; AGWAccessLogs = 14; Usage = 14 }
                }
            }
            Invoke-ApimLogCollector -RunPath $script:logRun.Path -Environment $script:logConfig.Environments[0]
            $manifest = Get-RunManifest -RunPath $script:logRun.Path
            $record = @($manifest.collectors | Where-Object name -CEQ LogAnalytics)[0]
            $record.status | Should -BeExactly Completed
            $record.files.Count | Should -Be 11
            @($manifest.evidenceWindows | Where-Object kind -CEQ AppGateway)[0].retentionDays | Should -Be 14
            $payload = Read-ApimObservedRouteEvidence -RunPath $script:logRun.Path -Kind appgwByListener
            $payload.workspaces[0].schema | Should -BeExactly ResourceSpecific
            $payload.workspaces[0].rows[0].clientCount | Should -Be 2
            Test-ApimLogSavedOutput -RunPath $script:logRun.Path -Collector $record | Should -Be $record.items
            foreach ($kind in @('appgwByListener', 'appgwNonEdge', 'directNonAppGw', 'headersLogged')) {
                Get-Content -LiteralPath (Join-Path $script:logRun.Path "logs/$kind.json") -Raw |
                    Should -Not -Match 'SYNTHETIC_DROP_SENTINEL|ClientIp"|CallerIpAddress|RequestHeaders'
            }
            Should -Invoke Invoke-ApimLogQuery -Exactly -Times 12
            $payload.workspaces[0].retentionDays = 30
            $null = Write-RunFile -RunPath $script:logRun.Path -RelativePath logs/appgwByListener.json -InputObject $payload
            { Test-ApimLogSavedOutput -RunPath $script:logRun.Path -Collector $record } |
                Should -Throw '*schema and retention*'
        }

        It 'preserves ordinary usage when gateway telemetry is unavailable and skips unconfigured non-edge queries' {
            Save-ApimRunSetting -RunPath $script:logRun.Path -Config $script:logConfig `
                -Environment $script:logConfig.Environments[0] -IncludeObservedRoutes
            Invoke-ApimLogCollector -RunPath $script:logRun.Path -Environment $script:logConfig.Environments[0]
            $manifest = Get-RunManifest -RunPath $script:logRun.Path
            @($manifest.evidenceWindows | Where-Object kind -CEQ Usage)[0].status | Should -BeExactly Completed
            @($manifest.evidenceWindows | Where-Object kind -CEQ AppGateway)[0].status | Should -BeExactly Failed
            $nonEdge = Read-ApimObservedRouteEvidence -RunPath $script:logRun.Path -Kind appgwNonEdge
            $nonEdge.workspaces[0].status | Should -BeExactly Skipped
            $nonEdge.workspaces[0].reason | Should -BeExactly Unconfigured
            $record = @($manifest.collectors | Where-Object name -CEQ LogAnalytics)[0]
            $record.status | Should -BeExactly Partial
            Test-ApimLogSavedOutput -RunPath $script:logRun.Path -Collector $record | Should -Be $record.items
        }

        It 'qualifies mixed gateway schemas and isolates a failed header query' {
            Save-ApimRunSetting -RunPath $script:logRun.Path -Config $script:logConfig `
                -Environment $script:logConfig.Environments[0] -IncludeObservedRoutes
            Mock Get-ApimWorkspaceSetting {
                [pscustomobject]@{
                    workspaceId = $WorkspaceId; resourceId = $script:logWorkspaceResource; retentionDays = 90
                    tables = @{ ApiManagementGatewayLogs = 30; AGWAccessLogs = 30; AzureDiagnostics = 30; Usage = 14 }
                }
            }
            Mock Invoke-ApimLogQuery {
                if ($Query -match 'headersObserved=') { throw 'Synthetic forbidden header query details.' }
                if ($Query -match 'Category == "GatewayLogs"' -and $Query -match 'summarize calls=count\(\)\s*$') {
                    return [pscustomobject]@{ calls = 0 }
                }
                Get-SyntheticLogRow -Query $Query
            }
            Invoke-ApimLogCollector -RunPath $script:logRun.Path -Environment $script:logConfig.Environments[0]
            $manifest = Get-RunManifest -RunPath $script:logRun.Path
            @($manifest.evidenceWindows | Where-Object kind -CEQ Usage)[0].status | Should -BeExactly Completed
            @($manifest.evidenceWindows | Where-Object kind -CEQ AppGateway)[0].schema | Should -BeExactly Mixed
            (Read-ApimObservedRouteEvidence -RunPath $script:logRun.Path -Kind headersLogged).workspaces[0].status |
                Should -BeExactly Failed
            $record = @($manifest.collectors | Where-Object name -CEQ LogAnalytics)[0]
            Test-ApimLogSavedOutput -RunPath $script:logRun.Path -Collector $record | Should -Be $record.items
        }

        It 'records observed-route opt-out without querying and preserves legacy log inventories' {
            Save-ApimRunSetting -RunPath $script:logRun.Path -Config $script:logConfig `
                -Environment $script:logConfig.Environments[0] -IncludeObservedRoutes -SkipLogs
            Invoke-ApimLogCollector -RunPath $script:logRun.Path -Environment $script:logConfig.Environments[0]
            $manifest = Get-RunManifest -RunPath $script:logRun.Path
            @($manifest.evidenceWindows | Where-Object reason -CEQ OptOut).Count | Should -Be 4
            $record = @($manifest.collectors | Where-Object name -CEQ LogAnalytics)[0]
            Test-ApimLogSavedOutput -RunPath $script:logRun.Path -Collector $record | Should -Be 0
            Should -Invoke Invoke-ApimLogQuery -Exactly -Times 0
        }

        It 'collects legacy gateway aggregates even when cost is excluded' {
            $script:logConfig.Edge.TrustedEdgeRanges = @('192.0.2.0/24')
            Save-ApimRunSetting -RunPath $script:logRun.Path -Config $script:logConfig `
                -Environment $script:logConfig.Environments[0] -IncludeObservedRoutes -SkipCost
            Mock Get-ApimWorkspaceSetting {
                [pscustomobject]@{
                    workspaceId = $WorkspaceId; resourceId = $script:logWorkspaceResource; retentionDays = 90
                    tables = @{ AzureDiagnostics = 60 }
                }
            }
            Invoke-ApimLogCollector -RunPath $script:logRun.Path -Environment $script:logConfig.Environments[0]
            $manifest = Get-RunManifest -RunPath $script:logRun.Path
            $record = @($manifest.collectors | Where-Object name -CEQ LogAnalytics)[0]
            $record.status | Should -BeExactly Completed
            $record.files.Count | Should -Be 10
            @($manifest.evidenceWindows | Where-Object kind -CEQ AppGateway)[0].schema | Should -BeExactly Legacy
            (Read-ApimObservedRouteEvidence -RunPath $script:logRun.Path -Kind appgwNonEdge).
                workspaces[0].rows[0].clientClass | Should -BeExactly NonEdge
            Test-ApimLogSavedOutput -RunPath $script:logRun.Path -Collector $record | Should -Be $record.items
            Test-Path -LiteralPath (Join-Path $script:logRun.Path cost/laIngestion.json) | Should -BeFalse
        }
    }
}
