$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Private offline rule engine and findings contract' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)
        $script:ruleRepoRoot = $RepoRoot

        BeforeAll {
            $script:ruleConfig = Import-PowerShellDataFile (
                Join-Path $script:ruleRepoRoot 'config/sample.psd1'
            )
            $script:ruleConfig.Output.Root = Join-Path $TestDrive 'restricted'
            $run = New-ApimRun -Config $script:ruleConfig `
                -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000002' `
                -Operator Synthetic -RunId 'synthetic-rules'
            $script:ruleManifest = Get-RunManifest -RunPath $run.Path
            $script:ruleModels = [ordered]@{
                apis = Get-Content -LiteralPath (
                    Join-Path $script:ruleRepoRoot (
                        'tests/fixtures/synthetic-reference/model/apis.exposure.json'
                    )
                ) -Raw | ConvertFrom-Json -Depth 100 -NoEnumerate
            }

            function Get-SyntheticRule {
                return @{
                    Id = 'APIM-SEC-003'
                    Title = 'Synthetic caller authentication check'
                    Pillar = 'Security'
                    Mcsb = 'IM-1'
                    Severity = 'High'
                    Scope = 'Api'
                    Requires = @('model/apis.json')
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
                        [ordered]@{ callerAuth = $x.callerAuth }
                    }
                    EvidenceText = {
                        param($x, $ctx)
                        $null = $x
                        $null = $ctx
                        'Synthetic evidence'
                    }
                    Recommendation = 'Use caller authentication.'
                    Effort = 'M'
                    References = @()
                    SourceFiles = @('raw/apis.json')
                    Enabled = $true
                }
            }
        }

        It 'emits one deterministic finding for a matching API, not a passing API' {
            $rule = Get-SyntheticRule
            $first = @(Invoke-ApimRuleEngine -Rules @($rule) `
                    -Models $script:ruleModels -Manifest $script:ruleManifest `
                    -Config $script:ruleConfig)
            $second = @(Invoke-ApimRuleEngine -Rules @($rule) `
                    -Models $script:ruleModels -Manifest $script:ruleManifest `
                    -Config $script:ruleConfig)

            $first.Count | Should -Be 1
            $first[0].findingKey |
                Should -Be 'APIM-SEC-003|apim-example-prod|api:status-v1'
            $first[0].evaluation | Should -Be 'Evaluated'
            $first[0].usage | Should -BeNullOrEmpty
            $first[0].exposure | Should -Be 'Unknown'
            $first[0].priorityScore | Should -Be 4.5
            (ConvertTo-Json -InputObject $first -Depth 100) |
                Should -Be (ConvertTo-Json -InputObject $second -Depth 100)
            $runPath = Join-Path $TestDrive 'repeated-findings'
            $path = Write-ApimFindingSet -RunPath $runPath -Findings $first
            $before = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            $null = Write-ApimFindingSet -RunPath $runPath -Findings $second
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash |
                Should -Be $before
        }

        It 'uses configurable severity, exposure, and actual usage weights' {
            $models = [ordered]@{
                apis = ConvertFrom-Json -InputObject (
                    ConvertTo-Json -InputObject $script:ruleModels.apis `
                        -Depth 100
                ) -Depth 100 -NoEnumerate
            }
            $models.apis[1].calls90d = 0
            $models.apis[1].exposure = 'Restricted'
            $config = $script:ruleConfig.Clone()
            $config.Scoring = @{
                Severity = @{ High = 2; Info = 0.5 }
                Exposure = @{ Restricted = 1.25; Unknown = 1; Platform = 1 }
                Usage = @{ Unused = 1.2; InUse = 2; NotApplicable = 1 }
            }
            $finding = @(Invoke-ApimRuleEngine -Rules @((Get-SyntheticRule)) `
                    -Models $models -Manifest $script:ruleManifest `
                    -Config $config)[0]
            $finding.usage | Should -Be 'Unused'
            $finding.priorityScore | Should -Be 3

            $models.apis[1].calls90d = 7
            $finding = @(Invoke-ApimRuleEngine -Rules @((Get-SyntheticRule)) `
                    -Models $models -Manifest $script:ruleManifest `
                    -Config $config)[0]
            $finding.usage | Should -Be 'InUse'
            $finding.priorityScore | Should -Be 5
        }

        It 'emits exactly one Info/NotEvaluated per rule when a required model is missing or failed' {
            $rule = Get-SyntheticRule
            $rule.Requires = @('model/apis.json', 'model/network.json')
            $models = [ordered]@{ apis = $script:ruleModels.apis }
            $finding = @(Invoke-ApimRuleEngine -Rules @($rule) -Models $models `
                    -Manifest $script:ruleManifest `
                    -Config $script:ruleConfig)[0]
            $finding.evaluation | Should -Be 'NotEvaluated'
            $finding.severity | Should -Be 'Info'
            $finding.scope | Should -Be 'missing-input'
            $finding.evidence.missingInputs | Should -Be @('model/network.json')
            $path = Write-ApimFindingSet -RunPath (
                Join-Path $TestDrive 'not-evaluated-output'
            ) -Findings @($finding)
            Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue

            $models.network = Get-Content -LiteralPath (
                Join-Path $script:ruleRepoRoot (
                    'tests/fixtures/synthetic-reference/model/network.json'
                )
            ) -Raw | ConvertFrom-Json -Depth 100 -NoEnumerate
            $finding = @(Invoke-ApimRuleEngine -Rules @($rule) -Models $models `
                    -Manifest $script:ruleManifest -Config $script:ruleConfig `
                    -UnavailableInputs 'model/network.json')[0]
            $finding.evaluation | Should -Be 'NotEvaluated'
            $finding.evidence.missingInputs | Should -Be @('model/network.json')
        }

        It 'marks an unavailable fact in a valid model NotEvaluated rather than a pass' {
            $rule = Get-SyntheticRule
            $rule.DataGaps = {
                param($ctx)
                if ($null -eq $ctx.Models.apis[0].calls90d) {
                    'model/apis.json#calls90d'
                }
            }
            $result = @(Invoke-ApimRuleEngine -Rules @($rule) `
                    -Models $script:ruleModels -Manifest $script:ruleManifest `
                    -Config $script:ruleConfig)
            $result.Count | Should -Be 1
            $result[0].evaluation | Should -Be 'NotEvaluated'
            $result[0].severity | Should -Be 'Info'
            $result[0].evidence.missingInputs |
                Should -Be @('model/apis.json#calls90d')
            $path = Write-ApimFindingSet -RunPath (
                Join-Path $TestDrive 'fact-gap'
            ) -Findings $result
            Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
        }

        It 'rejects undeclared or malformed fact-gap references' {
            $rule = Get-SyntheticRule
            $rule.DataGaps = { param($ctx) $null = $ctx; 'model/network.json#wafState' }
            {
                Invoke-ApimRuleEngine -Rules @($rule) `
                    -Models $script:ruleModels -Manifest $script:ruleManifest `
                    -Config $script:ruleConfig
            } | Should -Throw 'Rule data gap referenced an undeclared model field.'
            $rule.DataGaps = { param($ctx) $null = $ctx; '../private' }
            {
                Invoke-ApimRuleEngine -Rules @($rule) `
                    -Models $script:ruleModels -Manifest $script:ruleManifest `
                    -Config $script:ruleConfig
            } | Should -Throw 'Rule data gap referenced an undeclared model field.'
        }

        It 'rejects malformed available model data instead of marking it missing or passing' {
            $models = [ordered]@{ apis = @([pscustomobject]@{ apiId = 'bad' }) }
            {
                Invoke-ApimRuleEngine -Rules @((Get-SyntheticRule)) `
                    -Models $models -Manifest $script:ruleManifest `
                    -Config $script:ruleConfig
            } | Should -Throw "Model 'apis' failed schema validation."
        }

        It 'sorts by descending priority, then ordinal rule ID and scope' {
            $first = Get-SyntheticRule
            $first.Id = 'APIM-SEC-010'
            $first.Test = {
                param($x, $ctx)
                $null = $x
                $null = $ctx
                $true
            }
            $second = Get-SyntheticRule
            $second.Id = 'APIM-SEC-002'
            $second.Test = {
                param($x, $ctx)
                $null = $x
                $null = $ctx
                $true
            }
            $result = @(Invoke-ApimRuleEngine -Rules @($first, $second) `
                    -Models $script:ruleModels -Manifest $script:ruleManifest `
                    -Config $script:ruleConfig)
            @($result.ruleId) | Should -Be @(
                'APIM-SEC-002', 'APIM-SEC-002',
                'APIM-SEC-010', 'APIM-SEC-010'
            )
            $result[0].scope | Should -Be 'api:orders-v1'
            $result[1].scope | Should -Be 'api:status-v1'
        }

        It 'builds stable target keys for implemented <Scope> scope' `
            -TestCases @(
                @{ Scope = 'Operation'; Model = 'operations'; Prefix = 'operation:' }
                @{ Scope = 'Subscription'; Model = 'subscriptions'; Prefix = 'subscription:' }
                @{ Scope = 'NamedValue'; Model = 'namedValues'; Prefix = 'named-value:' }
                @{ Scope = 'Backend'; Model = 'backends'; Prefix = 'backend:' }
                @{ Scope = 'Certificate'; Model = 'certificates'; Prefix = 'certificate:' }
                @{ Scope = 'Route'; Model = 'exposure'; Prefix = 'route:' }
                @{ Scope = 'Network'; Model = 'network'; Prefix = 'network' }
            ) {
            param($Scope, $Model, $Prefix)

            $models = [ordered]@{}
            $models[$Model] = Get-Content -LiteralPath (
                Join-Path $script:ruleRepoRoot (
                    "tests/fixtures/synthetic-reference/model/$Model.json"
                )
            ) -Raw | ConvertFrom-Json -Depth 100 -NoEnumerate
            $rule = Get-SyntheticRule
            $rule.Scope = $Scope
            $rule.Requires = @("model/$Model.json")
            $rule.Applies = $null
            $rule.Evidence = {
                param($x, $ctx)
                $null = $x
                $null = $ctx
                @{ synthetic = $true }
            }
            $rule.Test = {
                param($x, $ctx)
                $null = $x
                $null = $ctx
                $true
            }
            $result = @(Invoke-ApimRuleEngine -Rules @($rule) `
                    -Models $models -Manifest $script:ruleManifest `
                    -Config $script:ruleConfig)
            $result.Count | Should -BeGreaterThan 0
            $result[0].scope.StartsWith($Prefix) | Should -BeTrue
            $result[0].findingKey |
                Should -Be "APIM-SEC-003|apim-example-prod|$($result[0].scope)"
        }

        It 'evaluates a service rule from the validated manifest' {
            $rule = Get-SyntheticRule
            $rule.Scope = 'Service'
            $rule.Requires = @()
            $rule.SourceFiles = @('raw/service.json')
            $rule.Applies = $null
            $rule.Evidence = {
                param($x, $ctx)
                $null = $x
                $null = $ctx
                @{ synthetic = $true }
            }
            $rule.Test = {
                param($x, $ctx)
                $null = $ctx
                $x.resourceId -like '*/service/*'
            }
            $result = @(Invoke-ApimRuleEngine -Rules @($rule) `
                    -Models ([ordered]@{}) -Manifest $script:ruleManifest `
                    -Config $script:ruleConfig)
            $result.Count | Should -Be 1
            $result[0].scope | Should -Be 'service'
            $result[0].exposure | Should -Be 'Platform'
            $result[0].usage | Should -Be 'NotApplicable'
        }

        It 'writes an empty findings array when every target passes' {
            $rule = Get-SyntheticRule
            $rule.Test = {
                param($x, $ctx)
                $null = $x
                $null = $ctx
                $false
            }
            $findings = @(Invoke-ApimRuleEngine -Rules @($rule) `
                    -Models $script:ruleModels -Manifest $script:ruleManifest `
                    -Config $script:ruleConfig)
            $findings.Count | Should -Be 0
            $path = Write-ApimFindingSet -RunPath (
                Join-Path $TestDrive 'empty-findings'
            ) -Findings $findings
            (Get-Content -LiteralPath $path -Raw).Trim() | Should -Be '[]'
        }

        It 'rejects a rule with invalid callback output and duplicate IDs' {
            $rule = Get-SyntheticRule
            $rule.Test = {
                param($x, $ctx)
                $null = $x
                $null = $ctx
                'true'
            }
            {
                Invoke-ApimRuleEngine -Rules @($rule) -Models $script:ruleModels `
                    -Manifest $script:ruleManifest -Config $script:ruleConfig
            } | Should -Throw 'Rule Test must return a Boolean.'

            $rule = Get-SyntheticRule
            {
                Invoke-ApimRuleEngine -Rules @($rule, $rule) `
                    -Models $script:ruleModels -Manifest $script:ruleManifest `
                    -Config $script:ruleConfig
            } | Should -Throw 'Rule catalog contains a duplicate rule ID.'
        }

        It 'rejects invalid evidence instead of returning a finding' {
            $rule = Get-SyntheticRule
            $rule.Evidence = {
                param($x, $ctx)
                $null = $x
                $null = $ctx
                'not-an-object'
            }
            {
                Invoke-ApimRuleEngine -Rules @($rule) -Models $script:ruleModels `
                    -Manifest $script:ruleManifest -Config $script:ruleConfig
            } | Should -Throw 'Rule evidence has an invalid contract.'
        }

        It 'loads only implemented catalog files and rejects malformed definitions' {
            $catalog = Join-Path $TestDrive 'catalog'
            $null = New-Item -Path $catalog -ItemType Directory -Force
            { Get-ApimRuleCatalog -CatalogPath $catalog } |
                Should -Throw 'Rule catalog has no implemented definitions.'
            $rule = Get-SyntheticRule
            $rule.Enabled = $false
            $ruleFile = Join-Path $catalog 'SEC.rules.ps1'
            $literal = "@{ Id = 'APIM-SEC-003'; Enabled = `$false }"
            Set-Content -LiteralPath $ruleFile -Value $literal
            { Get-ApimRuleCatalog -CatalogPath $catalog } |
                Should -Throw "Rule definition is missing 'Title'."
            $rule.Enabled | Should -BeFalse
        }

        It 'loads a valid synthetic catalog and skips a disabled rule' {
            $catalog = Join-Path $TestDrive 'valid-catalog'
            $null = New-Item -Path $catalog -ItemType Directory -Force
            @'
@{
    Id = 'APIM-SEC-003'
    Title = 'Synthetic check'
    Pillar = 'Security'
    Mcsb = 'IM-1'
    Severity = 'High'
    Scope = 'Api'
    Requires = @('model/apis.json')
    Applies = { param($x, $ctx) $null = $ctx; $x.reachability -eq 'Reachable' }
    Test = { param($x, $ctx) $null = $ctx; $x.callerAuth -eq 'None' }
    Evidence = { param($x, $ctx) $null = $ctx; @{ callerAuth = $x.callerAuth } }
    EvidenceText = { param($x, $ctx) $null = $x; $null = $ctx; 'Synthetic' }
    Recommendation = 'Use caller authentication.'
    Effort = 'M'
    References = @()
    SourceFiles = @('raw/apis.json')
    Enabled = $false
}
'@ | Set-Content -LiteralPath (Join-Path $catalog 'SEC.rules.ps1')

            $rules = @(Get-ApimRuleCatalog -CatalogPath $catalog)
            $rules.Count | Should -Be 1
            @(Invoke-ApimRuleEngine -Rules $rules `
                    -Models $script:ruleModels -Manifest $script:ruleManifest `
                    -Config $script:ruleConfig).Count | Should -Be 0
        }

        It 'rejects unsupported rule scopes and missing declared target models' {
            $rule = Get-SyntheticRule
            $rule.Scope = 'Portal'
            {
                Invoke-ApimRuleEngine -Rules @($rule) -Models $script:ruleModels `
                    -Manifest $script:ruleManifest -Config $script:ruleConfig
            } | Should -Throw 'Rule definition has an invalid contract.'
            $rule.Scope = 'Api'
            $rule.Requires = @('model/network.json')
            {
                Invoke-ApimRuleEngine -Rules @($rule) -Models $script:ruleModels `
                    -Manifest $script:ruleManifest -Config $script:ruleConfig
            } | Should -Throw 'Rule definition must require its target model.'
        }

        It 'validates findings before writing and preserves the output on invalid input' {
            $findings = @(Invoke-ApimRuleEngine -Rules @((Get-SyntheticRule)) `
                    -Models $script:ruleModels -Manifest $script:ruleManifest `
                    -Config $script:ruleConfig)
            $runPath = Join-Path $TestDrive 'findings-output'
            $path = Write-ApimFindingSet -RunPath $runPath -Findings $findings
            (Get-Content -LiteralPath $path -Raw | Test-Json `
                -SchemaFile $script:ApimFindingsSchemaPath) | Should -BeTrue
            $before = (Get-FileHash -LiteralPath $path).Hash
            $findings[0].usage = 'invalid'
            {
                Write-ApimFindingSet -RunPath $runPath -Findings $findings
            } | Should -Throw 'Findings failed schema validation.'
            (Get-FileHash -LiteralPath $path).Hash | Should -Be $before
        }

        It 'rejects a valid-shape finding with an inconsistent key or duplicate key' {
            $findings = @(Invoke-ApimRuleEngine -Rules @((Get-SyntheticRule)) `
                    -Models $script:ruleModels -Manifest $script:ruleManifest `
                    -Config $script:ruleConfig)
            $runPath = Join-Path $TestDrive 'invalid-keys'
            $findings[0].findingKey = 'APIM-SEC-003|wrong|api:status-v1'
            {
                Write-ApimFindingSet -RunPath $runPath -Findings $findings
            } | Should -Throw 'Findings contain an invalid or duplicate finding key.'
            $findings[0].findingKey = 'APIM-SEC-003|apim-example-prod|api:status-v1'
            {
                Write-ApimFindingSet -RunPath $runPath `
                    -Findings @($findings[0], $findings[0])
            } | Should -Throw 'Findings contain an invalid or duplicate finding key.'
            Test-Path -LiteralPath $runPath | Should -BeFalse
        }

        It 'rejects a NotEvaluated finding with non-Info severity' {
            $rule = Get-SyntheticRule
            $findings = @(Invoke-ApimRuleEngine -Rules @($rule) `
                    -Models ([ordered]@{}) -Manifest $script:ruleManifest `
                    -Config $script:ruleConfig)
            $findings[0].severity = 'High'
            {
                Write-ApimFindingSet -RunPath (
                    Join-Path $TestDrive 'invalid-not-evaluated'
                ) -Findings $findings
            } | Should -Throw 'Findings failed schema validation.'
        }

        It 'refuses a missing findings schema without persisting a file' {
            $original = $script:ApimFindingsSchemaPath
            $script:ApimFindingsSchemaPath = Join-Path $TestDrive 'absent.json'
            $runPath = Join-Path $TestDrive 'missing-schema'
            try {
                {
                    Write-ApimFindingSet -RunPath $runPath -Findings @()
                } | Should -Throw 'Findings schema was unavailable.'
                (Test-Path -LiteralPath (Join-Path $runPath 'findings.json')) |
                    Should -BeFalse
            }
            finally {
                $script:ApimFindingsSchemaPath = $original
            }
        }
    }
}
