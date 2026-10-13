$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Effective APIM policy flags' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)

        $script:policyFlagRepoRoot = $RepoRoot
        $emptyPolicyForCases = @'
<policies>
  <inbound />
  <backend />
  <outbound />
  <on-error />
</policies>
'@
        $positiveCases = @(
            @{
                name = 'JWT caller authentication'
                flag = 'callerAuthJwt'
                xml = '<policies><inbound><validate-jwt /></inbound></policies>'
            }
            @{
                name = 'Azure AD caller authentication'
                flag = 'callerAuthJwt'
                xml = '<policies><inbound><validate-azure-ad-token /></inbound></policies>'
            }
            @{
                name = 'client certificate validation'
                flag = 'callerAuthMtls'
                xml = '<policies><inbound><validate-client-certificate /></inbound></policies>'
            }
            @{
                name = 'certificate choose condition'
                flag = 'callerAuthMtls'
                xml = '<policies><inbound><choose><when condition="@(context.Request.Certificate != null)" /></choose></inbound></policies>'
            }
            @{
                name = 'rate limit'
                flag = 'throttling'
                xml = '<policies><inbound><rate-limit calls="1" renewal-period="60" /></inbound></policies>'
            }
            @{
                name = 'rate limit by key'
                flag = 'throttling'
                xml = '<policies><inbound><rate-limit-by-key calls="1" renewal-period="60" counter-key="x" /></inbound></policies>'
            }
            @{
                name = 'quota'
                flag = 'throttling'
                xml = '<policies><inbound><quota calls="1" renewal-period="60" /></inbound></policies>'
            }
            @{
                name = 'quota by key'
                flag = 'throttling'
                xml = '<policies><inbound><quota-by-key calls="1" renewal-period="60" counter-key="x" /></inbound></policies>'
            }
            @{
                name = 'LLM token limit'
                flag = 'throttling'
                xml = '<policies><inbound><llm-token-limit counter-key="x" tokens-per-minute="1" /></inbound></policies>'
            }
            @{
                name = 'Azure OpenAI token limit'
                flag = 'throttling'
                xml = '<policies><inbound><azure-openai-token-limit counter-key="x" tokens-per-minute="1" /></inbound></policies>'
            }
            @{
                name = 'IP filter'
                flag = 'ipFilter'
                xml = '<policies><inbound><ip-filter action="allow"><address>192.0.2.1</address></ip-filter></inbound></policies>'
            }
            @{
                name = 'original URL host restriction'
                flag = 'hostRestriction'
                xml = '<policies><inbound><choose><when condition="@(context.Request.OriginalUrl.Host != &quot;api.example.invalid&quot;)"><return-response><set-status code="403" reason="Forbidden" /></return-response></when></choose></inbound></policies>'
            }
            @{
                name = 'Host header restriction'
                flag = 'hostRestriction'
                xml = '<policies><inbound><choose><when condition="@(context.Request.Headers.GetValueOrDefault(&quot;Host&quot;) != &quot;api.example.invalid&quot;)"><return-response><set-status code="404" reason="Not Found" /></return-response></when></choose></inbound></policies>'
            }
            @{
                name = 'unsafe credentialed wildcard CORS'
                flag = 'corsUnsafe'
                xml = '<policies><inbound><cors allow-credentials="true"><allowed-origins><origin>*</origin></allowed-origins></cors></inbound></policies>'
            }
            @{
                name = 'managed identity backend authentication'
                flag = 'backendAuth'
                xml = '<policies><inbound><authentication-managed-identity resource="synthetic" /></inbound></policies>'
            }
            @{
                name = 'certificate backend authentication'
                flag = 'backendAuth'
                xml = '<policies><inbound><authentication-certificate certificate-id="synthetic" /></inbound></policies>'
            }
            @{
                name = 'authorization context backend authentication'
                flag = 'backendAuth'
                xml = '<policies><inbound><get-authorization-context provider-id="synthetic" /></inbound></policies>'
            }
            @{
                name = 'hard-coded header secret'
                flag = 'hardcodedSecret'
                xml = '<policies><inbound><set-header name="x-api-key"><value>synthetic-secret</value></set-header></inbound></policies>'
            }
            @{
                name = 'hard-coded query secret'
                flag = 'hardcodedSecret'
                xml = '<policies><inbound><set-query-parameter name="token"><value>synthetic-token</value></set-query-parameter></inbound></policies>'
            }
            @{
                name = 'hard-coded basic credential'
                flag = 'hardcodedSecret'
                xml = '<policies><inbound><authentication-basic username="synthetic-user" password="{{synthetic-password}}" /></inbound></policies>'
            }
            @{
                name = 'backend override'
                flag = 'backendOverride'
                xml = '<policies><inbound><set-backend-service backend-id="synthetic-backend" /></inbound></policies>'
            }
            @{
                name = 'plain HTTP backend override'
                flag = 'backendOverrideHttp'
                xml = '<policies><inbound><set-backend-service base-url="http://backend.example.invalid" /></inbound></policies>'
            }
            @{
                name = 'mock response'
                flag = 'mockOrTrace'
                xml = '<policies><inbound><mock-response status-code="200" /></inbound></policies>'
            }
            @{
                name = 'trace'
                flag = 'mockOrTrace'
                xml = '<policies><inbound><trace source="synthetic"><message>test</message></trace></inbound></policies>'
            }
            @{
                name = 'unconditional inbound response'
                flag = 'returnsWithoutBackend'
                xml = '<policies><inbound><return-response><set-status code="200" /></return-response></inbound></policies>'
            }
            @{
                name = 'missing base metadata'
                flag = 'baseMissing'
                xml = $emptyPolicyForCases
                baseMissing = @(
                    @{
                        scope = 'operation:synthetic-api|synthetic-operation'
                        section = 'backend'
                    }
                )
            }
        )
        $negativeCases = @(
            @{
                name = 'JWT caller authentication'
                flag = 'callerAuthJwt'
                xml = '<policies><inbound><set-header name="x"><value>safe</value></set-header></inbound></policies>'
            }
            @{
                name = 'mTLS caller authentication'
                flag = 'callerAuthMtls'
                xml = '<policies><inbound><choose><when condition="@(context.Request.Method == &quot;GET&quot;)" /></choose></inbound></policies>'
            }
            @{
                name = 'throttling'
                flag = 'throttling'
                xml = '<policies><inbound><retry count="1" interval="1" /></inbound></policies>'
            }
            @{
                name = 'IP filtering'
                flag = 'ipFilter'
                xml = '<policies><inbound><set-header name="x-forwarded-for"><value>safe</value></set-header></inbound></policies>'
            }
            @{
                name = 'host restriction'
                flag = 'hostRestriction'
                xml = '<policies><inbound><choose><when condition="@(context.Request.OriginalUrl.Host == &quot;api.example.invalid&quot;)"><return-response><set-status code="200" /></return-response></when></choose></inbound></policies>'
            }
            @{
                name = 'unsafe CORS'
                flag = 'corsUnsafe'
                xml = '<policies><inbound><cors allow-credentials="false"><allowed-origins><origin>*</origin></allowed-origins></cors></inbound></policies>'
            }
            @{
                name = 'backend authentication'
                flag = 'backendAuth'
                xml = '<policies><inbound><set-backend-service backend-id="synthetic" /></inbound></policies>'
            }
            @{
                name = 'hard-coded secret'
                flag = 'hardcodedSecret'
                xml = '<policies><inbound><set-header name="x-api-key"><value>{{synthetic-key}}</value></set-header><authentication-basic username="{{synthetic-user}}" password="{{synthetic-password}}" /></inbound></policies>'
            }
            @{
                name = 'backend override'
                flag = 'backendOverride'
                xml = '<policies><backend><forward-request /></backend></policies>'
            }
            @{
                name = 'plain HTTP backend override'
                flag = 'backendOverrideHttp'
                xml = '<policies><inbound><set-backend-service base-url="https://backend.example.invalid" /></inbound></policies>'
            }
            @{
                name = 'mock or trace'
                flag = 'mockOrTrace'
                xml = '<policies><inbound><set-header name="x"><value>safe</value></set-header></inbound></policies>'
            }
            @{
                name = 'return without backend'
                flag = 'returnsWithoutBackend'
                xml = '<policies><inbound><choose><when condition="@(true)"><return-response><set-status code="200" /></return-response></when></choose></inbound></policies>'
            }
            @{
                name = 'missing base'
                flag = 'baseMissing'
                xml = $emptyPolicyForCases
            }
        )

        BeforeAll {
            $script:emptyPolicy = @'
<policies>
  <inbound />
  <backend />
  <outbound />
  <on-error />
</policies>
'@
        }

        It 'detects <name>' -ForEach $positiveCases {
            param($flag, $xml, $baseMissing)

            $parameters = @{ EffectiveXml = $xml }
            if ($null -ne $baseMissing) {
                $parameters.BaseMissing = $baseMissing
            }
            $result = Get-ApimPolicyFlags @parameters

            $result.$flag | Should -BeTrue
        }

        It 'does not report <name> when its required pattern is absent' `
            -ForEach $negativeCases {
            param($flag, $xml)

            $result = Get-ApimPolicyFlags -EffectiveXml $xml

            $result.$flag | Should -BeFalse
        }

        It 'captures deterministic IP filter and backend override evidence' {
            $xml = @'
<policies>
  <inbound>
    <ip-filter action="allow" data-scope="api:synthetic-api">
      <address>192.0.2.2</address>
      <address>192.0.2.1</address>
      <address-range from="198.51.100.1" to="198.51.100.10" />
    </ip-filter>
    <set-backend-service data-scope="operation:synthetic-api|synthetic-operation" base-url="http://backend.example.invalid/path" />
  </inbound>
</policies>
'@

            $result = Get-ApimPolicyFlags -EffectiveXml $xml

            $result.ipFilters[0].action | Should -Be 'allow'
            $result.ipFilters[0].scope | Should -Be 'api:synthetic-api'
            $result.ipFilters[0].addresses |
                Should -Be @('192.0.2.1', '192.0.2.2')
            $result.ipFilters[0].addressRanges[0].from |
                Should -Be '198.51.100.1'
            $result.backendOverrides[0].scope |
                Should -Be 'operation:synthetic-api|synthetic-operation'
            $result.backendOverrides[0].baseUrl |
                Should -Be 'http://backend.example.invalid/path'
            $result.backendOverrideHttp | Should -BeTrue
        }

        It 'marks unresolved fragments as a partial evaluation' {
            $xml = @'
<policies>
  <inbound>
    <include-fragment data-scope="api:synthetic-api" fragment-id="missing" data-fragment-status="Missing" />
  </inbound>
</policies>
'@

            $result = Get-ApimPolicyFlags -EffectiveXml $xml

            $result.evaluationStatus | Should -Be 'Partial'
            $result.unresolvedFragments.Count | Should -Be 1
            $result.unresolvedFragments[0].fragmentId | Should -Be 'missing'
            $result.unresolvedFragments[0].scope |
                Should -Be 'api:synthetic-api'
        }

        It 'treats backend entity credentials as backend authentication' {
            $result = Get-ApimPolicyFlags `
                -EffectiveXml $script:emptyPolicy `
                -BackendCredentialConfigured

            $result.backendAuth | Should -BeTrue
        }

        It 'preserves hard-coded-secret flags and locations after redaction' {
            $xml = @'
<policies>
  <inbound>
    <set-header name="x-api-key"><value>synthetic-secret</value></set-header>
    <authentication-basic username="synthetic-user" password="synthetic-password" />
  </inbound>
</policies>
'@
            $before = Get-ApimPolicyFlags -EffectiveXml $xml
            $protected = Protect-ApimPolicyXml -Xml $xml
            $after = Get-ApimPolicyFlags -EffectiveXml $protected.Xml

            $before.hardcodedSecret | Should -BeTrue
            $after.hardcodedSecret | Should -BeTrue
            $after.hardcodedSecretLocations |
                Should -Be $before.hardcodedSecretLocations
            $protected.SecretLocations |
                Should -Be $before.hardcodedSecretLocations
            $protected.Xml | Should -Not -Match 'synthetic-secret'
            $protected.Xml | Should -Not -Match 'synthetic-password'
            $protected.Xml | Should -Not -Match 'synthetic-user'
            ([regex]::Matches(
                    $protected.Xml,
                    '\*\*\*REDACTED\*\*\*'
                )).Count | Should -Be 3
        }

        It 'does not turn redacted backend URLs into hard-coded-secret flags' {
            $xml = @'
<policies>
  <inbound>
    <set-backend-service base-url="http://backend.example.invalid/path?sig=synthetic-signature" />
  </inbound>
</policies>
'@
            $before = Get-ApimPolicyFlags -EffectiveXml $xml
            $protected = Protect-ApimPolicyXml -Xml $xml
            $after = Get-ApimPolicyFlags -EffectiveXml $protected.Xml

            $before.hardcodedSecret | Should -BeFalse
            $after.hardcodedSecret | Should -BeFalse
            $before.backendOverrideHttp | Should -BeTrue
            $after.backendOverrideHttp | Should -BeTrue
            $after.backendOverrides[0].baseUrl |
                Should -Be 'http://***REDACTED***'
            $protected.Xml | Should -Not -Match 'synthetic-signature'
        }

        It 'matches flags from the saved sanitized effective-policy fixtures' {
            $fixtureRoot = Join-Path $script:policyFlagRepoRoot `
                'tests/fixtures/synthetic-reference'
            $mergeSummary = Get-Content -LiteralPath (
                Join-Path $fixtureRoot 'model/policyMerge.json'
            ) -Raw | ConvertFrom-Json -Depth 100
            $expectedSummary = Get-Content -LiteralPath (
                Join-Path $fixtureRoot 'model/policyFlags.json'
            ) -Raw | ConvertFrom-Json -Depth 100

            $expectedSummary.policies.Count |
                Should -Be $mergeSummary.effectivePolicies.Count
            for ($index = 0;
                $index -lt $expectedSummary.policies.Count;
                $index++) {
                $mergeEntry = $mergeSummary.effectivePolicies[$index]
                $expected = $expectedSummary.policies[$index]
                $xml = Get-Content -LiteralPath (
                    Join-Path $fixtureRoot $mergeEntry.file
                ) -Raw
                $actual = Get-ApimPolicyFlags -EffectiveXml $xml `
                    -BaseMissing $mergeEntry.baseMissing

                $expected.product | Should -Be $mergeEntry.product
                $expected.apiId | Should -Be $mergeEntry.apiId
                $expected.operationId | Should -Be $mergeEntry.operationId
                $actual.evaluationStatus |
                    Should -Be $expected.evaluationStatus
                foreach ($property in $expected.flags.PSObject.Properties) {
                    $actual.($property.Name) | Should -Be $property.Value
                }
                $actual.hardcodedSecretLocations |
                    Should -Be $expected.hardcodedSecretLocations
            }
        }

        It 'rejects unsupported roots and invalid metadata' {
            {
                Get-ApimPolicyFlags -EffectiveXml '<fragment />'
            } | Should -Throw '*policies root*'
            {
                Get-ApimPolicyFlags -EffectiveXml $script:emptyPolicy `
                    -BaseMissing @(@{
                            scope = 'api:synthetic-api'
                            section = 'invalid'
                        })
            } | Should -Throw '*invalid entry*'
        }
    }
}
