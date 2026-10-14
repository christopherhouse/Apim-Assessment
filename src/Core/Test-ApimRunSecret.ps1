#Requires -Version 7.4

Set-StrictMode -Version Latest

function Test-ApimRunSecret {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunFolder,

        [switch] $WriteLocationReport
    )

    $ErrorActionPreference = 'Stop'
    $root = [System.IO.Path]::GetFullPath($RunFolder)
    Test-ConfigPathLink -Path $root -Context 'Secret scan'
    if (-not [System.IO.Directory]::Exists($root)) {
        throw 'Secret scan requires a saved run directory.'
    }
    $reportName = 'secret-scan-locations.json'
    $reportPath = Join-Path $root $reportName
    $pathComparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else { [System.StringComparison]::Ordinal }
    if ($WriteLocationReport) {
        Test-ConfigPathLink -Path $reportPath -Context 'Secret scan locations'
        $null = Write-RunFile -RunPath $root -RelativePath $reportName -InputObject (
            [ordered]@{
                schemaVersion = '1.0'
                status = 'Incomplete'
                locations = @()
            }
        )
    }
    $locations = [System.Collections.Generic.List[object]]::new()
    $currentFile = ''
    $currentPart = $null

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
    $patternKinds = @(
        'Jwt', 'PrivateKey', 'AuthorizationCredential',
        'UrlUserInfo', 'UrlQueryCredential', 'CredentialAssignment'
    )

    function Protect-SecretLocationText {
        param([AllowNull()][string] $Text)

        $result = $Text
        foreach ($expression in $expressions) {
            $result = $expression.Replace($result, '***REDACTED***')
        }
        return $result
    }

    function Add-SecretScanLocation {
        param(
            [string] $Kind,
            [AllowEmptyString()][string] $Location = '',
            [Nullable[int]] $Line,
            [Nullable[int]] $Column
        )

        if (-not $WriteLocationReport) { return }
        if ($locations.Count -ge 10000) {
            throw 'Secret scan location limit exceeded.'
        }
        $locations.Add([pscustomobject][ordered]@{
            file = Protect-SecretLocationText -Text $currentFile
            part = if ($null -eq $currentPart) {
                $null
            }
            else { Protect-SecretLocationText -Text $currentPart }
            kind = $Kind
            location = Protect-SecretLocationText -Text $Location
            line = $Line
            column = $Column
        })
    }

    function Test-LiteralCredential {
        param([AllowNull()][string] $Value)

        if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
        $trimmed = $Value.Trim() -replace '^(?i)(?:Bearer|Basic)\s+', ''
        return $trimmed -cne '***REDACTED***' -and
            $trimmed -notmatch '^\{\{[^{}]+\}\}$' -and
            $trimmed -notmatch '(?s)^@(?:\(.*\)|\{.*\})$'
    }

    function Test-SecretText {
        param(
            [AllowEmptyString()][string] $Text,
            [AllowEmptyString()][string] $Location = '',
            [Nullable[int]] $Line,
            [switch] $TextCoordinates,
            [switch] $NoLocation
        )

        $found = $false
        $lineStarts = [int[]] @()
        if ($TextCoordinates -and $WriteLocationReport) {
            $lineStarts = [int[]] @(
                0
                foreach ($newline in [regex]::Matches($Text, "`n")) {
                    $newline.Index + 1
                }
            )
        }
        for ($index = 0; $index -lt $expressions.Count; $index++) {
            $expression = $expressions[$index]
            foreach ($match in $expression.Matches($Text)) {
                if ($match.Groups['credential'].Success) {
                    $value = [System.Uri]::UnescapeDataString(
                        $match.Groups['credential'].Value
                    )
                    if (-not (Test-LiteralCredential -Value $value)) { continue }
                    if ($match.Value -match '^Basic\s+') {
                        try {
                            $payload = $value.PadRight(
                                [int] ([math]::Ceiling($value.Length / 4.0) * 4), '='
                            )
                            $decoded = [System.Convert]::FromBase64String($payload)
                        }
                        catch [System.FormatException] { continue }
                        if ($decoded -notcontains [byte] 58) { continue }
                    }
                }
                $found = $true
                if (-not $WriteLocationReport) { return $true }
                if ($NoLocation) { continue }
                $matchLine = $Line
                $column = $null
                if ($TextCoordinates) {
                    $lineIndex = [System.Array]::BinarySearch($lineStarts, [int] $match.Index)
                    if ($lineIndex -lt 0) { $lineIndex = -$lineIndex - 2 }
                    $matchLine = $lineIndex + 1
                    $column = $match.Index - $lineStarts[$lineIndex] + 1
                }
                Add-SecretScanLocation -Kind $patternKinds[$index] `
                    -Location $Location -Line $matchLine -Column $column
            }
        }
        return $found
    }

    function Test-SecretJsonElement {
        param(
            [System.Text.Json.JsonElement] $Element,
            [AllowEmptyString()][string] $Pointer = '',
            [Nullable[int]] $Line
        )

        $found = $false
        switch ($Element.ValueKind) {
            String {
                return Test-SecretText -Text $Element.GetString() `
                    -Location $Pointer -Line $Line
            }
            Array {
                $index = 0
                foreach ($child in $Element.EnumerateArray()) {
                    $found = (Test-SecretJsonElement -Element $child `
                            -Pointer "$Pointer/$index" -Line $Line) -or $found
                    $index++
                }
            }
            Object {
                $sensitiveValue = $false
                $literalValue = $false
                $valuePointer = $Pointer
                $index = 0
                foreach ($property in $Element.EnumerateObject()) {
                    $segment = $property.Name.Replace('~', '~0').Replace('/', '~1')
                    $childPointer = "$Pointer/$segment"
                    if (Test-SecretText -Text $property.Name -NoLocation) {
                        $found = $true
                        $childPointer = "$Pointer/[member:$index]"
                        Add-SecretScanLocation -Kind JsonPropertyName `
                            -Location $childPointer -Line $Line
                    }
                    if ($property.Name -eq 'secret' -and
                        $property.Value.ValueKind -eq 'True') {
                        $sensitiveValue = $true
                    }
                    if ($property.Name -eq 'value' -and
                        (Test-SecretCredentialElement -Element $property.Value)) {
                        $literalValue = $true
                        $valuePointer = $childPointer
                    }
                    if ($property.Name -in @('name', 'key') -and
                        $property.Value.ValueKind -eq 'String' -and
                        $property.Value.GetString() -match $credentialName) {
                        $sensitiveValue = $true
                    }
                    if ($property.Name -match $credentialName -and
                        (Test-SecretCredentialElement -Element $property.Value)) {
                        $found = $true
                        Add-SecretScanLocation -Kind JsonCredentialValue `
                            -Location $childPointer -Line $Line
                    }
                    $found = (Test-SecretJsonElement -Element $property.Value `
                            -Pointer $childPointer -Line $Line) -or $found
                    $index++
                }
                if ($sensitiveValue -and $literalValue) {
                    $found = $true
                    Add-SecretScanLocation -Kind JsonCredentialValue `
                        -Location $valuePointer -Line $Line
                }
            }
        }
        return $found
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

        $found = $false
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
            $nodes = $document.SelectNodes('//*')
            $xmlLocations = [System.Collections.Generic.Dictionary[System.Xml.XmlNode, string]]::new()
            if ($WriteLocationReport) {
                $childPositions = [System.Collections.Generic.Dictionary[System.Xml.XmlNode, int]]::new()
                foreach ($node in $nodes) {
                    $parent = $node.ParentNode
                    if (-not $childPositions.ContainsKey($parent)) {
                        $childPositions[$parent] = 0
                    }
                    $childPositions[$parent]++
                    $parentLocation = if ($xmlLocations.ContainsKey($parent)) {
                        $xmlLocations[$parent]
                    }
                    else { '' }
                    $xmlLocations[$node] = "$parentLocation/*[$($childPositions[$parent])]"
                }
            }
            foreach ($node in $nodes) {
                $nodeLocation = if ($WriteLocationReport) { $xmlLocations[$node] } else { '' }
                $attributeIndex = 1
                foreach ($attribute in $node.Attributes) {
                    $attributeLocation = "$nodeLocation/@*[$attributeIndex]"
                    $found = (Test-SecretText -Text $attribute.Value `
                            -Location $attributeLocation) -or $found
                    if ($attribute.LocalName -match $credentialName -and
                        (Test-LiteralCredential -Value $attribute.Value)) {
                        $found = $true
                        Add-SecretScanLocation -Kind XmlCredentialValue `
                            -Location $attributeLocation
                    }
                    $attributeIndex++
                }
                $leaf = @($node.ChildNodes | Where-Object NodeType -EQ Element).Count -eq 0
                if ($leaf) {
                    $found = (Test-SecretText -Text $node.InnerText `
                            -Location $nodeLocation) -or $found
                }
                if ($leaf -and $node.LocalName -match $credentialName -and
                    (Test-LiteralCredential -Value $node.InnerText)) {
                    $found = $true
                    Add-SecretScanLocation -Kind XmlCredentialValue `
                        -Location $nodeLocation
                }
                if ($node.LocalName -eq 'set-header' -and
                    $node.GetAttribute('name') -match $credentialName) {
                    foreach ($value in $node.SelectNodes('./value')) {
                        if (Test-LiteralCredential -Value $value.InnerText) {
                            $found = $true
                            $valueLocation = if ($WriteLocationReport) {
                                $xmlLocations[$value]
                            }
                            else { '' }
                            Add-SecretScanLocation -Kind XmlCredentialValue `
                                -Location $valueLocation
                        }
                    }
                }
            }
        }
        finally {
            $reader.Dispose()
            $stringReader.Dispose()
        }
        return $found
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
            $lineNumber = 0
            foreach ($line in $Text -split '\r?\n') {
                $lineNumber++
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $document = [System.Text.Json.JsonDocument]::Parse($line)
                try {
                    $found = (Test-SecretJsonElement -Element $document.RootElement `
                            -Line $lineNumber) -or $found
                }
                finally { $document.Dispose() }
            }
        }
        elseif ($Extension -in @('.xml', '.rels')) {
            $found = (Test-SecretXml -Text $Text) -or $found
        }
        elseif ($Extension -eq '.html') {
            $lineNumber = 0
            foreach ($line in $Text -split '\r?\n') {
                $lineNumber++
                $found = (Test-SecretText -Text (
                    [System.Net.WebUtility]::HtmlDecode($line)
                ) -Location decodedHtml -Line $lineNumber) -or $found
            }
        }
        else {
            $found = Test-SecretText -Text $Text -TextCoordinates
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
            if ($WriteLocationReport -and
                [string]::Equals($item.FullName, $reportPath,
                    $pathComparison)) {
                continue
            }
            $currentFile = [System.IO.Path]::GetRelativePath($root, $item.FullName)
            $currentPart = $null
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
                        $currentPart = $entry.FullName
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
    if ($WriteLocationReport) {
        Test-ConfigPathLink -Path $reportPath -Context 'Secret scan locations'
        $null = Write-RunFile -RunPath $root -RelativePath $reportName -InputObject (
            [ordered]@{
                schemaVersion = '1.0'
                status = if ($foundSecret) { 'CandidateDetected' } else { 'Clean' }
                locations = @($locations | Sort-Object file, part, location, line, column, kind -Unique)
            }
        )
    }
    return -not $foundSecret
}
