$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Evidence-backed REL catalog' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)
        $script:relRulesRepoRoot = $RepoRoot

        BeforeAll {
            $script:relRulesConfig = Import-PowerShellDataFile (
                Join-Path $script:relRulesRepoRoot 'config/sample.psd1'
            )
            $script:relRulesConfig.Output.Root = Join-Path $TestDrive 'restricted'
            $run = New-ApimRun -Config $script:relRulesConfig `
                -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000002' `
                -Operator Synthetic -RunId 'synthetic-rel-rules' `
                -StartedUtc ([datetimeoffset]::Parse(
                    '2026-10-13T00:00:00+00:00',
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::RoundtripKind
                ))
            $script:relRulesManifest = Get-RunManifest -RunPath $run.Path
            $script:relRules = @(
                Get-ApimRuleCatalog -CatalogPath (
                    Join-Path $script:relRulesRepoRoot 'rules'
                ) | Where-Object Id -Like 'APIM-REL-*'
            )
            $script:relFixtureRoot = Join-Path $script:relRulesRepoRoot (
                'tests/fixtures/synthetic-reference/model'
            )

            function Get-SyntheticRelModelSet {
                return [ordered]@{
                    service = Get-Content -LiteralPath (
                        Join-Path $script:relFixtureRoot 'service.json'
                    ) -Raw | ConvertFrom-Json -Depth 100
                    backends = Get-Content -LiteralPath (
                        Join-Path $script:relFixtureRoot 'backends.json'
                    ) -Raw | ConvertFrom-Json -Depth 100 -NoEnumerate
                    certificates = Get-Content -LiteralPath (
                        Join-Path $script:relFixtureRoot 'certificates.json'
                    ) -Raw | ConvertFrom-Json -Depth 100 -NoEnumerate
                    network = Get-Content -LiteralPath (
                        Join-Path $script:relFixtureRoot 'network.json'
                    ) -Raw | ConvertFrom-Json -Depth 100
                }
            }

            function Get-SyntheticRelFinding {
                param(
                    [Parameter(Mandatory)]
                    [string] $RuleId,

                    [Parameter(Mandatory)]
                    [System.Collections.IDictionary] $Models,

                    [System.Collections.IDictionary] $Config = (
                        $script:relRulesConfig
                    ),

                    [object] $Manifest = $script:relRulesManifest
                )

                $rule = @($script:relRules | Where-Object Id -EQ $RuleId)
                return @(Invoke-ApimRuleEngine -Rules $rule -Models $Models `
                        -Manifest $Manifest -Config $Config)
            }
        }

        It 'loads all six REL rules with empty references' {
            @($script:relRules.Id) | Should -Be @(
                'APIM-REL-001',
                'APIM-REL-002',
                'APIM-REL-003',
                'APIM-REL-004',
                'APIM-REL-005',
                'APIM-REL-006'
            )
            foreach ($rule in $script:relRules) {
                $rule.References.Count | Should -Be 0
                $rule.Enabled | Should -BeTrue
            }
        }

        It 'flags only production Premium services without zones' {
            $models = Get-SyntheticRelModelSet
            $found = @(Get-SyntheticRelFinding -RuleId 'APIM-REL-001' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].scope | Should -Be 'service'
            $found[0].evidence.skuName | Should -Be 'Premium'
            $found[0].evidence.zones.Count | Should -Be 0
            $found[0].sourceFiles | Should -Contain 'raw/service.json'

            $models.service.zones = @('1')
            @(Get-SyntheticRelFinding -RuleId 'APIM-REL-001' `
                    -Models $models).Count | Should -Be 0

            $manifest = $script:relRulesManifest |
                ConvertTo-Json -Depth 100 |
                ConvertFrom-Json -Depth 100
            $manifest.environment = 'Dev'
            $models.service.zones = @()
            @(Get-SyntheticRelFinding -RuleId 'APIM-REL-001' `
                    -Models $models -Manifest $manifest).Count | Should -Be 0
        }

        It 'flags production capacity below two units' {
            $models = Get-SyntheticRelModelSet
            @(Get-SyntheticRelFinding -RuleId 'APIM-REL-002' `
                    -Models $models).Count | Should -Be 0

            $models.service.skuCapacity = 1
            $found = @(Get-SyntheticRelFinding -RuleId 'APIM-REL-002' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].evidence.skuCapacity | Should -Be 1

            $models.service.skuCapacity = 2
            @(Get-SyntheticRelFinding -RuleId 'APIM-REL-002' `
                    -Models $models).Count | Should -Be 0
        }

        It 'flags only declared critical backends without resilience controls' {
            $models = Get-SyntheticRelModelSet
            @(Get-SyntheticRelFinding -RuleId 'APIM-REL-003' `
                    -Models $models).Count | Should -Be 0

            $config = $script:relRulesConfig.Clone()
            $config.RuleTargets = @{
                CriticalBackendIds = @('status-backend')
            }
            $found = @(Get-SyntheticRelFinding -RuleId 'APIM-REL-003' `
                    -Models $models -Config $config)
            $found.Count | Should -Be 1
            $found[0].scope | Should -Be 'backend:status-backend'
            $found[0].evidence.circuitBreakerConfigured |
                Should -BeFalse
            $found[0].evidence.poolConfigured | Should -BeFalse

            $models.backends[1].poolConfigured = $true
            @(Get-SyntheticRelFinding -RuleId 'APIM-REL-003' `
                    -Models $models -Config $config).Count | Should -Be 0

            $config.RuleTargets.CriticalBackendIds = @('missing-backend')
            $unknown = @(Get-SyntheticRelFinding -RuleId 'APIM-REL-003' `
                    -Models $models -Config $config)
            $unknown.Count | Should -Be 1
            $unknown[0].evaluation | Should -Be 'NotEvaluated'
            $unknown[0].evidence.missingInputs |
                Should -Contain 'model/backends.json#backendId'
        }

        It 'flags APIM-targeted probes not using the status endpoint' {
            $models = Get-SyntheticRelModelSet
            $found = @(Get-SyntheticRelFinding -RuleId 'APIM-REL-004' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].scope | Should -Be 'network'
            $found[0].evidence.probePaths | Should -Be @('/')
            $found[0].sourceFiles | Should -Contain 'raw/network/'

            $models.network.appGatewayProbeAlignment = 'Aligned'
            $models.network.appGatewayProbePaths = @(
                '/status-0123456789abcdef'
            )
            @(Get-SyntheticRelFinding -RuleId 'APIM-REL-004' `
                    -Models $models).Count | Should -Be 0

            $models.network.appGatewayProbeAlignment = 'NotApplicable'
            $models.network.appGatewayProbePaths = @()
            @(Get-SyntheticRelFinding -RuleId 'APIM-REL-004' `
                    -Models $models).Count | Should -Be 0
        }

        It 'uses the run timestamp and strict certificate threshold boundary' {
            $models = Get-SyntheticRelModelSet
            $found = @(Get-SyntheticRelFinding -RuleId 'APIM-REL-005' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].scope |
                Should -Be 'certificate:uploaded-certificate'
            $found[0].evidence.certExpiryDays | Should -Be 60
            $found[0].evidence.daysUntilExpiry | Should -Be 19

            $models.certificates[1].expirationDate = (
                [datetimeoffset] '2026-12-12T00:00:00Z'
            ).ToString('O')
            @(Get-SyntheticRelFinding -RuleId 'APIM-REL-005' `
                    -Models $models).Count | Should -Be 0

            $models.service.hostnameCertificateExpirations = @(
                '2026-10-20T00:00:00Z'
            )
            $hostname = @(Get-SyntheticRelFinding `
                    -RuleId 'APIM-REL-005' -Models $models)
            $hostname.Count | Should -Be 1
            $hostname[0].scope | Should -Be 'service'
            $hostname[0].evidence.assetType |
                Should -Be 'HostnameCertificate'
            $hostname[0].evidence.expiringCount | Should -Be 1
        }

        It 'flags platform versions outside stv2 and stv2.1' {
            $models = Get-SyntheticRelModelSet
            @(Get-SyntheticRelFinding -RuleId 'APIM-REL-006' `
                    -Models $models).Count | Should -Be 0

            $models.service.platformVersion = 'stv1'
            $found = @(Get-SyntheticRelFinding -RuleId 'APIM-REL-006' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].severity | Should -Be 'High'
            $found[0].evidence.platformVersion | Should -Be 'stv1'

            $models.service.platformVersion = 'stv2.1'
            @(Get-SyntheticRelFinding -RuleId 'APIM-REL-006' `
                    -Models $models).Count | Should -Be 0
        }

        It 'marks unavailable reliability facts NotEvaluated' -TestCases @(
            @{
                Id = 'APIM-REL-001'
                Missing = 'model/service.json#skuName'
                Setup = 'SkuName'
            }
            @{
                Id = 'APIM-REL-002'
                Missing = 'model/service.json#skuCapacity'
                Setup = 'SkuCapacity'
            }
            @{
                Id = 'APIM-REL-004'
                Missing = 'model/network.json#appGatewayProbeAlignment'
                Setup = 'Probe'
            }
            @{
                Id = 'APIM-REL-005'
                Missing = 'model/certificates.json#expirationDate'
                Setup = 'Certificate'
            }
            @{
                Id = 'APIM-REL-006'
                Missing = 'model/service.json#platformVersion'
                Setup = 'Platform'
            }
        ) {
            param($Id, $Missing, $Setup)

            $models = Get-SyntheticRelModelSet
            switch ($Setup) {
                SkuName {
                    $models.service.skuName = $null
                }
                SkuCapacity {
                    $models.service.skuCapacity = $null
                }
                Probe {
                    $models.network.appGatewayProbeAlignment = 'Unknown'
                    $models.network.appGatewayProbePaths = $null
                }
                Certificate {
                    foreach ($certificate in $models.certificates) {
                        $certificate.expirationDate = $null
                    }
                }
                Platform {
                    $models.service.platformVersion = $null
                }
            }

            $found = @(Get-SyntheticRelFinding -RuleId $Id `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].evaluation | Should -Be 'NotEvaluated'
            $found[0].severity | Should -Be 'Info'
            $found[0].evidence.missingInputs | Should -Contain $Missing
        }

        It 'retains a known expiring certificate when another expiry is unknown' {
            $models = Get-SyntheticRelModelSet
            $models.certificates[0].expirationDate = $null

            $found = @(Get-SyntheticRelFinding -RuleId 'APIM-REL-005' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].evaluation | Should -Be 'Evaluated'
            $found[0].scope |
                Should -Be 'certificate:uploaded-certificate'
        }

        It 'marks each REL rule NotEvaluated once when its model is missing' {
            foreach ($id in @($script:relRules.Id)) {
                $rule = @($script:relRules | Where-Object Id -EQ $id)
                $found = @(Get-SyntheticRelFinding -RuleId $id `
                        -Models ([ordered]@{}))
                $found.Count | Should -Be 1
                $found[0].evaluation | Should -Be 'NotEvaluated'
                $found[0].scope | Should -Be 'missing-input'
                $found[0].evidence.missingInputs.Count |
                    Should -Be @($rule[0].Requires).Count
            }
        }

        It 'persists deterministic schema-valid REL findings' {
            $models = Get-SyntheticRelModelSet
            $config = $script:relRulesConfig.Clone()
            $config.RuleTargets = @{
                CriticalBackendIds = @('status-backend')
            }
            $findings = @(Invoke-ApimRuleEngine -Rules $script:relRules `
                    -Models $models -Manifest $script:relRulesManifest `
                    -Config $config)
            @($findings.ruleId) | Should -Be @(
                'APIM-REL-001',
                'APIM-REL-005',
                'APIM-REL-003',
                'APIM-REL-004'
            )
            $first = Write-ApimFindingSet -RunPath (
                Join-Path $TestDrive 'rel-first'
            ) -Findings $findings
            $second = Write-ApimFindingSet -RunPath (
                Join-Path $TestDrive 'rel-second'
            ) -Findings $findings
            $json = Get-Content -LiteralPath $first -Raw
            $json | Should -Be (Get-Content -LiteralPath $second -Raw)
            ($json | Test-Json -SchemaFile (
                    Join-Path $script:relRulesRepoRoot 'schemas/findings.schema.json'
                )) | Should -BeTrue
        }
    }
}
