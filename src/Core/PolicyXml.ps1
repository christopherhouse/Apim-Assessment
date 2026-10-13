#Requires -Version 7.4

Set-StrictMode -Version Latest

function ConvertTo-ApimPolicyXmlDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Xml
    )

    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $document = [System.Xml.XmlDocument]::new()
    $document.PreserveWhitespace = $true
    $stringReader = [System.IO.StringReader]::new($Xml)
    $reader = $null
    try {
        $reader = [System.Xml.XmlReader]::Create($stringReader, $settings)
        $document.Load($reader)
    }
    catch {
        throw 'Policy XML was invalid or used a prohibited document type.'
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }
        $stringReader.Dispose()
    }

    if ($null -eq $document.DocumentElement) {
        throw 'Policy XML did not contain a document element.'
    }
    return ,$document
}

function Get-ApimPolicyNodeLocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlNode] $Node
    )

    $attributeName = $null
    $current = $Node
    if ($Node -is [System.Xml.XmlAttribute]) {
        $attributeName = $Node.LocalName
        $current = $Node.OwnerElement
    }

    $segments = [System.Collections.Generic.List[string]]::new()
    while ($null -ne $current -and
        $current.NodeType -eq [System.Xml.XmlNodeType]::Element) {
        $position = 1
        $sibling = $current.PreviousSibling
        while ($null -ne $sibling) {
            if ($sibling.NodeType -eq [System.Xml.XmlNodeType]::Element -and
                $sibling.LocalName -eq $current.LocalName) {
                $position++
            }
            $sibling = $sibling.PreviousSibling
        }
        $segments.Insert(0, "$($current.LocalName)[$position]")
        $current = $current.ParentNode
    }

    $location = '/' + ($segments -join '/')
    if ($null -ne $attributeName) {
        $location += "/@$attributeName"
    }
    return $location
}

function Test-ApimPolicySecretCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value,

        [AllowEmptyString()]
        [string] $ContextName = ''
    )

    $candidate = [regex]::Replace($Value, '\{\{[^{}]+\}\}', '')
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return $false
    }

    $trimmedCandidate = $candidate.TrimStart()
    $isExpression = $trimmedCandidate.StartsWith('@(') -or
        $trimmedCandidate.StartsWith('@{')
    if (-not $isExpression -and $ContextName -match
        '(?i)(authorization|auth|credential|key|secret|password|pwd|token|bearer|sig)') {
        return $true
    }
    if ($candidate -match '(?i)(key|secret|password|pwd|token|sig=[^&\s]+)' -or
        $candidate -match '(?i)\bbearer\s+\S+') {
        return $true
    }
    if ($candidate -match
        '(?<![A-Za-z0-9+/=])[A-Za-z0-9+/]{24,}={0,2}(?![A-Za-z0-9+/=])') {
        return $true
    }
    if ($candidate -match
        '(?<![A-Za-z0-9_-])eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+') {
        return $true
    }
    return $false
}

function Protect-ApimPolicyXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Xml
    )

    $document = ConvertTo-ApimPolicyXmlDocument -Xml $Xml
    if ($document.DocumentElement.LocalName -notin @('policies', 'fragment')) {
        throw 'Policy XML did not contain a supported policy root.'
    }
    $locations = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )

    $valueNodes = @($document.SelectNodes(
            "//*[local-name()='set-header' or " +
            "local-name()='set-query-parameter']/*[local-name()='value']"
        ))
    foreach ($valueNode in $valueNodes) {
        $contextName = ''
        $nameAttribute = $valueNode.ParentNode.Attributes['name']
        if ($null -ne $nameAttribute) {
            $contextName = [string] $nameAttribute.Value
        }
        if (Test-ApimPolicySecretCandidate -Value $valueNode.InnerText `
                -ContextName $contextName) {
            $null = $locations.Add(
                (Get-ApimPolicyNodeLocation -Node $valueNode)
            )
            $valueNode.InnerText = '***REDACTED***'
        }
    }

    $credentialAttributes = @($document.SelectNodes(
            "//*[local-name()='authentication-basic']/@username | " +
            "//*[local-name()='authentication-basic']/@password"
        ))
    foreach ($credentialAttribute in $credentialAttributes) {
        $candidate = [regex]::Replace(
            [string] $credentialAttribute.Value,
            '\{\{[^{}]+\}\}',
            ''
        )
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $null = $locations.Add(
                (Get-ApimPolicyNodeLocation -Node $credentialAttribute)
            )
            $credentialAttribute.Value = '***REDACTED***'
        }
    }

    $urlAttributes = @($document.SelectNodes(
            "//*[local-name()='send-request']/@url | " +
            "//*[local-name()='set-backend-service']/@base-url"
        ))
    foreach ($urlAttribute in $urlAttributes) {
        if (Test-ApimPolicySecretCandidate -Value $urlAttribute.Value) {
            $null = $locations.Add(
                (Get-ApimPolicyNodeLocation -Node $urlAttribute)
            )
            $urlAttribute.Value = '***REDACTED***'
        }
    }

    [string[]] $sortedLocations = @($locations)
    [System.Array]::Sort(
        $sortedLocations,
        [System.StringComparer]::Ordinal
    )
    return [pscustomobject]@{
        Xml             = $document.OuterXml
        SecretLocations = $sortedLocations
    }
}

function Add-ApimNormalizedPolicyNode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlNode] $Node,

        [Parameter(Mandatory)]
        [System.Text.StringBuilder] $Builder
    )

    if ($Node.NodeType -eq [System.Xml.XmlNodeType]::Comment) {
        return
    }
    if ($Node.NodeType -in @(
            [System.Xml.XmlNodeType]::Text,
            [System.Xml.XmlNodeType]::CDATA,
            [System.Xml.XmlNodeType]::Whitespace,
            [System.Xml.XmlNodeType]::SignificantWhitespace
        )) {
        $value = [regex]::Replace([string] $Node.Value, '\s+', ' ').Trim()
        if (-not [string]::IsNullOrEmpty($value)) {
            $null = $Builder.Append(
                [System.Security.SecurityElement]::Escape($value)
            )
        }
        return
    }
    if ($Node.NodeType -ne [System.Xml.XmlNodeType]::Element) {
        throw 'Policy XML contained an unsupported node type.'
    }

    $null = $Builder.Append('<').Append($Node.Name)
    $attributes = [System.Collections.Generic.SortedDictionary[
        string,
        System.Xml.XmlAttribute
    ]]::new([System.StringComparer]::Ordinal)
    foreach ($attribute in $Node.Attributes) {
        $attributes.Add($attribute.Name, $attribute)
    }
    foreach ($attribute in $attributes.Values) {
        $escapedValue = [System.Security.SecurityElement]::Escape(
            [string] $attribute.Value
        )
        $null = $Builder.Append(' ').Append($attribute.Name).
            Append('="').Append($escapedValue).Append('"')
    }

    $childBuilder = [System.Text.StringBuilder]::new()
    foreach ($child in $Node.ChildNodes) {
        Add-ApimNormalizedPolicyNode -Node $child -Builder $childBuilder
    }
    if ($childBuilder.Length -eq 0) {
        $null = $Builder.Append('/>')
        return
    }

    $null = $Builder.Append('>').Append($childBuilder.ToString()).
        Append('</').Append($Node.Name).Append('>')
}

function ConvertTo-ApimNormalizedPolicyXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Xml
    )

    $document = ConvertTo-ApimPolicyXmlDocument -Xml $Xml
    if ($document.DocumentElement.LocalName -notin @('policies', 'fragment')) {
        throw 'Policy XML did not contain a supported policy root.'
    }
    $builder = [System.Text.StringBuilder]::new()
    Add-ApimNormalizedPolicyNode -Node $document.DocumentElement `
        -Builder $builder
    return $builder.ToString().Replace("`r`n", "`n").Replace("`r", "`n")
}

function Get-ApimPolicySha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Xml
    )

    $normalized = ConvertTo-ApimNormalizedPolicyXml -Xml $Xml
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [System.Convert]::ToHexString($hash).ToLowerInvariant()
}
