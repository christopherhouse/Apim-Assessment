#Requires -Version 7.4

Set-StrictMode -Version Latest

@(
    @{
        Id = 'APIM-REL-001'
        Title = 'Production Premium instance is not zone-redundant'
        Pillar = 'Reliability'
        Mcsb = 'n/a'
        Severity = 'Medium'
        Scope = 'Service'
        Requires = @('model/service.json')
        DataGaps = {
            param($ctx)
            if ($ctx.Manifest.environment -ieq 'Prod' -and
                $null -eq $ctx.Models.service.skuName) {
                'model/service.json#skuName'
            }
        }
        Applies = {
            param($x, $ctx)
            $null = $x
            $ctx.Manifest.environment -ieq 'Prod' -and
                $ctx.Models.service.skuName -ieq 'Premium'
        }
        Test = {
            param($x, $ctx)
            $null = $x
            @($ctx.Models.service.zones).Count -eq 0
        }
        Evidence = {
            param($x, $ctx)
            $null = $x
            [ordered]@{
                environment = $ctx.Manifest.environment
                skuName = $ctx.Models.service.skuName
                zones = @($ctx.Models.service.zones)
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $x
            $null = $ctx
            'The production Premium APIM instance has no availability zones configured.'
        }
        Recommendation = 'Review regional and tier support, then plan zone-redundant APIM capacity where the production availability requirement justifies it.'
        Effort = 'L'
        References = @()
        SourceFiles = @('raw/service.json', 'model/service.json')
        Enabled = $true
    }
    @{
        Id = 'APIM-REL-002'
        Title = 'Production instance has fewer than two capacity units'
        Pillar = 'Reliability'
        Mcsb = 'n/a'
        Severity = 'Medium'
        Scope = 'Service'
        Requires = @('model/service.json')
        DataGaps = {
            param($ctx)
            if ($ctx.Manifest.environment -ieq 'Prod' -and
                $null -eq $ctx.Models.service.skuCapacity) {
                'model/service.json#skuCapacity'
            }
        }
        Applies = {
            param($x, $ctx)
            $null = $x
            $ctx.Manifest.environment -ieq 'Prod'
        }
        Test = {
            param($x, $ctx)
            $null = $x
            $null -ne $ctx.Models.service.skuCapacity -and
                $ctx.Models.service.skuCapacity -lt 2
        }
        Evidence = {
            param($x, $ctx)
            $null = $x
            [ordered]@{
                environment = $ctx.Manifest.environment
                skuName = $ctx.Models.service.skuName
                skuCapacity = $ctx.Models.service.skuCapacity
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $x
            "The production APIM instance has $($ctx.Models.service.skuCapacity) configured capacity unit(s)."
        }
        Recommendation = 'Review production throughput and availability requirements, then configure at least two units where the selected tier uses dedicated capacity.'
        Effort = 'M'
        References = @()
        SourceFiles = @('raw/service.json', 'model/service.json')
        Enabled = $true
    }
    @{
        Id = 'APIM-REL-003'
        Title = 'Critical backend has no circuit breaker or backend pool'
        Pillar = 'Reliability'
        Mcsb = 'n/a'
        Severity = 'Low'
        Scope = 'Backend'
        Requires = @('model/backends.json')
        DataGaps = {
            param($ctx)
            $criticalBackendIds = if (
                $ctx.Config.Contains('RuleTargets')
            ) {
                @($ctx.Config.RuleTargets.CriticalBackendIds)
            }
            else {
                @()
            }
            $knownCriticalBackends = @($ctx.Models.backends | Where-Object {
                    $backendId = $_.backendId
                    @($criticalBackendIds | Where-Object {
                            $_ -ieq $backendId
                        }).Count -gt 0
                })
            $knownPositive = @($knownCriticalBackends | Where-Object {
                    -not $_.circuitBreakerConfigured -and
                        -not $_.poolConfigured
                }).Count -gt 0
            $knownIds = @($ctx.Models.backends.backendId)
            if (-not $knownPositive -and
                @($criticalBackendIds | Where-Object {
                        $targetId = $_
                        @($knownIds | Where-Object {
                                $_ -ieq $targetId
                            }).Count -eq 0
                    }).Count -gt 0) {
                'model/backends.json#backendId'
            }
        }
        Applies = {
            param($x, $ctx)
            $criticalBackendIds = if (
                $ctx.Config.Contains('RuleTargets')
            ) {
                @($ctx.Config.RuleTargets.CriticalBackendIds)
            }
            else {
                @()
            }
            @($criticalBackendIds | Where-Object {
                    $_ -ieq $x.backendId
                }).Count -gt 0
        }
        Test = {
            param($x, $ctx)
            $null = $ctx
            -not $x.circuitBreakerConfigured -and
                -not $x.poolConfigured
        }
        Evidence = {
            param($x, $ctx)
            $null = $ctx
            [ordered]@{
                circuitBreakerConfigured = $x.circuitBreakerConfigured
                poolConfigured = $x.poolConfigured
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $ctx
            "Critical backend $($x.backendId) has neither a circuit breaker nor a backend pool configured."
        }
        Recommendation = 'Review failure and failover requirements for the declared critical backend, then configure an appropriate circuit breaker, backend pool, or documented equivalent.'
        Effort = 'M'
        References = @()
        SourceFiles = @('raw/backends.json', 'model/backends.json')
        Enabled = $true
    }
    @{
        Id = 'APIM-REL-004'
        Title = 'Application Gateway probe is not aligned to the APIM status endpoint'
        Pillar = 'Reliability'
        Mcsb = 'n/a'
        Severity = 'Low'
        Scope = 'Network'
        Requires = @('model/network.json')
        DataGaps = {
            param($ctx)
            if ($ctx.Models.network.appGatewayProbeAlignment -eq 'Unknown') {
                'model/network.json#appGatewayProbeAlignment'
            }
        }
        Test = {
            param($x, $ctx)
            $null = $ctx
            $x.appGatewayProbeAlignment -eq 'Misaligned'
        }
        Evidence = {
            param($x, $ctx)
            $null = $ctx
            [ordered]@{
                appGatewayProbeAlignment = (
                    $x.appGatewayProbeAlignment
                )
                probePaths = @($x.appGatewayProbePaths)
                expectedPath = '/status-0123456789abcdef'
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $x
            $null = $ctx
            'An APIM-targeted Application Gateway route uses a health probe path other than /status-0123456789abcdef.'
        }
        Recommendation = 'Align APIM-targeted Application Gateway health probes to the APIM status endpoint and confirm the expected host and response behavior.'
        Effort = 'S'
        References = @()
        SourceFiles = @(
            'raw/service.json',
            'raw/network/',
            'model/network.json'
        )
        Enabled = $true
    }
    @{
        Id = 'APIM-REL-005'
        Title = 'Certificate expires within the configured threshold'
        Pillar = 'Reliability'
        Mcsb = 'n/a'
        Severity = 'Medium'
        Scope = @('Service', 'Certificate')
        Requires = @('model/service.json', 'model/certificates.json')
        DataGaps = {
            param($ctx)
            $started = [datetimeoffset] $ctx.Manifest.startedUtc
            $thresholdDate = $started.AddDays(
                [double] $ctx.Config.Thresholds.CertExpiryDays
            )
            $certificatePositive = @($ctx.Models.certificates | Where-Object {
                    $null -ne $_.expirationDate -and
                        [datetimeoffset] $_.expirationDate -lt $thresholdDate
                }).Count -gt 0
            $hostnamePositive = @(
                $ctx.Models.service.hostnameCertificateExpirations |
                    Where-Object {
                        [datetimeoffset] $_ -lt $thresholdDate
                    }
            ).Count -gt 0
            if (-not $certificatePositive -and -not $hostnamePositive -and
                @($ctx.Models.certificates | Where-Object {
                        $null -eq $_.expirationDate
                    }).Count -gt 0) {
                'model/certificates.json#expirationDate'
            }
            if (-not $certificatePositive -and -not $hostnamePositive -and
                $ctx.Models.service.missingInputs -contains
                    'hostnameCertificateExpirations') {
                'model/service.json#hostnameCertificateExpirations'
            }
        }
        Test = {
            param($x, $ctx)
            $started = [datetimeoffset] $ctx.Manifest.startedUtc
            $thresholdDate = $started.AddDays(
                [double] $ctx.Config.Thresholds.CertExpiryDays
            )
            if ($null -ne $x.PSObject.Properties['certificateId']) {
                return $null -ne $x.expirationDate -and
                    [datetimeoffset] $x.expirationDate -lt $thresholdDate
            }
            return @(
                $ctx.Models.service.hostnameCertificateExpirations |
                    Where-Object {
                        [datetimeoffset] $_ -lt $thresholdDate
                    }
            ).Count -gt 0
        }
        Evidence = {
            param($x, $ctx)
            $started = [datetimeoffset] $ctx.Manifest.startedUtc
            $thresholdDays = [double] $ctx.Config.Thresholds.CertExpiryDays
            if ($null -eq $x.PSObject.Properties['certificateId']) {
                $expiringDates = @(
                    $ctx.Models.service.hostnameCertificateExpirations |
                        Where-Object {
                            [datetimeoffset] $_ -lt
                                $started.AddDays($thresholdDays)
                        }
                )
                return [ordered]@{
                    assetType = 'HostnameCertificate'
                    expirationDates = $expiringDates
                    certExpiryDays = $thresholdDays
                    expiringCount = $expiringDates.Count
                }
            }
            $expiration = [datetimeoffset] $x.expirationDate
            [ordered]@{
                assetType = 'Certificate'
                expirationDate = $x.expirationDate
                certExpiryDays = $thresholdDays
                daysUntilExpiry = [math]::Round(
                    ($expiration - $started).TotalDays,
                    1,
                    [MidpointRounding]::AwayFromZero
                )
            }
        }
        EvidenceText = {
            param($x, $ctx)
            if ($null -eq $x.PSObject.Properties['certificateId']) {
                return "One or more APIM hostname certificates expire within the configured $($ctx.Config.Thresholds.CertExpiryDays)-day threshold."
            }
            "Certificate $($x.certificateId) expires within the configured $($ctx.Config.Thresholds.CertExpiryDays)-day threshold."
        }
        Recommendation = 'Plan certificate renewal or replacement before expiry and verify the dependent APIM configuration will receive the updated certificate.'
        Effort = 'S'
        References = @()
        SourceFiles = @(
            'raw/service.json',
            'raw/certificates.json',
            'model/service.json',
            'model/certificates.json'
        )
        Enabled = $true
    }
    @{
        Id = 'APIM-REL-006'
        Title = 'APIM platform version is not stv2'
        Pillar = 'Reliability'
        Mcsb = 'n/a'
        Severity = 'High'
        Scope = 'Service'
        Requires = @('model/service.json')
        DataGaps = {
            param($ctx)
            if ($null -eq $ctx.Models.service.platformVersion) {
                'model/service.json#platformVersion'
            }
        }
        Test = {
            param($x, $ctx)
            $null = $x
            $null -ne $ctx.Models.service.platformVersion -and
                $ctx.Models.service.platformVersion -notin @('stv2', 'stv2.1')
        }
        Evidence = {
            param($x, $ctx)
            $null = $x
            [ordered]@{
                platformVersion = $ctx.Models.service.platformVersion
            }
        }
        EvidenceText = {
            param($x, $ctx)
            $null = $x
            "The APIM service reports platform version $($ctx.Models.service.platformVersion)."
        }
        Recommendation = 'Review APIM platform migration requirements and plan migration to a supported stv2 platform version.'
        Effort = 'L'
        References = @()
        SourceFiles = @('raw/service.json', 'model/service.json')
        Enabled = $true
    }
)
