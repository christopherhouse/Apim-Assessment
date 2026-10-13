#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimSubscriptionProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Context,

        [switch] $AllowMissing
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) {
        return $property.Value
    }
    if ($AllowMissing) {
        return $null
    }
    throw "$Context did not contain '$Name'."
}

function Get-ApimSubscriptionOwnerType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SubscriptionId,

        [AllowNull()]
        [string] $OwnerId
    )

    if ($SubscriptionId -eq 'master') {
        return 'BuiltIn'
    }
    if ([string]::IsNullOrWhiteSpace($OwnerId)) {
        return 'None'
    }
    if ($OwnerId -match '(?i)/users/[^/]+/?$') {
        return 'User'
    }
    return 'Unknown'
}

function ConvertTo-ApimCollectedSubscriptionDate {
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

function ConvertTo-ApimCollectedSubscription {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Resource
    )

    $subscriptionId = [string] (Get-ApimSubscriptionProperty `
            -InputObject $Resource -Name name -Context 'APIM subscription')
    if ([string]::IsNullOrWhiteSpace($subscriptionId)) {
        throw 'APIM subscription contained an invalid resource name.'
    }
    $properties = Get-ApimSubscriptionProperty -InputObject $Resource `
        -Name properties -Context 'APIM subscription'
    $displayValue = Get-ApimSubscriptionProperty `
            -InputObject $properties -Name displayName `
            -Context 'APIM subscription properties' -AllowMissing
    if ($null -ne $displayValue -and $displayValue -isnot [string]) {
        throw "APIM subscription field 'displayName' was not a string."
    }
    $displayName = if ([string]::IsNullOrWhiteSpace([string] $displayValue)) {
        $null
    }
    else {
        [string] $displayValue
    }
    $scope = [string] (Get-ApimSubscriptionProperty -InputObject $properties `
            -Name scope -Context 'APIM subscription properties')
    $state = [string] (Get-ApimSubscriptionProperty -InputObject $properties `
            -Name state -Context 'APIM subscription properties')
    if ([string]::IsNullOrWhiteSpace($scope) -or
        [string]::IsNullOrWhiteSpace($state)) {
        throw 'APIM subscription contained an invalid required property.'
    }

    $allowTracing = Get-ApimSubscriptionProperty `
        -InputObject $properties -Name allowTracing `
        -Context 'APIM subscription properties' -AllowMissing
    if ($null -ne $allowTracing -and $allowTracing -isnot [bool]) {
        throw "APIM subscription field 'allowTracing' was not Boolean."
    }
    $createdValue = Get-ApimSubscriptionProperty `
            -InputObject $properties -Name createdDate `
            -Context 'APIM subscription properties' -AllowMissing
    $createdDate = ConvertTo-ApimCollectedSubscriptionDate `
        -Value $createdValue -Context 'Subscription creation date' -AllowNull
    $expirationValue = Get-ApimSubscriptionProperty `
        -InputObject $properties -Name expirationDate `
        -Context 'APIM subscription properties' -AllowMissing
    $expirationDate = ConvertTo-ApimCollectedSubscriptionDate `
        -Value $expirationValue -Context 'Subscription expiration date' `
        -AllowNull
    $ownerId = [string] (Get-ApimSubscriptionProperty `
            -InputObject $properties -Name ownerId `
            -Context 'APIM subscription properties' -AllowMissing)

    return [pscustomobject] [ordered]@{
        name = $subscriptionId
        properties = [pscustomobject] [ordered]@{
            displayName = $displayName
            scope = $scope
            state = $state
            ownerType = Get-ApimSubscriptionOwnerType `
                -SubscriptionId $subscriptionId -OwnerId $ownerId
            createdDate = $createdDate
            expirationDate = $expirationDate
            allowTracing = $allowTracing
        }
    }
}

function Invoke-ApimSubscriptionCollector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunPath,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Environment
    )

    $collectorName = 'Subscriptions'
    $logPath = Join-Path $RunPath 'logs/run.log'
    $resourcePath = Get-ApimServiceResourcePath -Environment $Environment
    $uri = "${resourcePath}/subscriptions?api-version=2024-05-01"
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Set-RunStageStatus -RunPath $RunPath -Stage collect -Status InProgress
    Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
        -Status InProgress
    try {
        $response = Invoke-ApimArm -Uri $uri -LogPath $logPath
        if ($null -eq $response) {
            throw 'APIM subscription response was empty.'
        }

        $subscriptionNames = @(Get-ApimCollectionResourceName `
                -Payload $response -CollectionName 'APIM subscription')
        $resources = @($response.value)
        $resourceMap = [System.Collections.Generic.Dictionary[
            string,
            object
        ]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($resource in $resources) {
            $resourceMap.Add([string] $resource.name, $resource)
        }

        $subscriptions = @(
            foreach ($subscriptionName in $subscriptionNames) {
                ConvertTo-ApimCollectedSubscription `
                    -Resource $resourceMap[$subscriptionName]
            }
        )
        $payload = [pscustomobject] [ordered]@{
            value = $subscriptions
        }
        $filePath = Write-RunFile -RunPath $RunPath `
            -RelativePath 'raw/subscriptions.json' `
            -InputObject $payload -Depth 50

        $stopwatch.Stop()
        Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
            -Status Completed -Items $subscriptions.Count `
            -DurationSec $stopwatch.Elapsed.TotalSeconds
        Write-RunLog -Path $logPath -Level Info -Collector $collectorName `
            -Message 'Collected allowlisted APIM subscription metadata.'
        return $filePath
    }
    catch {
        $stopwatch.Stop()
        Set-RunCollectorStatus -RunPath $RunPath -Name $collectorName `
            -Status Failed -Errors 1 `
            -DurationSec $stopwatch.Elapsed.TotalSeconds
        Add-RunWarning -RunPath $RunPath `
            -Message 'Subscription collector failed; see the restricted run log.'
        Write-RunLog -Path $logPath -Level Error -Collector $collectorName `
            -Message 'APIM subscription collection failed.'
        throw
    }
}
