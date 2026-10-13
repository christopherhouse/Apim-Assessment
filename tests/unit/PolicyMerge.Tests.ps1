$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixtureRoot = Join-Path $repoRoot 'tests/fixtures/synthetic-reference'
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Effective APIM policy merge' {
    InModuleScope ApimAssessment -Parameters @{ FixtureRoot = $fixtureRoot } {
        param($FixtureRoot)

        $script:mergeFixtureRoot = $FixtureRoot

        BeforeAll {
            $script:globalPolicy = @'
<policies>
  <inbound><set-header name="x-global"><value>global</value></set-header></inbound>
  <backend><forward-request /></backend>
  <outbound />
  <on-error />
</policies>
'@
            $script:productPolicy = @'
<policies>
  <inbound><base /><rate-limit calls="20" renewal-period="60" /></inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
'@
            $script:apiPolicy = @'
<policies>
  <inbound>
    <base />
    <include-fragment fragment-id="common-auth" />
    <set-header name="x-api"><value>api</value></set-header>
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
'@
            $script:operationPolicy = @'
<policies>
  <inbound><base /><set-header name="x-operation"><value>operation</value></set-header></inbound>
  <backend><authentication-basic username="{{user}}" password="{{password}}" /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
'@
            $script:fragments = @{
                'common-auth' = @'
<fragment>
  <validate-jwt header-name="Authorization" />
</fragment>
'@
            }
        }

        It 'merges base inheritance, fragments, and source attribution' {
            $result = @(Merge-ApimPolicy -GlobalPolicy $script:globalPolicy `
                    -ProductPolicies @{ partner = $script:productPolicy } `
                    -ProductNames @('partner') -ApiPolicy $script:apiPolicy `
                    -OperationPolicy $script:operationPolicy `
                    -Fragments $script:fragments -ApiName 'orders-v1' `
                    -OperationName 'get-orders')

            $result.Count | Should -Be 1
            $document = ConvertTo-ApimPolicyXmlDocument `
                -Xml $result[0].effectiveXml
            $inbound = $document.DocumentElement.SelectSingleNode('inbound')
            @($inbound.ChildNodes | ForEach-Object LocalName) | Should -Be @(
                'set-header',
                'rate-limit',
                'validate-jwt',
                'set-header',
                'set-header'
            )
            $inbound.ChildNodes[0].GetAttribute('data-scope') |
                Should -Be 'global'
            $inbound.ChildNodes[1].GetAttribute('data-scope') |
                Should -Be 'product:partner'
            $inbound.ChildNodes[2].GetAttribute('data-scope') |
                Should -Be 'fragment:common-auth'
            $inbound.ChildNodes[3].GetAttribute('data-scope') |
                Should -Be 'api:orders-v1'
            $inbound.ChildNodes[4].GetAttribute('data-scope') |
                Should -Be 'operation:orders-v1|get-orders'

            $backend = $document.DocumentElement.SelectSingleNode('backend')
            @($backend.ChildNodes | ForEach-Object LocalName) |
                Should -Be @('authentication-basic')
            $result[0].baseMissing | ConvertTo-Json -Compress |
                Should -Be (
                    @(
                        [ordered]@{
                            scope = 'operation:orders-v1|get-orders'
                            section = 'backend'
                        }
                    ) | ConvertTo-Json -Compress
                )
            $result[0].fragmentIssues | Should -BeNullOrEmpty
            $result[0].sha256 | Should -Be (
                Get-ApimPolicySha256 -Xml $result[0].effectiveXml
            )
        }

        It 'inherits the parent unchanged when child policies are absent' {
            $result = @(Merge-ApimPolicy -GlobalPolicy $script:globalPolicy `
                    -ProductNames @('internal') -ApiName 'status-v1' `
                    -OperationName 'get-status')

            $result.Count | Should -Be 1
            $result[0].product | Should -Be 'internal'
            $result[0].baseMissing | Should -BeNullOrEmpty
            $result[0].effectiveXml | Should -Match 'x-global'
        }

        It 'detects a fragment cycle and retains an unresolved marker' {
            $apiPolicy = @'
<policies>
  <inbound><include-fragment fragment-id="a" /></inbound>
</policies>
'@
            $fragments = @{
                a = '<fragment><include-fragment fragment-id="b" /></fragment>'
                b = '<fragment><include-fragment fragment-id="a" /></fragment>'
            }

            $result = @(Merge-ApimPolicy -ApiPolicy $apiPolicy `
                    -Fragments $fragments -ApiName 'cycle-api' `
                    -OperationName 'cycle-operation')

            $result[0].product | Should -BeNullOrEmpty
            $result[0].fragmentIssues.Count | Should -Be 1
            $result[0].fragmentIssues[0].type | Should -Be 'Cycle'
            $result[0].fragmentIssues[0].path | Should -Be 'a>b>a'
            $result[0].effectiveXml | Should -Match (
                'data-fragment-status="Cycle"'
            )
        }

        It 'enforces the fragment expansion depth limit' {
            $apiPolicy = @'
<policies>
  <inbound><include-fragment fragment-id="f1" /></inbound>
</policies>
'@
            $fragments = @{
                f1 = '<fragment><include-fragment fragment-id="f2" /></fragment>'
                f2 = '<fragment><include-fragment fragment-id="f3" /></fragment>'
                f3 = '<fragment><include-fragment fragment-id="f4" /></fragment>'
                f4 = '<fragment><include-fragment fragment-id="f5" /></fragment>'
                f5 = '<fragment><include-fragment fragment-id="f6" /></fragment>'
                f6 = '<fragment><set-header name="x"><value>done</value></set-header></fragment>'
            }

            $result = @(Merge-ApimPolicy -ApiPolicy $apiPolicy `
                    -Fragments $fragments -ApiName 'depth-api' `
                    -OperationName 'depth-operation' -FragmentMaxDepth 5)

            $result[0].fragmentIssues.Count | Should -Be 1
            $result[0].fragmentIssues[0].type |
                Should -Be 'DepthExceeded'
            $result[0].fragmentIssues[0].fragmentId | Should -Be 'f6'
            $result[0].effectiveXml |
                Should -Match 'data-fragment-status="DepthExceeded"'
        }

        It 'retains a missing fragment marker with an explicit issue' {
            $apiPolicy = @'
<policies>
  <inbound><include-fragment fragment-id="not-present" /></inbound>
</policies>
'@

            $result = @(Merge-ApimPolicy -ApiPolicy $apiPolicy `
                    -ApiName 'missing-api' -OperationName 'missing-operation')

            $result[0].fragmentIssues.Count | Should -Be 1
            $result[0].fragmentIssues[0].type | Should -Be 'Missing'
            $result[0].fragmentIssues[0].fragmentId |
                Should -Be 'not-present'
            $result[0].effectiveXml |
                Should -Match 'data-fragment-status="Missing"'
        }

        It 'creates stable product paths and applies conservative flag aggregation' {
            $results = @(Merge-ApimPolicy -GlobalPolicy $script:globalPolicy `
                    -ProductPolicies @{ partner = $script:productPolicy } `
                    -ProductNames @('partner', 'internal') `
                    -ApiPolicy $script:apiPolicy -Fragments $script:fragments `
                    -ApiName 'orders-v1' -OperationName 'get-orders')

            $results.product | Should -Be @('internal', 'partner')
            $results[0].effectiveXml | Should -Not -Match 'rate-limit'
            $results[1].effectiveXml | Should -Match 'rate-limit'

            $flags = Merge-ApimProductPolicyFlag -ProductFlags @(
                @{ hardcodedSecret = $true; callerAuth = $true }
                @{ hardcodedSecret = $false; callerAuth = $false }
            ) -RiskFlag @('hardcodedSecret') -ControlFlag @('callerAuth')
            $flags.hardcodedSecret | Should -BeTrue
            $flags.callerAuth | Should -BeFalse
        }

        It 'produces identical effective hashes for formatting-only changes' {
            $alternateProduct = @'
<policies><inbound><base/><rate-limit renewal-period="60" calls="20"/></inbound>
<backend><base/></backend><outbound><base/></outbound><on-error><base/></on-error></policies>
'@
            $first = @(Merge-ApimPolicy -GlobalPolicy $script:globalPolicy `
                    -ProductPolicies @{ partner = $script:productPolicy } `
                    -ProductNames @('partner') -ApiName 'orders-v1' `
                    -OperationName 'get-orders')
            $second = @(Merge-ApimPolicy -GlobalPolicy $script:globalPolicy `
                    -ProductPolicies @{ partner = $alternateProduct } `
                    -ProductNames @('partner') -ApiName 'orders-v1' `
                    -OperationName 'get-orders')

            $first[0].sha256 | Should -Be $second[0].sha256
            $first[0].normalizedXml | Should -Be $second[0].normalizedXml
        }

        It 'matches the synthetic multi-product effective policy fixtures' {
            $policyRoot = Join-Path $script:mergeFixtureRoot 'policies'
            $globalPolicy = Get-Content -LiteralPath (
                Join-Path $policyRoot 'global.xml'
            ) -Raw
            $productPolicies = @{
                partner = Get-Content -LiteralPath (
                    Join-Path $policyRoot 'product.partner.xml'
                ) -Raw
            }
            $fragments = @{
                'common-auth' = Get-Content -LiteralPath (
                    Join-Path $policyRoot 'fragment.common-auth.xml'
                ) -Raw
            }

            $apiProducts = @{}
            foreach ($productName in @('internal', 'partner')) {
                $payload = Get-Content -LiteralPath (
                    Join-Path $script:mergeFixtureRoot `
                        "raw/productApis/$productName.json"
                ) -Raw | ConvertFrom-Json -Depth 100
                foreach ($apiName in Get-ApimCollectionResourceName `
                        -Payload $payload -CollectionName 'Product API') {
                    if (-not $apiProducts.ContainsKey($apiName)) {
                        $apiProducts[$apiName] = @()
                    }
                    $apiProducts[$apiName] = @($apiProducts[$apiName]) +
                        $productName
                }
            }

            $results = @(
                Merge-ApimPolicy -GlobalPolicy $globalPolicy `
                    -ProductPolicies $productPolicies `
                    -ProductNames $apiProducts['orders-v1'] `
                    -ApiPolicy (Get-Content -LiteralPath (
                            Join-Path $policyRoot 'api.orders-v1.xml'
                        ) -Raw) `
                    -OperationPolicy (Get-Content -LiteralPath (
                            Join-Path $policyRoot `
                                'op.orders-v1.get-orders.xml'
                        ) -Raw) `
                    -Fragments $fragments -ApiName 'orders-v1' `
                    -OperationName 'get-orders'
                Merge-ApimPolicy -GlobalPolicy $globalPolicy `
                    -ProductPolicies $productPolicies `
                    -ProductNames $apiProducts['status-v1'] `
                    -Fragments $fragments -ApiName 'status-v1' `
                    -OperationName 'get-status'
            )
            $results = @($results | Sort-Object apiId, operationId, product)

            $expected = Get-Content -LiteralPath (
                Join-Path $script:mergeFixtureRoot 'model/policyMerge.json'
            ) -Raw | ConvertFrom-Json -Depth 100
            $expected.effectivePolicies.Count | Should -Be $results.Count
            for ($index = 0; $index -lt $results.Count; $index++) {
                $actual = $results[$index]
                $expectedEntry = $expected.effectivePolicies[$index]
                $actual.product | Should -Be $expectedEntry.product
                $actual.apiId | Should -Be $expectedEntry.apiId
                $actual.operationId | Should -Be $expectedEntry.operationId
                $actual.sha256 | Should -Be $expectedEntry.sha256
                ($actual.baseMissing | ConvertTo-Json -Depth 20 -Compress) |
                    Should -Be (
                        $expectedEntry.baseMissing |
                            ConvertTo-Json -Depth 20 -Compress
                    )
                ($actual.fragmentIssues | ConvertTo-Json -Depth 20 -Compress) |
                    Should -Be (
                        $expectedEntry.fragmentIssues |
                            ConvertTo-Json -Depth 20 -Compress
                    )
                $expectedXml = Get-Content -LiteralPath (
                    Join-Path $script:mergeFixtureRoot $expectedEntry.file
                ) -Raw
                $actual.normalizedXml | Should -Be (
                    ConvertTo-ApimNormalizedPolicyXml -Xml $expectedXml
                )
            }
        }
    }
}
