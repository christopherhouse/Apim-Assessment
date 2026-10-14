#Requires -Version 7.4

Set-StrictMode -Version Latest

function New-SyntheticReferencePolicy {
    <#
    .SYNOPSIS
    Creates a sanitized synthetic policy and structural evidence, never raw XML.
    .NOTES
    Dot-source in ApimAssessment module scope to use its existing private helpers.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory synthetic constructor; performs no writes.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 60)]
        [int] $Index
    )

    $apiId = 'api-{0:d3}' -f $Index
    $inbound = '<base/>'
    if ($Index -gt 7) {
        $inbound += '<validate-jwt header-name="Authorization" />' +
            '<rate-limit calls="100" renewal-period="60" />'
    }
    if ($Index -le 2) {
        # Artificial candidate exists only in memory, before detection/redaction.
        $candidate = @('synthetic', 'credential', $Index) -join '-'
        $inbound += '<set-header name="Authorization" exists-action="override">' +
            "<value>$candidate</value></set-header>"
    }
    $backend = if ($Index -le 3) { '<forward-request/>' }
    else { '<base/>' }
    $xml = "<policies><inbound data-scope=`"api:$apiId`">$inbound</inbound>" +
        "<backend>$backend</backend><outbound><base/></outbound>" +
        '<on-error><base/></on-error></policies>'

    # Detect before Protect, matching collection's safety boundary.
    $locations = @(Get-ApimPolicySecretLocation -Document (
            ConvertTo-ApimPolicyXmlDocument -Xml $xml
        ))
    $protected = Protect-ApimPolicyXml -Xml $xml
    if (($locations -join '|') -cne ($protected.SecretLocations -join '|')) {
        throw 'Synthetic policy detection and redaction evidence differed.'
    }
    $baseMissing = @(
        if ($Index -le 3) {
            [pscustomobject]@{ scope = "api:$apiId"; section = 'backend' }
        }
    )
    $flags = Get-ApimPolicyFlags -EffectiveXml $protected.Xml `
        -BaseMissing $baseMissing
    return [pscustomobject][ordered]@{
        apiId = $apiId
        xml = $protected.Xml
        secretLocations = $locations
        flags = $flags
    }
}

function New-SyntheticReferenceModelSet {
    <#
    .SYNOPSIS
    Returns the ten registered synthetic models; performs no writes or calls.
    .PARAMETER WithUsage
    Supplies explicit artificial API/operation/route usage, including 11 unused
    APIs. Subscription usage remains unavailable in both scenarios.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure synthetic model constructor; reads fixtures without mutation.'
    )]
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param(
        [switch] $WithUsage
    )

    # Cloning is deliberately confined to this test-data generator, not runtime
    # package construction. Read fresh objects on every call; never mutate files.
    $modelRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'model'
    $models = [ordered]@{}
    foreach ($name in @(
            'service', 'apis', 'operations', 'policyMatrix', 'subscriptions',
            'namedValues', 'backends', 'certificates', 'network', 'exposure'
        )) {
        $fileName = if ($name -eq 'apis') { 'apis.exposure.json' }
        else { "$name.json" }
        $models[$name] = Get-Content -LiteralPath (
            Join-Path $modelRoot $fileName
        ) -Raw | ConvertFrom-Json -AsHashtable -Depth 100 -NoEnumerate
    }
    $templates = @{
        apis = ConvertTo-Json -InputObject $models.apis[1] -Depth 100
        operations = ConvertTo-Json -InputObject $models.operations[1] -Depth 100
        policyMatrix = ConvertTo-Json -InputObject $models.policyMatrix[1] -Depth 100
        exposure = ConvertTo-Json -InputObject $models.exposure[1] -Depth 100
    }
    $rows = @{
        apis = [System.Collections.Generic.List[object]]::new()
        operations = [System.Collections.Generic.List[object]]::new()
        policyMatrix = [System.Collections.Generic.List[object]]::new()
        exposure = [System.Collections.Generic.List[object]]::new()
    }
    for ($index = 1; $index -le 60; $index++) {
        $policy = New-SyntheticReferencePolicy -Index $index
        $flags = $policy.flags
        $apiId = $policy.apiId
        $products = @(if ($index -le 46) { 'internal' })
        $records = @{}
        foreach ($name in $templates.Keys) {
            $records[$name] = ConvertFrom-Json -InputObject $templates[$name] `
                -AsHashtable -Depth 100
            $records[$name].apiId = $apiId
        }

        $api = $records.apis
        $api.displayName = 'Synthetic API {0:d3}' -f $index
        $api.path = $apiId
        $api.products = $products
        $api.tags = @('synthetic')
        $api.versionSet = $apiId
        $api.revisionCount = 1
        $api.nonCurrentOnlineRevisions = 0
        $api.callerAuth = if ($flags.callerAuthJwt) { 'Entra/JWT' }
        else { 'SubscriptionKeyOnly' }

        $operation = $records.operations
        $operation.operationId = 'get-item'
        $operation.fullPath = "/$apiId"
        $operation.products = $products
        $operation.callerAuthJwt = $flags.callerAuthJwt
        $operation.callerAuthModes = @(
            if ($flags.callerAuthJwt) { 'Entra/JWT' }
        )
        $operation.hasUnauthenticatedPolicyPath = -not $flags.callerAuthJwt
        $operation.throttlingAllPaths = $flags.throttling
        foreach ($name in @('throttling', 'hardcodedSecret', 'baseMissing')) {
            $api[$name] = $flags.$name
            $operation[$name] = $flags.$name
        }

        $matrix = $records.policyMatrix
        $matrix.callerAuth = if ($flags.callerAuthJwt) { 'Pass' } else { 'Fail' }
        $matrix.rateLimit = if ($flags.throttling) { 'Pass' } else { 'Fail' }
        $matrix.noHardcodedSecret = if ($flags.hardcodedSecret) {
            'Fail'
        }
        else { 'Pass' }
        $matrix.basePresent = if ($flags.baseMissing) { 'Fail' } else { 'Pass' }

        $route = $records.exposure
        $route.routeKey = 'agw-synthetic-prod|public-https|' +
            "api.synthetic.invalid|/*|$apiId"
        if ($WithUsage) {
            $calls = if ($index -ge 50) { 0 } else { 100 + $index }
            $api.calls90d = $calls
            $operation.calls90d = $calls
            $api.callsViaAppGw = $calls
            $api.callsInternal = 0
            $api.lastCall = if ($calls -gt 0) {
                [datetime]::new(2026, 10, 1, 0, 0, 0, [DateTimeKind]::Utc)
            }
            else { $null }
            $route.callsViaAppGw = $calls
            $route.callsInternal = 0
            $route.exposure = if ($calls -gt 0) {
                'ExternalInUse'
            }
            else { 'ExternalUnintended' }
            $api.exposure = $route.exposure
            # The edge is still assumed, not verified: retain Medium confidence.
            $route.modelStatus = 'Complete'
            foreach ($record in @($api, $operation, $route)) {
                $record.missingInputs = @(
                    $record.missingInputs | Where-Object { $_ -ne 'usage' }
                )
            }
        }
        foreach ($name in $rows.Keys) {
            $rows[$name].Add($records[$name])
        }
    }
    foreach ($name in $rows.Keys) {
        $models[$name] = $rows[$name].ToArray()
    }
    $models.subscriptions[0].scopeTarget = 'api-001'
    return $models
}
