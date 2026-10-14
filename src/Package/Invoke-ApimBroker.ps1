#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimBrokerTool {
    [CmdletBinding()]
    param()
    $run = @{ type = 'string'; pattern = '^run-[a-f0-9]{32}$' }
    $digest = @{ type = 'string'; pattern = '^[a-f0-9]{64}$' }
    $output = @{ type = 'string'; pattern = '^output-[a-f0-9]{32}$' }
    $definitions = [ordered]@{
        run_assessment                  = @{
            configAlias = @{ type = 'string'; pattern = '^[a-z][a-z0-9-]{0,31}$' }
            environment = @{ type = 'string'; pattern = '^[A-Za-z][A-Za-z0-9-]{0,31}$' }
            options     = @{
                type = 'object'; additionalProperties = $false; required = @('stage')
                properties = @{ stage = @{ enum = @('All', 'Collect') } }
            }
        }
        get_assessment_status           = @{ runId = $run }
        promote_analysis_package        = @{ runId = $run }
        read_validated_analysis_package = @{ runId = $run }
        validate_agent_output           = @{
            runId = $run; packageSha256 = $digest
            kind = @{ enum = @('ExpertObservations', 'ExecutiveSummary') }
            json = @{ type = 'string'; minLength = 2; maxLength = 1048576 }
        }
        read_validated_agent_outputs    = @{ runId = $run }
        render_reports                  = @{
            runId                 = $run
            validatedAgentOutputs = @{ type = 'array'; maxItems = 3; uniqueItems = $true; items = $output }
        }
    }
    foreach ($name in $definitions.Keys) {
        [ordered]@{
            name        = $name
            description = switch ($name) {
                run_assessment { 'Start an operator-approved assessment; returns opaque ID and coarse status.' }
                get_assessment_status { 'Read fixed stage/status codes only.' }
                promote_analysis_package { 'Independently validate and promote a model-safe snapshot.' }
                read_validated_analysis_package { 'Read the digest-checked promoted model-safe package.' }
                validate_agent_output { 'Validate approved-code proposals and bind them to the exact package digest.' }
                read_validated_agent_outputs { 'Read only revalidated digest-bound specialist and executive proposals.' }
                render_reports { 'Render local reports; returns opaque artifact IDs only.' }
            }
            inputSchema = @{
                type = 'object'; additionalProperties = $false
                required = @($definitions[$name].Keys); properties = $definitions[$name]
            }
            annotations = @{
                readOnlyHint = $name -cin @('get_assessment_status', 'read_validated_analysis_package', 'read_validated_agent_outputs')
                destructiveHint = $false; openWorldHint = $false
            }
        }
    }
}

function ConvertFrom-ApimBrokerJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Json)
    if ([Text.Encoding]::UTF8.GetByteCount($Json) -gt 2MB) { throw 'BROKER_REQUEST_REJECTED' }
    $options = [Text.Json.JsonDocumentOptions]::new(); $options.MaxDepth = 32
    $document = [Text.Json.JsonDocument]::Parse($Json, $options)
    try { Assert-ApimAnalysisJsonMember -Element $document.RootElement }
    finally { $document.Dispose() }
    return ConvertFrom-Json -InputObject $Json -AsHashtable -Depth 32
}

function Get-ApimBrokerContext {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $OperatorConfigPath)
    $json = [Text.UTF8Encoding]::new($false, $true).GetString(
        (Read-ApimAnalysisSnapshot -Path $OperatorConfigPath)
    )
    $operator = ConvertFrom-ApimBrokerJson -Json $json
    $schema = Join-Path $analysisSchemaRoot 'broker-operator.schema.json'
    if (-not (Test-Json -Json $json -SchemaFile $schema -ErrorAction Stop)) {
        throw 'BROKER_ISOLATION_REJECTED'
    }
    $null = Assert-ApimAnalysisIsolation -RestrictedRoot $operator.restrictedRoot `
        -AnalysisRoot $operator.analysisRoot -PrivateStagingRoot $operator.privateStagingRoot `
        -VisibleRoots $operator.visibleRoots
    foreach ($path in @($OperatorConfigPath) + @($operator.aliases | ForEach-Object { $_.configPath })) {
        $full = [IO.Path]::GetFullPath($path)
        if (-not (Test-ConfigPathOverlap -First $operator.restrictedRoot -Second $full)) {
            throw 'BROKER_ISOLATION_REJECTED'
        }
        foreach ($visible in $operator.visibleRoots) {
            if (Test-ConfigPathOverlap -First $full -Second $visible) { throw 'BROKER_ISOLATION_REJECTED' }
        }
    }
    $aliases = @{}
    foreach ($entry in $operator.aliases) {
        if ($aliases.ContainsKey($entry.alias)) { throw 'BROKER_CONFIG_REJECTED' }
        $settings = Get-Config -Path $entry.configPath
        if ([IO.Path]::GetFullPath($settings.Output.Root) -cne
            [IO.Path]::GetFullPath($operator.restrictedRoot)) { throw 'BROKER_ISOLATION_REJECTED' }
        $aliases.Add($entry.alias, $entry)
    }
    $runs = @{}
    foreach ($entry in $operator.savedRuns) {
        if ($runs.ContainsKey($entry.runId)) { throw 'BROKER_CONFIG_REJECTED' }
        $path = Resolve-RunFilePath -RunPath $operator.restrictedRoot -RelativePath $entry.relativePath
        $null = Get-RunManifest -RunPath $path
        $runs.Add($entry.runId, @{ path = $path; publication = $null; outputs = @{} })
    }
    return @{ operator = $operator; aliases = $aliases; runs = $runs }
}

function Get-ApimBrokerPublication {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Context,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Run)
    if ($null -eq $Run.publication) { throw 'BROKER_PACKAGE_UNAVAILABLE' }
    $null = Assert-ApimAnalysisIsolation -RestrictedRoot $Context.operator.restrictedRoot `
        -AnalysisRoot $Context.operator.analysisRoot -PrivateStagingRoot $Context.operator.privateStagingRoot `
        -VisibleRoots $Context.operator.visibleRoots
    Assert-ApimAnalysisZone -Path $Context.operator.analysisRoot
    $directory = Join-Path $Context.operator.analysisRoot $Run.publication.version
    $bytes = Read-ApimAnalysisSnapshot -Path (Join-Path $directory 'analysis-package.json')
    if ((Get-ApimAnalysisDigest -Bytes $bytes) -cne $Run.publication.packageSha256) {
        throw 'BROKER_PACKAGE_REJECTED'
    }
    return [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
}

function Get-ApimBrokerOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Run,
        [Parameter(Mandatory)][string] $PackageJson
    )
    $sets = @(); $executives = @()
    foreach ($id in @($Run.outputs.Keys | Sort-Object)) {
        $entry = $Run.outputs[$id]
        if ($entry.packageSha256 -cne $Run.publication.packageSha256) { throw 'BROKER_OUTPUT_STALE' }
        $bindingPath = [IO.Path]::ChangeExtension($entry.path, '.binding.json')
        $bindingJson = [Text.UTF8Encoding]::new($false, $true).GetString(
            (Read-ApimAnalysisSnapshot -Path $bindingPath)
        )
        $binding = ConvertFrom-ApimBrokerJson -Json $bindingJson
        if (-not (Test-Json -Json $bindingJson -SchemaFile (
                    Join-Path $analysisSchemaRoot 'agent-output-binding.schema.json'
                ) -ErrorAction Stop) -or $binding.outputId -cne $id -or
            $binding.kind -cne $entry.kind -or
            $binding.packageSha256 -cne $entry.packageSha256 -or
            $binding.outputSha256 -cne $entry.outputSha256) {
            throw 'BROKER_OUTPUT_REJECTED'
        }
        $bytes = Read-ApimAnalysisSnapshot -Path $entry.path
        if ((Get-ApimAnalysisDigest -Bytes $bytes) -cne $entry.outputSha256) { throw 'BROKER_OUTPUT_REJECTED' }
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        if ($entry.kind -ceq 'ExpertObservations') { $sets += $text } else { $executives += $text }
    }
    $roles = @{}
    foreach ($text in $sets) {
        $null = Test-ApimAgentClaim -Kind ExpertObservations -Json $text -PackageJson $PackageJson
        $set = ConvertFrom-ApimAnalysisContractJson -Kind ExpertObservations -Json $text
        if ($roles.ContainsKey($set.analyst)) { throw 'BROKER_OUTPUT_REJECTED' }
        $roles.Add($set.analyst, $true)
    }
    if ($executives.Count -gt 1) { throw 'BROKER_OUTPUT_REJECTED' }
    foreach ($text in $executives) {
        $null = Test-ApimAgentClaim -Kind ExecutiveSummary -Json $text -PackageJson $PackageJson -ObservationJson $sets
    }
    return @{ observations = $sets; executives = $executives }
}

function Invoke-ApimBrokerTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Context,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Arguments
    )
    $tool = @(Get-ApimBrokerTool | Where-Object name -CEQ $Name)
    if ($tool.Count -ne 1) { throw 'BROKER_TOOL_REJECTED' }
    $schema = ConvertTo-Json -InputObject $tool[0].inputSchema -Depth 20 -Compress
    $json = ConvertTo-Json -InputObject $Arguments -Depth 32 -Compress
    if (-not (Test-Json -Json $json -Schema $schema -ErrorAction Stop)) { throw 'BROKER_ARGUMENT_REJECTED' }
    if ($Name -ceq 'run_assessment') {
        if (-not $Context.aliases.Contains($Arguments.configAlias)) { throw 'BROKER_ALIAS_REJECTED' }
        $alias = $Context.aliases[$Arguments.configAlias]
        if ($alias.environments -cnotcontains $Arguments.environment) { throw 'BROKER_ALIAS_REJECTED' }
        $result = Invoke-ApimAssessment -Config $alias.configPath -Environment $Arguments.environment -Stage $Arguments.options.stage
        if ($null -eq $result.RunId) { throw 'BROKER_ASSESSMENT_FAILED' }
        $path = Resolve-RunFilePath -RunPath $Context.operator.restrictedRoot -RelativePath $result.RunId
        $id = 'run-' + [guid]::NewGuid().ToString('N')
        $Context.runs.Add($id, @{ path = $path; publication = $null; outputs = @{} })
        return @{ runId = $id; status = if ($result.ExitCode -eq 0) { 'Completed' } elseif ($result.ExitCode -eq 3) { 'Partial' } else { 'Failed' } }
    }
    if (-not $Context.runs.Contains($Arguments.runId)) { throw 'BROKER_RUN_REJECTED' }
    $run = $Context.runs[$Arguments.runId]
    if ($Name -ceq 'get_assessment_status') {
        $manifest = Get-RunManifest -RunPath $run.path
        $stages = [ordered]@{}
        foreach ($stage in @('collect', 'analyze', 'modelSafe', 'report')) {
            $status = if ($stage -ceq 'modelSafe') { $manifest.modelSafe.promotion } else { $manifest.stages.$stage }
            if ($status -cnotin @('NotStarted', 'InProgress', 'Completed', 'Partial', 'Failed', 'Skipped')) {
                throw 'BROKER_STATUS_REJECTED'
            }
            $stages[$stage] = $status
        }
        return @{ runId = $Arguments.runId; stages = $stages }
    }
    if ($Name -ceq 'promote_analysis_package') {
        if ($null -ne $run.publication) {
            $null = Get-ApimBrokerPublication -Context $Context -Run $run
            return $run.publication
        }
        Test-ApimSavedFindingReplay -RunPath $run.path
        $settings = Get-ApimRunSetting -RunPath $run.path
        $candidate = New-ApimAnalysisPackage -RunPath $run.path -Config $settings.Config
        Assert-ApimAnalysisZone -Path $Context.operator.analysisRoot
        $versions = @(if (Test-Path -LiteralPath $Context.operator.analysisRoot) {
                Get-ChildItem -LiteralPath $Context.operator.analysisRoot -Directory | Sort-Object Name
            })
        $number = if ($versions.Count -eq 0) { 1 } else { [int]$versions[-1].Name.Substring(8) + 1 }
        if ($number -gt 999999) { throw 'BROKER_VERSION_REJECTED' }
        $publication = Publish-ApimAnalysisPackage -RestrictedRoot $run.path -CandidateId $candidate.candidateId `
            -AnalysisRoot $Context.operator.analysisRoot -PrivateStagingRoot $Context.operator.privateStagingRoot `
            -CopilotVisiblePath $Context.operator.visibleRoots -VisibleRootsComplete -Version ('version-{0:d6}' -f $number)
        $run.publication = @{ status = 'Promoted'; version = $publication.version; packageSha256 = $publication.packageSha256 }
        $run.candidateId = $candidate.candidateId
        $manifest = Get-RunManifest -RunPath $run.path
        $manifest.modelSafe.build = 'Completed'
        $manifest.modelSafe.validation = 'Passed'
        $manifest.modelSafe.promotion = 'Completed'
        $manifest.modelSafe.packageSha256 = $publication.packageSha256
        $null = Save-RunManifest -RunPath $run.path -Manifest $manifest
        return $run.publication
    }
    $packageJson = Get-ApimBrokerPublication -Context $Context -Run $run
    if ($Name -ceq 'read_validated_analysis_package') {
        return @{ packageSha256 = $run.publication.packageSha256; package = (ConvertFrom-ApimAnalysisContractJson -Kind AnalysisPackage -Json $packageJson) }
    }
    $outputs = Get-ApimBrokerOutput -Run $run -PackageJson $packageJson
    if ($Name -ceq 'read_validated_agent_outputs') {
        return @{ packageSha256 = $run.publication.packageSha256; observations = @($outputs.observations |
                    ForEach-Object { ConvertFrom-ApimAnalysisContractJson -Kind ExpertObservations -Json $_ })
            executive = @($outputs.executives | ForEach-Object { ConvertFrom-ApimAnalysisContractJson -Kind ExecutiveSummary -Json $_ })
        }
    }
    if ($Name -ceq 'validate_agent_output') {
        if ($Arguments.packageSha256 -cne $run.publication.packageSha256) { throw 'BROKER_OUTPUT_STALE' }
        $validation = @{ Kind = $Arguments.kind; Json = $Arguments.json; PackageJson = $packageJson }
        if ($Arguments.kind -ceq 'ExecutiveSummary') {
            if ($outputs.executives.Count -gt 0) { throw 'BROKER_OUTPUT_REJECTED' }
            $validation.ObservationJson = $outputs.observations
        }
        else {
            if ($outputs.executives.Count -gt 0) { throw 'BROKER_OUTPUT_REJECTED' }
            $new = ConvertFrom-ApimAnalysisContractJson -Kind ExpertObservations -Json $Arguments.json
            foreach ($text in $outputs.observations) {
                $prior = ConvertFrom-ApimAnalysisContractJson -Kind ExpertObservations -Json $text
                if ($prior.analyst -ceq $new.analyst) { throw 'BROKER_OUTPUT_REJECTED' }
            }
        }
        $null = Test-ApimAgentClaim @validation
        $id = 'output-' + [guid]::NewGuid().ToString('N')
        $relative = "restricted/agent-outputs/$id.json"
        $null = Write-RunFile -RunPath $run.path -RelativePath $relative -InputObject $Arguments.json -Format Text
        $path = Resolve-RunFilePath -RunPath $run.path -RelativePath $relative
        $outputDigest = Get-ApimAnalysisDigest -Bytes (Read-ApimAnalysisSnapshot -Path $path)
        $binding = @{ schemaVersion = '1.0'; outputId = $id; kind = $Arguments.kind
            packageSha256 = $run.publication.packageSha256; outputSha256 = $outputDigest }
        $bindingJson = ConvertTo-ApimAnalysisJson -Value $binding
        if (-not (Test-Json -Json $bindingJson -SchemaFile (
                    Join-Path $analysisSchemaRoot 'agent-output-binding.schema.json'
                ) -ErrorAction Stop)) { throw 'BROKER_OUTPUT_REJECTED' }
        $null = Write-RunFile -RunPath $run.path -RelativePath (
            [IO.Path]::ChangeExtension($relative, '.binding.json')
        ) -InputObject $bindingJson -Format Text
        $run.outputs.Add($id, @{ kind = $Arguments.kind; path = $path
                packageSha256 = $run.publication.packageSha256
                outputSha256 = $outputDigest
            })
        return @{ status = 'Validated'; outputId = $id; packageSha256 = $run.publication.packageSha256 }
    }
    if ($Name -ceq 'render_reports') {
        $selected = @{}
        foreach ($id in $Arguments.validatedAgentOutputs) {
            if (-not $run.outputs.Contains($id)) { throw 'BROKER_OUTPUT_REJECTED' }
            $selected.Add($id, $run.outputs[$id])
        }
        $selectedRun = @{ outputs = $selected; publication = $run.publication }
        $approved = Get-ApimBrokerOutput -Run $selectedRun -PackageJson $packageJson
        $result = Invoke-ApimReport -RunFolder $run.path
        if ($result.ExitCode -ne 0) { throw 'BROKER_RENDER_FAILED' }
        $paths = Get-ApimRenderedPath -RunPath $run.path
        if ($selected.Count -gt 0) {
            $null = Export-ApimExecutiveHtml -RunPath $run.path -WorkbookPath $paths.workbook -AgentOutputContext @{
                packageJson = $packageJson; observations = $approved.observations
                executives = $approved.executives; candidateId = $run.candidateId
            }
        }
        $artifacts = @()
        $registry = @()
        foreach ($path in @($paths.workbook, $paths.html)) {
            Test-ConfigPathLink -Path $path -Context 'Rendered broker artifact'
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'BROKER_RENDER_FAILED' }
            $id = 'artifact-' + [guid]::NewGuid().ToString('N')
            $artifacts += $id
            $registry += @{ artifactId = $id; relativePath = [IO.Path]::GetRelativePath($run.path, $path) }
        }
        $null = Write-RunFile -RunPath $run.path -RelativePath 'restricted/report-artifacts.json' `
            -InputObject @{ schemaVersion = '1.0'; artifacts = $registry }
        return @{ status = 'Completed'; artifacts = $artifacts }
    }
    throw 'BROKER_TOOL_REJECTED'
}

function Invoke-ApimBrokerWorker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Context,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Arguments
    )
    $directory = Join-Path $Context.operator.restrictedRoot (
        '.broker-' + [guid]::NewGuid().ToString('N')
    )
    Test-ConfigPathLink -Path $directory -Context 'Broker worker'
    $null = [IO.Directory]::CreateDirectory($directory)
    $requestPath = Join-Path $directory 'request.json'
    $responsePath = Join-Path $directory 'response.json'
    $process = [Diagnostics.Process]::new()
    $started = $false
    try {
        [IO.File]::WriteAllText($requestPath, (ConvertTo-Json -Depth 64 -Compress -InputObject @{
                    context = $Context; name = $Name; arguments = $Arguments
                }), [Text.UTF8Encoding]::new($false))
        $process.StartInfo = [Diagnostics.ProcessStartInfo]::new()
        $executable = if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' }
        $process.StartInfo.FileName = Join-Path $PSHOME $executable
        foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-File',
                (Join-Path (Split-Path $analysisSchemaRoot -Parent) 'scripts/Invoke-BrokerWorker.ps1'),
                '-RequestPath', $requestPath, '-ResponsePath', $responsePath)) {
            $process.StartInfo.ArgumentList.Add($argument)
        }
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        $null = $process.Start()
        $started = $true
        $stdout = $process.StandardOutput.BaseStream.CopyToAsync([IO.Stream]::Null)
        $stderr = $process.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)
        if (-not $process.WaitForExit(1200000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw 'BROKER_WORKER_TIMEOUT'
        }
        $null = $stdout.GetAwaiter().GetResult()
        $null = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $responsePath -PathType Leaf)) {
            throw 'BROKER_WORKER_FAILED'
        }
        $json = [Text.UTF8Encoding]::new($false, $true).GetString(
            (Read-ApimAnalysisSnapshot -Path $responsePath)
        )
        $response = ConvertFrom-Json -InputObject $json -AsHashtable -Depth 64
        if (-not $response.success) { throw 'BROKER_OPERATION_FAILED' }
        $Context.runs = $response.runs
        return $response.result
    }
    finally {
        if ($started -and -not $process.HasExited) {
            $process.Kill($true); $process.WaitForExit()
        }
        $process.Dispose()
        Test-ConfigPathLink -Path $directory -Context 'Owned broker cleanup'
        foreach ($path in @($requestPath, $responsePath)) {
            Test-ConfigPathLink -Path $path -Context 'Owned broker file'
            if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) }
        }
        [IO.Directory]::Delete($directory, $false)
    }
}

function Assert-ApimBrokerResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Result,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Context,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Arguments
    )
    $run = @{ type = 'string'; pattern = '^run-[a-f0-9]{32}$' }
    $digest = @{ type = 'string'; pattern = '^[a-f0-9]{64}$' }
    $properties = switch ($Name) {
        run_assessment { @{ runId = $run; status = @{ enum = @('Completed', 'Partial', 'Failed') } } }
        get_assessment_status {
            $stageProperties = @{}
            foreach ($key in @('collect', 'analyze', 'modelSafe', 'report')) {
                $stageProperties[$key] = @{ enum = @('NotStarted', 'InProgress', 'Completed', 'Partial', 'Failed', 'Skipped') }
            }
            @{ runId = $run; stages = @{ type = 'object'; additionalProperties = $false; required = @($stageProperties.Keys); properties = $stageProperties } }
        }
        promote_analysis_package { @{ status = @{ const = 'Promoted' }; version = @{ type = 'string'; pattern = '^version-[0-9]{6}$' }; packageSha256 = $digest } }
        read_validated_analysis_package { @{ packageSha256 = $digest; package = @{ type = 'object' } } }
        read_validated_agent_outputs { @{ packageSha256 = $digest; observations = @{ type = 'array'; maxItems = 2 }; executive = @{ type = 'array'; maxItems = 1 } } }
        validate_agent_output { @{ status = @{ const = 'Validated' }; packageSha256 = $digest; outputId = @{ type = 'string'; pattern = '^output-[a-f0-9]{32}$' } } }
        render_reports { @{ status = @{ const = 'Completed' }; artifacts = @{ type = 'array'; minItems = 2; maxItems = 2; items = @{ type = 'string'; pattern = '^artifact-[a-f0-9]{32}$' } } } }
        default { throw 'BROKER_RESULT_REJECTED' }
    }
    $schema = ConvertTo-Json -Depth 16 -Compress -InputObject @{
        type = 'object'; additionalProperties = $false; required = @($properties.Keys); properties = $properties
    }
    if (-not (Test-Json -Json (ConvertTo-Json -InputObject $Result -Depth 32 -Compress) -Schema $schema -ErrorAction Stop)) {
        throw 'BROKER_RESULT_REJECTED'
    }
    if ($Name -cin @('read_validated_analysis_package', 'read_validated_agent_outputs')) {
        $packageJson = Get-ApimBrokerPublication -Context $Context -Run $Context.runs[$Arguments.runId]
        if ($Result.packageSha256 -cne $Context.runs[$Arguments.runId].publication.packageSha256) {
            throw 'BROKER_RESULT_REJECTED'
        }
        if ($Name -ceq 'read_validated_analysis_package') {
            $json = ConvertTo-ApimAnalysisJson -Value $Result.package
            $null = Test-ApimAnalysisContract -Kind AnalysisPackage -Json $json
            Assert-ApimAnalysisScan -Package $Result.package
            if ($json -cne (ConvertTo-ApimAnalysisJson -Value (
                        ConvertFrom-ApimAnalysisContractJson -Kind AnalysisPackage -Json $packageJson
                    ))) { throw 'BROKER_RESULT_REJECTED' }
        }
        else {
            $texts = @($Result.observations | ForEach-Object { ConvertTo-ApimAnalysisJson -Value $_ })
            foreach ($text in $texts) {
                $null = Test-ApimAgentClaim -Kind ExpertObservations -Json $text -PackageJson $packageJson
            }
            foreach ($summary in $Result.executive) {
                $null = Test-ApimAgentClaim -Kind ExecutiveSummary -Json (
                    ConvertTo-ApimAnalysisJson -Value $summary
                ) -PackageJson $packageJson -ObservationJson $texts
            }
        }
    }
}
