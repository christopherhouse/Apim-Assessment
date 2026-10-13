#Requires -Version 7.4

Set-StrictMode -Version Latest

function ConvertTo-ApimSubscriptionDate {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context,

        [switch] $AllowNull
    )

    if ($null -eq $Value -or
        [string]::IsNullOrWhiteSpace([string] $Value)) {
        if ($AllowNull) {
            return $null
        }
        throw "$Context was missing."
    }
    $parsed = if ($Value -is [datetimeoffset]) {
        [datetimeoffset] $Value
    }
    elseif ($Value -is [datetime]) {
        [datetimeoffset] ([datetime] $Value).ToUniversalTime()
    }
    else {
        $candidate = [datetimeoffset]::MinValue
        if (-not [datetimeoffset]::TryParse(
                [string] $Value,
                [System.Globalization.CultureInfo]::InvariantCulture,
                (
                    [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
                    [System.Globalization.DateTimeStyles]::AdjustToUniversal
                ),
                [ref] $candidate
            )) {
            throw "$Context was not a valid date-time."
        }
        $candidate
    }
    return $parsed.ToUniversalTime().ToString('O')
}

function Get-ApimSubscriptionScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Scope
    )

    $normalized = $Scope.Trim().TrimEnd('/')
    if ($normalized -ieq '/apis') {
        return [pscustomobject] @{
            scopeType = 'AllApis'
            scopeTarget = $null
        }
    }
    if ($normalized -match '(?i)^/products/([^/]+)$') {
        return [pscustomobject] @{
            scopeType = 'Product'
            scopeTarget = [System.Uri]::UnescapeDataString($Matches[1])
        }
    }
    if ($normalized -match '(?i)^/apis/([^/]+)$') {
        return [pscustomobject] @{
            scopeType = 'Api'
            scopeTarget = [System.Uri]::UnescapeDataString($Matches[1])
        }
    }
    $servicePath = '(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+' +
        '/providers/Microsoft\.ApiManagement/service/[^/]+'
    if ($normalized -match (
            $servicePath + '$'
        )) {
        return [pscustomobject] @{
            scopeType = 'AllApis'
            scopeTarget = $null
        }
    }
    if ($normalized -match (
            $servicePath + '/products/([^/]+)$'
        )) {
        return [pscustomobject] @{
            scopeType = 'Product'
            scopeTarget = [System.Uri]::UnescapeDataString($Matches[1])
        }
    }
    if ($normalized -match (
            $servicePath + '/apis/([^/]+)$'
        )) {
        return [pscustomobject] @{
            scopeType = 'Api'
            scopeTarget = [System.Uri]::UnescapeDataString($Matches[1])
        }
    }
    throw 'APIM subscription scope was unsupported.'
}

function Get-ApimSubscriptionModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $SubscriptionsPayload
    )

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($subscription in Get-ApimModelCollection `
            -Payload $SubscriptionsPayload -Context 'APIM subscription payload') {
        $subscriptionId = [string] (Get-ApimModelValue `
                -InputObject $subscription -Name name `
                -Context 'APIM subscription')
        $properties = Get-ApimModelValue -InputObject $subscription `
            -Name properties -Context 'APIM subscription'
        $displayName = Get-ApimModelValue `
            -InputObject $properties -Name displayName `
            -Context 'APIM subscription properties'
        $state = [string] (Get-ApimModelValue -InputObject $properties `
                -Name state -Context 'APIM subscription properties')
        if (($null -ne $displayName -and
                    ($displayName -isnot [string] -or
                    [string]::IsNullOrWhiteSpace($displayName))) -or
                $state -notin @(
                    'active',
                    'suspended',
                    'submitted',
                    'rejected',
                    'cancelled',
                    'expired'
                )) {
            throw 'APIM subscription contained an invalid model property.'
        }
        $allowTracing = Get-ApimModelValue -InputObject $properties `
            -Name allowTracing -Context 'APIM subscription properties'
        if ($null -ne $allowTracing -and $allowTracing -isnot [bool]) {
            throw 'APIM subscription tracing setting was not Boolean.'
        }
        $ownerType = [string] (Get-ApimModelValue `
                -InputObject $properties -Name ownerType `
                -Context 'APIM subscription properties')
        if ($ownerType -notin @('BuiltIn', 'User', 'None', 'Unknown')) {
            throw 'APIM subscription contained an invalid owner type.'
        }
        $scopeValue = [string] (Get-ApimModelValue `
                -InputObject $properties -Name scope `
                -Context 'APIM subscription properties')
        $scope = Get-ApimSubscriptionScope -Scope $scopeValue
        $isBuiltInMaster = $subscriptionId -eq 'master' -and
            $scope.scopeType -eq 'AllApis'
        if (($isBuiltInMaster -and $ownerType -ne 'BuiltIn') -or
            (-not $isBuiltInMaster -and $ownerType -eq 'BuiltIn')) {
            throw 'APIM subscription built-in ownership was inconsistent.'
        }

        $expirationValue = Get-ApimModelValue -InputObject $properties `
            -Name expirationDate -Context 'APIM subscription properties' `
            -AllowMissing
        $expirationDate = ConvertTo-ApimSubscriptionDate `
            -Value $expirationValue -Context 'Subscription expiration date' `
            -AllowNull
        $createdValue = Get-ApimModelValue -InputObject $properties `
            -Name createdDate -Context 'APIM subscription properties'
        $createdDate = ConvertTo-ApimSubscriptionDate `
            -Value $createdValue -Context 'Subscription creation date' `
            -AllowNull
        $missingInputs = [System.Collections.Generic.List[string]]::new()
        $missingInputs.Add('usage')
        if ($null -eq $displayName) {
            $missingInputs.Add('displayName')
        }
        if ($null -eq $allowTracing) {
            $missingInputs.Add('allowTracing')
        }
        if ($null -eq $createdDate) {
            $missingInputs.Add('createdDate')
        }
        $flags = [System.Collections.Generic.List[string]]::new()
        if ($scope.scopeType -eq 'AllApis') {
            $flags.Add('AllApis')
        }
        if ($allowTracing) {
            $flags.Add('AllowTracing')
        }
        if ($isBuiltInMaster) {
            $flags.Add('BuiltInMaster')
        }
        if ($null -eq $expirationDate) {
            $flags.Add('NoExpiration')
        }
        if ($ownerType -eq 'None') {
            $flags.Add('OwnerMissing')
        }
        [string[]] $sortedFlags = $flags.ToArray()
        [System.Array]::Sort(
            $sortedFlags,
            [System.StringComparer]::Ordinal
        )

        $records.Add([pscustomobject] [ordered]@{
                subscriptionId = $subscriptionId
                displayName = $displayName
                scopeType = $scope.scopeType
                scopeTarget = $scope.scopeTarget
                state = $state
                ownerType = $ownerType
                createdDate = $createdDate
                expirationDate = $expirationDate
                allowTracing = $allowTracing
                calls90d = $null
                lastUsed = $null
                isBuiltInMaster = $isBuiltInMaster
                flags = $sortedFlags
                modelStatus = 'Partial'
                missingInputs = @($missingInputs | Sort-Object)
            })
    }
    return @($records | Sort-Object subscriptionId)
}

function Write-ApimSubscriptionModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Records
    )

    return Write-ApimModelSet -RunPath $RunPath `
        -Models ([ordered]@{ subscriptions = $Records })
}
