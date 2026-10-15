#Requires -Version 7.4

Set-StrictMode -Version Latest

function Test-ApimOpenApiSecret {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Text.Json.JsonElement] $Element)

    # Reuse the trusted scanner's exact detector initialization and nested
    # routines, without invoking its filesystem traversal or changing its API.
    # Fail closed if its internal contract changes. No candidate-derived code.
    $scanner = Get-Command Test-ApimRunSecret -CommandType Function
    $ast = $scanner.ScriptBlock.Ast
    if ($ast -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
        $ast = $ast.Body
    }
    $statements = $ast.EndBlock.Statements
    $required = @('credentialName', 'patterns', 'expressions', 'patternKinds')
    $found = 0
    Set-Variable -Name WriteLocationReport -Value $false
    foreach ($statement in $statements) {
        if ($statement -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $statement.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $statement.Left.VariablePath.UserPath -cin $required) {
            . ([scriptblock]::Create($statement.Extent.Text))
            $found++
        }
        elseif ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
            . ([scriptblock]::Create($statement.Extent.Text))
        }
    }
    if ($found -ne $required.Count) { throw 'OpenAPI document rejected.' }
    return Test-SecretJsonElement -Element $Element
}

function Test-ApimOpenApiJsonMember {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Text.Json.JsonElement] $Element)

    $pending = [Collections.Generic.Stack[System.Text.Json.JsonElement]]::new()
    $pending.Push($Element)
    while ($pending.Count) {
        $current = $pending.Pop()
        if ($current.ValueKind -eq 'Object') {
            # Case-insensitive uniqueness also prevents PS member ambiguity.
            $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($property in $current.EnumerateObject()) {
                if (-not $names.Add($property.Name)) { throw 'OpenAPI JSON rejected.' }
                $pending.Push($property.Value)
            }
        }
        elseif ($current.ValueKind -eq 'Array') {
            foreach ($child in $current.EnumerateArray()) { $pending.Push($child) }
        }
    }
}

function ConvertFrom-ApimOpenApiDocument {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Json)

    $document = $null
    try {
        if ([Text.Encoding]::UTF8.GetByteCount($Json) -gt 5MB) {
            throw 'Size'
        }
        $options = [System.Text.Json.JsonDocumentOptions]::new()
        $options.MaxDepth = 64
        $document = [System.Text.Json.JsonDocument]::Parse($Json, $options)
        Test-ApimOpenApiJsonMember -Element $document.RootElement
        $root = $document.RootElement
        if ($root.ValueKind -ne 'Object') { throw 'Shape' }
        $version = [System.Text.Json.JsonElement]::new()
        $supported = ($root.TryGetProperty('openapi', [ref] $version) -and
            $version.ValueKind -eq 'String' -and
            $version.GetString() -cmatch '^3\.(0|1)\.[0-9]+$')
        if (-not $supported) {
            $supported = $root.TryGetProperty('swagger', [ref] $version) -and
                $version.ValueKind -eq 'String' -and $version.GetString() -ceq '2.0'
        }
        $info = [System.Text.Json.JsonElement]::new()
        $paths = [System.Text.Json.JsonElement]::new()
        if (-not $supported -or -not $root.TryGetProperty('info', [ref] $info) -or
            $info.ValueKind -ne 'Object' -or -not $root.TryGetProperty('paths', [ref] $paths) -or
            $paths.ValueKind -ne 'Object') { throw 'Shape' }
        foreach ($field in @('title', 'version')) {
            $value = [System.Text.Json.JsonElement]::new()
            if (-not $info.TryGetProperty($field, [ref] $value) -or
                $value.ValueKind -ne 'String' -or
                [string]::IsNullOrWhiteSpace($value.GetString())) { throw 'Shape' }
        }
        if (Test-ApimOpenApiSecret -Element $root) { throw 'Secret' }
        return ConvertFrom-Json -InputObject $Json -Depth 64 -ErrorAction Stop
    }
    catch { throw 'OpenAPI document rejected.' }
    finally { if ($null -ne $document) { $document.Dispose() } }
}

function Get-ApimOpenApiFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $ApiId)

    # Digest filenames avoid reserved names, escaping aliases and long API IDs.
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
        [Text.Encoding]::UTF8.GetBytes($ApiId))).ToLowerInvariant()
    return "raw/openapi/api-$hash.json"
}

function Get-ApimOpenApiType {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Api)

    $properties = $Api.PSObject.Properties['properties']
    if ($null -eq $properties -or $null -eq $properties.Value) { return 'unknown' }
    foreach ($field in @('apiType', 'type')) {
        $property = $properties.Value.PSObject.Properties[$field]
        if ($null -ne $property -and $property.Value -is [string]) {
            if ($property.Value -cin @('http', 'soap', 'websocket', 'graphql', 'odata', 'grpc')) {
                return $property.Value
            }

            return 'unknown'
        }
    }
    return 'unknown'
}

function Test-ApimOpenApiCurrent {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Api)

    $properties = $Api.PSObject.Properties['properties']
    if ($null -eq $properties -or $null -eq $properties.Value) { return $true }
    $current = $properties.Value.PSObject.Properties['isCurrent']
    if ($null -ne $current -and $current.Value -isnot [bool]) {
        throw 'OpenAPI API metadata rejected.'
    }
    return $null -eq $current -or $current.Value
}

function Test-ApimOpenApiExportUri {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Uri)

    # Check original syntax before System.Uri normalizes dot paths or slashes.
    if ($Uri.Length -gt 8192 -or
        $Uri -cnotmatch '^https://[a-z0-9]{3,24}\.blob\.(?:core\.windows\.net|core\.usgovcloudapi\.net|core\.chinacloudapi\.cn|core\.cloudapi\.de)/api-export/[A-Za-z0-9_-][A-Za-z0-9_./-]*(?:\?[^#\s\\]*)?$' -or
        ($Uri -split '\?', 2)[0] -match '(?:^|/)\.\.?(?:/|$)|(?<!:)//') {
        throw 'OpenAPI download rejected.'
    }
    $target = [uri] $Uri
    if ($target.AbsolutePath -match '//|(?:^|/)\.\.?(?:/|$)' -or
        $target.AbsolutePath -match '(?i)listSecrets|listValue|listKeys|/secrets|regenerate|token' -or
        $target.UserInfo -or $target.Port -ne 443 -or $target.IsLoopback) {
        throw 'OpenAPI download rejected.'
    }
    return $target
}

function Get-ApimOpenApiDownloadHandler {
    [CmdletBinding()]
    param()

    if ($null -eq ('ApimOpenApiTransport' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Threading.Tasks;
public static class ApimOpenApiTransport {
    public static bool IsPublic(IPAddress address) {
        var ip = address.IsIPv4MappedToIPv6 ? address.MapToIPv4() : address;
        var b = ip.GetAddressBytes();
        // Azure public Blob transport is conservatively IPv4-only.
        return !(ip.AddressFamily != AddressFamily.InterNetwork ||
            b[0] == 0 || b[0] == 10 || b[0] == 127 ||
            (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
            (b[0] == 169 && b[1] == 254) ||
            (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
            (b[0] == 192 && (b[1] == 168 || b[1] == 0 || b[1] == 2)) ||
            (b[0] == 198 && (b[1] == 18 || b[1] == 19 || b[1] == 51)) ||
            (b[0] == 203 && b[1] == 0) || b[0] >= 224);
    }
    public static SocketsHttpHandler CreateHandler() {
        var handler = new SocketsHttpHandler();
        handler.AllowAutoRedirect = false;
        handler.UseCookies = false;
        handler.Credentials = null;
        handler.UseProxy = false;
        handler.ConnectCallback = async (context, cancellation) => {
            var addresses = await Dns.GetHostAddressesAsync(context.DnsEndPoint.Host, cancellation);
            if (addresses.Length == 0) throw new Exception("Download rejected.");
            foreach (var address in addresses) {
                if (!IsPublic(address))
                    throw new Exception("Download rejected.");
            }
            // Connect to the checked address, not a second DNS resolution.
            var socket = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
            try {
                await socket.ConnectAsync(new IPEndPoint(addresses[0], 443), cancellation);
                return new NetworkStream(socket, ownsSocket: true);
            } catch { socket.Dispose(); throw; }
        };
        return handler;
    }
}
'@
    }
    return [ApimOpenApiTransport]::CreateHandler()
}

function Invoke-ApimOpenApiDownload {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Uri)

    $handler = $null
    $client = $null
    $response = $null
    $stream = $null
    $buffered = $null
    $cancellation = $null
    try {
        $target = Test-ApimOpenApiExportUri -Uri $Uri
        $handler = Get-ApimOpenApiDownloadHandler
        $client = [Net.Http.HttpClient]::new($handler)
        $client.Timeout = [timespan]::FromSeconds(30)
        $cancellation = [Threading.CancellationTokenSource]::new([timespan]::FromSeconds(30))
        # ResponseHeadersRead bounds memory even when Content-Length is absent.
        $response = $client.GetAsync($target,
            [Net.Http.HttpCompletionOption]::ResponseHeadersRead,
            $cancellation.Token).GetAwaiter().GetResult()
        if ([int] $response.StatusCode -ne 200 -or
            $response.Content.Headers.ContentLength -gt 5MB) { throw 'Response' }
        $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $buffered = [IO.MemoryStream]::new()
        $buffer = [byte[]]::new(8192)
        while ($true) {
            $read = $stream.ReadAsync($buffer, 0, $buffer.Length,
                $cancellation.Token).GetAwaiter().GetResult()
            if ($read -eq 0) { break }
            if ($buffered.Length + $read -gt 5MB) { throw 'Size' }
            $buffered.Write($buffer, 0, $read)
        }
        return [Text.UTF8Encoding]::new($false, $true).GetString($buffered.ToArray())
    }
    catch { throw 'OpenAPI download rejected.' }
    finally {
        foreach ($resource in @($stream, $buffered, $response, $client, $handler, $cancellation)) {
            if ($null -ne $resource) { $resource.Dispose() }
        }
    }
}

function Get-ApimOpenApiExportJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ResourcePath,
        [Parameter(Mandatory)][string] $LogPath
    )

    $base = "${ResourcePath}?api-version=2024-05-01&export=true&format="
    $payload = $null
    try {
        $payload = Invoke-ApimArm -Uri ($base + 'openapi%2Bjson') -LogPath $LogPath
    }
    catch {
        # Deliberately closed compatibility decision: only guarded ARM 400/406.
        if ($_.Exception.Data['ApimArmFailure'] -ne $true -or
            $_.Exception.Data['StatusCode'] -notin @(400, 406)) {
            throw 'OpenAPI export failed.'
        }
        $payload = Invoke-ApimArm -Uri ($base + 'openapi%2Bjson-link') -LogPath $LogPath
    }
    if ($null -eq $payload -or
        $null -eq $payload.PSObject.Properties['id'] -or
        $payload.id -ine $ResourcePath -or
        $null -eq $payload.PSObject.Properties['properties']) {
        throw 'OpenAPI export failed.'
    }
    $properties = $payload.properties
    if ($null -eq $properties -or
        $null -eq $properties.PSObject.Properties['format'] -or
        $null -eq $properties.PSObject.Properties['value'] -or
        $null -eq $properties.value) { throw 'OpenAPI export failed.' }
    switch -CaseSensitive ($properties.format) {
        'openapi+json' {
            if ($properties.value -isnot [string]) { throw 'OpenAPI export failed.' }
            return $properties.value
        }
        'openapi+json-link' {
            # Documented ApiExportResultValue is an object containing link.
            if ($properties.value -isnot [pscustomobject] -or
                @($properties.value.PSObject.Properties).Count -ne 1 -or
                $null -eq $properties.value.PSObject.Properties['link'] -or
                $properties.value.link -isnot [string]) { throw 'OpenAPI export failed.' }
            # Validate before invoking even a mocked downloader.
            $null = Test-ApimOpenApiExportUri -Uri $properties.value.link
            return Invoke-ApimOpenApiDownload -Uri $properties.value.link
        }

        default { throw 'OpenAPI export failed.' }
    }
}

function Test-ApimOpenApiSavedOutput {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)][string] $RunPath,
                [Parameter(Mandatory)][object] $Collector
            )

            try {
                $indexPath = Resolve-RunFilePath -RunPath $RunPath -RelativePath raw/openapi/index.json
                Test-ConfigPathLink -Path $indexPath -Context 'OpenAPI index'
                if ((Get-Item -LiteralPath $indexPath -ErrorAction Stop).Length -gt 5MB) { throw 'Size' }
                $indexJson = [IO.File]::ReadAllText($indexPath)
                $options = [System.Text.Json.JsonDocumentOptions]::new()
                $options.MaxDepth = 20
                $indexDocument = [System.Text.Json.JsonDocument]::Parse($indexJson, $options)
                try { Test-ApimOpenApiJsonMember -Element $indexDocument.RootElement }
                finally { $indexDocument.Dispose() }
                $index = ConvertFrom-Json -InputObject $indexJson -Depth 20 -ErrorAction Stop
                if ($index.schemaVersion -isnot [string] -or
                    $index.schemaVersion -cne '1.0' -or $index.entries -isnot [array] -or
                    @($index.PSObject.Properties).Count -ne 2 -or
                    @($index.PSObject.Properties.Name | Where-Object {
                        $_ -cnotin @('schemaVersion', 'entries')
                    }).Count) { throw 'Index' }
                $apis = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath raw/apis.json -Collection
                $names = @(Get-ApimCollectionResourceName -Payload $apis -CollectionName 'APIM API')
                [array]::Sort($names, [StringComparer]::Ordinal)
                $currentNames = @(
                    foreach ($name in $names) {
                        $api = @($apis.value | Where-Object name -CEQ $name)[0]
                        if (Test-ApimOpenApiCurrent -Api $api) { $name }
                    }
                )
                if ($index.entries.Count -ne $currentNames.Count) { throw 'Inventory' }
                $expectedFiles = [Collections.Generic.List[string]]::new()
                $expectedFiles.Add('raw/openapi/index.json')
                $exported = 0
                $failed = 0
                $position = 0
                foreach ($entry in $index.entries) {
                    $api = @($apis.value | Where-Object name -CEQ $currentNames[$position])[0]
                    $type = Get-ApimOpenApiType -Api $api
                    if ($entry -isnot [pscustomobject] -or
                        @($entry.PSObject.Properties).Count -ne 6 -or
                        @($entry.PSObject.Properties.Name | Where-Object {
                            $_ -cnotin @('apiId', 'apiType', 'status', 'reasonCode', 'file', 'sha256')
                        }).Count -or
                        $entry.apiId -isnot [string] -or $entry.apiType -isnot [string] -or
                        $entry.status -isnot [string] -or $entry.reasonCode -isnot [string] -or
                        $entry.apiId -cne $currentNames[$position] -or
                        $entry.apiType -cne $type) { throw 'Entry' }
                    $position++
                    switch -CaseSensitive ($entry.status) {
                        'Exported' {
                            $expected = Get-ApimOpenApiFile -ApiId $entry.apiId
                            if ($type -cne 'http' -or $entry.reasonCode -cne 'Exported' -or
                                $entry.file -isnot [string] -or $entry.sha256 -isnot [string] -or
                                $entry.file -cne $expected -or $entry.sha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Export' }
                            $path = Resolve-RunFilePath -RunPath $RunPath -RelativePath $expected
                            Test-ConfigPathLink -Path $path -Context 'OpenAPI document'
                            if ((Get-Item -LiteralPath $path -ErrorAction Stop).Length -gt 5MB -or
                                (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $entry.sha256) {
                                throw 'Digest'
                            }
                            $json = [Text.UTF8Encoding]::new($false, $true).GetString([IO.File]::ReadAllBytes($path))
                            $null = ConvertFrom-ApimOpenApiDocument -Json $json
                            $expectedFiles.Add($expected)
                            $exported++
                        }
                        'Skipped' {
                            if ($type -ceq 'http' -or $entry.reasonCode -cne 'UnsupportedApiType' -or
                                $null -ne $entry.file -or $null -ne $entry.sha256) { throw 'Skip' }
                        }
                        'Failed' {
                            if ($type -cne 'http' -or
                                $entry.reasonCode -cnotin @('ExportFailed', 'DocumentRejected', 'PersistenceFailed') -or
                                $null -ne $entry.file -or $null -ne $entry.sha256) { throw 'Failure' }
                            $failed++
                        }
                        default { throw 'Status' }
                    }
                }
                $expectedStatus = if ($failed) { 'Partial' } else { 'Completed' }
                if ($Collector.status -cne $expectedStatus -or
                    $Collector.items -ne $exported -or $Collector.errors -ne $failed -or
                    $Collector.files -isnot [array] -or
                    $Collector.files.Count -ne $expectedFiles.Count -or
                    (Compare-Object -ReferenceObject @($expectedFiles.ToArray()) -DifferenceObject @($Collector.files) -CaseSensitive) -or
                    @($Collector.files | Sort-Object -Unique).Count -ne $Collector.files.Count) { throw 'Manifest' }
                return $exported
            }
            catch { throw 'OpenAPI saved output rejected.' }
        }
