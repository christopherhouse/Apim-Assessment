#Requires -Version 7.4

Set-StrictMode -Version Latest

function ConvertTo-ApimPolicyMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context
    )

    $result = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($key in $InputObject.Keys) {
        $name = [string] $key
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw "$Context contained an invalid name."
        }
        if ($result.ContainsKey($name)) {
            throw "$Context contained duplicate names."
        }
        $result.Add($name, $InputObject[$key])
    }
    return ,$result
}

function Format-ApimPolicyNode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlNode] $Node
    )

    foreach ($child in @($Node.ChildNodes)) {
        if ($child.NodeType -eq [System.Xml.XmlNodeType]::Comment -or
            ($child.NodeType -in @(
                    [System.Xml.XmlNodeType]::Text,
                    [System.Xml.XmlNodeType]::Whitespace,
                    [System.Xml.XmlNodeType]::SignificantWhitespace
                ) -and [string]::IsNullOrWhiteSpace([string] $child.Value))) {
            $null = $Node.RemoveChild($child)
            continue
        }
        if ($child.NodeType -eq [System.Xml.XmlNodeType]::Element) {
            Format-ApimPolicyNode -Node $child
        }
    }
}

function ConvertTo-ApimScopedPolicyElement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlElement] $Element,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Scope
    )

    $Element.SetAttribute('data-scope', $Scope)
    foreach ($child in @($Element.ChildNodes)) {
        if ($child.NodeType -eq [System.Xml.XmlNodeType]::Element) {
            ConvertTo-ApimScopedPolicyElement -Element $child -Scope $Scope
        }
    }
}

function ConvertTo-ApimAttributedPolicyDocument {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string] $Xml,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Scope
    )

    if ([string]::IsNullOrWhiteSpace($Xml)) {
        return $null
    }

    $document = ConvertTo-ApimPolicyXmlDocument -Xml $Xml
    if ($document.DocumentElement.LocalName -ne 'policies') {
        throw 'Policy layer XML did not contain a policies root.'
    }
    Format-ApimPolicyNode -Node $document

    $knownSections = @('inbound', 'backend', 'outbound', 'on-error')
    foreach ($child in @($document.DocumentElement.ChildNodes)) {
        if ($child.NodeType -ne [System.Xml.XmlNodeType]::Element -or
            $child.LocalName -notin $knownSections) {
            throw 'Policy layer XML contained an unsupported root child.'
        }
    }
    foreach ($sectionName in $knownSections) {
        $sections = @($document.DocumentElement.SelectNodes(
                "./*[local-name()='$sectionName']"
            ))
        if ($sections.Count -gt 1) {
            throw 'Policy layer XML contained a duplicate policy section.'
        }
        if ($sections.Count -eq 1) {
            ConvertTo-ApimScopedPolicyElement -Element $sections[0] `
                -Scope $Scope
        }
    }
    return ,$document
}

function Get-ApimEmptyPolicyDocument {
    [CmdletBinding()]
    param()

    $document = [System.Xml.XmlDocument]::new()
    $document.PreserveWhitespace = $false
    $document.LoadXml(
        '<policies><inbound/><backend/><outbound/><on-error/></policies>'
    )
    return ,$document
}

function Merge-ApimPolicyLayer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlDocument] $Parent,

        [AllowNull()]
        [System.Xml.XmlDocument] $Child,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Scope,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]] $BaseMissing,

        [switch] $RecordMissingBase
    )

    if ($null -eq $Child) {
        return
    }

    foreach ($sectionName in @('inbound', 'backend', 'outbound', 'on-error')) {
        $childSection = $Child.DocumentElement.SelectSingleNode(
            "./*[local-name()='$sectionName']"
        )
        if ($null -eq $childSection) {
            continue
        }
        $parentSection = $Parent.DocumentElement.SelectSingleNode(
            "./*[local-name()='$sectionName']"
        )
        if ($null -eq $parentSection) {
            throw 'Effective policy document was missing a required section.'
        }

        $importedSection = $Parent.ImportNode($childSection, $true)
        $baseNodes = @($importedSection.ChildNodes | Where-Object {
                $_.NodeType -eq [System.Xml.XmlNodeType]::Element -and
                $_.LocalName -eq 'base'
            })
        if ($baseNodes.Count -gt 1) {
            throw 'Policy section contained more than one base element.'
        }
        if ($baseNodes.Count -eq 1) {
            $baseNode = $baseNodes[0]
            foreach ($parentChild in @($parentSection.ChildNodes)) {
                $clone = $parentChild.CloneNode($true)
                $null = $importedSection.InsertBefore($clone, $baseNode)
            }
            $null = $importedSection.RemoveChild($baseNode)
        }
        elseif ($RecordMissingBase) {
            $BaseMissing.Add([pscustomobject] [ordered]@{
                    scope   = $Scope
                    section = $sectionName
                })
        }

        $null = $Parent.DocumentElement.ReplaceChild(
            $importedSection,
            $parentSection
        )
    }
}

function ConvertTo-ApimFragmentDocumentMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Fragments
    )

    $inputMap = ConvertTo-ApimPolicyMap -InputObject $Fragments `
        -Context 'Policy fragment map'
    $result = [System.Collections.Generic.Dictionary[
        string,
        System.Xml.XmlDocument
    ]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $inputMap.GetEnumerator()) {
        if ($null -eq $entry.Value -or
            [string]::IsNullOrWhiteSpace([string] $entry.Value)) {
            throw 'Policy fragment XML was empty.'
        }
        $document = ConvertTo-ApimPolicyXmlDocument -Xml ([string] $entry.Value)
        if ($document.DocumentElement.LocalName -ne 'fragment') {
            throw 'Policy fragment XML did not contain a fragment root.'
        }
        Format-ApimPolicyNode -Node $document
        if ($null -ne $document.DocumentElement.SelectSingleNode(
                ".//*[local-name()='base']"
            )) {
            throw 'Policy fragment XML contained a prohibited base element.'
        }
        $result.Add($entry.Key, $document)
    }
    return ,$result
}

function Add-ApimFragmentIssue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]] $Issues,

        [Parameter(Mandatory)]
        [ValidateSet('Cycle', 'DepthExceeded', 'Missing', 'MissingId')]
        [string] $Type,

        [AllowEmptyString()]
        [string] $FragmentId,

        [Parameter(Mandatory)]
        [string[]] $Path
    )

    $Issues.Add([pscustomobject] [ordered]@{
            type       = $Type
            fragmentId = $FragmentId
            path       = $Path -join '>'
        })
}

function Expand-ApimPolicyInclude {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlElement] $Include,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.Dictionary[
            string,
            System.Xml.XmlDocument
        ]] $FragmentMap,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]] $Issues,

        [Parameter(Mandatory)]
        [ValidateRange(1, 100)]
        [int] $Depth,

        [Parameter(Mandatory)]
        [ValidateRange(1, 20)]
        [int] $MaxDepth,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Stack
    )

    $fragmentId = $Include.GetAttribute('fragment-id')
    if ([string]::IsNullOrWhiteSpace($fragmentId)) {
        Add-ApimFragmentIssue -Issues $Issues -Type MissingId `
            -FragmentId '' -Path $Stack
        $Include.SetAttribute('data-fragment-status', 'MissingId')
        return
    }

    $path = @($Stack) + $fragmentId
    foreach ($ancestorId in $Stack) {
        if ($ancestorId.Equals(
                $fragmentId,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
            Add-ApimFragmentIssue -Issues $Issues -Type Cycle `
                -FragmentId $fragmentId -Path $path
            $Include.SetAttribute('data-fragment-status', 'Cycle')
            return
        }
    }
    if ($Depth -gt $MaxDepth) {
        Add-ApimFragmentIssue -Issues $Issues -Type DepthExceeded `
            -FragmentId $fragmentId -Path $path
        $Include.SetAttribute('data-fragment-status', 'DepthExceeded')
        return
    }
    if (-not $FragmentMap.ContainsKey($fragmentId)) {
        Add-ApimFragmentIssue -Issues $Issues -Type Missing `
            -FragmentId $fragmentId -Path $path
        $Include.SetAttribute('data-fragment-status', 'Missing')
        return
    }

    $parent = $Include.ParentNode
    if ($null -eq $parent) {
        throw 'Policy fragment include was detached from the effective policy.'
    }
    $document = $Include.OwnerDocument
    $insertedNodes = [System.Collections.Generic.List[System.Xml.XmlElement]]::new()
    foreach ($fragmentChild in @(
            $FragmentMap[$fragmentId].DocumentElement.ChildNodes
        )) {
        if ($fragmentChild.NodeType -ne [System.Xml.XmlNodeType]::Element) {
            throw 'Policy fragment contained unsupported root content.'
        }
        $imported = [System.Xml.XmlElement] $document.ImportNode(
            $fragmentChild,
            $true
        )
        ConvertTo-ApimScopedPolicyElement -Element $imported `
            -Scope "fragment:$fragmentId"
        $null = $parent.InsertBefore($imported, $Include)
        $insertedNodes.Add($imported)
    }
    $null = $parent.RemoveChild($Include)

    foreach ($insertedNode in $insertedNodes) {
        $nestedIncludes = [System.Collections.Generic.List[
            System.Xml.XmlElement
        ]]::new()
        if ($insertedNode.LocalName -eq 'include-fragment') {
            $nestedIncludes.Add($insertedNode)
        }
        foreach ($nested in @($insertedNode.SelectNodes(
                    ".//*[local-name()='include-fragment']"
                ))) {
            $nestedIncludes.Add([System.Xml.XmlElement] $nested)
        }
        foreach ($nestedInclude in $nestedIncludes) {
            if ($null -ne $nestedInclude.ParentNode -and
                -not $nestedInclude.HasAttribute('data-fragment-status')) {
                Expand-ApimPolicyInclude -Include $nestedInclude `
                    -FragmentMap $FragmentMap -Issues $Issues `
                    -Depth ($Depth + 1) -MaxDepth $MaxDepth -Stack $path
            }
        }
    }
}

function Expand-ApimPolicyFragment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlDocument] $Document,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.Dictionary[
            string,
            System.Xml.XmlDocument
        ]] $FragmentMap,

        [Parameter(Mandatory)]
        [ValidateRange(1, 20)]
        [int] $MaxDepth
    )

    $issues = [System.Collections.Generic.List[object]]::new()
    $includeNodes = @($Document.SelectNodes(
            "//*[local-name()='include-fragment']"
        ))
    foreach ($includeNode in $includeNodes) {
        if ($null -ne $includeNode.ParentNode -and
            -not $includeNode.HasAttribute('data-fragment-status')) {
            Expand-ApimPolicyInclude `
                -Include ([System.Xml.XmlElement] $includeNode) `
                -FragmentMap $FragmentMap -Issues $issues `
                -Depth 1 -MaxDepth $MaxDepth -Stack @()
        }
    }

    return @($issues | Sort-Object type, fragmentId, path)
}

function Merge-ApimPolicy {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string] $GlobalPolicy,

        [System.Collections.IDictionary] $ProductPolicies = @{},

        [AllowEmptyCollection()]
        [string[]] $ProductNames = @(),

        [AllowNull()]
        [string] $ApiPolicy,

        [AllowNull()]
        [string] $OperationPolicy,

        [System.Collections.IDictionary] $Fragments = @{},

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ApiName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $OperationName,

        [ValidateRange(1, 20)]
        [int] $FragmentMaxDepth = 5
    )

    $productPolicyMap = ConvertTo-ApimPolicyMap `
        -InputObject $ProductPolicies -Context 'Product policy map'
    $fragmentMap = ConvertTo-ApimFragmentDocumentMap -Fragments $Fragments

    $uniqueProductNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $sortedProductNames = [System.Collections.Generic.List[string]]::new()
    foreach ($productName in $ProductNames) {
        if ([string]::IsNullOrWhiteSpace($productName)) {
            throw 'Product names contained an invalid value.'
        }
        if (-not $uniqueProductNames.Add($productName)) {
            throw 'Product names contained duplicate values.'
        }
        $sortedProductNames.Add($productName)
    }
    [string[]] $productNameArray = $sortedProductNames.ToArray()
    [System.Array]::Sort(
        $productNameArray,
        [System.StringComparer]::Ordinal
    )

    $productPaths = [System.Collections.Generic.List[object]]::new()
    if ($productNameArray.Count -eq 0) {
        $productPaths.Add($null)
    }
    else {
        foreach ($productName in $productNameArray) {
            $productPaths.Add($productName)
        }
    }

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($productName in $productPaths) {
        $baseMissing = [System.Collections.Generic.List[object]]::new()
        $effective = Get-ApimEmptyPolicyDocument

        $globalDocument = ConvertTo-ApimAttributedPolicyDocument `
            -Xml $GlobalPolicy -Scope 'global'
        Merge-ApimPolicyLayer -Parent $effective -Child $globalDocument `
            -Scope 'global' -BaseMissing $baseMissing

        if ($null -ne $productName) {
            $productXml = if ($productPolicyMap.ContainsKey($productName)) {
                [string] $productPolicyMap[$productName]
            }
            else {
                $null
            }
            $productScope = "product:$productName"
            $productDocument = ConvertTo-ApimAttributedPolicyDocument `
                -Xml $productXml -Scope $productScope
            Merge-ApimPolicyLayer -Parent $effective -Child $productDocument `
                -Scope $productScope -BaseMissing $baseMissing `
                -RecordMissingBase
        }

        $apiScope = "api:$ApiName"
        $apiDocument = ConvertTo-ApimAttributedPolicyDocument `
            -Xml $ApiPolicy -Scope $apiScope
        Merge-ApimPolicyLayer -Parent $effective -Child $apiDocument `
            -Scope $apiScope -BaseMissing $baseMissing -RecordMissingBase

        $operationScope = "operation:$ApiName|$OperationName"
        $operationDocument = ConvertTo-ApimAttributedPolicyDocument `
            -Xml $OperationPolicy -Scope $operationScope
        Merge-ApimPolicyLayer -Parent $effective -Child $operationDocument `
            -Scope $operationScope -BaseMissing $baseMissing `
            -RecordMissingBase

        $fragmentIssues = @(Expand-ApimPolicyFragment `
                -Document $effective -FragmentMap $fragmentMap `
                -MaxDepth $FragmentMaxDepth)
        $xml = $effective.OuterXml
        $normalizedXml = ConvertTo-ApimNormalizedPolicyXml -Xml $xml
        $results.Add([pscustomobject] [ordered]@{
                product        = $productName
                apiId          = $ApiName
                operationId    = $OperationName
                effectiveXml   = $xml
                normalizedXml  = $normalizedXml
                sha256         = Get-ApimPolicySha256 -Xml $xml
                baseMissing    = @($baseMissing |
                        Sort-Object scope, section)
                fragmentIssues = $fragmentIssues
            })
    }

    return $results.ToArray()
}

function Merge-ApimProductPolicyFlag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object[]] $ProductFlags,

        [AllowEmptyCollection()]
        [string[]] $RiskFlag = @(),

        [AllowEmptyCollection()]
        [string[]] $ControlFlag = @()
    )

    if ($ProductFlags.Count -eq 0) {
        throw 'At least one product policy flag set is required.'
    }

    $riskNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $controlNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($name in $RiskFlag) {
        if ([string]::IsNullOrWhiteSpace($name) -or
            -not $riskNames.Add($name)) {
            throw 'Risk flag names contained an invalid or duplicate value.'
        }
    }
    foreach ($name in $ControlFlag) {
        if ([string]::IsNullOrWhiteSpace($name) -or
            -not $controlNames.Add($name) -or
            $riskNames.Contains($name)) {
            throw 'Control flag names contained an invalid or duplicate value.'
        }
    }

    [string[]] $sortedRiskNames = @($riskNames)
    [string[]] $sortedControlNames = @($controlNames)
    [System.Array]::Sort($sortedRiskNames, [System.StringComparer]::Ordinal)
    [System.Array]::Sort($sortedControlNames, [System.StringComparer]::Ordinal)

    $result = [ordered]@{}
    foreach ($name in $sortedRiskNames + $sortedControlNames) {
        $values = [System.Collections.Generic.List[bool]]::new()
        foreach ($flagSet in $ProductFlags) {
            $value = $null
            if ($flagSet -is [System.Collections.IDictionary] -and
                $flagSet.Contains($name)) {
                $value = $flagSet[$name]
            }
            else {
                $property = $flagSet.PSObject.Properties[$name]
                if ($null -ne $property) {
                    $value = $property.Value
                }
            }
            if ($value -isnot [bool]) {
                throw "Policy flag '$name' was missing or was not Boolean."
            }
            $values.Add([bool] $value)
        }

        if ($riskNames.Contains($name)) {
            $result[$name] = $values.Contains($true)
        }
        else {
            $result[$name] = -not $values.Contains($false)
        }
    }
    return [pscustomobject] $result
}
