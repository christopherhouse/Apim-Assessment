$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Closed model-safe analysis contracts' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)

        $script:analysisContractRepoRoot = $RepoRoot

        BeforeAll {
            function Get-AnalysisContractFixture {
                param([string] $Name)

                $path = Join-Path $script:analysisContractRepoRoot (
                    "tests/fixtures/synthetic-reference/analysis-contracts/$Name.json"
                )
                return Get-Content -LiteralPath $path -Raw |
                    ConvertFrom-Json -AsHashtable -Depth 32
            }

            function ConvertTo-ContractTestJson {
                param([object] $Value)

                return ConvertTo-Json -InputObject $Value -Depth 32 -Compress
            }

            function Test-ExecutiveContractFixture {
                param(
                    [System.Collections.IDictionary] $Summary,
                    [string[]] $ObservationJson
                )

                Test-ApimAnalysisContract -Kind ExecutiveSummary `
                    -Json (ConvertTo-ContractTestJson $Summary) `
                    -PackageJson (ConvertTo-ContractTestJson $script:contractPackage) `
                    -ObservationJson $ObservationJson
            }
        }

        BeforeEach {
            $script:contractPackage = Get-AnalysisContractFixture 'analysis-package'
            $script:contractArchitecture = Get-AnalysisContractFixture (
                'expert-observations.architecture'
            )
            $script:contractSecurity = Get-AnalysisContractFixture (
                'expert-observations.security'
            )
            $script:contractExecutive = Get-AnalysisContractFixture 'executive-summary'
            $script:contractObservationJson = @(
                ConvertTo-ContractTestJson $script:contractArchitecture
                ConvertTo-ContractTestJson $script:contractSecurity
            )
        }

        It 'accepts the synthetic package, both specialists, and their cited executive summary' {
            $packageJson = ConvertTo-ContractTestJson $script:contractPackage
            $result = @(Test-ApimAnalysisContract -Kind AnalysisPackage -Json $packageJson)
            $result.Count | Should -Be 1
            $result[0] | Should -BeTrue
            foreach ($json in $script:contractObservationJson) {
                Test-ApimAnalysisContract -Kind ExpertObservations -Json $json `
                    -PackageJson $packageJson | Should -BeTrue
            }
            Test-ExecutiveContractFixture -Summary $script:contractExecutive `
                -ObservationJson $script:contractObservationJson | Should -BeTrue
            @(Get-ChildItem -LiteralPath $TestDrive -Force).Count | Should -Be 0
        }

        It 'allows empty fact/finding/observation arrays without inventing successful findings' {
            $script:contractPackage.facts = @()
            $script:contractPackage.findings = @()
            $script:contractArchitecture.observations = @()
            $packageJson = ConvertTo-ContractTestJson $script:contractPackage
            Test-ApimAnalysisContract -Kind AnalysisPackage -Json $packageJson |
                Should -BeTrue
            Test-ApimAnalysisContract -Kind ExpertObservations -PackageJson $packageJson `
                -Json (ConvertTo-ContractTestJson $script:contractArchitecture) |
                Should -BeTrue
        }

        It 'rejects unknown fields in <Location>' -ForEach @(
            @{ Location = 'package'; Kind = 'AnalysisPackage' }
            @{ Location = 'entity'; Kind = 'AnalysisPackage' }
            @{ Location = 'fact'; Kind = 'AnalysisPackage' }
            @{ Location = 'finding'; Kind = 'AnalysisPackage' }
            @{ Location = 'specialist'; Kind = 'ExpertObservations' }
            @{ Location = 'observation'; Kind = 'ExpertObservations' }
            @{ Location = 'executive'; Kind = 'ExecutiveSummary' }
            @{ Location = 'priority'; Kind = 'ExecutiveSummary' }
        ) {
            $contract = switch ($Kind) {
                AnalysisPackage { $script:contractPackage }
                ExpertObservations { $script:contractArchitecture }
                ExecutiveSummary { $script:contractExecutive }
            }
            $target = switch ($Location) {
                entity { $contract.entities[0] }
                fact { $contract.facts[0] }
                finding { $contract.findings[0] }
                observation { $contract.observations[0] }
                priority { $contract.priorities[0] }
                default { $contract }
            }
            $target['unexpected'] = 'synthetic-private-canary'
            $parameters = @{ Kind = $Kind; Json = ConvertTo-ContractTestJson $contract }
            if ($Kind -ne 'AnalysisPackage') {
                $parameters.PackageJson = ConvertTo-ContractTestJson $script:contractPackage
            }
            {
                Test-ApimAnalysisContract @parameters
            } | Should -Throw '*schema validation failed*'
        }

        It 'rejects package <Name>' -ForEach @(
            @{ Name = 'literal URL'; Change = { param($x) $x.facts[0].value = 'https://example.invalid/private' } }
            @{ Name = 'unrestricted text'; Change = { param($x) $x.facts[0].value = 'synthetic unrestricted prose' } }
            @{ Name = 'exact usage'; Change = { param($x) $x.facts[3].value = 12345 } }
            @{ Name = 'exact cost'; Change = { param($x) $x.facts[0].code = 'CostTrend'; $x.facts[0].value = 123.45 } }
            @{ Name = 'exact priority'; Change = { param($x) $x.findings[0]['priorityScore'] = 9 } }
            @{ Name = 'negative count'; Change = { param($x) $x.facts[4].value = -1 } }
            @{ Name = 'excessive count'; Change = { param($x) $x.facts[4].value = 10001 } }
            @{ Name = 'fractional count'; Change = { param($x) $x.facts[4].value = 1.5 } }
            @{ Name = 'numeric boolean'; Change = { param($x) $x.facts[5].value = 0 } }
            @{ Name = 'code/value mismatch'; Change = { param($x) $x.facts[0].value = 'HostWide' } }
            @{ Name = 'unknown code'; Change = { param($x) $x.facts[0].code = 'UnapprovedCode' } }
            @{ Name = 'invalid alias'; Change = { param($x) $x.entities[0].alias = 'synthetic.example.invalid' } }
            @{ Name = 'zero alias'; Change = { param($x) $x.entities[0].alias = 'service-000' } }
            @{ Name = 'newline alias'; Change = { param($x) $x.entities[0].alias = "service-001`n" } }
            @{ Name = 'unicode alias'; Change = { param($x) $x.entities[0].alias = 'service-' + [char]0xFF11 + '01' } }
            @{ Name = 'incorrect alias kind'; Change = { param($x) $x.entities[0].kind = 'Api' } }
            @{ Name = 'duplicate alias'; Change = { param($x) $x.entities += $x.entities[0] } }
            @{ Name = 'duplicate fact ID'; Change = { param($x) $x.facts[1].factId = $x.facts[0].factId } }
            @{ Name = 'newline fact ID'; Change = { param($x) $x.facts[0].factId += "`n" } }
            @{ Name = 'duplicate finding ID'; Change = { param($x) $x.findings[1].findingId = $x.findings[0].findingId } }
            @{ Name = 'unresolved fact subject'; Change = { param($x) $x.facts[0].subjectAlias = 'network-999' } }
            @{ Name = 'unresolved finding subject'; Change = { param($x) $x.findings[0].subjectAlias = 'route-999' } }
            @{ Name = 'unresolved fact reference'; Change = { param($x) $x.findings[0].factRefs = @('fact-999999') } }
            @{ Name = 'cross-kind fact reference'; Change = { param($x) $x.findings[0].factRefs = @('finding-000001') } }
            @{ Name = 'uncited evaluated finding'; Change = { param($x) $x.findings[0].factRefs = @() } }
            @{ Name = 'NotEvaluated severity override'; Change = { param($x) $x.findings[2].severity = 'High' } }
            @{ Name = 'NotEvaluated priority override'; Change = { param($x) $x.findings[2].priorityBucket = 'High' } }
            @{ Name = 'unqualified NotEvaluated finding'; Change = { param($x) $x.findings[2].dataGaps = @() } }
            @{ Name = 'omitted finding data gap'; Change = { param($x) $x.dataGaps = @('UsageUnavailable') } }
            @{ Name = 'duplicate citation'; Change = { param($x) $x.findings[0].factRefs = @('fact-000002', 'fact-000002') } }
        ) {
            & $Change $script:contractPackage
            {
                Test-ApimAnalysisContract -Kind AnalysisPackage `
                    -Json (ConvertTo-ContractTestJson $script:contractPackage)
            } | Should -Throw
        }

        It 'permits bounded counts, booleans, unknown posture, and relative cost trends' {
            foreach ($value in @(0, 10000)) {
                $script:contractPackage.facts[4].value = $value
                Test-ApimAnalysisContract -Kind AnalysisPackage `
                    -Json (ConvertTo-ContractTestJson $script:contractPackage) |
                    Should -BeTrue
            }
            foreach ($value in @($true, $false, $null)) {
                $script:contractPackage.facts[5].value = $value
                Test-ApimAnalysisContract -Kind AnalysisPackage `
                    -Json (ConvertTo-ContractTestJson $script:contractPackage) |
                    Should -BeTrue
            }
            $script:contractPackage.facts[0].code = 'CostTrend'
            $script:contractPackage.facts[0].value = 'Increasing'
            Test-ApimAnalysisContract -Kind AnalysisPackage `
                -Json (ConvertTo-ContractTestJson $script:contractPackage) |
                Should -BeTrue
        }

        It 'rejects specialist <Name>' -ForEach @(
            @{ Name = 'unknown rationale'; Change = { param($x) $x.observations[0].rationaleCode = 'invented narrative' } }
            @{ Name = 'free-text recommendation'; Change = { param($x) $x.observations[0].recommendationCode = 'synthetic prose' } }
            @{ Name = 'severity override'; Change = { param($x) $x.observations[0]['severity'] = 'Low' } }
            @{ Name = 'resolved finding'; Change = { param($x) $x.observations[0]['status'] = 'Resolved' } }
            @{ Name = 'unresolved finding'; Change = { param($x) $x.observations[0].findingRefs = @('finding-999999') } }
            @{ Name = 'unresolved fact'; Change = { param($x) $x.observations[0].factRefs = @('fact-999999') } }
            @{ Name = 'uncited observation'; Change = { param($x) $x.observations[0].findingRefs = @(); $x.observations[0].factRefs = @() } }
            @{ Name = 'duplicate observation ID'; Change = { param($x) $x.observations += $x.observations[0] } }
            @{ Name = 'wrong analyst ID'; Change = { param($x) $x.observations[0].observationId = 'observation-security-001' } }
            @{ Name = 'newline observation ID'; Change = { param($x) $x.observations[0].observationId += "`n" } }
            @{ Name = 'wrong analyst category'; Change = { param($x) $x.observations[0].category = 'Security' } }
        ) {
            & $Change $script:contractArchitecture
            {
                Test-ApimAnalysisContract -Kind ExpertObservations `
                    -Json (ConvertTo-ContractTestJson $script:contractArchitecture) `
                    -PackageJson (ConvertTo-ContractTestJson $script:contractPackage)
            } | Should -Throw
        }

        It 'rejects executive <Name>' -ForEach @(
            @{ Name = 'unapproved code'; Change = { param($x) $x.priorities[0].code = 'unsupported narrative' } }
            @{ Name = 'wrong item section'; Change = { param($x) $x.priorities[0].itemId = 'theme-001' } }
            @{ Name = 'duplicate item ID'; Change = { param($x) $x.priorities[1].itemId = $x.priorities[0].itemId } }
            @{ Name = 'unresolved finding'; Change = { param($x) $x.priorities[0].findingRefs = @('finding-999999') } }
            @{ Name = 'unresolved fact'; Change = { param($x) $x.decisions[0].factRefs = @('fact-999999') } }
            @{ Name = 'unresolved observation'; Change = { param($x) $x.priorities[0].observationRefs = @('observation-architecture-999') } }
            @{ Name = 'uncited item'; Change = { param($x) $x.priorities[0].findingRefs = @(); $x.priorities[0].observationRefs = @() } }
            @{ Name = 'lost assumption'; Change = { param($x) $x.assumptions = @('TelemetryUnavailable') } }
            @{ Name = 'invented assumption'; Change = { param($x) $x.assumptions += 'OwnerIntentUnverified' } }
            @{ Name = 'lost data gap'; Change = { param($x) $x.dataGaps = @('UsageUnavailable') } }
            @{ Name = 'invented data gap'; Change = { param($x) $x.dataGaps += 'RbacUnavailable' } }
        ) {
            & $Change $script:contractExecutive
            {
                Test-ExecutiveContractFixture -Summary $script:contractExecutive `
                    -ObservationJson $script:contractObservationJson
            } | Should -Throw
        }

        It 'accepts a deterministic-only executive summary without specialist references' {
            foreach ($priority in $script:contractExecutive.priorities) {
                $priority.observationRefs = @()
            }
            Test-ApimAnalysisContract -Kind ExecutiveSummary `
                -Json (ConvertTo-ContractTestJson $script:contractExecutive) `
                -PackageJson (ConvertTo-ContractTestJson $script:contractPackage) |
                Should -BeTrue
        }

        It 'does not trust unresolved, invalid, or repeated specialist context' {
            $script:contractArchitecture.observations[0].factRefs = @('fact-999999')
            {
                Test-ExecutiveContractFixture -Summary $script:contractExecutive `
                    -ObservationJson @(
                        ConvertTo-ContractTestJson $script:contractArchitecture
                        ConvertTo-ContractTestJson $script:contractSecurity
                    )
            } | Should -Throw '*unsupported reference*'
            {
                Test-ExecutiveContractFixture -Summary $script:contractExecutive `
                    -ObservationJson @(
                        $script:contractObservationJson[0]
                        $script:contractObservationJson[0]
                    )
            } | Should -Throw '*duplicate analyst roles*'
            {
                Test-ExecutiveContractFixture -Summary $script:contractExecutive `
                    -ObservationJson @()
            } | Should -Throw '*unsupported reference*'
        }

        It 'requires package context and validates it before accepting observations' {
            $json = ConvertTo-ContractTestJson $script:contractArchitecture
            {
                Test-ApimAnalysisContract -Kind ExpertObservations -Json $json
            } | Should -Throw '*requires a validated package context*'
            $script:contractPackage.facts[1].factId = $script:contractPackage.facts[0].factId
            {
                Test-ApimAnalysisContract -Kind ExpertObservations -Json $json `
                    -PackageJson (ConvertTo-ContractTestJson $script:contractPackage)
            } | Should -Throw '*invalid fact IDs*'
        }

        It 'rejects duplicate decoded JSON member names even when both values are valid' {
            $json = ConvertTo-ContractTestJson $script:contractPackage
            foreach ($duplicate in @(
                    '"schemaVersion":"1.0",',
                    '"schema\u0056ersion":"1.0",'
                )) {
                $candidate = '{' + $duplicate + $json.Substring(1)
                {
                    Test-ApimAnalysisContract -Kind AnalysisPackage -Json $candidate
                } | Should -Throw '*JSON or schema validation failed*'
            }
            $nested = $json.Replace(
                '"value":"Internal"', '"value":"Internal","value":"Internal"'
            )
            {
                Test-ApimAnalysisContract -Kind AnalysisPackage -Json $nested
            } | Should -Throw '*JSON or schema validation failed*'
        }

        It 'fails closed without reflecting planted input or validator errors' {
            $canary = 'synthetic-private-' + 'canary'
            $json = '{"schemaVersion":"1.0","unexpected":"' + $canary + '"}'
            $errorRecord = $null
            try { Test-ApimAnalysisContract -Kind AnalysisPackage -Json $json }
            catch { $errorRecord = $_ }
            $errorRecord | Should -Not -BeNullOrEmpty
            $errorRecord.ToString() | Should -Not -Match $canary
            Mock Test-Json { throw 'synthetic-private-canary' }
            $errorRecord = $null
            try {
                Test-ApimAnalysisContract -Kind AnalysisPackage `
                    -Json (ConvertTo-ContractTestJson $script:contractPackage)
            }
            catch { $errorRecord = $_ }
            $errorRecord.ToString() | Should -Be (
                'Analysis contract JSON or schema validation failed.'
            )
        }

        It 'rejects malformed and excessive JSON before invoking schema validation' {
            Mock Test-Json { $true }
            foreach ($json in @(
                    '{invalid',
                    (('{"nested":' * 33) + '{}' + ('}' * 33))
                )) {
                {
                    Test-ApimAnalysisContract -Kind AnalysisPackage -Json $json
                } | Should -Throw '*JSON or schema validation failed*'
            }
            foreach ($json in @(
                    (' ' * (16MB + 1)),
                    ([string][char]0x0100 * (8MB + 1))
                )) {
                {
                    Test-ApimAnalysisContract -Kind AnalysisPackage -Json $json
                } | Should -Throw '*size limit exceeded*'
            }
            Should -Invoke Test-Json -Times 0 -Exactly
        }

        It 'rejects unknown schema versions and inappropriate reference contexts' {
            $script:contractPackage.schemaVersion = '9.9'
            $json = ConvertTo-ContractTestJson $script:contractPackage
            {
                Test-ApimAnalysisContract -Kind AnalysisPackage -Json $json
            } | Should -Throw '*schema validation failed*'
            {
                Test-ApimAnalysisContract -Kind AnalysisPackage -Json $json `
                    -PackageJson $json
            } | Should -Throw '*does not accept external reference context*'
            {
                Test-ApimAnalysisContract -Kind ExpertObservations `
                    -Json '{}' -ObservationJson @()
            } | Should -Throw '*Only executive validation*'
        }
    }
}
