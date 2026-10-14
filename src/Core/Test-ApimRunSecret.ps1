#Requires -Version 7.4

Set-StrictMode -Version Latest

function Test-ApimRunSecret {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunFolder
    )

    $ErrorActionPreference = 'Stop'
    $root = [System.IO.Path]::GetFullPath($RunFolder)
    Test-ConfigPathLink -Path $root -Context 'Secret scan'
    if (-not [System.IO.Directory]::Exists($root)) {
        throw 'Secret scan requires a saved run directory.'
    }

    $credentialName = '(?i)^(?:password|pwd|secret|client[-_ ]?secret|client[-_ ]?key|api[-_ ]?key|subscription[-_ ]?key|ocp-apim-subscription-key|primary[-_ ]?key|secondary[-_ ]?key|accountkey|sharedaccesskey|sharedaccesssignature|access[-_ ]?token|refresh[-_ ]?token|token|sig|authorization|proxy-authorization|x-api-key)$'
    $patterns = @(
        '\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\b',
        '-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----',
        '(?<![\w-])(?:Bearer|Basic)\s+(?<credential>[A-Za-z0-9._~+/=-]+|\*\*\*REDACTED\*\*\*|\{\{[^{}]+\}\})',
        '\b[a-z][a-z0-9+.-]*://[^/\s:@]+:(?<credential>[^/\s@]+)@',
        '[?&](?:sig|token|code|key|password|pwd|secret|api[-_]?key|subscription[-_]?key)=(?<credential>[^&#\s]+)',
        @'
\b(?:password|pwd|secret|client[-_ ]?secret|client[-_ ]?key|api[-_ ]?key|subscription[-_ ]?key|ocp-apim-subscription-key|primary[-_ ]?key|secondary[-_ ]?key|accountkey|sharedaccesskey|sharedaccesssignature|access[-_ ]?token|refresh[-_ ]?token)\s*[:=]\s*(?:"(?<credential>[^"]*)"|'(?<credential>[^']*)'|(?<credential>[^,;\s<]+))
'@.Trim()
    )
    $expressions = @(
        foreach ($pattern in $patterns) {
            [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase,
                [timespan]::FromSeconds(1))
        }
    )

    function Test-LiteralCredential {
        param([AllowNull()][string] $Value)

        if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
        $trimmed = $Value.Trim() -replace '^(?i)(?:Bearer|Basic)\s+', ''
        return $trimmed -cne '***REDACTED***' -and
            $trimmed -notmatch '^\{\{[^{}]+\}\}$' -and
            $trimmed -notmatch '(?s)^@(?:\(.*\)|\{.*\})$'
    }

    function Test-SecretText {
        param([AllowEmptyString()][string] $Text)

        foreach ($expression in $expressions) {
            foreach ($match in $expression.Matches($Text)) {
                if (-not $match.Groups['credential'].Success) { return $true }
                $value = [System.Uri]::UnescapeDataString(
                    $match.Groups['credential'].Value
                )
                if (Test-LiteralCredential -Value $value) { return $true }
            }
        }
        return $false
    }

    function Test-SecretJsonElement {
        param([System.Text.Json.JsonElement] $Element)

        switch ($Element.ValueKind) {
            String { return Test-SecretText -Text $Element.GetString() }
            Array {
                foreach ($child in $Element.EnumerateArray()) {
                    if (Test-SecretJsonElement -Element $child) { return $true }
                }
            }
            Object {
                $sensitiveValue = $false
                $literalValue = $false
                foreach ($property in $Element.EnumerateObject()) {
                    if ($property.Name -eq 'secret' -and
                        $property.Value.ValueKind -eq 'True') {
                        $sensitiveValue = $true
                    }
                    if ($property.Name -eq 'value' -and
                        (Test-SecretCredentialElement -Element $property.Value)) {
                        $literalValue = $true
                    }
                    if ($property.Name -in @('name', 'key') -and
                        $property.Value.ValueKind -eq 'String' -and
                        $property.Value.GetString() -match $credentialName) {
                        $sensitiveValue = $true
                    }
                    if (Test-SecretText -Text $property.Name) { return $true }
                    if ($property.Name -match $credentialName -and
                        (Test-SecretCredentialElement -Element $property.Value)) {
                        return $true
                    }
                    if (Test-SecretJsonElement -Element $property.Value) {
                        return $true
                    }
                }
                if ($sensitiveValue -and $literalValue) { return $true }
            }
        }
        return $false
    }

    function Test-SecretCredentialElement {
        param([System.Text.Json.JsonElement] $Element)

        if ($Element.ValueKind -eq 'String') {
            return Test-LiteralCredential -Value $Element.GetString()
        }
        if ($Element.ValueKind -eq 'Number') { return $true }
        if ($Element.ValueKind -eq 'Array') {
            foreach ($child in $Element.EnumerateArray()) {
                if (Test-SecretCredentialElement -Element $child) { return $true }
            }
        }
        if ($Element.ValueKind -eq 'Object') {
            foreach ($property in $Element.EnumerateObject()) {
                if (Test-SecretCredentialElement -Element $property.Value) { return $true }
            }
        }
        return $false
    }

    function Test-SecretXml {
        param([string] $Text)

        $settings = [System.Xml.XmlReaderSettings]::new()
        $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $settings.MaxCharactersInDocument = 64MB
        $stringReader = [System.IO.StringReader]::new($Text)
        $reader = [System.Xml.XmlReader]::Create($stringReader, $settings)
        try {
            $document = [System.Xml.XmlDocument]::new()
            $document.XmlResolver = $null
            $document.Load($reader)
            foreach ($node in $document.SelectNodes('//*')) {
                foreach ($attribute in $node.Attributes) {
                    if ((Test-SecretText -Text $attribute.Value) -or
                        ($attribute.LocalName -match $credentialName -and
                            (Test-LiteralCredential -Value $attribute.Value))) {
                        return $true
                    }
                }
                $leaf = @($node.ChildNodes | Where-Object NodeType -EQ Element).Count -eq 0
                if ($leaf -and (Test-SecretText -Text $node.InnerText)) {
                    return $true
                }
                if ($leaf -and $node.LocalName -match $credentialName -and
                    (Test-LiteralCredential -Value $node.InnerText)) {
                    return $true
                }
                if ($node.LocalName -eq 'set-header' -and
                    $node.GetAttribute('name') -match $credentialName) {
                    foreach ($value in $node.SelectNodes('./value')) {
                        if (Test-LiteralCredential -Value $value.InnerText) {
                            return $true
                        }
                    }
                }
            }
        }
        finally {
            $reader.Dispose()
            $stringReader.Dispose()
        }
        return $false
    }

    function Read-SecretScanText {
        param([System.IO.Stream] $Stream, [long] $Length)

        if ($Length -gt 64MB) { throw 'Secret scan size limit exceeded.' }
        $bytes = [byte[]]::new([int] $Length)
        $Stream.ReadExactly($bytes, 0, $bytes.Length)
        if ($Stream.ReadByte() -ne -1) { throw 'Secret scan file changed or exceeded its limit.' }
        $encoding = [System.Text.UTF8Encoding]::new($false, $true)
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254) {
            $encoding = [System.Text.UnicodeEncoding]::new($false, $true, $true)
        }
        elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 254 -and $bytes[1] -eq 255) {
            $encoding = [System.Text.UnicodeEncoding]::new($true, $true, $true)
        }
        $text = $encoding.GetString($bytes).TrimStart([char] 0xFEFF)
        if ($text -match '[\x00-\x08\x0B\x0C\x0E-\x1F]') {
            throw 'Secret scan encountered unsupported binary content.'
        }
        return $text
    }

    function Test-SecretArtifactText {
        param([string] $Text, [string] $Extension)

        $found = $false
        if ($Extension -eq '.json') {
            $document = [System.Text.Json.JsonDocument]::Parse($Text)
            try {
                $found = (Test-SecretJsonElement -Element $document.RootElement) -or $found
            }
            finally { $document.Dispose() }
        }
        elseif ($Extension -in @('.log', '.jsonl')) {
            foreach ($line in $Text -split '\r?\n') {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $document = [System.Text.Json.JsonDocument]::Parse($line)
                try {
                    $found = (Test-SecretJsonElement -Element $document.RootElement) -or $found
                }
                finally { $document.Dispose() }
            }
        }
        elseif ($Extension -in @('.xml', '.rels')) {
            $found = (Test-SecretXml -Text $Text) -or $found
        }
        elseif ($Extension -eq '.html') {
            $found = (Test-SecretText -Text (
                [System.Net.WebUtility]::HtmlDecode($Text)
            )) -or $found
        }
        else {
            $found = Test-SecretText -Text $Text
        }
        return $found
    }

    $foundSecret = $false
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push($root)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        Test-ConfigPathLink -Path $directory -Context 'Secret scan'
        foreach ($item in Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop) {
            Test-ConfigPathLink -Path $item.FullName -Context 'Secret scan'
            if ($item.PSIsContainer) {
                $pending.Push($item.FullName)
                continue
            }
            if ($item.Length -gt 64MB) { throw 'Secret scan size limit exceeded.' }
            $extension = $item.Extension.ToLowerInvariant()
            if ($extension -notin @(
                    '.json', '.xml', '.log', '.jsonl', '.txt', '.md', '.html', '.xlsx'
                )) {
                throw 'Secret scan encountered an unsupported artifact.'
            }
            $stream = [System.IO.File]::Open($item.FullName, [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            try {
                if ($extension -ne '.xlsx') {
                    $text = Read-SecretScanText -Stream $stream -Length $stream.Length
                    $foundSecret = (Test-SecretArtifactText -Text $text `
                            -Extension $extension) -or $foundSecret
                    continue
                }
                $archive = [System.IO.Compression.ZipArchive]::new(
                    $stream, [System.IO.Compression.ZipArchiveMode]::Read, $true
                )
                try {
                    $total = 0L
                    $names = [System.Collections.Generic.HashSet[string]]::new(
                        [System.StringComparer]::OrdinalIgnoreCase
                    )
                    foreach ($entry in $archive.Entries) {
                        if (-not $names.Add($entry.FullName) -or
                            $entry.FullName -match '(?:^/|\\|:|(?:^|/)\.\.(?:/|$))') {
                            throw 'Secret scan rejected the workbook entry inventory.'
                        }
                        $total += $entry.Length
                        if ($entry.Length -gt 16MB -or $total -gt 64MB) {
                            throw 'Secret scan workbook size limit exceeded.'
                        }
                        if ($entry.FullName.EndsWith('/') -and $entry.Length -eq 0) {
                            continue
                        }
                        $entryExtension = [System.IO.Path]::GetExtension(
                            $entry.FullName
                        ).ToLowerInvariant()
                        if ($entryExtension -notin @('.xml', '.rels')) {
                            throw 'Secret scan encountered an unsupported workbook part.'
                        }
                        $entryStream = $entry.Open()
                        try {
                            $text = Read-SecretScanText -Stream $entryStream -Length $entry.Length
                            $foundSecret = (Test-SecretArtifactText -Text $text `
                                    -Extension $entryExtension) -or $foundSecret
                        }
                        finally { $entryStream.Dispose() }
                    }
                    if (-not $names.Contains('[Content_Types].xml') -or
                        -not $names.Contains('xl/workbook.xml')) {
                        throw 'Secret scan requires a recognizable workbook.'
                    }
                }
                finally { $archive.Dispose() }
            }
            finally { $stream.Dispose() }
        }
    }
    $null = Get-RunManifest -RunPath $root
    return -not $foundSecret
}
