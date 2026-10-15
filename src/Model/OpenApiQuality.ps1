#Requires -Version 7.4
Set-StrictMode -Version Latest

function Get-ApimOpenApiRulesetHash {
    [CmdletBinding()]
    param()
    $path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'rulesets/apim-style.yaml'
    try {
        if (((Get-Item -LiteralPath $path -ErrorAction Stop).Attributes -band
                [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'LinkedRuleset' }
        return (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    }
    catch { throw 'Trusted OpenAPI ruleset is unavailable.' }
}

function Invoke-ApimQualityProcess {
    <#
    .SYNOPSIS
    Private bounded process transport. No output or exception text escapes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Executable,
        [Parameter(Mandatory)][string[]] $Arguments,
        [AllowNull()][string] $InputText,
        [ValidateRange(1, 120)][int] $TimeoutSeconds = 30,
        [ValidateRange(128, 4194304)][int] $MaxOutputBytes = 2097152
    )
    $process = [System.Diagnostics.Process]::new()
    $output = [System.IO.MemoryStream]::new()
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $started = $false
    try {
        $start = [System.Diagnostics.ProcessStartInfo]::new($Executable)
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardInput = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        # Do not inherit Node code-injection, debug or extra-CA options.
        $start.Environment.Remove('NODE_OPTIONS') | Out-Null
        $start.Environment.Remove('NODE_PATH') | Out-Null
        $start.Environment.Remove('NODE_EXTRA_CA_CERTS') | Out-Null
        foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
        $process.StartInfo = $start
        if (-not $process.Start()) { throw 'ProcessUnavailable' }
        $started = $true
        $buffers = @([byte[]]::new(4096), [byte[]]::new(4096))
        $streams = @($process.StandardOutput.BaseStream, $process.StandardError.BaseStream)
        $tasks = @($streams[0].ReadAsync($buffers[0], 0, 4096),
            $streams[1].ReadAsync($buffers[1], 0, 4096))
        $done = @($false, $false)
        $bytes = [System.Text.UTF8Encoding]::new($false, $true).GetBytes([string]$InputText)
        $write = $process.StandardInput.BaseStream.WriteAsync($bytes, 0, $bytes.Length)
        $inputClosed = $false
        $total = 0
        $stderrBytes = 0
        while (-not ($done[0] -and $done[1] -and $process.HasExited)) {
            if ($clock.Elapsed.TotalSeconds -gt $TimeoutSeconds) { throw 'ProcessTimeout' }
            if (-not $inputClosed -and $write.IsCompleted) {
                $null = $write.GetAwaiter().GetResult()
                $process.StandardInput.Close()
                $inputClosed = $true
            }
            for ($i = 0; $i -lt 2; $i++) {
                if ($done[$i] -or -not $tasks[$i].IsCompleted) { continue }
                $count = $tasks[$i].GetAwaiter().GetResult()
                if ($count -eq 0) { $done[$i] = $true; continue }
                $total += $count
                if ($total -gt $MaxOutputBytes) { throw 'ProcessOutputLimit' }
                if ($i -eq 0) { $output.Write($buffers[$i], 0, $count) }
                else { $stderrBytes += $count }
                $tasks[$i] = $streams[$i].ReadAsync($buffers[$i], 0, 4096)
            }
            Start-Sleep -Milliseconds 5
        }
        if (-not $inputClosed) { $null = $write.GetAwaiter().GetResult() }
        return @{
            succeeded = $true; exitCode = $process.ExitCode
            stdout = [System.Text.UTF8Encoding]::new($false, $true).GetString($output.ToArray())
            hasStderr = ($stderrBytes -gt 0)
        }
    }
    catch { return @{ succeeded = $false; exitCode = $null; stdout = $null; hasStderr = $false } }
    finally {
        if ($started -and -not $process.HasExited) {
            try { $process.Kill($true); $null = $process.WaitForExit(2000) }
            catch { Write-Verbose 'Bounded process cleanup did not complete.' }
        }
        $process.Dispose()
        $output.Dispose()
    }
}

function Get-ApimSpectralTool {
    [CmdletBinding()]
    param()
    $root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $package = Join-Path $root '.tools/spectral/node_modules/@stoplight/spectral-cli'
    $metadata = Join-Path $package 'package.json'
    $entry = Join-Path $package 'dist/index.js'
    $node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $node -or -not (Test-Path -LiteralPath $metadata -PathType Leaf) -or
        -not (Test-Path -LiteralPath $entry -PathType Leaf)) { return $null }
    try {
        $data = [System.IO.File]::ReadAllText($metadata) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if ($data.name -cne '@stoplight/spectral-cli' -or $data.version -cne '6.17.0') { return $null }
        $version = Invoke-ApimQualityProcess -Executable $node.Source -Arguments @('--version') -TimeoutSeconds 30
        if (-not $version.succeeded -or $version.exitCode -ne 0 -or $version.hasStderr -or
            $version.stdout.Trim() -notmatch '^v(\d+)\.\d+\.\d+$') { return $null }
        $major = [int]$Matches[1]
        if ($major -ne 22 -and $major -lt 24) { return $null }
        return @{ executable = $node.Source; entryPoint = $entry; version = '6.17.0' }
    }
    catch { return $null }
}

function Test-ApimOpenApiDocument {
    <#
    .SYNOPSIS
    Independently checks bounded JSON, duplicate members, document shape and resolution inputs.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Json)
    if ([System.Text.Encoding]::UTF8.GetByteCount($Json) -gt 8388608) { return 'ExecutionFailed' }
    $document = $null
    try {
        $options = [System.Text.Json.JsonDocumentOptions]::new()
        $options.MaxDepth = 64
        $document = [System.Text.Json.JsonDocument]::Parse($Json, $options)
        $root = $document.RootElement
        if ($root.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { return 'ExecutionFailed' }
        $stack = [System.Collections.Generic.Stack[System.Text.Json.JsonElement]]::new()
        $stack.Push($root)
        $nodes = 0
        $unsupportedReference = $false
        while ($stack.Count -gt 0) {
            $element = $stack.Pop()
            $nodes++
            if ($nodes -gt 200000) { return 'ExecutionFailed' }
            if ($element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
                $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                foreach ($property in $element.EnumerateObject()) {
                    if (-not $names.Add($property.Name)) { return 'ExecutionFailed' }
                    if ($property.Name -cin @('$id', '$schema', '$recursiveRef', 'jsonSchemaDialect')) {
                        $unsupportedReference = $true
                    }
                    if ($property.Name -cin @('$ref', '$dynamicRef')) {
                        if ($property.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::String -or
                            -not $property.Value.GetString().StartsWith('#', [System.StringComparison]::Ordinal)) {
                            $unsupportedReference = $true
                        }
                    }
                    # Legacy JSON Schema id can change the reference base as well.
                    if ($property.Name -ceq 'id' -and $property.Value.ValueKind -eq
                        [System.Text.Json.JsonValueKind]::String) { $unsupportedReference = $true }
                    $stack.Push($property.Value)
                }
            }
            elseif ($element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
                foreach ($item in $element.EnumerateArray()) { $stack.Push($item) }
            }
        }
        if ($unsupportedReference) { return 'UnsupportedReference' }
        $version = [System.Text.Json.JsonElement]::new()
        $supported = ($root.TryGetProperty('openapi', [ref]$version) -and
            $version.ValueKind -eq [System.Text.Json.JsonValueKind]::String -and
            $version.GetString() -cmatch '^3\.[01]\.\d+$')
        if (-not $supported) {
            $supported = ($root.TryGetProperty('swagger', [ref]$version) -and
                $version.ValueKind -eq [System.Text.Json.JsonValueKind]::String -and $version.GetString() -ceq '2.0')
        }
        $info = [System.Text.Json.JsonElement]::new()
        $paths = [System.Text.Json.JsonElement]::new()
        if (-not $supported -or -not $root.TryGetProperty('info', [ref]$info) -or
            $info.ValueKind -ne [System.Text.Json.JsonValueKind]::Object -or
            -not $root.TryGetProperty('paths', [ref]$paths) -or
            $paths.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { return 'ExecutionFailed' }
        return 'Supported'
    }
    catch { return 'ExecutionFailed' }
    finally { if ($null -ne $document) { $document.Dispose() } }
}

function Invoke-ApimSpectral {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Json,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Tool
    )
    # Defence in depth: direct adapter callers cannot skip reference preflight.
    if ((Test-ApimOpenApiDocument -Json $Json) -cne 'Supported' -or $Tool.version -cne '6.17.0') {
        return @{ succeeded = $false; errorCount = $null; warningCount = $null }
    }
    try {
        $null = Get-ApimOpenApiRulesetHash
        $ruleset = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'rulesets/apim-style.yaml'
        $result = Invoke-ApimQualityProcess -Executable $Tool.executable -InputText $Json -Arguments @(
            '--max-old-space-size=128', $Tool.entryPoint, 'lint', '--ruleset', $ruleset,
            '--format', 'json', '--fail-severity', 'warn', '--quiet'
        )
        if (-not $result.succeeded -or $result.exitCode -notin @(0, 1) -or $result.hasStderr) {
            throw 'LintExecutionFailed'
        }
        $diagnostics = ConvertFrom-Json -InputObject $result.stdout -AsHashtable -NoEnumerate -ErrorAction Stop
        if ($diagnostics -isnot [array]) { throw 'InvalidLintOutput' }
        $errors = 0
        $warnings = 0
        foreach ($diagnostic in $diagnostics) {
            if ($diagnostic -isnot [System.Collections.IDictionary] -or
                $diagnostic.severity -isnot [long] -and $diagnostic.severity -isnot [int] -or
                $diagnostic.severity -notin @(0, 1, 2, 3) -or
                $diagnostic.code -isnot [string] -or
                $diagnostic.code -cin @('invalid-ref', 'parser', 'unrecognized-format')) {
                throw 'InvalidLintOutput'
            }
            if ($diagnostic.severity -eq 0) { $errors++ }
            if ($diagnostic.severity -eq 1) { $warnings++ }
        }
        if (($result.exitCode -eq 1) -ne ($errors + $warnings -gt 0)) { throw 'InvalidLintExit' }
        return @{ succeeded = $true; errorCount = $errors; warningCount = $warnings }
    }
    catch { return @{ succeeded = $false; errorCount = $null; warningCount = $null } }
}

function Get-ApimQualityCoverage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Api,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Operations
    )
    $described = 0
    if ($Api.apiId -isnot [string] -or [string]::IsNullOrEmpty($Api.apiId) -or
        ($Api.operationCount -isnot [int] -and $Api.operationCount -isnot [long]) -or
        $Api.operationCount -lt 0) { throw 'Invalid quality API.' }
    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($operation in $Operations) {
        if ($operation.apiId -cne $Api.apiId -or $operation.hasDescription -isnot [bool] -or
            $operation.operationId -isnot [string] -or [string]::IsNullOrEmpty($operation.operationId) -or
            -not $ids.Add($operation.operationId)) { throw 'Invalid quality operations.' }
        if ($operation.hasDescription) { $described++ }
    }
    if ($Operations.Count -gt $Api.operationCount) { throw 'Invalid quality operation count.' }
    $coverage = $null
    if ($Operations.Count -eq $Api.operationCount -and $Api.operationCount -gt 0) {
        $coverage = 100.0 * $described / $Api.operationCount
    }
    return @{ described = $described; coverage = $coverage }
}

function Get-ApimOpenApiQuality {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Api,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Operations,
        [AllowNull()][AllowEmptyString()][string] $Json,
        [ValidateRange(0, 100)][int] $ErrorPenalty = 10,
        [ValidateRange(0, 100)][int] $WarningPenalty = 2
    )
    $coverage = Get-ApimQualityCoverage -Api $Api -Operations $Operations
    $row = [ordered]@{
        schemaVersion = '1.0'; apiId = $Api.apiId; status = 'ExportUnavailable'
        errorCount = $null; warningCount = $null; score = $null
        operationCount = $Api.operationCount; describedOperationCount = $coverage.described
        descriptionCoverage = $coverage.coverage; sourceSha256 = $null
        rulesetSha256 = Get-ApimOpenApiRulesetHash; toolVersion = $null
        errorPenalty = $ErrorPenalty; warningPenalty = $WarningPenalty
        modelStatus = 'Partial'; missingInputs = @()
    }
    if ($Api.apiType -ine 'http') { $row.status = 'UnsupportedApi' }
    elseif (-not [string]::IsNullOrEmpty($Json)) {
        $row.sourceSha256 = [Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData(
                [System.Text.UTF8Encoding]::new($false, $true).GetBytes($Json))).ToLowerInvariant()
        $preflight = Test-ApimOpenApiDocument -Json $Json
        if ($preflight -cne 'Supported') { $row.status = $preflight }
        else {
            try {
                $tool = Get-ApimSpectralTool
                if ($null -eq $tool) { $row.status = 'ToolUnavailable' }
                else {
                    $row.toolVersion = $tool.version
                    $result = Invoke-ApimSpectral -Json $Json -Tool $tool
                    if (-not $result.succeeded -or $result.errorCount -isnot [int] -or
                        $result.warningCount -isnot [int] -or $result.errorCount -lt 0 -or
                        $result.warningCount -lt 0) { $row.status = 'ExecutionFailed' }
                    else {
                        $row.status = 'Scored'
                        $row.errorCount = $result.errorCount
                        $row.warningCount = $result.warningCount
                        $row.score = [int][Math]::Max(0, 100 - [long]$result.errorCount * $ErrorPenalty -
                            [long]$result.warningCount * $WarningPenalty)
                    }
                }
            }
            catch { $row.status = 'ExecutionFailed' }
        }
    }
    $missing = [System.Collections.Generic.List[string]]::new()
    if ($row.status -cne 'Scored') { $missing.Add($row.status) }
    if ($Operations.Count -ne $Api.operationCount) { $missing.Add('OperationsIncomplete') }
    if ($Api.operationCount -eq 0) { $missing.Add('NoOperations') }
    $row.missingInputs = @($missing | Sort-Object -CaseSensitive)
    if ($missing.Count -eq 0) { $row.modelStatus = 'Complete' }
    return [pscustomobject]$row
}

function Test-ApimOpenApiQualityModel {
    <#
    .SYNOPSIS
    Pure closed-contract and semantic validation. Does not access files or execute tools.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Quality,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Apis,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Operations
    )
    try {
        $apiMap = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        foreach ($api in $Apis) { $apiMap.Add($api.apiId, $api) }
        $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $fields = @('schemaVersion', 'apiId', 'status', 'errorCount', 'warningCount', 'score',
            'operationCount', 'describedOperationCount', 'descriptionCoverage', 'sourceSha256',
            'rulesetSha256', 'toolVersion', 'errorPenalty', 'warningPenalty', 'modelStatus', 'missingInputs')
        foreach ($row in $Quality) {
            $keys = if ($row -is [System.Collections.IDictionary]) { @($row.Keys) } else { @($row.PSObject.Properties.Name) }
            if ($keys.Count -ne $fields.Count -or @($keys | Where-Object { $_ -cnotin $fields }).Count -gt 0) { return $false }
            if ($row.schemaVersion -isnot [string] -or $row.schemaVersion -cne '1.0' -or
                $row.status -isnot [string] -or $row.modelStatus -isnot [string] -or
                $row.apiId -isnot [string] -or [string]::IsNullOrEmpty($row.apiId) -or
                -not $apiMap.ContainsKey($row.apiId) -or -not $ids.Add($row.apiId)) { return $false }
            foreach ($name in @('operationCount', 'describedOperationCount', 'errorPenalty', 'warningPenalty')) {
                if (($row.$name -isnot [int] -and $row.$name -isnot [long]) -or $row.$name -lt 0) { return $false }
            }
            if ($row.errorPenalty -gt 100 -or $row.warningPenalty -gt 100 -or
                $row.rulesetSha256 -isnot [string] -or $row.rulesetSha256 -cnotmatch '^[a-f0-9]{64}$' -or
                ($null -ne $row.sourceSha256 -and ($row.sourceSha256 -isnot [string] -or
                    $row.sourceSha256 -cnotmatch '^[a-f0-9]{64}$')) -or
                ($null -ne $row.toolVersion -and
                    ($row.toolVersion -isnot [string] -or $row.toolVersion -cne '6.17.0'))) { return $false }
            $api = $apiMap[$row.apiId]
            $coverage = Get-ApimQualityCoverage -Api $api -Operations @(
                $Operations | Where-Object apiId -CEQ $api.apiId)
            if ($row.operationCount -ne $api.operationCount -or $row.describedOperationCount -ne $coverage.described -or
                ($null -eq $row.descriptionCoverage) -ne ($null -eq $coverage.coverage)) { return $false }
            if ($null -ne $row.descriptionCoverage -and
                (($row.descriptionCoverage -isnot [double] -and $row.descriptionCoverage -isnot [decimal] -and
                    $row.descriptionCoverage -isnot [int] -and $row.descriptionCoverage -isnot [long]) -or
                    [double]$row.descriptionCoverage -ne $coverage.coverage)) { return $false }
            $reasons = [System.Collections.Generic.List[string]]::new()
            if ($row.status -ceq 'Scored') {
                foreach ($name in @('errorCount', 'warningCount', 'score')) {
                    if (($row.$name -isnot [int] -and $row.$name -isnot [long]) -or $row.$name -lt 0 -or
                        $row.$name -gt [int]::MaxValue) { return $false }
                }
                if ($null -eq $row.sourceSha256 -or $row.toolVersion -cne '6.17.0' -or $api.apiType -ine 'http' -or
                    $row.score -ne [Math]::Max(0, 100 - [long]$row.errorCount * $row.errorPenalty -
                        [long]$row.warningCount * $row.warningPenalty)) { return $false }
            }
            else {
                if ($row.status -cnotin @('ToolUnavailable', 'UnsupportedReference', 'UnsupportedApi',
                        'ExportUnavailable', 'ExecutionFailed') -or $null -ne $row.errorCount -or
                    $null -ne $row.warningCount -or $null -ne $row.score) { return $false }
                if (($row.status -ceq 'UnsupportedApi') -ne ($api.apiType -ine 'http')) { return $false }
                if ($row.status -cin @('ToolUnavailable', 'UnsupportedReference') -and $null -eq $row.sourceSha256) { return $false }
                if ($row.status -cin @('UnsupportedApi', 'ExportUnavailable') -and
                    ($null -ne $row.sourceSha256 -or $null -ne $row.toolVersion)) { return $false }
                if ($row.status -cin @('ToolUnavailable', 'UnsupportedReference') -and $null -ne $row.toolVersion) { return $false }
                $reasons.Add($row.status)
            }
            if ($null -eq $coverage.coverage -and $api.operationCount -gt 0) { $reasons.Add('OperationsIncomplete') }
            if ($api.operationCount -eq 0) { $reasons.Add('NoOperations') }
            $expectedStatus = if ($reasons.Count -eq 0) { 'Complete' } else { 'Partial' }
            if ($row.modelStatus -cne $expectedStatus -or $row.missingInputs -isnot [array] -or
                ($row.missingInputs | ConvertTo-Json -Compress -AsArray) -cne
                    (@($reasons | Sort-Object -CaseSensitive) | ConvertTo-Json -Compress -AsArray) -or
                $api.openApiScore -cne $row.score) { return $false }
        }
        foreach ($operation in $Operations) {
            if (-not $apiMap.ContainsKey($operation.apiId)) { return $false }
        }
        return $true
    }
    catch { return $false }
}
