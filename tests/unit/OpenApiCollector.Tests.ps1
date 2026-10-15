$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Restricted OpenAPI collection' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)
        $script:openApiRoot = $RepoRoot
        BeforeEach {
            $config = Import-PowerShellDataFile (Join-Path $script:openApiRoot 'config/sample.psd1')
            $config.Output.Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $script:oaEnvironment = $config.Environments[0]
            $script:oaRun = New-ApimRun -Config $config -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000010' -Operator Synthetic -RunId synthetic-openapi
            $script:oaJson = '{"openapi":"3.0.3","info":{"title":"Synthetic API","version":"1.0"},"paths":{}}'
            $script:oaApi = [pscustomobject]@{ name = 'synthetic-api'
                properties = [pscustomobject]@{ type = 'http'; isCurrent = $true } }
            $null = Write-RunFile -RunPath $script:oaRun.Path -RelativePath raw/apis.json `
                -InputObject ([pscustomobject]@{ value = @($script:oaApi) })
            Mock Invoke-ApimArm {
                [pscustomobject]@{
                    id = "$(Get-ApimServiceResourcePath -Environment $script:oaEnvironment)/apis/synthetic-api"
                    properties = [pscustomobject]@{ format = 'openapi+json'; value = $script:oaJson }
                }
            }
            Mock Invoke-ApimOpenApiDownload { throw 'Unexpected network.' }
        }

        It 'exports validated inline bytes and binds the exact closed index and manifest' {
            Invoke-ApimOpenApiCollector -RunPath $script:oaRun.Path -Environment $script:oaEnvironment
            $record = (Get-RunManifest -RunPath $script:oaRun.Path).collectors | Where-Object name -CEQ OpenApi
            Test-ApimCollectorOutput -RunPath $script:oaRun.Path -Environment $script:oaEnvironment -Collector $record
            $index = Read-ApimSmokeOutputJson -RunPath $script:oaRun.Path -RelativePath raw/openapi/index.json
            @($index.PSObject.Properties.Name) | Should -Be @('schemaVersion', 'entries')
            @($index.entries[0].PSObject.Properties.Name) |
                Should -Be @('apiId', 'apiType', 'status', 'reasonCode', 'file', 'sha256')
            $index.entries[0].status | Should -Be Exported
            $record.items | Should -Be 1
            $record.files.Count | Should -Be 2
            Should -Invoke Invoke-ApimArm -Exactly -Times 1 -ParameterFilter {
                $Uri -clike '*format=openapi%2Bjson'
            }
            Should -Invoke Invoke-ApimOpenApiDownload -Exactly -Times 0
        }

        It 'supports OAS 2.0 and 3.1 without requiring operations' -TestCases @(
            @{ VersionField = '"swagger":"2.0"' }, @{ VersionField = '"openapi":"3.1.1"' }
        ) {
            param($VersionField)
            $json = '{' + $VersionField + ',"info":{"title":"Synthetic","version":"1"},"paths":{}}'
            { ConvertFrom-ApimOpenApiDocument -Json $json } | Should -Not -Throw
        }

        It 'rejects malformed, duplicate, unsupported, deep, oversized and secret-bearing documents safely' -TestCases @(
            @{ Kind = 'malformed' }, @{ Kind = 'duplicate' }, @{ Kind = 'nestedDuplicate' },
            @{ Kind = 'caseDuplicate' }, @{ Kind = 'unsupported' }, @{ Kind = 'shape' },
            @{ Kind = 'depth' }, @{ Kind = 'size' }, @{ Kind = 'secret' },
            @{ Kind = 'querySecret' }, @{ Kind = 'headerSecret' }, @{ Kind = 'privateKey' }
        ) {
            param($Kind)
            $json = switch ($Kind) {
                malformed { '{synthetic-private' }
                duplicate { $script:oaJson.Replace('"paths":{}', '"paths":{},"paths":{}') }
                nestedDuplicate { $script:oaJson.Replace('"paths":{}', '"paths":{"/x":{"get":{},"get":{}}}') }
                caseDuplicate { $script:oaJson.Replace('"paths":{}', '"paths":{},"Paths":{}') }
                unsupported { $script:oaJson.Replace('3.0.3', '4.0.0') }
                shape { '{"openapi":"3.0.3","info":{},"paths":[]}' }
                depth { $script:oaJson.Replace('"paths":{}', ('"paths":' + ('{"x":' * 66) + '{}' + ('}' * 66))) }
                size { $script:oaJson.Replace('Synthetic API', ('x' * 5MB)) }
                secret { $script:oaJson.Replace('"paths":{}', '"paths":{},"password":"synthetic-private"') }
                querySecret { $script:oaJson.Replace('Synthetic API', 'https://example.invalid/?sig=synthetic-private') }
                headerSecret { $script:oaJson.Replace('"paths":{}', '"paths":{},"example":{"name":"Authorization","value":"Bearer synthetic-private"}') }
                privateKey { $script:oaJson.Replace('Synthetic API', '-----BEGIN PRIVATE KEY-----') }
            }
            { ConvertFrom-ApimOpenApiDocument -Json $json } | Should -Throw 'OpenAPI document rejected.'
            $script:oaJson = $json
            { Invoke-ApimOpenApiCollector -RunPath $script:oaRun.Path -Environment $script:oaEnvironment } |
                Should -Throw 'OpenAPI collection incomplete.'
            $index = Read-ApimSmokeOutputJson -RunPath $script:oaRun.Path -RelativePath raw/openapi/index.json
            $index.entries[0].reasonCode | Should -Be DocumentRejected
            @(Get-ChildItem (Join-Path $script:oaRun.Path raw/openapi) -File).Name | Should -Be @('index.json')
            Get-Content (Join-Path $script:oaRun.Path raw/openapi/index.json) -Raw |
                Should -Not -Match 'synthetic-private|BEGIN PRIVATE KEY'
            $record = (Get-RunManifest -RunPath $script:oaRun.Path).collectors | Where-Object name -CEQ OpenApi
            Test-ApimOpenApiSavedOutput -RunPath $script:oaRun.Path -Collector $record | Should -Be 0
        }

        It 'uses one documented link fallback only after guarded 400 or 406' -TestCases @(
            @{ StatusCode = 400 }, @{ StatusCode = 406 }
        ) {
            param($StatusCode)
            $script:oaStatus = $StatusCode
            Mock Invoke-ApimArm {
                if ($Uri -clike '*format=openapi%2Bjson') {
                    throw (Get-ApimArmFailure -StatusCode $script:oaStatus -Attempts 1)
                }
                [pscustomobject]@{
                    id = "$(Get-ApimServiceResourcePath -Environment $script:oaEnvironment)/apis/synthetic-api"
                    properties = [pscustomobject]@{ format = 'openapi+json-link'
                        value = [pscustomobject]@{ link = 'https://syntheticstore.blob.core.windows.net/api-export/synthetic.json?sig=synthetic-private' } }
                }
            }
            Mock Invoke-ApimOpenApiDownload { $script:oaJson }
            Invoke-ApimOpenApiCollector -RunPath $script:oaRun.Path -Environment $script:oaEnvironment
            Should -Invoke Invoke-ApimArm -Exactly -Times 2
            Should -Invoke Invoke-ApimOpenApiDownload -Exactly -Times 1
            foreach ($file in Get-ChildItem $script:oaRun.Path -Recurse -File) {
                Get-Content $file.FullName -Raw | Should -Not -Match 'synthetic-private|sig='
            }
        }

        It 'does not fallback after authorization, server, unmarked or transport errors' -TestCases @(
            @{ StatusCode = 401 }, @{ StatusCode = 403 }, @{ StatusCode = 404 },
            @{ StatusCode = 500 }, @{ StatusCode = 0 }, @{ StatusCode = -1 }
        ) {
            param($StatusCode)
            $script:oaStatus = $StatusCode
            Mock Invoke-ApimArm {
                if ($script:oaStatus -eq -1) {
                    $errorValue = [InvalidOperationException]::new('synthetic-private')
                    $errorValue.Data['StatusCode'] = 400
                    throw $errorValue
                }
                throw (Get-ApimArmFailure -StatusCode $script:oaStatus -Attempts 1)
            }
            { Invoke-ApimOpenApiCollector -RunPath $script:oaRun.Path -Environment $script:oaEnvironment } |
                Should -Throw 'OpenAPI collection incomplete.'
            Should -Invoke Invoke-ApimArm -Exactly -Times 1
            Should -Invoke Invoke-ApimOpenApiDownload -Exactly -Times 0
        }

        It 'refuses untrusted, ambiguous or encoded download targets before transport' -TestCases @(
            @{ Uri = 'http://syntheticstore.blob.core.windows.net/api-export/a.json' },
            @{ Uri = 'https://user:pass@syntheticstore.blob.core.windows.net/api-export/a.json' },
            @{ Uri = 'https://syntheticstore.blob.core.windows.net:443/api-export/a.json' },
            @{ Uri = 'https://syntheticstore.blob.core.windows.net:444/api-export/a.json' },
            @{ Uri = 'https://syntheticstore.blob.core.windows.net.evil.invalid/api-export/a.json' },
            @{ Uri = 'https://127.0.0.1/api-export/a.json' },
            @{ Uri = 'https://localhost/api-export/a.json' },
            @{ Uri = 'https://syntheticstore.privatelink.blob.core.windows.net/api-export/a.json' },
            @{ Uri = 'https://syntheticstore.blob.core.windows.net/other/a.json' },
            @{ Uri = 'https://syntheticstore.blob.core.windows.net/api-export/../a.json' },
            @{ Uri = 'https://syntheticstore.blob.core.windows.net/api-export/a/../b.json' },
            @{ Uri = 'https://syntheticstore.blob.core.windows.net/api-export/a/./b.json' },
            @{ Uri = 'https://syntheticstore.blob.core.windows.net/api-export/%2e%2e/a.json' },
            @{ Uri = 'https://syntheticstore.blob.core.windows.net/api-export/a%2fb.json' },
            @{ Uri = 'https://syntheticstore.blob.core.windows.net/api-export//a.json' },
            @{ Uri = 'https://syntheticstore.blob.core.windows.net/api-export/a.json#fragment' }
        ) {
            param($Uri)
            $script:oaTarget = $Uri
            { Test-ApimOpenApiExportUri -Uri $script:oaTarget } | Should -Throw 'OpenAPI download rejected.'
        }

        It 'accepts only approved cloud Blob export suffixes' -TestCases @(
            @{ Suffix = 'core.windows.net' }, @{ Suffix = 'core.usgovcloudapi.net' },
            @{ Suffix = 'core.chinacloudapi.cn' }, @{ Suffix = 'core.cloudapi.de' }
        ) {
            param($Suffix)
            $script:oaTarget = "https://syntheticstore.blob.$Suffix/api-export/a.json?sig=synthetic"
            { Test-ApimOpenApiExportUri -Uri $script:oaTarget } |
                Should -Not -Throw
        }

        It 'retains valid Partial files, skips nonHTTP and exports only current revision with safe filenames' {
            $apis = @(
                [pscustomobject]@{ name = '../CON'; properties = [pscustomobject]@{ type = 'http'; isCurrent = $true } },
                [pscustomobject]@{ name = 'failed'; properties = [pscustomobject]@{ type = 'http' } },
                [pscustomobject]@{ name = 'socket'; properties = [pscustomobject]@{ type = 'websocket' } },
                [pscustomobject]@{ name = 'unknown'; properties = [pscustomobject]@{} },
                [pscustomobject]@{ name = 'old;rev=1'; properties = [pscustomobject]@{ type = 'http'; isCurrent = $false } }
            )
            $null = Write-RunFile -RunPath $script:oaRun.Path -RelativePath raw/apis.json `
                -InputObject ([pscustomobject]@{ value = $apis })
            Mock Get-ApimOpenApiExportJson {
                if ($ResourcePath -clike '*/failed') { throw 'synthetic-private' }
                $script:oaJson
            }
            { Invoke-ApimOpenApiCollector -RunPath $script:oaRun.Path -Environment $script:oaEnvironment -ThrottleLimit 1 } |
                Should -Throw 'OpenAPI collection incomplete.'
            $index = Read-ApimSmokeOutputJson -RunPath $script:oaRun.Path -RelativePath raw/openapi/index.json
            $index.entries.apiId | Should -Be @('../CON', 'failed', 'socket', 'unknown')
            $index.entries.status | Should -Be @('Exported', 'Failed', 'Skipped', 'Skipped')
            $index.entries[0].file | Should -Match '^raw/openapi/api-[a-f0-9]{64}\.json$'
            $record = (Get-RunManifest -RunPath $script:oaRun.Path).collectors | Where-Object name -CEQ OpenApi
            $record.status | Should -Be Partial
            $record.files.Count | Should -Be 2
            Test-ApimCollectorOutput -RunPath $script:oaRun.Path -Environment $script:oaEnvironment -Collector $record
            Should -Invoke Get-ApimOpenApiExportJson -Exactly -Times 2
        }

        It 'accepts a matching documented link envelope on the initial export attempt' {
            Mock Invoke-ApimArm {
                [pscustomobject]@{
                    id = "$(Get-ApimServiceResourcePath -Environment $script:oaEnvironment)/apis/synthetic-api"
                    properties = [pscustomobject]@{ format = 'openapi+json-link'
                        value = [pscustomobject]@{ link = 'https://syntheticstore.blob.core.windows.net/api-export/a.json?sig=synthetic-private' } }
                }
            }
            Mock Invoke-ApimOpenApiDownload { $script:oaJson }
            Invoke-ApimOpenApiCollector -RunPath $script:oaRun.Path -Environment $script:oaEnvironment
            Should -Invoke Invoke-ApimArm -Exactly -Times 1
            Should -Invoke Invoke-ApimOpenApiDownload -Exactly -Times 1
        }

        It 'rejects mismatching export envelope targets and formats without downloads' -TestCases @(
            @{ Kind = 'id' }, @{ Kind = 'format' }, @{ Kind = 'object' }, @{ Kind = 'url' }
        ) {
            param($Kind)
            $script:oaKind = $Kind
            Mock Invoke-ApimArm {
                $id = "$(Get-ApimServiceResourcePath -Environment $script:oaEnvironment)/apis/synthetic-api"
                $format = 'openapi+json'
                $value = $script:oaJson
                switch ($script:oaKind) {
                    id { $id += '-wrong' }
                    format { $format = 'swagger-link' }
                    object { $value = ConvertFrom-Json $value }
                    url { $format = 'openapi+json-link'; $value = [pscustomobject]@{ link = 'https://example.invalid/private' } }
                }
                [pscustomobject]@{ id = $id; properties = [pscustomobject]@{ format = $format; value = $value } }
            }
            { Invoke-ApimOpenApiCollector -RunPath $script:oaRun.Path -Environment $script:oaEnvironment } |
                Should -Throw 'OpenAPI collection incomplete.'
            Should -Invoke Invoke-ApimOpenApiDownload -Exactly -Times 0
        }

        It 'rejects tampered, unknown or unlisted saved output' -TestCases @(
            @{ Kind = 'bytes' }, @{ Kind = 'field' }, @{ Kind = 'reason' },
            @{ Kind = 'missingApi' }, @{ Kind = 'file' }, @{ Kind = 'inventory' },
            @{ Kind = 'duplicate' }, @{ Kind = 'entryDuplicate' }, @{ Kind = 'caseDuplicate' },
            @{ Kind = 'versionType' }
        ) {
            param($Kind)
            Invoke-ApimOpenApiCollector -RunPath $script:oaRun.Path -Environment $script:oaEnvironment
            $record = (Get-RunManifest -RunPath $script:oaRun.Path).collectors | Where-Object name -CEQ OpenApi
            $index = Read-ApimSmokeOutputJson -RunPath $script:oaRun.Path -RelativePath raw/openapi/index.json
            switch ($Kind) {
                bytes { Add-Content (Join-Path $script:oaRun.Path $index.entries[0].file) ' ' }
                field { $index.entries[0] | Add-Member extra synthetic }
                reason { $index.entries[0].reasonCode = 'Other' }
                missingApi { $index.entries = @() }
                file { $index.entries[0].file = 'raw/openapi/other.json' }
                inventory { $record.files = @('raw/openapi/index.json') }
                versionType { $index.schemaVersion = 1.0 }
            }
            $null = Write-RunFile -RunPath $script:oaRun.Path -RelativePath raw/openapi/index.json -InputObject $index
            if ($Kind -cin @('duplicate', 'entryDuplicate', 'caseDuplicate')) {
                $json = ConvertTo-Json -InputObject $index -Depth 20
                $json = switch ($Kind) {
                    duplicate { $json -replace '"schemaVersion"\s*:', '"schemaVersion":"1.0","schemaVersion":' }
                    entryDuplicate { $json -replace '"status"\s*:', '"status":"Exported","status":' }
                    caseDuplicate { $json -replace '"status"\s*:', '"Status":"Exported","status":' }
                }
                $null = Write-RunFile -RunPath $script:oaRun.Path -RelativePath raw/openapi/index.json -Format Text `
                    -InputObject $json
            }
            { Test-ApimCollectorOutput -RunPath $script:oaRun.Path -Environment $script:oaEnvironment -Collector $record } |
                Should -Throw 'OpenAPI saved output rejected.'
        }
        It 'fails closed when in-memory scanning is incomplete without persisting document content' {
            Mock Test-ApimOpenApiSecret { throw 'synthetic-private' }
            { Invoke-ApimOpenApiCollector -RunPath $script:oaRun.Path -Environment $script:oaEnvironment } |
                Should -Throw 'OpenAPI collection incomplete.'
            $index = Read-ApimSmokeOutputJson -RunPath $script:oaRun.Path -RelativePath raw/openapi/index.json
            $index.entries[0].reasonCode | Should -Be DocumentRejected
            @(Get-ChildItem (Join-Path $script:oaRun.Path raw/openapi) -File).Name | Should -Be @('index.json')
        }

        It 'records safe persistence failures without losing the per-API index' {
            Mock Write-RunFile { throw 'synthetic-private' } -ParameterFilter {
                $RelativePath -clike 'raw/openapi/api-*.json'
            }
            { Invoke-ApimOpenApiCollector -RunPath $script:oaRun.Path -Environment $script:oaEnvironment } |
                Should -Throw 'OpenAPI collection incomplete.'
            $index = Read-ApimSmokeOutputJson -RunPath $script:oaRun.Path -RelativePath raw/openapi/index.json
            $index.entries[0].reasonCode | Should -Be PersistenceFailed
            $index.entries[0].file | Should -BeNullOrEmpty
            $index.entries[0].sha256 | Should -BeNullOrEmpty
        }
    }
}

Describe 'Credential-free bounded OpenAPI downloader' {
        InModuleScope ApimAssessment {
            BeforeAll {
                $script:oaProductionHandler = ${function:Get-ApimOpenApiDownloadHandler}
                if ($null -eq ('SyntheticOpenApiHandler' -as [type])) {
                    Add-Type -TypeDefinition @'
    using System;
    using System.IO;
    using System.Net;
    using System.Net.Http;
    using System.Threading;
    using System.Threading.Tasks;
    public sealed class SyntheticOpenApiContent : HttpContent {
        private readonly byte[] bytes;
        public SyntheticOpenApiContent(byte[] data) { bytes = data; }
        protected override bool TryComputeLength(out long length) { length = 0; return false; }
        protected override Task SerializeToStreamAsync(Stream stream, TransportContext context) {
            return stream.WriteAsync(bytes, 0, bytes.Length);
        }
        protected override Task<Stream> CreateContentReadStreamAsync() {
            return Task.FromResult<Stream>(new MemoryStream(bytes));
        }
    }
    public sealed class SyntheticOpenApiHandler : HttpMessageHandler {
        public static int Status;
        public static byte[] Bytes;
        public static bool UnknownLength;
        public static bool Timeout;
        public static int Calls;
        public static string Method;
        public static bool HasCredentials;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellation) {
            Calls++;
            Method = request.Method.Method;
            HasCredentials = request.Headers.Authorization != null || request.Headers.Contains("Cookie");
            if (Timeout) return Task.FromException<HttpResponseMessage>(new TaskCanceledException("synthetic-private"));
            var response = new HttpResponseMessage((HttpStatusCode)Status);
            response.Content = UnknownLength ? new SyntheticOpenApiContent(Bytes) : new ByteArrayContent(Bytes);
            if (Status >= 300 && Status < 400)
                response.Headers.Location = new Uri("http://127.0.0.1/synthetic-private");
            return Task.FromResult(response);
        }
    }
'@
                }
            }
            BeforeEach {
                [SyntheticOpenApiHandler]::Status = 200
                [SyntheticOpenApiHandler]::Bytes = [Text.Encoding]::UTF8.GetBytes('{"synthetic":true}')
                [SyntheticOpenApiHandler]::UnknownLength = $false
                [SyntheticOpenApiHandler]::Timeout = $false
                [SyntheticOpenApiHandler]::Calls = 0
                Mock Get-ApimOpenApiDownloadHandler { [SyntheticOpenApiHandler]::new() }
            }

            It 'issues one credential-free GET without ARM authorization' {
                Invoke-ApimOpenApiDownload -Uri 'https://syntheticstore.blob.core.windows.net/api-export/a.json?sig=synthetic-private' |
                    Should -Be '{"synthetic":true}'
                [SyntheticOpenApiHandler]::Calls | Should -Be 1
                [SyntheticOpenApiHandler]::Method | Should -Be GET
                [SyntheticOpenApiHandler]::HasCredentials | Should -BeFalse
            }

            It 'fails safely on redirects, errors, oversize streams, timeout and invalid UTF8' -TestCases @(
                @{ Kind = 'redirect301' }, @{ Kind = 'redirect302' }, @{ Kind = 'redirect307' },
                @{ Kind = 'redirect308' }, @{ Kind = 'authorization' }, @{ Kind = 'sizeHeader' },
                @{ Kind = 'sizeStream' }, @{ Kind = 'timeout' }, @{ Kind = 'utf8' }
            ) {
                param($Kind)
                switch ($Kind) {
                    redirect301 { [SyntheticOpenApiHandler]::Status = 301 }
                    redirect302 { [SyntheticOpenApiHandler]::Status = 302 }
                    redirect307 { [SyntheticOpenApiHandler]::Status = 307 }
                    redirect308 { [SyntheticOpenApiHandler]::Status = 308 }
                    authorization { [SyntheticOpenApiHandler]::Status = 403 }
                    sizeHeader { [SyntheticOpenApiHandler]::Bytes = [byte[]]::new(5MB + 1) }
                    sizeStream {
                        [SyntheticOpenApiHandler]::Bytes = [byte[]]::new(5MB + 1)
                        [SyntheticOpenApiHandler]::UnknownLength = $true
                    }
                    timeout { [SyntheticOpenApiHandler]::Timeout = $true }
                    utf8 { [SyntheticOpenApiHandler]::Bytes = [byte[]]@(255, 255) }
                }
                {
                    Invoke-ApimOpenApiDownload -Uri 'https://syntheticstore.blob.core.windows.net/api-export/a.json?sig=synthetic-private'
                } | Should -Throw 'OpenAPI download rejected.'
                [SyntheticOpenApiHandler]::Calls | Should -Be 1
                [SyntheticOpenApiHandler]::HasCredentials | Should -BeFalse
            }

            It 'configures the production transport to refuse redirects, credentials, cookies and proxies' {
                # Call the original helper despite the per-test mock. No request is sent.
                $handler = & $script:oaProductionHandler
                try {
                    $handler.AllowAutoRedirect | Should -BeFalse
                    $handler.UseCookies | Should -BeFalse
                    $handler.UseProxy | Should -BeFalse
                    $handler.Credentials | Should -BeNullOrEmpty
                    $handler.ConnectCallback | Should -Not -BeNullOrEmpty
                }
                finally { $handler.Dispose() }
            }

            It 'rejects private, loopback, linklocal, mapped, IPv6 and reserved IPs offline' -TestCases @(
                @{ Address = '127.0.0.1' }, @{ Address = '10.1.2.3' }, @{ Address = '172.16.1.2' },
                @{ Address = '192.168.1.2' }, @{ Address = '169.254.169.254' }, @{ Address = '100.64.0.1' },
                @{ Address = '0.0.0.0' }, @{ Address = '224.0.0.1' }, @{ Address = '198.18.0.1' },
                @{ Address = '192.0.2.1' }, @{ Address = '::1' }, @{ Address = '::ffff:127.0.0.1' }
            ) {
                param($Address)
                # Compile/configure only; never resolve a hostname or open a socket.
                $handler = & $script:oaProductionHandler
                $handler.Dispose()
                [ApimOpenApiTransport]::IsPublic([Net.IPAddress]::Parse($Address)) | Should -BeFalse
            }
        }
}
