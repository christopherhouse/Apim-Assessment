#Requires -Version 7.4

Set-StrictMode -Version Latest

@(
    @{
        Id = 'APIM-GOV-001'
        Title = 'API is not assigned to a product'
        Pillar = 'OperationalExcellence'
        Mcsb = 'n/a'
        Severity = 'Medium'
        Scope = 'Api'
        Requires = @('model/apis.json')
        Test = {
            param($x, $ctx)
            $null = $ctx
            @($x.products).Count -eq 0
        }
        Evidence = {
            param($x, $ctx)
            $null = $ctx
            [ordered]@{
                path = $x.path
                products = @($x.products)
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $ctx
            "API path /$($x.path) is not assigned to any product."
        }
        Recommendation = 'Assign the API to an intentionally governed product, or document why productless publication is required.'
        Effort = 'S'
        References = @()
        SourceFiles = @(
            'raw/apis.json',
            'raw/productApis/',
            'model/apis.json'
        )
        Enabled = $true
    }
    @{
        Id = 'APIM-GOV-002'
        Title = 'API is missing an owner or team tag'
        Pillar = 'OperationalExcellence'
        Mcsb = 'n/a'
        Severity = 'Low'
        Scope = 'Api'
        Requires = @('model/apis.json')
        Test = {
            param($x, $ctx)
            $null = $ctx
            $null -eq $x.ownerTag
        }
        Evidence = {
            param($x, $ctx)
            $null = $ctx
            [ordered]@{
                path = $x.path
                ownerTag = $x.ownerTag
                tags = @($x.tags)
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $ctx
            "API path /$($x.path) has no owner or team tag."
        }
        Recommendation = 'Add the approved owner or team tag so accountability and review routing are explicit.'
        Effort = 'S'
        References = @()
        SourceFiles = @(
            'raw/apis.json',
            'raw/apiTags/',
            'model/apis.json'
        )
        Enabled = $true
    }
    @{
        Id = 'APIM-GOV-005'
        Title = 'Non-current API revision remains online'
        Pillar = 'OperationalExcellence'
        Mcsb = 'n/a'
        Severity = 'Low'
        Scope = 'Api'
        Requires = @('model/apis.json')
        Test = {
            param($x, $ctx)
            $null = $ctx
            $x.nonCurrentOnlineRevisions -gt 0
        }
        Evidence = {
            param($x, $ctx)
            $null = $ctx
            [ordered]@{
                path = $x.path
                revisionCount = $x.revisionCount
                nonCurrentOnlineRevisions = $x.nonCurrentOnlineRevisions
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $ctx
            "API path /$($x.path) has $($x.nonCurrentOnlineRevisions) non-current revision(s) online."
        }
        Recommendation = 'Review non-current online revisions and retire those that are no longer intentionally serving traffic.'
        Effort = 'S'
        References = @()
        SourceFiles = @(
            'raw/apis.json',
            'raw/apiRevisions/',
            'model/apis.json'
        )
        Enabled = $true
    }
    @{
        Id = 'APIM-GOV-006'
        Title = 'API is unversioned or belongs to a single-version version set'
        Pillar = 'OperationalExcellence'
        Mcsb = 'n/a'
        Severity = 'Low'
        Scope = 'Api'
        Requires = @('model/apis.json')
        DataGaps = {
            param($ctx)
            $knownPositive = @($ctx.Models.apis | Where-Object {
                    $null -eq $_.versionSet
                }).Count -gt 0
            $incompleteSet = $false
            foreach ($group in @(
                    $ctx.Models.apis |
                        Where-Object { $null -ne $_.versionSet } |
                        Group-Object versionSet
                )) {
                if (@($group.Group | Where-Object {
                            $null -eq $_.version
                        }).Count -gt 0) {
                    $incompleteSet = $true
                    continue
                }
                if (@($group.Group.version | Select-Object -Unique).Count -le
                    1) {
                    $knownPositive = $true
                }
            }
            if (-not $knownPositive -and $incompleteSet) {
                'model/apis.json#version'
            }
        }
        Test = {
            param($x, $ctx)
            if ($null -eq $x.versionSet) {
                return $true
            }
            $members = @($ctx.Models.apis | Where-Object {
                    $_.versionSet -eq $x.versionSet
                })
            if (@($members | Where-Object {
                        $null -eq $_.version
                    }).Count -gt 0) {
                return $false
            }
            return @($members.version | Select-Object -Unique).Count -le 1
        }
        Evidence = {
            param($x, $ctx)
            $members = if ($null -eq $x.versionSet) {
                @($x)
            }
            else {
                @($ctx.Models.apis | Where-Object {
                        $_.versionSet -eq $x.versionSet
                    })
            }
            [ordered]@{
                path = $x.path
                versionSet = $x.versionSet
                version = $x.version
                versionSetMemberCount = $members.Count
                distinctVersionCount = @(
                    $members.version |
                        Where-Object { $null -ne $_ } |
                        Select-Object -Unique
                ).Count
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $ctx
            if ($null -eq $x.versionSet) {
                return "API path /$($x.path) is not assigned to a version set."
            }
            return "API path /$($x.path) belongs to a version set with only one known version."
        }
        Recommendation = 'Review the API versioning strategy and either establish a deliberate multi-version lifecycle or document why versioning is unnecessary.'
        Effort = 'M'
        References = @()
        SourceFiles = @('raw/apis.json', 'model/apis.json')
        Enabled = $true
    }
    @{
        Id = 'APIM-GOV-008'
        Title = 'API paths use inconsistent versioning conventions'
        Pillar = 'OperationalExcellence'
        Mcsb = 'n/a'
        Severity = 'Low'
        Scope = 'Service'
        Requires = @('model/apis.json')
        Test = {
            param($x, $ctx)
            $null = $x
            $conventions = @($ctx.Models.apis | ForEach-Object {
                    if ($_.path -match '(?i)^api/v[0-9]+(?:/|$)') {
                        'ApiVersionPrefix'
                    }
                    elseif ($_.path -match '(?i)^v[0-9]+(?:/|$)') {
                        'VersionPrefix'
                    }
                    elseif ($_.path -match '(?i)(^|/)v[0-9]+(?:/|$)') {
                        'OtherVersionSegment'
                    }
                    else {
                        'NoVersionSegment'
                    }
                } | Select-Object -Unique)
            $conventions.Count -gt 1
        }
        Evidence = {
            param($x, $ctx)
            $null = $x
            $distribution = [ordered]@{
                ApiVersionPrefix = 0
                VersionPrefix = 0
                OtherVersionSegment = 0
                NoVersionSegment = 0
            }
            foreach ($api in $ctx.Models.apis) {
                $convention = if (
                    $api.path -match '(?i)^api/v[0-9]+(?:/|$)'
                ) {
                    'ApiVersionPrefix'
                }
                elseif ($api.path -match '(?i)^v[0-9]+(?:/|$)') {
                    'VersionPrefix'
                }
                elseif ($api.path -match '(?i)(^|/)v[0-9]+(?:/|$)') {
                    'OtherVersionSegment'
                }
                else {
                    'NoVersionSegment'
                }
                $distribution[$convention]++
            }
            [ordered]@{
                apiCount = @($ctx.Models.apis).Count
                conventions = @($distribution.Keys | Where-Object {
                        $distribution[$_] -gt 0
                    })
                distribution = $distribution
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $x
            $null = $ctx
            'API paths use more than one version-segment convention.'
        }
        Recommendation = 'Adopt a consistent API path and versioning convention for new APIs, and plan migrations for exceptions.'
        Effort = 'M'
        References = @()
        SourceFiles = @('raw/apis.json', 'model/apis.json')
        Enabled = $true
    }
    @{
        Id = 'APIM-GOV-010'
        Title = 'Operation policy drops inherited controls by omitting base'
        Pillar = 'OperationalExcellence'
        Mcsb = 'n/a'
        Severity = 'Medium'
        Scope = 'Operation'
        Requires = @('model/operations.json')
        DataGaps = {
            param($ctx)
            if (@($ctx.Models.operations | Where-Object {
                        $_.baseMissing
                    }).Count -eq 0 -and
                @($ctx.Models.operations | Where-Object {
                        $_.policyEvaluationStatus -eq 'Partial'
                    }).Count -gt 0) {
                'model/operations.json#baseMissing'
            }
        }
        Test = {
            param($x, $ctx)
            $null = $ctx
            $x.baseMissing
        }
        Evidence = {
            param($x, $ctx)
            $null = $ctx
            [ordered]@{
                method = $x.method
                path = $x.fullPath
                policyEvaluationStatus = $x.policyEvaluationStatus
                baseMissing = $x.baseMissing
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $ctx
            "Operation $($x.method) $($x.fullPath) has an effective policy path that omits base inheritance."
        }
        Recommendation = 'Review the effective policy path and restore base inheritance where parent controls should continue to apply.'
        Effort = 'S'
        References = @()
        SourceFiles = @('raw/policies/', 'model/operations.json')
        Enabled = $true
    }
)
