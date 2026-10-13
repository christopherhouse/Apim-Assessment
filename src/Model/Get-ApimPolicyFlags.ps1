#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimPolicySourceScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlNode] $Node
    )

    $current = if ($Node -is [System.Xml.XmlAttribute]) {
        $Node.OwnerElement
    }
    else {
        $Node
    }
    while ($null -ne $current -and
        $current.NodeType -eq [System.Xml.XmlNodeType]::Element) {
        $scope = ([System.Xml.XmlElement] $current).GetAttribute('data-scope')
        if (-not [string]::IsNullOrWhiteSpace($scope)) {
            return $scope
        }
        $current = $current.ParentNode
    }
    return $null
}

function Test-ApimPolicyHostCondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Condition
    )

    return $Condition -match
        '(?i)context\s*\.\s*Request\s*\.\s*OriginalUrl\s*\.\s*Host' -or
        $Condition -match
        '(?i)context\s*\.\s*Request\s*\.\s*Headers\s*\[\s*["'']Host["'']\s*\]' -or
        $Condition -match
        '(?i)context\s*\.\s*Request\s*\.\s*Headers\s*\.\s*GetValueOrDefault\s*\(\s*["'']Host["'']'
}

function Get-ApimPolicyBaseMissingDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $BaseMissing
    )

    $details = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($entry in $BaseMissing) {
        if ($null -eq $entry) {
            throw 'Base-missing metadata contained a null entry.'
        }
        if ($entry -is [System.Collections.IDictionary]) {
            if (-not $entry.Contains('scope') -or
                -not $entry.Contains('section')) {
                throw 'Base-missing metadata contained an invalid entry.'
            }
            $scope = [string] $entry['scope']
            $section = [string] $entry['section']
        }
        else {
            $scopeProperty = $entry.PSObject.Properties['scope']
            $sectionProperty = $entry.PSObject.Properties['section']
            if ($null -eq $scopeProperty -or $null -eq $sectionProperty) {
                throw 'Base-missing metadata contained an invalid entry.'
            }
            $scope = [string] $scopeProperty.Value
            $section = [string] $sectionProperty.Value
        }
        if ([string]::IsNullOrWhiteSpace($scope) -or
            $section -notin @('inbound', 'backend', 'outbound', 'on-error')) {
            throw 'Base-missing metadata contained an invalid entry.'
        }
        $key = "$scope`u{001F}$section"
        if ($seen.Add($key)) {
            $details.Add([pscustomobject] [ordered]@{
                    scope   = $scope
                    section = $section
                })
        }
    }
    return @($details | Sort-Object scope, section)
}

function Get-ApimPolicyUnresolvedFragment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlDocument] $Document
    )

    $details = [System.Collections.Generic.List[object]]::new()
    foreach ($include in @($Document.SelectNodes(
                "//*[local-name()='include-fragment' and " +
                '@data-fragment-status]'
            ))) {
        $status = ([System.Xml.XmlElement] $include).
            GetAttribute('data-fragment-status')
        if ($status -notin @(
                'Missing',
                'MissingId',
                'Cycle',
                'DepthExceeded'
            )) {
            throw 'Effective policy contained an invalid fragment status.'
        }
        $details.Add([pscustomobject] [ordered]@{
                location   = Get-ApimPolicyNodeLocation -Node $include
                status     = $status
                fragmentId = ([System.Xml.XmlElement] $include).
                    GetAttribute('fragment-id')
                scope      = Get-ApimPolicySourceScope -Node $include
            })
    }
    return @($details | Sort-Object location, status, fragmentId)
}

function Get-ApimPolicyIpFilterDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlDocument] $Document
    )

    $details = [System.Collections.Generic.List[object]]::new()
    foreach ($filter in @($Document.SelectNodes(
                "//*[local-name()='ip-filter']"
            ))) {
        $addresses = [System.Collections.Generic.List[string]]::new()
        foreach ($address in @($filter.SelectNodes(
                    "./*[local-name()='address']"
                ))) {
            $value = $address.InnerText.Trim()
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $addresses.Add($value)
            }
        }
        [string[]] $sortedAddresses = $addresses.ToArray()
        [System.Array]::Sort(
            $sortedAddresses,
            [System.StringComparer]::Ordinal
        )

        $ranges = [System.Collections.Generic.List[object]]::new()
        foreach ($range in @($filter.SelectNodes(
                    "./*[local-name()='address-range']"
                ))) {
            $ranges.Add([pscustomobject] [ordered]@{
                    from = ([System.Xml.XmlElement] $range).
                        GetAttribute('from')
                    to   = ([System.Xml.XmlElement] $range).
                        GetAttribute('to')
                })
        }
        $details.Add([pscustomobject] [ordered]@{
                location      = Get-ApimPolicyNodeLocation -Node $filter
                scope         = Get-ApimPolicySourceScope -Node $filter
                action        = ([System.Xml.XmlElement] $filter).
                    GetAttribute('action')
                addresses     = $sortedAddresses
                addressRanges = @($ranges | Sort-Object from, to)
            })
    }
    return @($details | Sort-Object location)
}

function Get-ApimPolicySecretLocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlDocument] $Document
    )

    $locations = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($valueNode in @($Document.SelectNodes(
                "//*[local-name()='set-header' or " +
                "local-name()='set-query-parameter']/*[local-name()='value']"
            ))) {
        $contextName = ''
        $nameAttribute = $valueNode.ParentNode.Attributes['name']
        if ($null -ne $nameAttribute) {
            $contextName = [string] $nameAttribute.Value
        }
        if ($valueNode.InnerText -eq '***REDACTED***' -or
            (Test-ApimPolicySecretCandidate -Value $valueNode.InnerText `
                    -ContextName $contextName)) {
            $null = $locations.Add(
                (Get-ApimPolicyNodeLocation -Node $valueNode)
            )
        }
    }

    foreach ($credentialAttribute in @($Document.SelectNodes(
                "//*[local-name()='authentication-basic']/@username | " +
                "//*[local-name()='authentication-basic']/@password"
            ))) {
        $candidate = [regex]::Replace(
            [string] $credentialAttribute.Value,
            '\{\{[^{}]+\}\}',
            ''
        )
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $null = $locations.Add(
                (Get-ApimPolicyNodeLocation -Node $credentialAttribute)
            )
        }
    }

    [string[]] $sortedLocations = @($locations)
    [System.Array]::Sort(
        $sortedLocations,
        [System.StringComparer]::Ordinal
    )
    return $sortedLocations
}

function Get-ApimPolicyBackendOverrideDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlDocument] $Document
    )

    $details = [System.Collections.Generic.List[object]]::new()
    foreach ($override in @($Document.SelectNodes(
                "//*[local-name()='set-backend-service']"
            ))) {
        $element = [System.Xml.XmlElement] $override
        $baseUrl = $element.GetAttribute('base-url')
        $insecureHttp = $baseUrl -match '(?i)^http://'
        if (-not [string]::IsNullOrWhiteSpace($baseUrl) -and
            (Test-ApimPolicyUrlSecretCandidate -Value $baseUrl)) {
            $baseUrl = '***REDACTED***'
        }
        $details.Add([pscustomobject] [ordered]@{
                location     = Get-ApimPolicyNodeLocation -Node $override
                scope        = Get-ApimPolicySourceScope -Node $override
                backendId    = $element.GetAttribute('backend-id')
                baseUrl      = $baseUrl
                insecureHttp = $insecureHttp
            })
    }
    return @($details | Sort-Object location)
}

function Get-ApimPolicyFlags {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseSingularNouns',
        '',
        Justification = 'The specification names this private helper Get-PolicyFlags.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $EffectiveXml,

        [AllowEmptyCollection()]
        [object[]] $BaseMissing = @(),

        [switch] $BackendCredentialConfigured
    )

    $document = ConvertTo-ApimPolicyXmlDocument -Xml $EffectiveXml
    if ($document.DocumentElement.LocalName -ne 'policies') {
        throw 'Effective policy XML did not contain a policies root.'
    }

    $baseMissingDetails = @(Get-ApimPolicyBaseMissingDetail `
            -BaseMissing $BaseMissing)
    $unresolvedFragments = @(Get-ApimPolicyUnresolvedFragment `
            -Document $document)
    $ipFilters = @(Get-ApimPolicyIpFilterDetail -Document $document)
    $hardcodedSecretLocations = @(Get-ApimPolicySecretLocation `
            -Document $document)
    $backendOverrides = @(Get-ApimPolicyBackendOverrideDetail `
            -Document $document)

    $callerAuthJwt = $null -ne $document.SelectSingleNode(
        "//*[local-name()='validate-jwt' or " +
        "local-name()='validate-azure-ad-token']"
    )
    $callerAuthMtls = $null -ne $document.SelectSingleNode(
        "//*[local-name()='validate-client-certificate']"
    )
    if (-not $callerAuthMtls) {
        foreach ($when in @($document.SelectNodes(
                    "//*[local-name()='choose']/*[local-name()='when']"
                ))) {
            if (([System.Xml.XmlElement] $when).GetAttribute('condition') `
                -match
                '(?i)context\s*\.\s*Request\s*\.\s*Certificate') {
                $callerAuthMtls = $true
                break
            }
        }
    }

    $throttling = $null -ne $document.SelectSingleNode(
        "//*[local-name()='rate-limit' or " +
        "local-name()='rate-limit-by-key' or " +
        "local-name()='quota' or local-name()='quota-by-key' or " +
        "local-name()='llm-token-limit' or " +
        "local-name()='azure-openai-token-limit']"
    )

    $hostRestriction = $false
    foreach ($when in @($document.SelectNodes(
                "//*[local-name()='choose']/*[local-name()='when']"
            ))) {
        $condition = ([System.Xml.XmlElement] $when).
            GetAttribute('condition')
        if (-not (Test-ApimPolicyHostCondition -Condition $condition)) {
            continue
        }
        foreach ($status in @($when.SelectNodes(
                    ".//*[local-name()='return-response']" +
                    "//*[local-name()='set-status']"
                ))) {
            if (([System.Xml.XmlElement] $status).GetAttribute('code') `
                -in @('403', '404')) {
                $hostRestriction = $true
                break
            }
        }
        if ($hostRestriction) {
            break
        }
    }

    $corsUnsafe = $false
    foreach ($cors in @($document.SelectNodes(
                "//*[local-name()='cors']"
            ))) {
        if (([System.Xml.XmlElement] $cors).
            GetAttribute('allow-credentials') -ine 'true') {
            continue
        }
        foreach ($origin in @($cors.SelectNodes(
                    "./*[local-name()='allowed-origins']" +
                    "/*[local-name()='origin']"
                ))) {
            if ($origin.InnerText.Trim() -eq '*') {
                $corsUnsafe = $true
                break
            }
        }
        if ($corsUnsafe) {
            break
        }
    }

    $backendAuth = $BackendCredentialConfigured -or
        $null -ne $document.SelectSingleNode(
        "//*[local-name()='authentication-managed-identity' or " +
        "local-name()='authentication-certificate' or " +
        "local-name()='get-authorization-context']"
    )
    $mockOrTrace = $null -ne $document.SelectSingleNode(
        "//*[local-name()='mock-response' or local-name()='trace']"
    )
    $returnsWithoutBackend = $null -ne $document.SelectSingleNode(
        "/*[local-name()='policies']/*[local-name()='inbound']" +
        "//*[local-name()='return-response' and " +
        "not(ancestor::*[local-name()='choose'])]"
    )

    return [pscustomobject] [ordered]@{
        evaluationStatus       = if ($unresolvedFragments.Count -eq 0) {
            'Complete'
        }
        else {
            'Partial'
        }
        callerAuthJwt          = $callerAuthJwt
        callerAuthMtls         = $callerAuthMtls
        throttling             = $throttling
        ipFilter               = $ipFilters.Count -gt 0
        hostRestriction        = $hostRestriction
        corsUnsafe             = $corsUnsafe
        backendAuth            = $backendAuth
        hardcodedSecret        = $hardcodedSecretLocations.Count -gt 0
        backendOverride        = $backendOverrides.Count -gt 0
        backendOverrideHttp    = @($backendOverrides |
                Where-Object insecureHttp).Count -gt 0
        mockOrTrace            = $mockOrTrace
        returnsWithoutBackend  = $returnsWithoutBackend
        baseMissing            = $baseMissingDetails.Count -gt 0
        ipFilters              = $ipFilters
        hardcodedSecretLocations = $hardcodedSecretLocations
        backendOverrides       = $backendOverrides
        baseMissingDetails     = $baseMissingDetails
        unresolvedFragments    = $unresolvedFragments
    }
}
