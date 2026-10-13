$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Policy XML safety and hashing' {
    InModuleScope ApimAssessment {
        It 'redacts hard-coded policy secret candidates and records locations only' {
            $xml = @'
<policies>
  <inbound>
    <set-header name="x-api-key" exists-action="override">
      <value>synthetic-secret-value</value>
    </set-header>
    <send-request url="https://example.invalid/path?sig=synthetic-signature" />
  </inbound>
  <backend>
    <authentication-basic username="{{backend-user}}" password="synthetic-password" />
  </backend>
</policies>
'@

            $result = Protect-ApimPolicyXml -Xml $xml

            $result.Xml | Should -Not -Match 'synthetic-secret-value'
            $result.Xml | Should -Not -Match 'synthetic-signature'
            $result.Xml | Should -Not -Match 'synthetic-password'
            $result.Xml | Should -Match (
                'url="https://\*\*\*REDACTED\*\*\*"'
            )
            ([regex]::Matches($result.Xml, '\*\*\*REDACTED\*\*\*')).Count |
                Should -Be 3
            $result.SecretLocations | Should -Be @(
                '/policies[1]/backend[1]/authentication-basic[1]/@password'
                '/policies[1]/inbound[1]/send-request[1]/@url'
                '/policies[1]/inbound[1]/set-header[1]/value[1]'
            )
        }

        It 'preserves named-value references without treating them as literals' {
            $xml = @'
<policies>
  <inbound>
    <set-header name="x-api-key" exists-action="override">
      <value>{{api-key}}</value>
    </set-header>
  </inbound>
</policies>
'@

            $result = Protect-ApimPolicyXml -Xml $xml

            $result.Xml | Should -Match '\{\{api-key\}\}'
            $result.SecretLocations | Should -BeNullOrEmpty
        }

        It 'preserves dynamic authorization expressions without secret literals' {
            $xml = @'
<policies>
  <inbound>
    <set-header name="Authorization" exists-action="override">
      <value>@(context.Request.Headers.GetValueOrDefault("Authorization", ""))</value>
    </set-header>
  </inbound>
</policies>
'@

            $result = Protect-ApimPolicyXml -Xml $xml

            $result.Xml | Should -Match 'GetValueOrDefault'
            $result.SecretLocations | Should -BeNullOrEmpty
        }

        It 'redacts URL user information while retaining only the scheme' {
            $xml = @'
<policies>
  <inbound>
    <send-request url="https://synthetic-user:synthetic-pass@example.invalid/path" />
  </inbound>
</policies>
'@

            $result = Protect-ApimPolicyXml -Xml $xml

            $result.Xml | Should -Not -Match 'synthetic-user'
            $result.Xml | Should -Not -Match 'synthetic-pass'
            $result.Xml | Should -Match (
                'url="https://\*\*\*REDACTED\*\*\*"'
            )
            $result.SecretLocations | Should -Be @(
                '/policies[1]/inbound[1]/send-request[1]/@url'
            )
        }

        It 'hashes equivalent policy XML identically' {
            $first = @'
<policies>
  <!-- ignored -->
  <inbound>
    <set-header name="x" exists-action="override"><value>synthetic</value></set-header>
  </inbound>
</policies>
'@
            $second = @'
<policies><inbound><set-header exists-action="override" name="x">
<value> synthetic </value></set-header></inbound></policies>
'@

            Get-ApimPolicySha256 -Xml $first |
                Should -Be (Get-ApimPolicySha256 -Xml $second)
        }

        It 'rejects document type declarations without exposing source content' {
            {
                Protect-ApimPolicyXml -Xml (
                    '<!DOCTYPE policies [<!ENTITY private "synthetic">]>' +
                    '<policies>&private;</policies>'
                )
            } | Should -Throw '*prohibited document type*'
        }

        It 'rejects malformed attribute quoting without repairing policy source' {
            $invalidXml = '<policies><inbound><set-header ' +
                'name="bad "quote"" /></inbound></policies>'

            { Protect-ApimPolicyXml -Xml $invalidXml } |
                Should -Throw 'Policy XML was invalid or used a prohibited document type.'
        }

        It 'accepts XML-encoded quotes in a policy expression attribute' {
            $xml = '<policies><inbound><set-variable name="synthetic" ' +
                'value="@(context.Request.Headers.ContainsKey(&quot;jwt&quot;))" />' +
                '</inbound></policies>'

            $protected = Protect-ApimPolicyXml -Xml $xml

            $protected.Xml | Should -Match '&quot;jwt&quot;'
            $protected.SecretLocations | Should -BeNullOrEmpty
        }

        It 'rejects XML that is not a policy or fragment document' {
            {
                Protect-ApimPolicyXml -Xml '<configuration />'
            } | Should -Throw '*supported policy root*'
        }
    }
}
