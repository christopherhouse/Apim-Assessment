$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force
AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Isolated synthetic broker workflow' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:brokerRepository = $Repository
        BeforeAll {
            . (Join-Path $script:brokerRepository 'tests/helpers/New-SyntheticCollectedRun.ps1')
            function Get-SyntheticBrokerContext {
                param([string] $Root)
                $restricted = Join-Path $Root 'restricted'
                $fixture = New-SyntheticCollectedRun -RepoRoot $script:brokerRepository -OutputRoot $restricted
                (Invoke-ApimAnalyze -RunFolder $fixture.Run.Path).ExitCode | Should -Be 0
                $operator = @{
                    schemaVersion = '1.0'; restrictedRoot = $restricted
                    analysisRoot = Join-Path $Root 'analysis'; privateStagingRoot = Join-Path $Root 'stage'
                    visibleRoots = @((Join-Path $Root 'analysis')); visibleRootsComplete = $true
                    exclusiveFilesystem = $true; approved = $true; aliases = @()
                    savedRuns = @(@{ runId = 'run-00000000000000000000000000000001'; relativePath = $fixture.Run.RunId })
                }
                $path = Join-Path $restricted 'broker.json'
                [IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $operator -Depth 10))
                return @{ context = (Get-ApimBrokerContext -OperatorConfigPath $path); configPath = $path; fixture = $fixture }
            }
            function Invoke-SyntheticBroker {
                param([object] $Context, [string] $Name, [hashtable] $Arguments)
                $result = Invoke-ApimBrokerWorker -Context $Context -Name $Name -Arguments $Arguments
                Assert-ApimBrokerResult -Name $Name -Result $result -Context $Context -Arguments $Arguments
                return $result
            }
        }

        It 'promotes raw-derived evidence and binds validated proposals without polluting immutable publication' {
            $setup = Get-SyntheticBrokerContext -Root (Join-Path $TestDrive 'workflow')
            $context = $setup.context; $id = 'run-00000000000000000000000000000001'
            $publication = Invoke-SyntheticBroker -Context $context -Name promote_analysis_package -Arguments @{ runId = $id }
            $read = Invoke-SyntheticBroker -Context $context -Name read_validated_analysis_package -Arguments @{ runId = $id }
            $read.packageSha256 | Should -Be $publication.packageSha256
            $condition = @($read.package.facts | Where-Object { $_.code -ceq 'AssessmentCondition' -and $_.value -ceq 'PolicyCredentialDetected' })[0]
            $finding = @($read.package.findings | Where-Object { $_.factRefs -ccontains $condition.factId })[0]
            $proposal = @{
                schemaVersion = '1.0'; analyst = 'Security'
                observations = @(@{ observationId = 'observation-security-001'; category = 'Security'
                        confidence = $condition.confidence; factRefs = @($condition.factId); findingRefs = @($finding.findingId)
                        rationaleCode = 'SecretHandlingRisk'; recommendationCode = 'RemoveHardcodedSecrets' })
            } | ConvertTo-Json -Depth 10 -Compress
            $accepted = Invoke-SyntheticBroker -Context $context -Name validate_agent_output -Arguments @{
                runId = $id; kind = 'ExpertObservations'; json = $proposal; packageSha256 = $publication.packageSha256
            }
            $accepted.outputId | Should -Match '^output-[a-f0-9]{32}$'
            $output = Invoke-SyntheticBroker -Context $context -Name read_validated_agent_outputs -Arguments @{ runId = $id }
            $output.observations.Count | Should -Be 1
            $summary = @{
                schemaVersion = '1.0'; posture = 'ActionRequired'; confidence = 'Medium'
                priorities = @(@{ itemId = 'priority-001'; code = 'ProtectSecrets'; confidence = $condition.confidence
                        findingRefs = @($finding.findingId); factRefs = @(); observationRefs = @('observation-security-001') })
                themes = @(); decisions = @(); roadmap = @()
                assumptions = $read.package.assumptions; dataGaps = $read.package.dataGaps
            } | ConvertTo-Json -Depth 10 -Compress
            $executive = Invoke-SyntheticBroker -Context $context -Name validate_agent_output -Arguments @{
                runId = $id; kind = 'ExecutiveSummary'; json = $summary; packageSha256 = $publication.packageSha256
            }
            $rendered = Invoke-SyntheticBroker -Context $context -Name render_reports -Arguments @{
                runId = $id; validatedAgentOutputs = @($accepted.outputId, $executive.outputId)
            }
            $rendered.artifacts.Count | Should -Be 2
            $paths = Get-ApimRenderedPath -RunPath $setup.fixture.Run.Path
            $html = Get-Content -LiteralPath $paths.html -Raw
            $html | Should -Match 'Validated AI synthesis'
            $html | Should -Match 'finding-[0-9]+'
            $html | Should -Not -Match 'api-00[12]|candidate-[a-f0-9]{32}'
            $version = Join-Path $context.operator.analysisRoot $publication.version
            @(Get-ChildItem -LiteralPath $version -Force).Name | Should -Be @('analysis-package.json', 'validation-attestation.json')
            $arguments = @{ runId = $id; kind = 'ExpertObservations'; json = $proposal; packageSha256 = ('a' * 64) }
            { Invoke-SyntheticBroker -Context $context -Name validate_agent_output -Arguments $arguments } | Should -Throw 'BROKER_OPERATION_FAILED'
            $entry = $context.runs[$id].outputs[$accepted.outputId]
            $bindingPath = [IO.Path]::ChangeExtension($entry.path, '.binding.json')
            $bindingJson = Get-Content -LiteralPath $bindingPath -Raw
            $binding = $bindingJson | ConvertFrom-Json -AsHashtable
            $binding.outputId | Should -Be $accepted.outputId
            $binding.packageSha256 | Should -Be $publication.packageSha256
            $binding.outputSha256 | Should -Be (
                (Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash.ToLowerInvariant()
            )
            $binding.packageSha256 = 'a' * 64
            [IO.File]::WriteAllText($bindingPath, (ConvertTo-Json -InputObject $binding))
            { Invoke-SyntheticBroker -Context $context -Name read_validated_agent_outputs -Arguments @{ runId = $id } } | Should -Throw 'BROKER_OPERATION_FAILED'
            [IO.File]::WriteAllText($bindingPath, $bindingJson)
            [IO.File]::AppendAllText($entry.path, ' ')
            { Invoke-SyntheticBroker -Context $context -Name read_validated_agent_outputs -Arguments @{ runId = $id } } | Should -Throw 'BROKER_OPERATION_FAILED'
        }

        It 'rejects unknown operations, caller paths, unknown runs and tampered promoted bytes' {
            $setup = Get-SyntheticBrokerContext -Root (Join-Path $TestDrive 'mutations')
            $context = $setup.context; $id = 'run-00000000000000000000000000000001'
            foreach ($case in @(
                    @{ name = 'shell'; arguments = @{ command = 'NEVER_FORWARD_BROKER_CANARY' } },
                    @{ name = 'get_assessment_status'; arguments = @{ runId = $id; path = 'NEVER_FORWARD_BROKER_CANARY' } },
                    @{ name = 'read_validated_analysis_package'; arguments = @{ runId = 'run-00000000000000000000000000000099' } }
                )) {
                { Invoke-SyntheticBroker -Context $context -Name $case.name -Arguments $case.arguments } | Should -Throw 'BROKER_OPERATION_FAILED'
            }
            $publication = Invoke-SyntheticBroker -Context $context -Name promote_analysis_package -Arguments @{ runId = $id }
            $path = Join-Path (Join-Path $context.operator.analysisRoot $publication.version) 'analysis-package.json'
            [IO.File]::AppendAllText($path, ' ')
            { Invoke-SyntheticBroker -Context $context -Name read_validated_analysis_package -Arguments @{ runId = $id } } | Should -Throw 'BROKER_OPERATION_FAILED'
        }

        It 'renders paired deterministic local deliverables without specialist output' {
            $setup = Get-SyntheticBrokerContext -Root (Join-Path $TestDrive 'fallback')
            $context = $setup.context; $id = 'run-00000000000000000000000000000001'
            $null = Invoke-SyntheticBroker -Context $context -Name promote_analysis_package -Arguments @{ runId = $id }
            $result = Invoke-SyntheticBroker -Context $context -Name render_reports -Arguments @{ runId = $id; validatedAgentOutputs = @() }
            $result.artifacts.Count | Should -Be 2
            $paths = Get-ApimRenderedPath -RunPath $setup.fixture.Run.Path
            (Get-Content -LiteralPath $paths.html -Raw) | Should -Match 'Deterministic report / no AI synthesis'
            [IO.Path]::ChangeExtension($paths.workbook, '.html') | Should -Be $paths.html
            $registry = Get-Content -LiteralPath (
                Join-Path $setup.fixture.Run.Path 'restricted/report-artifacts.json'
            ) -Raw | ConvertFrom-Json
            $registry.artifacts.artifactId | Should -Be $result.artifacts
        }

        It 'starts only a registered alias/environment and exposes a new opaque ID, never runtime paths' {
            $setup = Get-SyntheticBrokerContext -Root (Join-Path $TestDrive 'start')
            $context = $setup.context
            $context.aliases.Add('synthetic-test', @{ configPath = 'SYNTHETIC_PRIVATE_CONFIG_PATH'; environments = @('Test') })
            Mock Invoke-ApimAssessment {
                [pscustomobject]@{ RunId = 'synthetic-operational'; ExitCode = 3; Status = 'SYNTHETIC_PRIVATE_STATUS' }
            }
            $result = Invoke-ApimBrokerTool -Context $context -Name run_assessment `
                -Arguments @{ configAlias = 'synthetic-test'; environment = 'Test'; options = @{ stage = 'Collect' } }
            $result.runId | Should -Match '^run-[a-f0-9]{32}$'
            $result.status | Should -Be 'Partial'
            ($result | ConvertTo-Json) | Should -Not -Match 'SYNTHETIC_PRIVATE|synthetic-operational|configPath|path'
            Should -Invoke Invoke-ApimAssessment -Times 1 -Exactly -ParameterFilter {
                $Config -ceq 'SYNTHETIC_PRIVATE_CONFIG_PATH' -and $Environment -ceq 'Test' -and $Stage -ceq 'Collect'
            }
            foreach ($arguments in @(
                    @{ configAlias = 'unregistered'; environment = 'Test'; options = @{ stage = 'All' } },
                    @{ configAlias = 'synthetic-test'; environment = 'Prod'; options = @{ stage = 'All' } },
                    @{ configAlias = 'synthetic-test'; environment = 'Test'; options = @{ stage = 'All'; path = 'SYNTHETIC_PRIVATE' } }
                )) {
                { Invoke-ApimBrokerTool -Context $context -Name run_assessment -Arguments $arguments } | Should -Throw
            }
            Should -Invoke Invoke-ApimAssessment -Times 1 -Exactly
        }

        It 'rejects incomplete or overlapping operator admission without exposing paths' {
            $setup = Get-SyntheticBrokerContext -Root (Join-Path $TestDrive 'admission')
            $operator = $setup.context.operator
            foreach ($case in @('incomplete', 'overlap', 'unapproved', 'nonexclusive')) {
                $changed = $operator.Clone()
                switch ($case) {
                    incomplete { $changed.visibleRootsComplete = $false }
                    overlap { $changed.visibleRoots = @($changed.restrictedRoot) }
                    unapproved { $changed.approved = $false }
                    nonexclusive { $changed.exclusiveFilesystem = $false }
                }
                [IO.File]::WriteAllText($setup.configPath, (ConvertTo-Json -InputObject $changed -Depth 10))
                { Get-ApimBrokerContext -OperatorConfigPath $setup.configPath } | Should -Throw
            }
        }

        It 'speaks closed MCP lifecycle and tool calls through an actual stdio process' {
            $setup = Get-SyntheticBrokerContext -Root (Join-Path $TestDrive 'stdio')
            $process = [Diagnostics.Process]::new()
            $info = [Diagnostics.ProcessStartInfo]::new()
            $info.FileName = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
            foreach ($argument in @('-NoProfile', '-NonInteractive', '-File',
                    (Join-Path $script:brokerRepository 'scripts/Start-ApimBroker.ps1'),
                    '-OperatorConfigPath', $setup.configPath)) { $info.ArgumentList.Add($argument) }
            $info.UseShellExecute = $false; $info.RedirectStandardInput = $true
            $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
            $process.StartInfo = $info
            $null = $process.Start()
            $stderr = $process.StandardError.ReadToEndAsync()
            try {
                $messages = @(
                    '{"jsonrpc":"2.0","id":1,"method":"tools/list"}',
                    '{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"synthetic","version":"1.0"}}}',
                    '{"jsonrpc":"2.0","method":"notifications/initialized"}',
                    '{"jsonrpc":"2.0","id":3,"method":"tools/list"}',
                    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_assessment_status","arguments":{"runId":"run-00000000000000000000000000000001"}}}',
                    '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_assessment_status","arguments":{"runId":"run-00000000000000000000000000000001","path":"NEVER_FORWARD_BROKER_CANARY"}}}',
                    '{"jsonrpc":"2.0","id":6,"method":"resources/read","params":{"uri":"NEVER_FORWARD_BROKER_CANARY"}}',
                    '{"jsonrpc":"2.0","id":7,"id":8,"method":"ping"}'
                )
                foreach ($message in $messages) { $process.StandardInput.WriteLine($message) }
                $process.StandardInput.Close()
                $stdout = $process.StandardOutput.ReadToEndAsync()
                $process.WaitForExit(60000) | Should -BeTrue
                $text = $stdout.GetAwaiter().GetResult()
                $stderr.GetAwaiter().GetResult() | Should -BeNullOrEmpty
                $text | Should -Not -Match 'NEVER_FORWARD_BROKER_CANARY|synthetic-operational|configPath|restrictedRoot'
                $lines = @($text.Trim() -split '\r?\n' | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable })
                $lines.Count | Should -Be 7
                $lines[0].error.message | Should -Be 'BROKER_REQUEST_REJECTED'
                $lines[1].result.protocolVersion | Should -Be '2025-11-25'
                $lines[2].result.tools.Count | Should -Be 7
                $lines[3].result.isError | Should -BeFalse
                $lines[4].result.isError | Should -BeTrue
                $lines[5].error.code | Should -Be -32601
                $lines[6].error.message | Should -Be 'BROKER_REQUEST_REJECTED'
            }
            finally {
                if (-not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
                $process.Dispose()
            }
        }
    }
}
