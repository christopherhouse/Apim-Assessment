$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Local saved-run secret scan' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)

        $script:secretScanRepoRoot = $RepoRoot

        BeforeAll {
            function Write-SecretScanWorkbook {
                param([string] $Path, [hashtable] $Parts)

                $archive = [System.IO.Compression.ZipFile]::Open(
                    $Path, [System.IO.Compression.ZipArchiveMode]::Create
                )
                try {
                    foreach ($name in $Parts.Keys) {
                        $entry = $archive.CreateEntry($name)
                        $writer = [System.IO.StreamWriter]::new($entry.Open())
                        try { $writer.Write($Parts[$name]) }
                        finally { $writer.Dispose() }
                    }
                }
                finally { $archive.Dispose() }
            }
        }

        BeforeEach {
            $config = Import-PowerShellDataFile (
                Join-Path $script:secretScanRepoRoot 'config/sample.psd1'
            )
            $config.Output.Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $script:scanRun = New-ApimRun -Config $config -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000002' `
                -Operator Synthetic -RunId synthetic-scan
        }

        It 'accepts all sanitized reference JSON/XML and leaves files unchanged' {
            $fixtureRoot = Join-Path $script:secretScanRepoRoot (
                'tests/fixtures/synthetic-reference'
            )
            foreach ($file in Get-ChildItem -LiteralPath $fixtureRoot -Recurse -File |
                    Where-Object Extension -In @('.json', '.xml')) {
                $relative = [System.IO.Path]::GetRelativePath($fixtureRoot, $file.FullName)
                $target = Join-Path $script:scanRun.Path $relative
                $null = New-Item -ItemType Directory -Path (Split-Path $target) -Force
                Copy-Item -LiteralPath $file.FullName -Destination $target
            }
            $before = @(Get-ChildItem -LiteralPath $script:scanRun.Path -Recurse -File |
                Get-FileHash | Select-Object -ExpandProperty Hash)
            Test-ApimRunSecret -RunFolder $script:scanRun.Path | Should -BeTrue
            $after = @(Get-ChildItem -LiteralPath $script:scanRun.Path -Recurse -File |
                Get-FileHash | Select-Object -ExpandProperty Hash)
            $after | Should -Be $before
        }

        It 'rejects a synthetic <Name> in <Extension>' -ForEach @(
            @{ Name = 'subscription key'; Extension = '.json'; Text = '{"primaryKey":"synthetic-planted-key"}' }
            @{ Name = 'escaped property'; Extension = '.json'; Text = '{"client\u0053ecret":"synthetic-planted-value"}' }
            @{ Name = 'escaped JWT'; Extension = '.json'; Text = '{"message":"\u0065yJsynthetic.synthetic.payload"}' }
            @{ Name = 'nested credential'; Extension = '.json'; Text = '{"credentials":{"header":{"x-api-key":["synthetic"]}}}' }
            @{ Name = 'numeric password'; Extension = '.json'; Text = '{"password":123456}' }
            @{ Name = 'named value'; Extension = '.json'; Text = '{"properties":{"secret":true,"value":"synthetic-planted-value"}}' }
            @{ Name = 'header'; Extension = '.json'; Text = '{"name":"Ocp-Apim-Subscription-Key","value":"synthetic-planted-value"}' }
            @{ Name = 'XML attribute'; Extension = '.xml'; Text = '<policies><authentication-basic password="synthetic-planted-value"/></policies>' }
            @{ Name = 'XML header'; Extension = '.xml'; Text = '<set-header name="x-api-key"><value>synthetic-planted-value</value></set-header>' }
            @{ Name = 'XML entity'; Extension = '.xml'; Text = '<root>Bear&#101;r synthetic-planted-value</root>' }
            @{ Name = 'log connection string'; Extension = '.log'; Text = '{"message":"Server=synthetic;Password=synthetic-planted-value;"}' }
            @{ Name = 'account connection string'; Extension = '.txt'; Text = 'AccountName=synthetic;AccountKey=synthetic-planted-value;' }
            @{ Name = 'SAS connection string'; Extension = '.txt'; Text = 'Endpoint=sb://example.invalid/;SharedAccessKey=synthetic-planted-value' }
            @{ Name = 'SAS URL'; Extension = '.txt'; Text = 'https://example.invalid/?sig=synthetic-planted-value' }
            @{ Name = 'URL password'; Extension = '.txt'; Text = 'https://synthetic:planted@example.invalid/' }
            @{ Name = 'basic authorization'; Extension = '.txt'; Text = 'Basic c3ludGhldGljOnBsYW50ZWQ=' }
            @{ Name = 'JWT'; Extension = '.txt'; Text = 'eyJsynthetic.synthetic.payload' }
            @{ Name = 'private key'; Extension = '.txt'; Text = '-----BEGIN PRIVATE KEY----- synthetic -----END PRIVATE KEY-----' }
            @{ Name = 'HTML entity'; Extension = '.html'; Text = '<p>Bear&#101;r synthetic-planted-value</p>' }
        ) {
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path "planted$Extension") `
                -Value $Text -NoNewline
            Test-ApimRunSecret -RunFolder $script:scanRun.Path | Should -BeFalse
        }

        It 'accepts markers, policy references/expressions, metadata, IDs and hashes' {
            $text = @'
{"password":"***REDACTED***","secret":true,"value":"{{named-value}}","secretIdentifier":"https://example.invalid/secrets/name","authorization":"Bearer ***REDACTED***","primaryKey":null,"apiKey":"","effectiveXml":"<authentication-basic password=\"***REDACTED***\"/>","policy":"<set-header name=\"x-api-key\"><value>@(context.Variables[\"key\"])</value></set-header>","hash":"abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789","id":"00000000-0000-0000-0000-000000000001"}
'@
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'clean.json') -Value $text
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'clean.xml') `
                -Value '<set-header name="x-api-key"><value>{{named-value}}</value></set-header>'
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'clean.txt') `
                -Value 'Bearer ***REDACTED*** Password=***REDACTED*** https://example.invalid/?sig=%2A%2A%2AREDACTED%2A%2A%2A'
            Test-ApimRunSecret -RunFolder $script:scanRun.Path | Should -BeTrue
        }

        It 'decodes UTF-16 text before scanning' {
            [System.IO.File]::WriteAllText(
                (Join-Path $script:scanRun.Path 'utf16.txt'),
                'Password=synthetic-planted-value', [System.Text.Encoding]::Unicode
            )
            Test-ApimRunSecret -RunFolder $script:scanRun.Path | Should -BeFalse
        }

        It 'does not mistake Basic routing or authentication prose for a credential' {
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'description.txt') `
                -Value 'Basic rule forwards every API. Basic authentication requires verification.'
            Test-ApimRunSecret -RunFolder $script:scanRun.Path | Should -BeTrue
        }

        It 'accepts JWT selectors and descriptive authentication metadata in <Extension>' -ForEach @(
            @{ Extension = '.xml' }
            @{ Extension = '.json' }
            @{ Extension = '.log' }
        ) {
            $policy = @'
<policies><inbound><validate-jwt header-name="Authorization" require-scheme="Bearer" failed-validation-error-message="A Bearer token is required."><openid-config url="https://example.invalid/.well-known/openid-configuration"/></validate-jwt><set-header name="Authorization"><value>Bearer</value></set-header><!-- Bearer token validation --></inbound></policies>
'@
            $text = if ($Extension -eq '.xml') { $policy }
            else {
                @{ effectiveXml = $policy; description = 'Inspect the Bearer token.' } |
                    ConvertTo-Json -Compress
            }
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path "metadata$Extension") `
                -Value $text
            Test-ApimRunSecret -RunFolder $script:scanRun.Path -WriteLocationReport |
                Should -BeTrue
            $report = Get-Content -LiteralPath (
                Join-Path $script:scanRun.Path 'secret-scan-locations.json'
            ) -Raw | ConvertFrom-Json
            $report.locations.Count | Should -Be 0
        }

        It 'accepts scheme-only JSON header definitions and descriptive log messages' {
            $text = @'
{"headers":[{"name":"Authorization","value":"Bearer"},{"key":"Proxy-Authorization","value":"Basic"},{"Authorization":"Bearer"}],"message":"Expected a Bearer token.","title":"Bearer JWT verification"}
'@
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'metadata.log') `
                -Value $text
            Test-ApimRunSecret -RunFolder $script:scanRun.Path | Should -BeTrue
        }

        It 'retains actual credential detection for <Name>' -ForEach @(
            @{ Name = 'literal JWT-policy token'; Extension = '.xml'; Text = '<validate-jwt header-name="Authorization" token-value="synthetic-opaque-value"/>' }
            @{ Name = 'literal Entra-policy token'; Extension = '.xml'; Text = '<validate-azure-ad-token header-name="Authorization" token-value="synthetic-opaque-value"/>' }
            @{ Name = 'literal signing key'; Extension = '.xml'; Text = '<validate-jwt header-name="Authorization"><issuer-signing-keys><key>synthetic-opaque-value</key></issuer-signing-keys></validate-jwt>' }
            @{ Name = 'literal decryption key'; Extension = '.xml'; Text = '<validate-jwt><decryption-keys><key>synthetic-opaque-value</key></decryption-keys></validate-jwt>' }
            @{ Name = 'real authorization value'; Extension = '.json'; Text = '{"name":"Authorization","value":"Bearer synthetic-opaque-value"}' }
            @{ Name = 'weak password equal to scheme'; Extension = '.json'; Text = '{"password":"Bearer"}' }
            @{ Name = 'weak API key equal to scheme'; Extension = '.json'; Text = '{"name":"x-api-key","value":"Bearer"}' }
            @{ Name = 'secret flag before header name'; Extension = '.json'; Text = '{"secret":true,"name":"Authorization","value":"Bearer"}' }
            @{ Name = 'secret flag after header name'; Extension = '.json'; Text = '{"name":"Authorization","secret":true,"value":"Bearer"}' }
            @{ Name = 'credential key before header name'; Extension = '.json'; Text = '{"key":"password","name":"Authorization","value":"Bearer"}' }
            @{ Name = 'credential key after header name'; Extension = '.json'; Text = '{"name":"Authorization","key":"password","value":"Bearer"}' }
            @{ Name = 'token in descriptive text'; Extension = '.json'; Text = '{"description":"Bearer synthetic-opaque-value"}' }
            @{ Name = 'JWT in descriptive text'; Extension = '.json'; Text = '{"message":"Bearer eyJsynthetic.synthetic.payload"}' }
            @{ Name = 'literal token equal to prose noun'; Extension = '.xml'; Text = '<set-header name="Authorization"><value>Bearer token</value></set-header>' }
            @{ Name = 'serialized policy comment'; Extension = '.json'; Text = '{"effectiveXml":"<policies><!-- Bearer synthetic-opaque-value --><inbound/></policies>"}' }
            @{ Name = 'serialized policy instruction'; Extension = '.json'; Text = '{"effectiveXml":"<policies><?synthetic Bearer synthetic-opaque-value?><inbound/></policies>"}' }
            @{ Name = 'serialized policy mixed text'; Extension = '.json'; Text = '{"effectiveXml":"<policies><inbound><set-body>Bearer synthetic-opaque-value<synthetic/></set-body></inbound></policies>"}' }
            @{ Name = 'serialized policy mixed CDATA'; Extension = '.json'; Text = '{"effectiveXml":"<policies><inbound><set-body><![CDATA[Bearer synthetic-opaque-value]]><synthetic/></set-body></inbound></policies>"}' }
        ) {
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path "credential$Extension") `
                -Value $Text
            Test-ApimRunSecret -RunFolder $script:scanRun.Path -WriteLocationReport |
                Should -BeFalse
        }

        It 'accepts JWT token and signing-key policy references rather than exempting the policy' {
            $policy = @'
<validate-jwt header-name="Authorization" token-value="@(context.Request.Headers.GetValueOrDefault(&quot;Authorization&quot;))"><issuer-signing-keys><key>{{signing-key}}</key></issuer-signing-keys><decryption-keys><key>***REDACTED***</key></decryption-keys></validate-jwt>
'@
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'references.xml') `
                -Value $policy
            Test-ApimRunSecret -RunFolder $script:scanRun.Path | Should -BeTrue
        }

        It 'fails closed on malformed serialized policy XML' {
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'invalid-policy.json') `
                -Value '{"effectiveXml":"<policies><inbound></policies>"}'
            { Test-ApimRunSecret -RunFolder $script:scanRun.Path } | Should -Throw
        }

        It 'preserves log lines and JSON pointers for embedded policy XML locations' {
            $policy = '<validate-jwt token-value="synthetic-opaque-value"/>'
            $text = @{ policies = @(@{ effectiveXml = $policy }) } | ConvertTo-Json -Compress
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'policy.log') `
                -Value ('{"message":"clean"}' + "`n" + $text)
            Test-ApimRunSecret -RunFolder $script:scanRun.Path -WriteLocationReport |
                Should -BeFalse
            $report = Get-Content -LiteralPath (
                Join-Path $script:scanRun.Path 'secret-scan-locations.json'
            ) -Raw | ConvertFrom-Json
            $report.locations.location | Should -Be '/policies/0/effectiveXml/*[1]/@*[1]'
            $report.locations.line | Should -Be 2
        }

        It 'records every duplicate credential value rather than the final sibling pointer' {
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'duplicate.json') `
                -Value '{"name":"Authorization","value":"synthetic-opaque-value","value":"Bearer"}'
            Test-ApimRunSecret -RunFolder $script:scanRun.Path -WriteLocationReport |
                Should -BeFalse
            $report = Get-Content -LiteralPath (
                Join-Path $script:scanRun.Path 'secret-scan-locations.json'
            ) -Raw | ConvertFrom-Json
            $report.locations.Count | Should -Be 1
            $report.locations.location | Should -Be '/value'
        }

        It 'reports all source locations without captured credential values or excerpts' {
            $planted = 'synthetic-' + 'planted-value'
            $json = '{"items":[{"password":"' + $planted + '"},{"apiKey":"' + $planted + '"}]}'
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'nested.json') -Value $json
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'policy.xml') `
                -Value ('<policies><inbound><authentication-basic password="' + $planted +
                    '"/><set-header name="x-api-key"><value>' + $planted +
                    '</value></set-header></inbound></policies>')
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'plain.txt') `
                -Value ("safe`nPassword=$planted`nBearer $planted")
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'run.log') `
                -Value ('{"message":"safe"}' + "`n" + '{"password":"' + $planted + '"}')
            Test-ApimRunSecret -RunFolder $script:scanRun.Path -WriteLocationReport |
                Should -BeFalse
            $reportText = Get-Content -LiteralPath (
                Join-Path $script:scanRun.Path 'secret-scan-locations.json'
            ) -Raw
            $reportText | Should -Not -Match $planted
            $report = $reportText | ConvertFrom-Json
            $report.schemaVersion | Should -Be '1.1'
            $report.status | Should -Be CandidateDetected
            @($report.locations | Where-Object file -EQ 'nested.json').location |
                Should -Be @('/items/0/password', '/items/1/apiKey')
            @($report.locations | Where-Object file -EQ 'policy.xml').location |
                Should -Contain '/*[1]/*[1]/*[1]/@*[1]'
            @($report.locations | Where-Object file -EQ 'policy.xml').location |
                Should -Contain '/*[1]/*[1]/*[2]/*[1]'
            $plain = @($report.locations | Where-Object file -EQ 'plain.txt')
            $plain.line | Should -Be @(2, 3)
            $plain.column | Should -Be @(1, 1)
            ($report.locations | Where-Object file -EQ 'run.log').line | Should -Be 2
            ($report.locations | Where-Object file -EQ 'run.log').location |
                Should -Be '/password'
            $reportText | Should -Not -Match [regex]::Escape($script:scanRun.Path)
        }

        It 'reports workbook parts and positional XML paths without values' {
            $path = Join-Path $script:scanRun.Path 'report.xlsx'
            Write-SecretScanWorkbook -Path $path -Parts @{
                '[Content_Types].xml' = '<Types/>'
                'xl/workbook.xml' = '<workbook/>'
                'xl/sharedStrings.xml' = '<sst><si><t>Bearer synthetic-planted-value</t></si></sst>'
                'xl/worksheets/sheet1.xml' = '<worksheet><sheetData><row><c><is><t>Bearer synthetic-planted-value</t></is></c></row></sheetData></worksheet>'
            }
            Test-ApimRunSecret -RunFolder $script:scanRun.Path -WriteLocationReport |
                Should -BeFalse
            $report = Get-Content -LiteralPath (
                Join-Path $script:scanRun.Path 'secret-scan-locations.json'
            ) -Raw | ConvertFrom-Json
            $report.locations.part | Should -Be @(
                'xl/sharedStrings.xml', 'xl/worksheets/sheet1.xml'
            )
            $report.locations.location | Should -Be @(
                '/*[1]/*[1]/*[1]', '/*[1]/*[1]/*[1]/*[1]/*[1]/*[1]'
            )
        }

        It 'refreshes candidate locations on rescans and marks failed rescans incomplete' {
            $path = Join-Path $script:scanRun.Path 'planted.json'
            $reportPath = Join-Path $script:scanRun.Path 'secret-scan-locations.json'
            Set-Content -LiteralPath $path -Value '{"password":"synthetic-planted-value"}'
            Test-ApimRunSecret -RunFolder $script:scanRun.Path -WriteLocationReport |
                Should -BeFalse
            Set-Content -LiteralPath $path -Value '{"password":"***REDACTED***"}'
            Test-ApimRunSecret -RunFolder $script:scanRun.Path -WriteLocationReport |
                Should -BeTrue
            $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
            $report.status | Should -Be Clean
            $report.locations.Count | Should -Be 0
            Set-Content -LiteralPath $path -Value '{invalid'
            { Test-ApimRunSecret -RunFolder $script:scanRun.Path -WriteLocationReport } |
                Should -Throw
            $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
            $report.status | Should -Be Incomplete
            $report.locations.Count | Should -Be 0
        }

        It 'does not persist secret-like property names in location paths' {
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'property.json') `
                -Value '{"eyJsynthetic.synthetic.payload":"safe"}'
            Test-ApimRunSecret -RunFolder $script:scanRun.Path -WriteLocationReport |
                Should -BeFalse
            $text = Get-Content -LiteralPath (
                Join-Path $script:scanRun.Path 'secret-scan-locations.json'
            ) -Raw
            $text | Should -Not -Match 'eyJsynthetic'
            ($text | ConvertFrom-Json).locations.location | Should -Be '/[member:0]'
        }

        It 'emits only closed coarse summary rows matching deterministic local artifact IDs' {
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'first.json') `
                -Value '{"password":"synthetic-planted-value","apiKey":"synthetic-planted-value"}'
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'second.json') `
                -Value '{"password":"synthetic-planted-value"}'
            $received = [System.Collections.Generic.List[object]]::new()
            $callback = {
                param($Rows)
                foreach ($row in $Rows) { $received.Add($row) }
            }.GetNewClosure()
            { Test-ApimRunSecret -RunFolder $script:scanRun.Path -OnSummary $callback } |
                Should -Throw '*summary requires location reporting*'
            Test-ApimRunSecret -RunFolder $script:scanRun.Path -WriteLocationReport `
                -OnSummary $callback | Should -BeFalse
            $received.Count | Should -Be 3
            $received.row | Should -Be @(1, 2, 3)
            $received.artifactId | Should -Be @(
                'artifact-0001', 'artifact-0001', 'artifact-0002'
            )
            foreach ($row in $received) {
                @($row.PSObject.Properties.Name) |
                    Should -Be @('row', 'artifactId', 'kind', 'line', 'column')
            }
            $json = ConvertTo-Json -InputObject $received.ToArray()
            $json | Should -Not -Match 'first\.json|second\.json|password|apiKey|synthetic-planted-value'
            $reportPath = Join-Path $script:scanRun.Path 'secret-scan-locations.json'
            $firstReport = Get-Content -LiteralPath $reportPath -Raw
            ($firstReport | ConvertFrom-Json).locations.artifactId |
                Should -Be $received.artifactId
            Test-ApimRunSecret -RunFolder $script:scanRun.Path -WriteLocationReport |
                Should -BeFalse
            (Get-Content -LiteralPath $reportPath -Raw) | Should -Be $firstReport
        }

        It 'fails closed rather than presenting a truncated location report' {
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'many.txt') `
                -Value (('Bearer synthetic-planted-value' + "`n") * 10001)
            { Test-ApimRunSecret -RunFolder $script:scanRun.Path -WriteLocationReport } |
                Should -Throw '*location limit*'
            $report = Get-Content -LiteralPath (
                Join-Path $script:scanRun.Path 'secret-scan-locations.json'
            ) -Raw | ConvertFrom-Json
            $report.status | Should -Be Incomplete
            $report.locations.Count | Should -Be 0
        }

        It 'fails closed for <Name>' -ForEach @(
            @{ Name = 'malformed JSON'; Extension = '.json'; Text = '{invalid' }
            @{ Name = 'malformed XML'; Extension = '.xml'; Text = '<invalid>' }
            @{ Name = 'DTD'; Extension = '.xml'; Text = '<!DOCTYPE root [<!ENTITY x "synthetic">]><root>&x;</root>' }
            @{ Name = 'malformed log'; Extension = '.log'; Text = '{"message":"safe"}' + "`n" + 'not json' }
            @{ Name = 'unsupported file'; Extension = '.bin'; Text = 'synthetic' }
            @{ Name = 'corrupt workbook'; Extension = '.xlsx'; Text = 'not a zip' }
        ) {
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path "invalid$Extension") `
                -Value $Text
            { Test-ApimRunSecret -RunFolder $script:scanRun.Path } | Should -Throw
        }

        It 'fails closed for invalid UTF-8 disguised as text' {
            [System.IO.File]::WriteAllBytes(
                (Join-Path $script:scanRun.Path 'invalid.txt'), [byte[]] @(0xC3, 0x28)
            )
            { Test-ApimRunSecret -RunFolder $script:scanRun.Path } | Should -Throw
        }

        It 'fails closed for a missing manifest or root' {
            { Test-ApimRunSecret -RunFolder (Join-Path $TestDrive 'absent') } | Should -Throw
            Remove-Item -LiteralPath (Join-Path $script:scanRun.Path 'manifest.json')
            { Test-ApimRunSecret -RunFolder $script:scanRun.Path } | Should -Throw
        }

        It 'rejects an oversized file without reading it' {
            $stream = [System.IO.File]::Create((Join-Path $script:scanRun.Path 'large.txt'))
            try { $stream.SetLength(64MB + 1) }
            finally { $stream.Dispose() }
            { Test-ApimRunSecret -RunFolder $script:scanRun.Path } |
                Should -Throw '*size limit*'
        }

        It 'does not return a clean result on an unreadable artifact' {
            $path = Join-Path $script:scanRun.Path 'locked.json'
            Set-Content -LiteralPath $path -Value '{}'
            $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            try {
                { Test-ApimRunSecret -RunFolder $script:scanRun.Path } | Should -Throw
            }
            finally { $stream.Dispose() }
        }

        It 'rejects links without scanning their target' {
            $target = Join-Path $TestDrive 'synthetic-link-target'
            $null = New-Item -ItemType Directory -Path $target
            $kind = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
            $link = Join-Path $script:scanRun.Path 'linked'
            $null = New-Item -ItemType $kind -Path $link -Target $target
            try {
                { Test-ApimRunSecret -RunFolder $script:scanRun.Path } |
                    Should -Throw '*symbolic link or junction*'
            }
            finally { [System.IO.Directory]::Delete($link) }
        }

        It 'scans compressed workbook text and rejects unsafe parts' {
            $path = Join-Path $script:scanRun.Path 'report.xlsx'
            $parts = @{
                '[Content_Types].xml' = '<Types/>'
                'xl/workbook.xml' = '<workbook/>'
                'xl/sharedStrings.xml' = '<sst><si><t>Bearer synthetic-planted-value</t></si></sst>'
            }
            Write-SecretScanWorkbook -Path $path -Parts $parts
            Test-ApimRunSecret -RunFolder $script:scanRun.Path | Should -BeFalse
            Remove-Item -LiteralPath $path
            $parts['xl/sharedStrings.xml'] = '<sst><si><t>Bearer ***REDACTED***</t></si></sst>'
            Write-SecretScanWorkbook -Path $path -Parts $parts
            Test-ApimRunSecret -RunFolder $script:scanRun.Path | Should -BeTrue
            Remove-Item -LiteralPath $path
            $parts['xl/unsupported.bin'] = 'synthetic'
            Write-SecretScanWorkbook -Path $path -Parts $parts
            { Test-ApimRunSecret -RunFolder $script:scanRun.Path } |
                Should -Throw '*unsupported workbook part*'
        }

        It 'rejects oversized expanded workbook entries' {
            $path = Join-Path $script:scanRun.Path 'large.xlsx'
            Write-SecretScanWorkbook -Path $path -Parts @{
                '[Content_Types].xml' = '<Types/>'
                'xl/workbook.xml' = '<workbook/>'
                'xl/sharedStrings.xml' = 'x' * (16MB + 1)
            }
            { Test-ApimRunSecret -RunFolder $script:scanRun.Path } |
                Should -Throw '*workbook size limit*'
        }

        It 'rejects an unsafe workbook inventory' {
            $path = Join-Path $script:scanRun.Path 'unsafe.xlsx'
            Write-SecretScanWorkbook -Path $path -Parts @{
                '[Content_Types].xml' = '<Types/>'
                'xl/workbook.xml' = '<workbook/>'
                '../outside.xml' = '<root/>'
            }
            { Test-ApimRunSecret -RunFolder $script:scanRun.Path } |
                Should -Throw '*entry inventory*'
        }

        It 'rejects an oversized workbook total even when each entry is below its limit' {
            $path = Join-Path $script:scanRun.Path 'expanded.xlsx'
            $part = '<root>' + ('x' * 13MB) + '</root>'
            $parts = @{
                '[Content_Types].xml' = '<Types/>'
                'xl/workbook.xml' = '<workbook/>'
            }
            for ($index = 0; $index -lt 5; $index++) {
                $parts["xl/part$index.xml"] = $part
            }
            Write-SecretScanWorkbook -Path $path -Parts $parts
            { Test-ApimRunSecret -RunFolder $script:scanRun.Path } |
                Should -Throw '*workbook size limit*'
        }

        It 'requires recognizable workbook parts' {
            $path = Join-Path $script:scanRun.Path 'missing.xlsx'
            Write-SecretScanWorkbook -Path $path -Parts @{ 'xl/sharedStrings.xml' = '<sst/>' }
            { Test-ApimRunSecret -RunFolder $script:scanRun.Path } |
                Should -Throw '*recognizable workbook*'
        }

        It 'requires a clean scan for smoke success in the <Mode> case' -ForEach @(
            @{ Mode = 'clean'; Status = 'Completed'; ExitCode = 0; ScanStatus = 'SECRET_SCAN_PASS' }
            @{ Mode = 'secret'; Status = 'Completed'; ExitCode = 4; ScanStatus = 'SECRET_SCAN_FAIL' }
            @{ Mode = 'invalid'; Status = 'Completed'; ExitCode = 4; ScanStatus = 'SECRET_SCAN_ERROR' }
            @{ Mode = 'partial'; Status = 'Partial'; ExitCode = 3; ScanStatus = 'SECRET_SCAN_PASS' }
        ) {
            $source = Get-Content -LiteralPath (
                Join-Path $script:secretScanRepoRoot 'config/sample.psd1'
            ) -Raw
            $runRoot = Split-Path $script:scanRun.Path -Parent
            $configFile = Join-Path $TestDrive 'synthetic-smoke-config.psd1'
            $source = $source.Replace('<absolute-external-restricted-path>', $runRoot).
                Replace('<absolute-external-analysis-path>', (Join-Path $TestDrive 'analysis'))
            Set-Content -LiteralPath $configFile -Value $source
            if ($Mode -eq 'secret') {
                Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'planted.txt') `
                    -Value 'Password=synthetic-planted-value'
            }
            if ($Mode -eq 'invalid') {
                Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'unsupported.bin') `
                    -Value 'synthetic'
            }
            $wrapper = Join-Path $TestDrive 'synthetic-smoke-wrapper.ps1'
            $wrapperText = @'
param($Repository, $Config, $Status)
$global:syntheticModule = Import-Module (Join-Path $Repository 'ApimAssessment.psd1') -Force -PassThru
& $global:syntheticModule {
    param($status)
    $script:syntheticSmokeStatus = $status
    function script:Invoke-ApimSmoke {
        [pscustomobject]@{
            RunId = 'synthetic-scan'
            Status = $script:syntheticSmokeStatus
            Checks = @([pscustomobject]@{ Status = 'Completed' })
        }
    }
    function script:Test-ApimSmokeOutput {}
    function script:Get-ApimSmokeQueryCheck {
        foreach ($kind in @('appgwByListener', 'appgwNonEdge', 'directNonAppGw', 'headersLogged')) {
            [pscustomobject]@{ Name = $kind; Status = 'Skipped' }
        }
    }
} $Status
function Import-Module {
    [CmdletBinding()]
    param($Name, [switch] $Force, [switch] $PassThru)
    if ($Name -notlike 'Az.*') { return $global:syntheticModule }
}
function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        Subscription = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000001' }
        Tenant = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000002' }
    }
}
& (Join-Path $Repository 'scripts/Invoke-ApimSmoke.ps1') -Config $Config -Environment Prod -MicrosoftOwnedTestEnvironment
exit $LASTEXITCODE
'@
            Set-Content -LiteralPath $wrapper -Value $wrapperText
            $output = & pwsh -NoProfile -File $wrapper -Repository $script:secretScanRepoRoot `
                -Config $configFile -Status $Status 2>&1
            $LASTEXITCODE | Should -Be $ExitCode
            $joined = $output -join "`n"
            $joined | Should -Match $ScanStatus
            $joined | Should -Match '\[QUERY\] appgwByListener - Skipped'
            $joined | Should -Match '\[QUERY\] appgwNonEdge - Skipped'
            $joined | Should -Match '\[QUERY\] directNonAppGw - Skipped'
            $joined | Should -Match '\[QUERY\] headersLogged - Skipped'
            $joined | Should -Not -Match 'synthetic-planted-value|unsupported\.bin'
            $joined | Should -Not -Match [regex]::Escape($script:scanRun.Path)
            $output[-1] | Should -Match "exit code $ExitCode"
            if ($ExitCode -eq 4) { $joined | Should -Not -Match '\[SMOKE\] PASS' }
            if ($Mode -eq 'secret') {
                $joined | Should -Match 'SECRET_SCAN_FINDINGS'
                $joined | Should -Match 'artifact-0001\s+CredentialAssignment\s+1\s+1'
                $joined | Should -Not -Match 'planted\.txt'
                $joined.IndexOf('SECRET_SCAN_FINDINGS') |
                    Should -BeLessThan $joined.LastIndexOf('[SMOKE] FAIL')
            }
            else { $joined | Should -Not -Match 'SECRET_SCAN_FINDINGS' }
        }

        It 'reports only fixed safe status and the exit code from the standalone command' {
            $entrypoint = Join-Path $script:secretScanRepoRoot 'scripts/Test-ApimRunSecrets.ps1'
            $output = & pwsh -NoProfile -File $entrypoint -RunFolder $script:scanRun.Path 2>&1
            $LASTEXITCODE | Should -Be 0
            ($output -join "`n") | Should -Be (
                'SECRET_SCAN_PASS: no supported secret patterns detected. Exit code: 0.'
            )
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'planted.txt') `
                -Value 'Password=synthetic-planted-value'
            $output = & pwsh -NoProfile -File $entrypoint -RunFolder $script:scanRun.Path 2>&1
            $LASTEXITCODE | Should -Be 1
            @($output | ForEach-Object ToString) | Should -Contain (
                'SECRET_SCAN_DETAILS: open secret-scan-locations.json in the supplied run folder locally. It lists file locations and match categories, not values. Do not paste it into Copilot.'
            )
            $output[-1] | Should -Be (
                'SECRET_SCAN_FAIL: secret-like candidate detected; this may be a false positive. Exit code: 1.'
            )
            $joined = $output -join "`n"
            $joined | Should -Match 'artifact-0001\s+CredentialAssignment\s+1\s+1'
            $joined | Should -Not -Match 'planted\.txt|synthetic-planted-value'
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'unsupported.bin') `
                -Value 'synthetic'
            $output = & pwsh -NoProfile -File $entrypoint -RunFolder $script:scanRun.Path 2>&1
            $LASTEXITCODE | Should -Be 2
            $output[-2] | Should -Be (
                'SECRET_SCAN_DETAILS: no complete locations report is available for this attempt; an existing report may be absent or stale. Resolve local scan/read/write errors and rerun.'
            )
            $output[-1] | Should -Be (
                'SECRET_SCAN_ERROR: scan incomplete; inspect the run locally. Exit code: 2.'
            )
        }
    }
}
