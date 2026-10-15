#Requires -Version 7.4

Set-StrictMode -Version Latest

foreach ($definition in @(
        @{ Id = 'APIM-POR-001'; Title = 'Developer portal not enabled or published'; Severity = 'Medium'
            Fields = @('developerPortalStatus', 'published')
            Recommendation = 'Confirm the intended portal experience and review enablement and publication through the approved deployment process.' }
        @{ Id = 'APIM-POR-002'; Title = 'Username/password sign-in or open sign-up enabled'; Severity = 'Medium'
            Fields = @('basicAuthEnabled', 'signupEnabled', 'identityProviderTypes', 'delegatedRegistration')
            Recommendation = 'Review direct basic-auth, sign-up and non-Entra identity settings against approved portal authentication requirements.' }
        @{ Id = 'APIM-POR-003'; Title = 'Product visibility differs from explicit group intent'; Severity = 'Low'
            Fields = @('productVisibility')
            Recommendation = 'Confirm explicit public/private product intent and intended group memberships before reviewing product access.' }
        @{ Id = 'APIM-POR-005'; Title = 'Legacy portal still enabled'; Severity = 'Low'
            Fields = @('legacyPortalStatus')
            Recommendation = 'Review remaining legacy portal dependencies and plan an approved transition to the developer portal.' }
    )) {
    $id = $definition.Id
    $fields = $definition.Fields
    $risk = {
        param($portal)
        switch ($id) {
            APIM-POR-001 { return $portal.developerPortalStatus -ceq 'Disabled' -or $portal.published -eq $false }
            APIM-POR-002 { return $portal.basicAuthEnabled -eq $true -or $portal.signupEnabled -eq $true -or $portal.nonEntraProviderEnabled -eq $true }
            APIM-POR-003 { return @($portal.productVisibility | Where-Object visibilityMismatch -EQ $true).Count -gt 0 }
            APIM-POR-005 { return $portal.legacyPortalStatus -ceq 'Enabled' }
        }
        throw 'Unsupported portal rule.'
    }.GetNewClosure()
    @{
        Id = $id
        Title = $definition.Title
        Pillar = 'OperationalExcellence'
        Mcsb = 'n/a'
        Severity = $definition.Severity
        Scope = 'Portal'
        Requires = @('model/portal.json')
        DataGaps = {
            param($ctx)
            if (-not (& $risk $ctx.Models.portal)) {
                foreach ($field in $fields) {
                    $unknown = switch ($field) {
                        identityProviderTypes { $null -eq $ctx.Models.portal.nonEntraProviderEnabled }
                        productVisibility {
                            $ctx.Models.portal.productVisibility.Count -eq 0 -or
                                @($ctx.Models.portal.productVisibility | Where-Object {
                                        $_.productFound -ne $true -or $null -eq $_.visibilityMismatch
                                    }).Count -gt 0
                        }
                        basicAuthEnabled {
                            $null -eq $ctx.Models.portal.basicAuthEnabled -or
                                $ctx.Models.portal.basicAuthEvidence -cne 'Direct'
                        }
                        default { $null -eq $ctx.Models.portal.$field }
                    }
                    if ($unknown -or $field -cin $ctx.Models.portal.missingInputs) {
                        "model/portal.json#$field"
                    }
                }
            }
        }.GetNewClosure()
        Test = { param($x, $ctx) $null = $ctx; [bool] (& $risk $x) }.GetNewClosure()
        Evidence = {
            param($x, $ctx)
            $null = $ctx
            $evidence = [ordered]@{
                modelStatus = $x.modelStatus
                missingInputs = @($x.missingInputs)
            }
            foreach ($field in $fields) { $evidence[$field] = $x.$field }
            if ($id -ceq 'APIM-POR-002') {
                $evidence.basicAuthDetection = $x.basicAuthEvidence
                $evidence.nonEntraProviderEnabled = $x.nonEntraProviderEnabled
            }
            return $evidence
        }.GetNewClosure()
        EvidenceText = {
            param($x, $ctx)
            $null = $x; $null = $ctx
            'Validated portal settings show a readiness gap; basic authentication uses direct enableBasicAuth evidence and missing facts remain qualified.'
        }
        Recommendation = $definition.Recommendation
        Effort = 'M'
        References = @()
        SourceFiles = @('model/portal.json')
        Enabled = $true
    }
}

@{
    Id = 'APIM-POR-004'
    Title = 'Weak API documentation'
    Pillar = 'OperationalExcellence'
    Mcsb = 'n/a'
    Severity = 'Low'
    Scope = 'Api'
    Requires = @('model/apis.json', 'model/operations.json')
    OptionalRequires = @('model/openApiQuality.json')
    DataGaps = {
        param($ctx)
        $incomplete = $false
        foreach ($api in $ctx.Models.apis) {
            $operations = @($ctx.Models.operations | Where-Object apiId -CEQ $api.apiId)
            $complete = $api.operationCount -gt 0 -and $operations.Count -eq $api.operationCount
            if (($null -ne $api.openApiScore -and $api.openApiScore -lt 70) -or
                ($complete -and @($operations | Where-Object hasDescription -EQ $true).Count /
                    $operations.Count -lt 0.8)) { return }
            if (-not $complete) { $incomplete = $true }
        }
        if ($incomplete) { 'model/operations.json#documentation' }
    }
    Test = {
        param($x, $ctx)
        $operations = @($ctx.Models.operations | Where-Object apiId -CEQ $x.apiId)
        return ($null -ne $x.openApiScore -and $x.openApiScore -lt 70) -or
            ($operations.Count -gt 0 -and $operations.Count -eq $x.operationCount -and
                @($operations | Where-Object hasDescription -EQ $true).Count / $operations.Count -lt 0.8)
    }
    Evidence = {
        param($x, $ctx)
        $operations = @($ctx.Models.operations | Where-Object apiId -CEQ $x.apiId)
        $quality = @(if ($ctx.Models.Contains('openApiQuality')) {
                $ctx.Models.openApiQuality | Where-Object apiId -CEQ $x.apiId
            })
        $evidence = [ordered]@{
            describedOperations = @($operations | Where-Object hasDescription -EQ $true).Count
            operationCount = $operations.Count
            expectedOperationCount = $x.operationCount
            openApiScore = $x.openApiScore
            method = if ($quality.Count -eq 1 -and $quality[0].status -ceq 'Scored') {
                'SpectralAndOperationDescriptionCoverage'
            } else { 'OperationDescriptionCoverage' }
        }
        if ($quality.Count -eq 1) {
            $evidence.qualityStatus = $quality[0].status
            $evidence.qualityMissingInputs = @($quality[0].missingInputs)
        }
        return $evidence
    }
    EvidenceText = {
        param($x, $ctx)
        $quality = @(if ($ctx.Models.Contains('openApiQuality')) {
                $ctx.Models.openApiQuality | Where-Object apiId -CEQ $x.apiId
            })
        if ($quality.Count -eq 1 -and $quality[0].status -ceq 'Scored') {
            'Operation-description coverage is below 80 percent or the saved, validated Spectral OpenAPI score is below 70.'
        }
        elseif ($null -ne $x.openApiScore) {
            'Operation-description coverage is below 80 percent or an available OpenAPI score is below 70.'
        }
        else {
            'Operation-description coverage is below 80 percent; an OpenAPI quality score is unavailable, so description coverage is the fallback.'
        }
    }
    Recommendation = 'Improve operation descriptions and review available OpenAPI quality evidence; description coverage is the offline fallback, not a full specification-quality scan.'
    Effort = 'M'
    References = @()
    SourceFiles = @('model/apis.json', 'model/operations.json')
    Enabled = $true
}
