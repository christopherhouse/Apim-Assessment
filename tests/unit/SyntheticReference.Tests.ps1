$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Scaled synthetic reference models' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)

        $script:syntheticReferenceRoot = Join-Path $RepoRoot (
            'tests/fixtures/synthetic-reference'
        )

        BeforeAll {
            . (Join-Path $script:syntheticReferenceRoot (
                    'scaled/New-SyntheticReference.ps1'
                ))
        }

        It 'returns all ten valid models and exact structural counts (usage=<Usage>)' `
            -TestCases @(@{ Usage = $false }, @{ Usage = $true }) {
            param($Usage)

            $models = New-SyntheticReferenceModelSet -WithUsage:$Usage
            $models -is [System.Collections.IDictionary] | Should -BeTrue
            @($models.Keys) | Should -Be @(
                'service', 'apis', 'operations', 'policyMatrix', 'subscriptions',
                'namedValues', 'backends', 'certificates', 'network', 'exposure'
            )
            foreach ($name in $models.Keys) {
                Test-ApimModelJson -Name $name -Json (
                    ConvertTo-Json -InputObject $models[$name] -Depth 100
                )
            }
            foreach ($name in 'apis', 'operations', 'policyMatrix', 'exposure') {
                $models[$name].Count | Should -Be 60
                @($models[$name].apiId | Select-Object -Unique).Count |
                    Should -Be 60
            }
            $models.apis.apiId | Should -Be @(1..60 | ForEach-Object {
                    'api-{0:d3}' -f $_
                })
            $models.subscriptions.Count | Should -Be 6
            @($models.subscriptions | Where-Object scopeType -EQ AllApis).Count |
                Should -Be 4
            $models.subscriptions[0].scopeTarget | Should -Be 'api-001'
            $models.namedValues.Count | Should -Be 3
            $models.backends.Count | Should -Be 2
            $models.certificates.Count | Should -Be 2
            @($models.apis | Where-Object { $_.products.Count -eq 0 }).Count |
                Should -Be 14
            @($models.apis | Where-Object {
                    $_.callerAuth -eq 'SubscriptionKeyOnly' -and
                    $_.reachability -eq 'Reachable'
                }).Count | Should -Be 7
            @($models.apis | Where-Object baseMissing).Count | Should -Be 3
            @($models.apis | Where-Object hardcodedSecret).Count | Should -Be 2
        }

        It 'keeps policy cohorts coherent across APIs, operations, matrix and routes' {
            $models = New-SyntheticReferenceModelSet
            for ($i = 0; $i -lt 60; $i++) {
                $api = $models.apis[$i]
                $operation = $models.operations[$i]
                $matrix = $models.policyMatrix[$i]
                $route = $models.exposure[$i]
                $policy = New-SyntheticReferencePolicy -Index ($i + 1)
                $flags = $policy.flags
                foreach ($record in @($operation, $matrix, $route, $policy)) {
                    $record.apiId | Should -Be $api.apiId
                }
                $operation.products | Should -Be $api.products
                $operation.fullPath | Should -Be "/$($api.path)"
                $operation.callerAuthJwt | Should -Be ($i -ge 7)
                $operation.hasUnauthenticatedPolicyPath | Should -Be ($i -lt 7)
                $operation.callerAuthModes.Count | Should -Be ([int]($i -ge 7))
                $operation.throttlingAllPaths | Should -Be $api.throttling
                foreach ($name in 'baseMissing', 'hardcodedSecret', 'throttling') {
                    $api[$name] | Should -Be $flags.$name
                    $operation[$name] | Should -Be $flags.$name
                }
                $matrix.callerAuth | Should -Be $(
                    if ($i -lt 7) { 'Fail' } else { 'Pass' }
                )
                $matrix.rateLimit | Should -Be $matrix.callerAuth
                $matrix.basePresent | Should -Be $(
                    if ($i -lt 3) { 'Fail' } else { 'Pass' }
                )
                $matrix.noHardcodedSecret | Should -Be $(
                    if ($i -lt 2) { 'Fail' } else { 'Pass' }
                )
                $route.routeKey | Should -Be (
                    'agw-synthetic-prod|public-https|' +
                    "api.synthetic.invalid|/*|$($api.apiId)"
                )
                $route.reachability | Should -Be 'Reachable'
                $route.restriction | Should -Be 'None'
                $route.ruleType | Should -Be 'Basic'
                $route.pattern | Should -Be '/*'
                $route.wafState | Should -Be 'Disabled'
                $route.edge | Should -Be 'Cloudflare-Assumed'
                $route.confidence | Should -Be 'Medium'
            }
            $models.network.virtualNetworkType | Should -Be 'Internal'
            $models.network.nsgEvaluation | Should -Be 'Restricted'
            $models.network.directPublic | Should -BeFalse
            $models.network.wafState | Should -Be 'Disabled'
        }

        It 'does not invent usage, zero calls, or external usage classification by default' {
            $models = New-SyntheticReferenceModelSet
            foreach ($name in 'apis', 'operations', 'subscriptions', 'exposure') {
                foreach ($record in $models[$name]) {
                    $record.missingInputs | Should -Contain 'usage'
                    $record.modelStatus | Should -Be 'Partial'
                    foreach ($field in 'calls90d', 'callsViaAppGw', 'callsInternal',
                        'lastCall', 'lastUsed', 'p95Ms', 'backendP95Ms', 'pct5xx') {
                        if ($record.Contains($field)) {
                            $record[$field] | Should -BeNullOrEmpty
                        }
                    }
                }
            }
            foreach ($record in @($models.apis) + @($models.exposure)) {
                $record.exposure | Should -Be 'Unknown'
            }
        }

        It 'supplies exactly eleven unused APIs only in the explicit usage scenario' {
            $models = New-SyntheticReferenceModelSet -WithUsage
            @($models.apis | Where-Object calls90d -EQ 0).apiId |
                Should -Be @(50..60 | ForEach-Object { 'api-{0:d3}' -f $_ })
            foreach ($i in 0..59) {
                $api = $models.apis[$i]
                $route = $models.exposure[$i]
                $models.operations[$i].calls90d | Should -Be $api.calls90d
                $route.callsViaAppGw | Should -Be $api.calls90d
                $api.callsInternal | Should -Be 0
                $route.callsInternal | Should -Be 0
                $api.exposure | Should -Be $route.exposure
                $route.exposure | Should -Be $(
                    if ($i -ge 49) { 'ExternalUnintended' }
                    else { 'ExternalInUse' }
                )
                foreach ($record in @($api, $models.operations[$i], $route)) {
                    $record.missingInputs | Should -Not -Contain 'usage'
                }
                $api.missingInputs | Should -Contain 'diagnostics'
                $api.p95Ms | Should -BeNullOrEmpty
                $api.modelStatus | Should -Be 'Partial'
            }
            foreach ($subscription in $models.subscriptions) {
                $subscription.calls90d | Should -BeNullOrEmpty
                $subscription.missingInputs | Should -Contain 'usage'
            }
        }

        It 'detects the artificial candidate before protection and exposes only redacted evidence' {
            $script:syntheticDetectedBeforeProtect = $false
            $script:syntheticOriginalDetect = (
                Get-Command Get-ApimPolicySecretLocation
            ).ScriptBlock
            $script:syntheticOriginalProtect = (
                Get-Command Protect-ApimPolicyXml
            ).ScriptBlock
            Mock Get-ApimPolicySecretLocation {
                $result = @(& $script:syntheticOriginalDetect -Document $Document)
                if ($Document.OuterXml -notmatch '\*\*\*REDACTED\*\*\*') {
                    $result.Count | Should -Be 1
                    $script:syntheticDetectedBeforeProtect = $true
                }
                return $result
            }
            Mock Protect-ApimPolicyXml {
                $script:syntheticDetectedBeforeProtect | Should -BeTrue
                $Xml | Should -Not -Match '\*\*\*REDACTED\*\*\*'
                & $script:syntheticOriginalProtect -Xml $Xml
            }
            $policy = New-SyntheticReferencePolicy -Index 1
            $script:syntheticDetectedBeforeProtect | Should -BeTrue
            $policy.secretLocations.Count | Should -Be 1
            Should -Invoke Protect-ApimPolicyXml -Times 1 -Exactly
            Should -Invoke Get-ApimPolicySecretLocation -Times 2 -Exactly
        }

        It 'returns sanitized policy XML with exact secret locations and no literal candidate' {
            foreach ($index in 1..60) {
                $policy = New-SyntheticReferencePolicy -Index $index
                $policy.secretLocations.Count | Should -Be ([int]($index -le 2))
                if ($index -le 2) {
                    $policy.secretLocations | Should -Be @(
                        '/policies[1]/inbound[1]/set-header[1]/value[1]'
                    )
                    $policy.xml | Should -Match '\*\*\*REDACTED\*\*\*'
                    $policy.flags.hardcodedSecret | Should -BeTrue
                }
                $candidate = @('synthetic', 'credential', $index) -join '-'
                (ConvertTo-Json -InputObject $policy -Depth 100).Contains($candidate) |
                    Should -BeFalse
            }
        }

        It 'is deterministic, independent and round-trips with existing persistence (usage=<Usage>)' `
            -TestCases @(@{ Usage = $false }, @{ Usage = $true }) {
            param($Usage)

            $models = New-SyntheticReferenceModelSet -WithUsage:$Usage
            $json = ConvertTo-Json -InputObject $models -Depth 100
            $json | Should -Be (ConvertTo-Json -Depth 100 -InputObject (
                    New-SyntheticReferenceModelSet -WithUsage:$Usage
                ))
            $runPath = Join-Path $TestDrive "models-$Usage"
            $paths = @(Write-ApimModelSet -RunPath $runPath -Models $models)
            $paths.Count | Should -Be 10
            $hashes = @($paths | ForEach-Object { (Get-FileHash $_).Hash })
            $loaded = Get-ApimModelSet -RunPath $runPath
            (ConvertTo-Json -InputObject $loaded -Depth 100) | Should -Be $json
            $null = Write-ApimModelSet -RunPath $runPath -Models $loaded
            @($paths | ForEach-Object { (Get-FileHash $_).Hash }) |
                Should -Be $hashes
            foreach ($path in $paths) {
                $saved = Get-Content -LiteralPath $path -Raw
                foreach ($index in 1..2) {
                    $saved.Contains(
                        (@('synthetic', 'credential', $index) -join '-')
                    ) | Should -BeFalse
                }
            }
            $models.apis[0].products[0] = 'changed'
            $models.apis[1].products | Should -Be @('internal')
            $fresh = New-SyntheticReferenceModelSet -WithUsage:$Usage
            $fresh.apis[0].products | Should -Be @('internal')
        }

        It 'preserves compact raw, policy and model fixtures byte-for-byte' {
            $files = @(foreach ($folder in 'raw', 'policies', 'model') {
                    Get-ChildItem -LiteralPath (
                        Join-Path $script:syntheticReferenceRoot $folder
                    ) -File -Recurse
                })
            $before = @($files | ForEach-Object { (Get-FileHash $_.FullName).Hash })
            $null = New-SyntheticReferenceModelSet
            $null = New-SyntheticReferenceModelSet -WithUsage
            @($files | ForEach-Object { (Get-FileHash $_.FullName).Hash }) |
                Should -Be $before
            $compact = Get-Content -LiteralPath (
                Join-Path $script:syntheticReferenceRoot 'model/apis.json'
            ) -Raw | ConvertFrom-Json
            $compact.Count | Should -Be 2
            $compact.apiId | Should -Be @('orders-v1', 'status-v1')
        }
    }
}
