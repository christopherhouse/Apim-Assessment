$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force
AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Source-bound observed-route exposure' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:observedRouteRepository = $Repository

        BeforeAll {
            . (Join-Path $script:observedRouteRepository 'tests/helpers/New-SyntheticTelemetryRun.ps1')

            function Save-SyntheticRoutePayload {
                param([string] $Kind, [object] $Payload, [string] $Status = 'Completed')
                $null = Write-RunFile -RunPath $script:observedRoutePath -RelativePath "logs/$Kind.json" -InputObject $Payload
                $record = @((Get-RunManifest -RunPath $script:observedRoutePath).collectors |
                        Where-Object name -CEQ LogAnalytics)[0]
                $items = 0
                foreach ($file in $record.files) {
                    if ($file -ceq 'logs/workspaces.json') { continue }
                    $saved = Read-ApimSmokeOutputJson -RunPath $script:observedRoutePath -RelativePath $file
                    foreach ($workspace in $saved.workspaces) { $items += $workspace.rows.Count }
                }
                Set-RunCollectorStatus -RunPath $script:observedRoutePath -Name LogAnalytics -Status $Status `
                    -Items $items -Files $record.files
            }

            function Add-SyntheticPrivateRoute {
                $gateway = Read-ApimSmokeOutputJson -RunPath $script:observedRoutePath `
                    -RelativePath raw/network/appgw.agw-synthetic-prod.json
                $frontendId = "$($gateway.id)/frontendIPConfigurations/private"
                $listenerId = "$($gateway.id)/httpListeners/private-https"
                $gateway.properties.frontendIPConfigurations += [pscustomobject]@{
                    id = $frontendId; name = 'private'; properties = @{ privateIPAddress = '10.20.1.10' }
                }
                $listener = $gateway.properties.httpListeners[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json
                $listener.id = $listenerId; $listener.name = 'private-https'
                $listener.properties.frontendIPConfiguration.id = $frontendId
                $gateway.properties.httpListeners += $listener
                $rule = $gateway.properties.requestRoutingRules[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json
                $rule.id = "$($gateway.id)/requestRoutingRules/private-route"; $rule.name = 'private-route'
                $rule.properties.httpListener.id = $listenerId; $rule.properties.priority = 110
                $gateway.properties.requestRoutingRules += $rule
                $null = Write-RunFile -RunPath $script:observedRoutePath `
                    -RelativePath raw/network/appgw.agw-synthetic-prod.json -InputObject $gateway
            }

            function Add-SyntheticRouteWorkspaceCopy {
                $newId = '00000000-0000-0000-0000-000000000099'
                $context = Get-ApimRunSetting -RunPath $script:observedRoutePath
                $context.Settings.telemetry.workspaceIds += $newId
                $null = Write-RunFile -RunPath $script:observedRoutePath `
                    -RelativePath restricted/run-settings.json -InputObject $context.Settings
                foreach ($entry in @($context.Manifest.evidenceWindows | Where-Object {
                            $_.kind -cin @('Usage', 'Security', 'Ingestion', 'AppGateway')
                        })) {
                    $copy = $entry | ConvertTo-Json -Depth 10 | ConvertFrom-Json
                    $copy.target = $newId
                    $context.Manifest.evidenceWindows += $copy
                }
                $null = Save-RunManifest -RunPath $script:observedRoutePath -Manifest $context.Manifest
                $record = @($context.Manifest.collectors | Where-Object name -CEQ LogAnalytics)[0]
                foreach ($file in $record.files) {
                    $payload = Read-ApimSmokeOutputJson -RunPath $script:observedRoutePath -RelativePath $file
                    $copy = $payload.workspaces[0] | ConvertTo-Json -Depth 30 | ConvertFrom-Json
                    $copy.workspaceId = $newId
                    if ($file -ceq 'logs/workspaces.json') { $copy.resourceId += '-copy' }
                    $payload.workspaces += $copy
                    $null = Write-RunFile -RunPath $script:observedRoutePath -RelativePath $file -InputObject $payload
                }
                $payload = Read-ApimLogEvidence -RunPath $script:observedRoutePath -Kind usageByRoute
                Save-SyntheticRoutePayload -Kind usageByRoute -Payload $payload
            }
        }

        BeforeEach {
            $script:observedRouteInput = New-SyntheticTelemetryRun -RepoRoot $script:observedRouteRepository `
                -OutputRoot (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) -IncludeObservedRoutes
            $script:observedRoutePath = $script:observedRouteInput.Run.Path
            Mock Invoke-ApimArm { throw 'Observed-route replay must remain offline.' }
            Mock Invoke-ApimLogQuery { throw 'Observed-route replay must not query Azure.' }
            Mock Get-ApimSpectralTool { return $null }
        }

        It 'classifies complete positive and zero gateway usage and replays byte-identically offline' {
            (Invoke-ApimAnalyze -RunFolder $script:observedRoutePath).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:observedRoutePath
            $orders = @($models.exposure | Where-Object apiId -CEQ orders-v1)[0]
            $orders.exposure | Should -BeExactly ExternalInUse
            $orders.callsViaAppGw | Should -Be 25
            $orders.callsInternal | Should -Be 10
            $orders.confidence | Should -BeExactly High
            @($models.exposure | Where-Object apiId -CEQ status-v1)[0].exposure | Should -BeExactly ExternalUnintended
            @($models.apis | Where-Object apiId -CEQ orders-v1)[0].callsViaAppGw | Should -Be 25
            $first = Get-Content -LiteralPath (Join-Path $script:observedRoutePath model/exposure.json) -Raw
            (Invoke-ApimAnalyze -RunFolder $script:observedRoutePath).ExitCode | Should -Be 0
            Get-Content -LiteralPath (Join-Path $script:observedRoutePath model/exposure.json) -Raw | Should -BeExactly $first
            Should -Invoke Invoke-ApimArm -Exactly -Times 0
            Should -Invoke Invoke-ApimLogQuery -Exactly -Times 0
        }

        It 'never treats partial query evidence as zero usage' {
            $context = Get-ApimRunSetting -RunPath $script:observedRoutePath
            $entry = @($context.Manifest.evidenceWindows | Where-Object kind -CEQ Usage)[0]
            $entry.status = 'Partial'; $entry.reason = 'Unavailable'
            $null = Save-RunManifest -RunPath $script:observedRoutePath -Manifest $context.Manifest
            $payload = Read-ApimLogEvidence -RunPath $script:observedRoutePath -Kind usageByRoute
            $payload.workspaces[0].status = 'Partial'; $payload.workspaces[0].rows = @()
            Save-SyntheticRoutePayload -Kind usageByRoute -Payload $payload -Status Partial
            (Invoke-ApimAnalyze -RunFolder $script:observedRoutePath).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:observedRoutePath
            $models.exposure.exposure | Should -Be @('Unknown', 'Unknown')
            @($models.exposure | Where-Object { $null -ne $_.callsViaAppGw }).Count | Should -Be 0
        }

        It 'withholds public attribution for unclassified caller routes without discarding known internal calls' {
            $payload = Read-ApimLogEvidence -RunPath $script:observedRoutePath -Kind usageByRoute
            $payload.workspaces[0].rows[0].route = 'Unknown'
            Save-SyntheticRoutePayload -Kind usageByRoute -Payload $payload
            (Invoke-ApimAnalyze -RunFolder $script:observedRoutePath).ExitCode | Should -Be 0
            $orders = @((Get-ApimModelSet -RunPath $script:observedRoutePath).exposure |
                    Where-Object apiId -CEQ orders-v1)[0]
            $orders.exposure | Should -BeExactly Unknown
            $orders.callsViaAppGw | Should -BeNullOrEmpty
            $orders.callsInternal | Should -Be 10
            $orders.missingInputs | Should -Contain unknownCallerRoute
        }

        It 'does not proportionally assign mixed public and private listener totals to individual APIs' {
            Add-SyntheticPrivateRoute
            $payload = Read-ApimObservedRouteEvidence -RunPath $script:observedRoutePath -Kind appgwByListener
            $row = $payload.workspaces[0].rows[0] | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $row.listener = 'private-https'; $row.rule = 'private-route'; $row.calls = 15
            $payload.workspaces[0].rows += $row
            Save-SyntheticRoutePayload -Kind appgwByListener -Payload $payload
            (Invoke-ApimAnalyze -RunFolder $script:observedRoutePath).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:observedRoutePath
            $orders = @($models.exposure | Where-Object apiId -CEQ orders-v1)[0]
            $orders.exposure | Should -BeExactly Unknown
            $orders.callsViaAppGw | Should -BeNullOrEmpty
            $orders.confidence | Should -BeExactly Medium
            $orders.missingInputs | Should -Contain privateListener
            @($models.exposure | Where-Object apiId -CEQ status-v1)[0].exposure | Should -BeExactly ExternalUnintended
        }

        It 'uses same-window listener evidence to distinguish idle private listeners from observed public use' {
            Add-SyntheticPrivateRoute
            (Invoke-ApimAnalyze -RunFolder $script:observedRoutePath).ExitCode | Should -Be 0
            $orders = @((Get-ApimModelSet -RunPath $script:observedRoutePath).exposure |
                    Where-Object apiId -CEQ orders-v1)[0]
            $orders.exposure | Should -BeExactly ExternalInUse
            $orders.callsViaAppGw | Should -Be 25
            $orders.confidence | Should -BeExactly Medium
        }

        It 'does not use shorter listener windows to resolve public-private ambiguity' {
            Add-SyntheticPrivateRoute
            $context = Get-ApimRunSetting -RunPath $script:observedRoutePath
            $workspace = $context.Settings.telemetry.workspaceIds[0]
            $window = Get-ApimEvidenceWindow -EndUtc $context.Manifest.startedUtc -Kind AppGateway `
                -Length $context.Manifest.windows.usageDays -RetentionDays 30
            Set-ApimEvidenceWindow -RunPath $script:observedRoutePath -Kind AppGateway -Target $workspace `
                -Window $window -Schema ResourceSpecific -Status Completed
            foreach ($kind in @('appgwByListener', 'appgwNonEdge')) {
                $payload = Read-ApimObservedRouteEvidence -RunPath $script:observedRoutePath -Kind $kind
                foreach ($field in $window.PSObject.Properties.Name) { $payload.workspaces[0].$field = $window.$field }
                Save-SyntheticRoutePayload -Kind $kind -Payload $payload
            }
            $metadata = Read-ApimLogEvidence -RunPath $script:observedRoutePath -Kind workspaces
            @($metadata.workspaces[0].tables | Where-Object name -CEQ AGWAccessLogs)[0].retentionDays = 30
            $null = Write-RunFile -RunPath $script:observedRoutePath -RelativePath logs/workspaces.json -InputObject $metadata
            (Invoke-ApimAnalyze -RunFolder $script:observedRoutePath).ExitCode | Should -Be 0
            $orders = @((Get-ApimModelSet -RunPath $script:observedRoutePath).exposure |
                    Where-Object apiId -CEQ orders-v1)[0]
            $orders.exposure | Should -BeExactly Unknown
            $orders.missingInputs | Should -Contain privateListener
        }

        It 'deduplicates identical workspace copies and withholds conflicting overlapping traffic' {
            Add-SyntheticRouteWorkspaceCopy
            (Invoke-ApimAnalyze -RunFolder $script:observedRoutePath).ExitCode | Should -Be 0
            $models = Get-ApimModelSet -RunPath $script:observedRoutePath
            @($models.exposure | Where-Object apiId -CEQ orders-v1)[0].callsViaAppGw | Should -Be 25
            $payload = Read-ApimLogEvidence -RunPath $script:observedRoutePath -Kind usageByRoute
            $payload.workspaces[1].rows[0].calls = 26
            Save-SyntheticRoutePayload -Kind usageByRoute -Payload $payload
            (Invoke-ApimAnalyze -RunFolder $script:observedRoutePath).ExitCode | Should -Be 0
            (Get-ApimModelSet -RunPath $script:observedRoutePath).exposure.exposure | Should -Be @('Unknown', 'Unknown')
        }

        It 'rejects model, source, network and closed-evidence tampering before downstream use' {
            (Invoke-ApimAnalyze -RunFolder $script:observedRoutePath).ExitCode | Should -Be 0
            $exposure = Get-Content -LiteralPath (
                Join-Path $script:observedRoutePath model/exposure.json
            ) -Raw | ConvertFrom-Json -Depth 100
            $exposure[0].callsViaAppGw = 99
            $null = Write-RunFile -RunPath $script:observedRoutePath -RelativePath model/exposure.json -InputObject $exposure
            { Get-ApimModelSet -RunPath $script:observedRoutePath } | Should -Throw '*validated sources*'
            (Invoke-ApimAnalyze -RunFolder $script:observedRoutePath).ExitCode | Should -Be 0
            $network = Read-ApimSmokeOutputJson -RunPath $script:observedRoutePath -RelativePath model/network.json
            $network.directPublic = $true
            $null = Write-RunFile -RunPath $script:observedRoutePath -RelativePath model/network.json -InputObject $network
            { Get-ApimModelSet -RunPath $script:observedRoutePath } | Should -Throw '*validated sources*'
            (Invoke-ApimAnalyze -RunFolder $script:observedRoutePath).ExitCode | Should -Be 0
            $payload = Read-ApimLogEvidence -RunPath $script:observedRoutePath -Kind usageByRoute
            $payload.workspaces[0].rows[0].calls = 26
            Save-SyntheticRoutePayload -Kind usageByRoute -Payload $payload
            { Get-ApimModelSet -RunPath $script:observedRoutePath } | Should -Throw '*validated sources*'
            $headers = Read-ApimObservedRouteEvidence -RunPath $script:observedRoutePath -Kind headersLogged
            $headers.workspaces[0].rows[0] | Add-Member headerValue 'SYNTHETIC_FORBIDDEN_VALUE'
            $null = Write-RunFile -RunPath $script:observedRoutePath -RelativePath logs/headersLogged.json -InputObject $headers
            (Invoke-ApimAnalyze -RunFolder $script:observedRoutePath).ExitCode | Should -Be 4
        }

        It 'renders observed labels and counts locally while retaining the existing model-safe allowlist' {
            (Invoke-ApimAnalyze -RunFolder $script:observedRoutePath).ExitCode | Should -Be 0
            $candidate = New-ApimAnalysisPackage -RunPath $script:observedRoutePath -Config $script:observedRouteInput.Config
            $candidatePath = Join-Path $script:observedRoutePath (
                "restricted/candidates/$($candidate.candidateId)/analysis-package.json"
            )
            (Test-ApimAnalysisPackage -CandidatePath $candidatePath).status | Should -BeExactly Passed
            $json = Get-Content -LiteralPath $candidatePath -Raw
            $json | Should -Not -Match 'orders-v1|agw-synthetic|gatewayId|workspaceId|listener|clientCount|headersObserved'
            $package = ConvertFrom-Json $json
            $package.facts.Where({ $_.code -ceq 'Exposure' }).value | Should -Contain ExternalInUse
            $excel = Export-ApimActionPlan -RunPath $script:observedRoutePath
            $workbook = Open-ExcelPackage -Path $excel
            try {
                $sheet = $workbook.Workbook.Worksheets['Exposure Map']
                $table = $sheet.Tables['tblExposure']
                $headers = @{}
                for ($column = $table.Address.Start.Column; $column -le $table.Address.End.Column; $column++) {
                    $headers[$sheet.Cells[$table.Address.Start.Row, $column].Text] = $column
                }
                $row = $table.Address.Start.Row + 1
                $sheet.Cells[$row, $headers.Exposure].Text | Should -BeExactly ExternalInUse
                $sheet.Cells[$row, $headers['Calls via App Gateway']].Value | Should -Be 25
            }
            finally { $workbook.Dispose() }
            (Export-ApimExecutiveHtml -RunPath $script:observedRoutePath -WorkbookPath $excel).status |
                Should -BeExactly Completed
            Get-Content -LiteralPath ([IO.Path]::ChangeExtension($excel, '.html')) -Raw |
                Should -Match 'ExternalInUse'
        }
    }
}
