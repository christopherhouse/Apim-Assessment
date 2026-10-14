#Requires -Version 7.4

Set-StrictMode -Version Latest

@(
    @{
        Id = 'APIM-SEC-001'
        Title = 'Legacy TLS protocol or cipher is enabled'
        Pillar = 'Security'
        Mcsb = 'DP-3'
        Severity = 'Medium'
        Scope = 'Service'
        Requires = @('model/service.json')
        DataGaps = {
            param($ctx)
            if ($null -eq $ctx.Models.service.legacyTlsEnabled) {
                'model/service.json#legacyTlsEnabled'
            }
        }
        Test = {
            param($x, $ctx)
            $null = $x
            $ctx.Models.service.legacyTlsEnabled -eq $true
        }
        Evidence = {
            param($x, $ctx)
            $null = $x
            [ordered]@{
                legacyTlsEnabled = (
                    $ctx.Models.service.legacyTlsEnabled
                )
                enabledLegacyTlsControls = @(
                    $ctx.Models.service.enabledLegacyTlsControls
                )
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $x
            "Legacy TLS controls are enabled: $(
                @($ctx.Models.service.enabledLegacyTlsControls) -join ', '
            )."
        }
        Recommendation = 'Review client and backend compatibility, then disable legacy TLS protocols and the 3DES cipher where the service tier supports configuration.'
        Effort = 'M'
        References = @()
        SourceFiles = @('raw/service.json', 'model/service.json')
        Enabled = $true
    }
    @{
        Id = 'APIM-SEC-002'
        Title = 'Minimum management API version is not enforced'
        Pillar = 'Security'
        Mcsb = 'AM-1'
        Severity = 'Low'
        Scope = 'Service'
        Requires = @('model/service.json')
        Test = {
            param($x, $ctx)
            $null = $x
            $null -eq $ctx.Models.service.minApiVersion
        }
        Evidence = {
            param($x, $ctx)
            $null = $x
            [ordered]@{
                minApiVersion = $ctx.Models.service.minApiVersion
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $x
            $null = $ctx
            'The APIM service does not enforce a minimum management API version.'
        }
        Recommendation = 'Define and maintain an approved minimum management API version for APIM control-plane requests.'
        Effort = 'S'
        References = @()
        SourceFiles = @('raw/service.json', 'model/service.json')
        Enabled = $true
    }
    @{
        Id = 'APIM-SEC-003'
        Title = 'Reachable API has no caller authentication beyond a subscription key'
        Pillar = 'Security'
        Mcsb = 'IM-1'
        Severity = 'High'
        Scope = 'Api'
        Requires = @('model/apis.json')
        DataGaps = {
            param($ctx)
            $targets = @($ctx.Models.apis | Where-Object {
                    $_.reachability -eq 'Reachable'
                })
            if (@($targets | Where-Object {
                        $_.callerAuth -eq 'SubscriptionKeyOnly'
                    }).Count -eq 0 -and
                @($targets | Where-Object {
                        $null -eq $_.callerAuth
                    }).Count -gt 0) {
                'model/apis.json#callerAuth'
            }
        }
        Applies = {
            param($x, $ctx)
            $null = $ctx
            $x.reachability -eq 'Reachable'
        }
        Test = {
            param($x, $ctx)
            $null = $ctx
            $x.callerAuth -eq 'SubscriptionKeyOnly'
        }
        Evidence = {
            param($x, $ctx)
            $null = $ctx
            [ordered]@{
                path = $x.path
                reachability = $x.reachability
                exposure = $x.exposure
                callerAuth = $x.callerAuth
                subscriptionRequired = $x.subscriptionRequired
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $ctx
            "Reachable API path /$($x.path) relies on a subscription key without stronger caller authentication."
        }
        Recommendation = 'Review caller identity requirements and use an appropriate token or client-certificate validation control where needed; retain subscription keys for identification or metering only.'
        Effort = 'M'
        References = @()
        SourceFiles = @('raw/apis.json', 'raw/policies/', 'model/apis.json')
        Enabled = $true
    }
    @{
        Id = 'APIM-SEC-004'
        Title = 'Reachable API requires neither a subscription nor caller authentication'
        Pillar = 'Security'
        Mcsb = 'IM-1'
        Severity = 'High'
        Scope = 'Api'
        Requires = @('model/apis.json')
        DataGaps = {
            param($ctx)
            $targets = @($ctx.Models.apis | Where-Object {
                    $_.reachability -eq 'Reachable' -and
                    -not $_.subscriptionRequired
                })
            if (@($targets | Where-Object {
                        $_.callerAuth -eq 'None'
                    }).Count -eq 0 -and
                @($targets | Where-Object {
                        $null -eq $_.callerAuth
                    }).Count -gt 0) {
                'model/apis.json#callerAuth'
            }
        }
        Applies = {
            param($x, $ctx)
            $null = $ctx
            $x.reachability -eq 'Reachable' -and
                -not $x.subscriptionRequired
        }
        Test = {
            param($x, $ctx)
            $null = $ctx
            $x.callerAuth -eq 'None'
        }
        Evidence = {
            param($x, $ctx)
            $null = $ctx
            [ordered]@{
                path = $x.path
                reachability = $x.reachability
                exposure = $x.exposure
                callerAuth = $x.callerAuth
                subscriptionRequired = $x.subscriptionRequired
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $ctx
            "Reachable API path /$($x.path) requires neither a subscription nor caller authentication."
        }
        Recommendation = 'Confirm that anonymous access is intended; otherwise require an appropriate subscription and caller-authentication control.'
        Effort = 'M'
        References = @()
        SourceFiles = @('raw/apis.json', 'raw/policies/', 'model/apis.json')
        Enabled = $true
    }
    @{
        Id = 'APIM-SEC-005'
        Title = 'Active subscription is scoped to all APIs'
        Pillar = 'Security'
        Mcsb = 'PA-7'
        Severity = 'High'
        Scope = 'Subscription'
        Requires = @('model/subscriptions.json')
        Applies = {
            param($x, $ctx)
            $null = $ctx
            $x.state -eq 'active'
        }
        Test = {
            param($x, $ctx)
            $null = $ctx
            $x.scopeType -eq 'AllApis'
        }
        Evidence = {
            param($x, $ctx)
            $null = $ctx
            [ordered]@{
                scopeType = $x.scopeType
                state = $x.state
                ownerType = $x.ownerType
                isBuiltInMaster = $x.isBuiltInMaster
                expirationDate = $x.expirationDate
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $ctx
            if ($x.isBuiltInMaster) {
                'The active built-in master subscription is scoped to all APIs.'
            }
            else {
                'An active subscription is scoped to all APIs.'
            }
        }
        Recommendation = 'Review the need for all-API access and narrow or suspend broad subscriptions that are not explicitly required.'
        Effort = 'S'
        References = @()
        SourceFiles = @('raw/subscriptions.json', 'model/subscriptions.json')
        Enabled = $true
    }
    @{
        Id = 'APIM-SEC-007'
        Title = 'Policy contains a hard-coded credential'
        Pillar = 'Security'
        Mcsb = 'DP-7'
        Severity = 'High'
        Scope = 'Operation'
        Requires = @('model/operations.json')
        Test = {
            param($x, $ctx)
            $null = $ctx
            $x.hardcodedSecret
        }
        Evidence = {
            param($x, $ctx)
            $null = $ctx
            [ordered]@{
                method = $x.method
                path = $x.fullPath
                hardcodedSecret = $x.hardcodedSecret
                policyEvaluationStatus = $x.policyEvaluationStatus
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $ctx
            "Operation $($x.method) $($x.fullPath) contains a detected hard-coded credential location; no value is retained."
        }
        Recommendation = 'Replace hard-coded policy credentials with an approved secret reference or identity-based mechanism and rotate the exposed credential through the authorized operational process.'
        Effort = 'M'
        References = @()
        SourceFiles = @('raw/policies/', 'model/operations.json')
        Enabled = $true
    }
    @{
        Id = 'APIM-SEC-008'
        Title = 'Secret-like named value is stored as plain text'
        Pillar = 'Security'
        Mcsb = 'DP-7'
        Severity = 'Medium'
        Scope = 'NamedValue'
        Requires = @('model/namedValues.json')
        Test = {
            param($x, $ctx)
            $null = $ctx
            $x.plainTextSecretLike
        }
        Evidence = {
            param($x, $ctx)
            $null = $ctx
            [ordered]@{
                secret = $x.secret
                plainTextSecretLike = $x.plainTextSecretLike
                secretPatternLocations = @($x.secretPatternLocations)
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $ctx
            "Named value has secret-like content or naming at structural location(s): $(@($x.secretPatternLocations) -join ', '); no value is retained."
        }
        Recommendation = 'Store sensitive named values as secrets backed by an approved secret-management mechanism and rotate any exposed credential through the authorized operational process.'
        Effort = 'S'
        References = @()
        SourceFiles = @('raw/namedValues.json', 'model/namedValues.json')
        Enabled = $true
    }
    @{
        Id = 'APIM-SEC-009'
        Title = 'Secret or certificate is not healthy in Key Vault'
        Pillar = 'Security'
        Mcsb = 'DP-7'
        Severity = 'Medium'
        Scope = @('NamedValue', 'Certificate')
        Requires = @(
            'model/namedValues.json',
            'model/certificates.json'
        )
        DataGaps = {
            param($ctx)
            $positiveNamedValue = @($ctx.Models.namedValues | Where-Object {
                    $_.secret -and (
                        $_.keyVaultBacked -eq $false -or
                        ($null -ne $_.keyVaultStatus -and
                            $_.keyVaultStatus -cne 'Success')
                    )
                })
            $positiveCertificate = @(
                $ctx.Models.certificates | Where-Object {
                    $_.keyVaultBacked -eq $false
                }
            )
            if ($positiveNamedValue.Count -eq 0 -and
                $positiveCertificate.Count -eq 0) {
                if (@($ctx.Models.namedValues | Where-Object {
                            $_.secret -and
                            $null -eq $_.keyVaultBacked
                        }).Count -gt 0) {
                    'model/namedValues.json#keyVaultBacked'
                }
                if (@($ctx.Models.namedValues | Where-Object {
                            $_.secret -and
                            $_.keyVaultBacked -eq $true -and
                            $null -eq $_.keyVaultStatus
                        }).Count -gt 0) {
                    'model/namedValues.json#keyVaultStatus'
                }
                if (@($ctx.Models.certificates | Where-Object {
                            $null -eq $_.keyVaultBacked
                        }).Count -gt 0) {
                    'model/certificates.json#keyVaultBacked'
                }
            }
        }
        Applies = {
            param($x, $ctx)
            $null = $ctx
            if ($null -ne $x.PSObject.Properties['namedValueId']) {
                return $x.secret
            }
            return $true
        }
        Test = {
            param($x, $ctx)
            $null = $ctx
            if ($null -ne $x.PSObject.Properties['namedValueId']) {
                return $x.keyVaultBacked -eq $false -or
                    ($null -ne $x.keyVaultStatus -and
                        $x.keyVaultStatus -cne 'Success')
            }
            return $x.keyVaultBacked -eq $false
        }
        Evidence = {
            param($x, $ctx)
            $null = $ctx
            $isNamedValue = (
                $null -ne $x.PSObject.Properties['namedValueId']
            )
            [ordered]@{
                assetType = if ($isNamedValue) {
                    'NamedValue'
                }
                else {
                    'Certificate'
                }
                secret = if ($isNamedValue) { $x.secret } else { $null }
                keyVaultBacked = $x.keyVaultBacked
                keyVaultStatus = if ($isNamedValue) {
                    $x.keyVaultStatus
                }
                else {
                    $null
                }
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $ctx
            if ($null -ne $x.PSObject.Properties['namedValueId']) {
                if ($x.keyVaultBacked -eq $false) {
                    return 'Secret named value is not backed by Key Vault.'
                }
                return 'Key Vault synchronization for a secret named value is not successful.'
            }
            return 'Certificate is not backed by Key Vault.'
        }
        Recommendation = 'Use an approved Key Vault reference for secrets and certificates, and investigate unsuccessful synchronization through the authorized operational process.'
        Effort = 'M'
        References = @()
        SourceFiles = @(
            'raw/namedValues.json',
            'raw/certificates.json',
            'model/namedValues.json',
            'model/certificates.json'
        )
        Enabled = $true
    }
    @{
        Id = 'APIM-SEC-010'
        Title = 'HTTPS backend certificate validation is disabled'
        Pillar = 'Security'
        Mcsb = 'DP-3'
        Severity = 'Medium'
        Scope = 'Backend'
        Requires = @('model/backends.json')
        DataGaps = {
            param($ctx)
            $targets = @($ctx.Models.backends | Where-Object {
                    $_.scheme -eq 'https'
                })
            $positive = @($targets | Where-Object {
                    $_.tlsValidationChain -eq $false -or
                    $_.tlsValidationName -eq $false
                })
            if ($positive.Count -eq 0) {
                if (@($targets | Where-Object {
                            $null -eq $_.tlsValidationChain
                        }).Count -gt 0) {
                    'model/backends.json#tlsValidationChain'
                }
                if (@($targets | Where-Object {
                            $null -eq $_.tlsValidationName
                        }).Count -gt 0) {
                    'model/backends.json#tlsValidationName'
                }
            }
        }
        Applies = {
            param($x, $ctx)
            $null = $ctx
            $x.scheme -eq 'https'
        }
        Test = {
            param($x, $ctx)
            $null = $ctx
            $x.tlsValidationChain -eq $false -or
                $x.tlsValidationName -eq $false
        }
        Evidence = {
            param($x, $ctx)
            $null = $ctx
            [ordered]@{
                scheme = $x.scheme
                tlsValidationChain = $x.tlsValidationChain
                tlsValidationName = $x.tlsValidationName
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $x
            $null = $ctx
            'HTTPS backend certificate chain or hostname validation is explicitly disabled.'
        }
        Recommendation = 'Enable backend certificate chain and hostname validation unless an approved exception is documented and independently protected.'
        Effort = 'S'
        References = @()
        SourceFiles = @('raw/backends.json', 'model/backends.json')
        Enabled = $true
    }
    @{
        Id = 'APIM-SEC-011'
        Title = 'Backend target uses unapproved plain HTTP'
        Pillar = 'Security'
        Mcsb = 'DP-3'
        Severity = 'Medium'
        Scope = @('Backend', 'Operation')
        Requires = @(
            'model/backends.json',
            'model/operations.json'
        )
        DataGaps = {
            param($ctx)
            $backendExceptions = @()
            $operationExceptions = @()
            if ($ctx.Config.Contains('RuleExceptions')) {
                $backendExceptions = @(
                    $ctx.Config.RuleExceptions.
                        ApprovedPlainHttpBackendIds
                )
                $operationExceptions = @(
                    $ctx.Config.RuleExceptions.
                        ApprovedPlainHttpOperationKeys
                )
            }
            $positiveBackend = @($ctx.Models.backends | Where-Object {
                    $_.scheme -eq 'http' -and
                    $_.backendId -notin $backendExceptions
                })
            $positiveOperation = @($ctx.Models.operations | Where-Object {
                    $_.backendOverrideHttp -and
                    "$($_.apiId)/$($_.operationId)" -notin
                        $operationExceptions
                })
            if ($positiveBackend.Count -eq 0 -and
                $positiveOperation.Count -eq 0 -and
                @($ctx.Models.operations | Where-Object {
                        $_.policyEvaluationStatus -eq 'Partial' -and
                        "$($_.apiId)/$($_.operationId)" -notin
                            $operationExceptions
                    }).Count -gt 0) {
                'model/operations.json#backendOverrideHttp'
            }
        }
        Applies = {
            param($x, $ctx)
            $null = $ctx
            if ($null -ne $x.PSObject.Properties['backendId']) {
                return $x.scheme -eq 'http'
            }
            return $x.backendOverrideHttp
        }
        Test = {
            param($x, $ctx)
            $backendExceptions = @()
            $operationExceptions = @()
            if ($ctx.Config.Contains('RuleExceptions')) {
                $backendExceptions = @(
                    $ctx.Config.RuleExceptions.
                        ApprovedPlainHttpBackendIds
                )
                $operationExceptions = @(
                    $ctx.Config.RuleExceptions.
                        ApprovedPlainHttpOperationKeys
                )
            }
            if ($null -ne $x.PSObject.Properties['backendId']) {
                return $x.backendId -notin $backendExceptions
            }
            return "$($x.apiId)/$($x.operationId)" -notin
                $operationExceptions
        }
        Evidence = {
            param($x, $ctx)
            $null = $ctx
            $isBackend = $null -ne $x.PSObject.Properties['backendId']
            [ordered]@{
                assetType = if ($isBackend) { 'Backend' } else { 'Operation' }
                scheme = if ($isBackend) { $x.scheme } else { 'http' }
                method = if ($isBackend) { $null } else { $x.method }
                path = if ($isBackend) { $null } else { $x.fullPath }
                backendOverrideHttp = if ($isBackend) {
                    $false
                }
                else {
                    $x.backendOverrideHttp
                }
                approvedException = $false
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $ctx
            if ($null -ne $x.PSObject.Properties['backendId']) {
                return 'Backend entity uses plain HTTP without an approved internal-service exception.'
            }
            return "Operation $($x.method) $($x.fullPath) overrides its backend target to plain HTTP without an approved exception."
        }
        Recommendation = 'Use HTTPS for backend traffic, or document the exact internal target in the approved exception allowlist after validating compensating network controls.'
        Effort = 'M'
        References = @()
        SourceFiles = @(
            'raw/backends.json',
            'raw/policies/',
            'model/backends.json',
            'model/operations.json'
        )
        Enabled = $true
    }
    @{
        Id = 'APIM-SEC-012'
        Title = 'API policy permits unsafe credentialed cross-origin requests'
        Pillar = 'Security'
        Mcsb = 'DP-3'
        Severity = 'Medium'
        Scope = 'Api'
        Requires = @('model/apis.json')
        DataGaps = {
            param($ctx)
            if (@($ctx.Models.apis | Where-Object {
                        $_.corsUnsafe -eq $true
                    }).Count -eq 0 -and
                @($ctx.Models.apis | Where-Object {
                        $null -eq $_.corsUnsafe
                    }).Count -gt 0) {
                'model/apis.json#corsUnsafe'
            }
        }
        Test = {
            param($x, $ctx)
            $null = $ctx
            $x.corsUnsafe -eq $true
        }
        Evidence = {
            param($x, $ctx)
            $null = $ctx
            [ordered]@{
                path = $x.path
                corsUnsafe = $x.corsUnsafe
                reachability = $x.reachability
                exposure = $x.exposure
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $ctx
            "API path /$($x.path) permits a wildcard CORS origin with credentials."
        }
        Recommendation = 'Review allowed origins and credentials support, and restrict cross-origin access to explicitly approved origins.'
        Effort = 'S'
        References = @()
        SourceFiles = @('raw/policies/', 'model/apis.json')
        Enabled = $true
    }
    @{
        Id = 'APIM-SEC-014'
        Title = 'Diagnostics log bodies or sensitive request headers'
        Pillar = 'Security'
        Mcsb = 'LT-3'
        Severity = 'Medium'
        Scope = 'Api'
        Requires = @('model/apis.json')
        DataGaps = {
            param($ctx)
            $positive = @($ctx.Models.apis | Where-Object {
                    $_.bodyLogging -eq $true -or
                    $_.sensitiveHeadersLogged -eq $true
                })
            if ($positive.Count -eq 0) {
                if (@($ctx.Models.apis | Where-Object {
                            $null -eq $_.bodyLogging
                        }).Count -gt 0) {
                    'model/apis.json#bodyLogging'
                }
                if (@($ctx.Models.apis | Where-Object {
                            $null -eq $_.sensitiveHeadersLogged
                        }).Count -gt 0) {
                    'model/apis.json#sensitiveHeadersLogged'
                }
            }
        }
        Test = {
            param($x, $ctx)
            $null = $ctx
            $x.bodyLogging -eq $true -or
                $x.sensitiveHeadersLogged -eq $true
        }
        Evidence = {
            param($x, $ctx)
            $null = $ctx
            [ordered]@{
                path = $x.path
                bodyLogging = $x.bodyLogging
                sensitiveHeadersLogged = $x.sensitiveHeadersLogged
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $ctx
            "API path /$($x.path) logs message bodies or a sensitive request header."
        }
        Recommendation = 'Review diagnostic payload and header capture, and retain only the minimum fields required for approved operational monitoring.'
        Effort = 'S'
        References = @()
        SourceFiles = @(
            'raw/diagnostics.json',
            'raw/apiDiagnostics/',
            'model/apis.json'
        )
        Enabled = $true
    }
    @{
        Id = 'APIM-SEC-015'
        Title = 'Subscription permits request tracing'
        Pillar = 'Security'
        Mcsb = 'LT-3'
        Severity = 'Medium'
        Scope = 'Subscription'
        Requires = @('model/subscriptions.json')
        DataGaps = {
            param($ctx)
            if (@($ctx.Models.subscriptions | Where-Object {
                        $_.allowTracing -eq $true
                    }).Count -eq 0 -and
                @($ctx.Models.subscriptions | Where-Object {
                        $null -eq $_.allowTracing
                    }).Count -gt 0) {
                'model/subscriptions.json#allowTracing'
            }
        }
        Test = {
            param($x, $ctx)
            $null = $ctx
            $x.allowTracing -eq $true
        }
        Evidence = {
            param($x, $ctx)
            $null = $ctx
            [ordered]@{
                scopeType = $x.scopeType
                state = $x.state
                allowTracing = $x.allowTracing
                isBuiltInMaster = $x.isBuiltInMaster
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $x
            $null = $ctx
            'A subscription permits request tracing.'
        }
        Recommendation = 'Review the operational need for subscription tracing and disable it where it is not explicitly required.'
        Effort = 'S'
        References = @()
        SourceFiles = @('raw/subscriptions.json', 'model/subscriptions.json')
        Enabled = $true
    }
    @{
        Id = 'APIM-SEC-019'
        Title = 'APIM service has no managed identity'
        Pillar = 'Security'
        Mcsb = 'IM-3'
        Severity = 'Low'
        Scope = 'Service'
        Requires = @('model/service.json')
        Test = {
            param($x, $ctx)
            $null = $x
            $ctx.Models.service.managedIdentity -eq 'None'
        }
        Evidence = {
            param($x, $ctx)
            $null = $x
            [ordered]@{
                managedIdentity = $ctx.Models.service.managedIdentity
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $x
            $null = $ctx
            'The APIM service has no system-assigned or user-assigned managed identity.'
        }
        Recommendation = 'Review APIM dependencies that support managed identity and enable an appropriate service identity where it reduces credential use.'
        Effort = 'S'
        References = @()
        SourceFiles = @('raw/service.json', 'model/service.json')
        Enabled = $true
    }
    @{
        Id = 'APIM-SEC-020'
        Title = 'Production operation contains a mock or trace policy'
        Pillar = 'Security'
        Mcsb = 'n/a'
        Severity = 'Medium'
        Scope = 'Operation'
        Requires = @('model/operations.json')
        Applies = {
            param($x, $ctx)
            $null = $x
            $ctx.Manifest.environment -ieq 'Prod'
        }
        Test = {
            param($x, $ctx)
            $null = $ctx
            $x.mockOrTrace
        }
        Evidence = {
            param($x, $ctx)
            [ordered]@{
                method = $x.method
                path = $x.fullPath
                environment = $ctx.Manifest.environment
                mockOrTrace = $x.mockOrTrace
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $ctx
            "Production operation $($x.method) $($x.fullPath) contains a mock or trace policy."
        }
        Recommendation = 'Confirm whether mock or trace behavior is intended in production and remove it from effective policy when it is not required.'
        Effort = 'S'
        References = @()
        SourceFiles = @('raw/policies/', 'model/operations.json')
        Enabled = $true
    }
)
