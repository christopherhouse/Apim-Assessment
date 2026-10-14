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
            $joined | Should -Not -Match 'synthetic-planted-value|unsupported\.bin'
            $joined | Should -Not -Match [regex]::Escape($script:scanRun.Path)
            $output[-1] | Should -Match "exit code $ExitCode"
            if ($ExitCode -eq 4) { $joined | Should -Not -Match '\[SMOKE\] PASS' }
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
            ($output -join "`n") | Should -Be (
                'SECRET_SCAN_FAIL: secret candidate detected; inspect the run locally. Exit code: 1.'
            )
            Set-Content -LiteralPath (Join-Path $script:scanRun.Path 'unsupported.bin') `
                -Value 'synthetic'
            $output = & pwsh -NoProfile -File $entrypoint -RunFolder $script:scanRun.Path 2>&1
            $LASTEXITCODE | Should -Be 2
            ($output -join "`n") | Should -Be (
                'SECRET_SCAN_ERROR: scan incomplete; inspect the run locally. Exit code: 2.'
            )
        }
    }
}
