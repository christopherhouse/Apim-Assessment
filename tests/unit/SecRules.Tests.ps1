$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Evidence-backed SEC catalog' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)
        $script:secRulesRepoRoot = $RepoRoot

        BeforeAll {
            $script:secRulesConfig = Import-PowerShellDataFile (
                Join-Path $script:secRulesRepoRoot 'config/sample.psd1'
            )
            $script:secRulesConfig.Output.Root = Join-Path $TestDrive 'restricted'
            $run = New-ApimRun -Config $script:secRulesConfig `
                -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000002' `
                -Operator Synthetic -RunId 'synthetic-sec-rules'
            $script:secRulesManifest = Get-RunManifest -RunPath $run.Path
            $script:secRules = @(
                Get-ApimRuleCatalog -CatalogPath (
                    Join-Path $script:secRulesRepoRoot 'rules'
                ) | Where-Object Id -Like 'APIM-SEC-*'
            )
            $script:secFixtureRoot = Join-Path $script:secRulesRepoRoot (
                'tests/fixtures/synthetic-reference/model'
            )

            function Get-SyntheticSecModelSet {
                return [ordered]@{
                    apis = Get-Content -LiteralPath (
                        Join-Path $script:secFixtureRoot 'apis.exposure.json'
                    ) -Raw | ConvertFrom-Json -Depth 100 -NoEnumerate
                    operations = Get-Content -LiteralPath (
                        Join-Path $script:secFixtureRoot 'operations.json'
                    ) -Raw | ConvertFrom-Json -Depth 100 -NoEnumerate
                    subscriptions = Get-Content -LiteralPath (
                        Join-Path $script:secFixtureRoot 'subscriptions.json'
                    ) -Raw | ConvertFrom-Json -Depth 100 -NoEnumerate
                }
            }

            function Get-SyntheticSecFinding {
                param(
                    [Parameter(Mandatory)]
                    [string] $RuleId,

                    [Parameter(Mandatory)]
                    [System.Collections.IDictionary] $Models,

                    [object] $Manifest = $script:secRulesManifest
                )

                $rule = @($script:secRules | Where-Object Id -EQ $RuleId)
                return @(Invoke-ApimRuleEngine -Rules $rule -Models $Models `
                        -Manifest $Manifest -Config $script:secRulesConfig)
            }
        }

        It 'loads the eight currently model-backed SEC rules with empty references' {
            @($script:secRules.Id) | Should -Be @(
                'APIM-SEC-003', 'APIM-SEC-004', 'APIM-SEC-005',
                'APIM-SEC-007', 'APIM-SEC-012', 'APIM-SEC-014',
                'APIM-SEC-015', 'APIM-SEC-020'
            )
            foreach ($rule in $script:secRules) {
                $rule.References.Count | Should -Be 0
                $rule.Enabled | Should -BeTrue
            }
        }

        It 'flags reachable subscription-key-only APIs and preserves traceable evidence' {
            $models = Get-SyntheticSecModelSet
            $found = @(Get-SyntheticSecFinding -RuleId 'APIM-SEC-003' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].scope | Should -Be 'api:status-v1'
            $found[0].evidence.callerAuth | Should -Be 'SubscriptionKeyOnly'
            $found[0].evidence.reachability | Should -Be 'Reachable'
            $found[0].sourceFiles | Should -Contain 'model/apis.json'

            $models.apis[1].callerAuth = 'Entra/JWT'
            @(Get-SyntheticSecFinding -RuleId 'APIM-SEC-003' `
                    -Models $models).Count | Should -Be 0
        }

        It 'does not lose a known SEC-003 finding because another API auth fact is unknown' {
            $models = Get-SyntheticSecModelSet
            $models.apis[0].callerAuth = $null
            $found = @(Get-SyntheticSecFinding -RuleId 'APIM-SEC-003' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].scope | Should -Be 'api:status-v1'
            $found[0].evaluation | Should -Be 'Evaluated'
        }

        It 'flags a reachable API with neither subscription nor caller authentication' {
            $models = Get-SyntheticSecModelSet
            $models.apis[1].subscriptionRequired = $false
            $models.apis[1].callerAuth = 'None'
            $found = @(Get-SyntheticSecFinding -RuleId 'APIM-SEC-004' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].scope | Should -Be 'api:status-v1'
            $found[0].evidence.subscriptionRequired | Should -BeFalse
            $found[0].evidence.callerAuth | Should -Be 'None'

            $models.apis[1].callerAuth = 'Entra/JWT'
            @(Get-SyntheticSecFinding -RuleId 'APIM-SEC-004' `
                    -Models $models).Count | Should -Be 0
        }

        It 'flags only active all-API subscriptions' {
            $models = Get-SyntheticSecModelSet
            $found = @(Get-SyntheticSecFinding -RuleId 'APIM-SEC-005' `
                    -Models $models)
            $found.Count | Should -Be 3
            @($found.evidence.scopeType | Select-Object -Unique) |
                Should -Be @('AllApis')
            @($found.evidence.state | Select-Object -Unique) |
                Should -Be @('active')
            @($found.sourceFiles) |
                Should -Contain 'model/subscriptions.json'

            foreach ($subscription in $models.subscriptions) {
                if ($subscription.scopeType -eq 'AllApis') {
                    $subscription.state = 'suspended'
                }
            }
            @(Get-SyntheticSecFinding -RuleId 'APIM-SEC-005' `
                    -Models $models).Count | Should -Be 0
        }

        It 'flags structural hard-coded credential detections without secret values' {
            $models = Get-SyntheticSecModelSet
            $found = @(Get-SyntheticSecFinding -RuleId 'APIM-SEC-007' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].scope | Should -Be 'operation:orders-v1/get-orders'
            $found[0].evidence.hardcodedSecret | Should -BeTrue
            @($found[0].evidence.PSObject.Properties.Name) |
                Should -Not -Contain 'value'
            $found[0].sourceFiles | Should -Contain 'raw/policies/'

            $models.operations[0].hardcodedSecret = $false
            @(Get-SyntheticSecFinding -RuleId 'APIM-SEC-007' `
                    -Models $models).Count | Should -Be 0
        }

        It 'flags unsafe CORS and leaves known safe APIs unflagged' {
            $models = Get-SyntheticSecModelSet
            $models.apis[0].corsUnsafe = $true
            $found = @(Get-SyntheticSecFinding -RuleId 'APIM-SEC-012' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].scope | Should -Be 'api:orders-v1'
            $found[0].evidence.corsUnsafe | Should -BeTrue

            $models.apis[0].corsUnsafe = $false
            @(Get-SyntheticSecFinding -RuleId 'APIM-SEC-012' `
                    -Models $models).Count | Should -Be 0
        }

        It 'flags known diagnostic body logging even while another API is unknown' {
            $models = Get-SyntheticSecModelSet
            $models.apis[0].bodyLogging = $true
            $found = @(Get-SyntheticSecFinding -RuleId 'APIM-SEC-014' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].scope | Should -Be 'api:orders-v1'
            $found[0].evidence.bodyLogging | Should -BeTrue
            $found[0].sourceFiles | Should -Contain 'raw/apiDiagnostics/'

            foreach ($api in $models.apis) {
                $api.bodyLogging = $false
                $api.sensitiveHeadersLogged = $false
            }
            @(Get-SyntheticSecFinding -RuleId 'APIM-SEC-014' `
                    -Models $models).Count | Should -Be 0
        }

        It 'flags subscriptions that permit tracing' {
            $models = Get-SyntheticSecModelSet
            $found = @(Get-SyntheticSecFinding -RuleId 'APIM-SEC-015' `
                    -Models $models)
            $found.Count | Should -Be 2
            @($found.evidence.allowTracing | Select-Object -Unique) |
                Should -Be @($true)
            $found[0].sourceFiles | Should -Contain 'raw/subscriptions.json'

            foreach ($subscription in $models.subscriptions) {
                $subscription.allowTracing = $false
            }
            @(Get-SyntheticSecFinding -RuleId 'APIM-SEC-015' `
                    -Models $models).Count | Should -Be 0
        }

        It 'flags mock or trace policy only for the production environment' {
            $models = Get-SyntheticSecModelSet
            $models.operations[0].mockOrTrace = $true
            $found = @(Get-SyntheticSecFinding -RuleId 'APIM-SEC-020' `
                    -Models $models)
            $found.Count | Should -Be 1
            $found[0].evidence.environment | Should -Be 'Prod'
            $found[0].evidence.mockOrTrace | Should -BeTrue

            $devManifest = $script:secRulesManifest |
                ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
            $devManifest.environment = 'Dev'
            @(Get-SyntheticSecFinding -RuleId 'APIM-SEC-020' `
                    -Models $models -Manifest $devManifest).Count |
                Should -Be 0
        }

        It 'marks unknown applicable facts NotEvaluated instead of passing' `
            -TestCases @(
                @{ Id = 'APIM-SEC-003'; Missing = 'callerAuth'; Setup = 'Sec003' }
                @{ Id = 'APIM-SEC-004'; Missing = 'callerAuth'; Setup = 'Sec004' }
                @{ Id = 'APIM-SEC-012'; Missing = 'corsUnsafe'; Setup = 'Sec012' }
                @{ Id = 'APIM-SEC-014'; Missing = 'bodyLogging'; Setup = 'Sec014' }
                @{ Id = 'APIM-SEC-015'; Missing = 'allowTracing'; Setup = 'Sec015' }
            ) {
            param($Id, $Missing, $Setup)

            $models = Get-SyntheticSecModelSet
            switch ($Setup) {
                Sec003 {
                    $models.apis[1].callerAuth = $null
                }
                Sec004 {
                    $models.apis[1].subscriptionRequired = $false
                    $models.apis[1].callerAuth = $null
                }
                Sec012 {
                    $models.apis[0].corsUnsafe = $null
                }
                Sec014 {
                    $null = $models
                }
                Sec015 {
                    foreach ($subscription in $models.subscriptions) {
                        $subscription.allowTracing = $false
                    }
                    $models.subscriptions[0].allowTracing = $null
                }
            }
            if ($Id -eq 'APIM-SEC-003') {
                $models.apis[0].callerAuth = 'Entra/JWT'
            }
            $finding = @(Get-SyntheticSecFinding -RuleId $Id `
                    -Models $models)
            $finding.Count | Should -Be 1
            $finding[0].evaluation | Should -Be 'NotEvaluated'
            $finding[0].severity | Should -Be 'Info'
            $finding[0].evidence.missingInputs |
                Should -Contain "model/$(
                    if ($Id -eq 'APIM-SEC-015') {
                        'subscriptions'
                    }
                    else {
                        'apis'
                    }
                ).json#$Missing"
        }

        It 'marks each SEC rule NotEvaluated once when its required model is missing' {
            foreach ($id in @($script:secRules.Id)) {
                $finding = @(Get-SyntheticSecFinding -RuleId $id `
                        -Models ([ordered]@{}))
                $finding.Count | Should -Be 1
                $finding[0].evaluation | Should -Be 'NotEvaluated'
                $finding[0].severity | Should -Be 'Info'
                $finding[0].scope | Should -Be 'missing-input'
                $finding[0].evidence.missingInputs.Count | Should -Be 1
            }
        }

        It 'persists deterministic schema-valid SEC findings' {
            $models = Get-SyntheticSecModelSet
            $models.apis[0].corsUnsafe = $true
            $models.apis[0].bodyLogging = $true
            $models.apis[1].subscriptionRequired = $false
            $models.apis[1].callerAuth = 'None'
            $models.operations[0].mockOrTrace = $true
            $findings = @(Invoke-ApimRuleEngine -Rules $script:secRules `
                    -Models $models -Manifest $script:secRulesManifest `
                    -Config $script:secRulesConfig)
            @($findings.ruleId) | Should -Contain 'APIM-SEC-004'
            @($findings.ruleId) | Should -Contain 'APIM-SEC-020'
            $first = Write-ApimFindingSet -RunPath (
                Join-Path $TestDrive 'sec-first'
            ) -Findings $findings
            $second = Write-ApimFindingSet -RunPath (
                Join-Path $TestDrive 'sec-second'
            ) -Findings $findings
            $json = Get-Content -LiteralPath $first -Raw
            $json | Should -Be (Get-Content -LiteralPath $second -Raw)
            ($json | Test-Json -SchemaFile (
                    Join-Path $script:secRulesRepoRoot 'schemas/findings.schema.json'
                )) | Should -BeTrue
        }
    }
}
