BeforeAll {
    $script:apiRepo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:apiSource = Join-Path $script:apiRepo 'infra\live-validation-lab'
    . (Join-Path $script:apiRepo 'scripts\lab\LabBootstrap.Core.ps1')
    . (Join-Path $script:apiRepo 'scripts\lab\LabFoundation.Core.ps1')
    . (Join-Path $script:apiRepo 'scripts\lab\LabApis.Core.ps1')
    $script:apiSample = [IO.File]::ReadAllText((Join-Path $script:apiSource 'apis.sample.json'))
}

Describe 'Closed private lab API parameters' {
    BeforeEach {
        $script:apiConfig = Read-LabJson $script:apiSample
    }

    It 'writes only the required API parameters and calculated gateway bounds' {
        $result = Get-LabApiParameterSet $script:apiSample
        @($result.parameters.Keys) | Should -Be @('apimName', 'tenantId', 'frontendResourceClientId',
            'backendAudienceClientId', 'workerClientId', 'backendOrigin', 'workerPrivateIp',
            'gatewayAddressStart', 'gatewayAddressEnd')
        $result.parameters.gatewayAddressStart.value | Should -BeExactly '10.240.0.0'
        $result.parameters.gatewayAddressEnd.value | Should -BeExactly '10.240.0.255'
        $result.parameters.backendOrigin.value | Should -BeExactly 'https://backend.synthetic.invalid'
        $result.parameters.workerPrivateIp.value | Should -BeExactly '10.240.1.68'
    }

    It 'preserves an alternate validated private layout' {
        $script:apiConfig.gatewayCidr = '172.20.0.0/24'
        $script:apiConfig.workerCidr = '172.20.1.64/27'
        $script:apiConfig.workerPrivateIp = '172.20.1.68'
        $result = Get-LabApiParameterSet ($script:apiConfig | ConvertTo-Json -Depth 8)
        $result.parameters.gatewayAddressStart.value | Should -BeExactly '172.20.0.0'
        $result.parameters.gatewayAddressEnd.value | Should -BeExactly '172.20.0.255'
        $result.parameters.workerPrivateIp.value | Should -BeExactly '172.20.1.68'
    }

    It 'rejects <Case>' -ForEach @(
        @{ Case = 'unknown private fields'; Change = { param($c) $c['clientSecret'] = 'SYNTHETIC_PRIVATE_CANARY' } },
        @{ Case = 'missing audience'; Change = { param($c) $c.Remove('frontendResourceClientId') } },
        @{ Case = 'unsupported versions'; Change = { param($c) $c.schemaVersion = '2.0' } },
        @{ Case = 'empty tenant IDs'; Change = { param($c) $c.tenantId = '00000000-0000-0000-0000-000000000000' } },
        @{ Case = 'malformed caller IDs'; Change = { param($c) $c.workerClientId = 'not-a-guid' } },
        @{ Case = 'equal frontend and backend audiences'; Change = { param($c) $c.backendAudienceClientId = $c.frontendResourceClientId } },
        @{ Case = 'caller and audience identity conflicts'; Change = { param($c) $c.workerClientId = $c.frontendResourceClientId } },
        @{ Case = 'policy injection in service names'; Change = { param($c) $c.apimName = 'synthetic<xml>' } },
        @{ Case = 'plain HTTP origins'; Change = { param($c) $c.backendOrigin = 'http://backend.synthetic.invalid' } },
        @{ Case = 'origin paths'; Change = { param($c) $c.backendOrigin = 'https://backend.synthetic.invalid/plm' } },
        @{ Case = 'origin ports'; Change = { param($c) $c.backendOrigin = 'https://backend.synthetic.invalid:443' } },
        @{ Case = 'origin credentials'; Change = { param($c) $c.backendOrigin = 'https://synthetic@backend.synthetic.invalid' } },
        @{ Case = 'origin queries'; Change = { param($c) $c.backendOrigin = 'https://backend.synthetic.invalid?x=1' } },
        @{ Case = 'origin IP literals'; Change = { param($c) $c.backendOrigin = 'https://10.240.1.68' } },
        @{ Case = 'noncanonical gateway CIDRs'; Change = { param($c) $c.gatewayCidr = '10.240.0.1/24' } },
        @{ Case = 'public gateway CIDRs'; Change = { param($c) $c.gatewayCidr = '192.0.2.0/24' } },
        @{ Case = 'unrestricted gateway CIDRs'; Change = { param($c) $c.gatewayCidr = '0.0.0.0/0' } },
        @{ Case = 'undersized gateway CIDRs'; Change = { param($c) $c.gatewayCidr = '10.240.0.0/25' } },
        @{ Case = 'public worker CIDRs'; Change = { param($c) $c.workerCidr = '192.0.2.0/27' } },
        @{ Case = 'overlapping source subnets'; Change = { param($c) $c.workerCidr = '10.240.0.64/27'; $c.workerPrivateIp = '10.240.0.68' } },
        @{ Case = 'worker addresses outside the subnet'; Change = { param($c) $c.workerPrivateIp = '10.240.2.68' } },
        @{ Case = 'reserved worker addresses'; Change = { param($c) $c.workerPrivateIp = '10.240.1.67' } },
        @{ Case = 'worker broadcast addresses'; Change = { param($c) $c.workerPrivateIp = '10.240.1.95' } }
    ) {
        $null = & $Change $script:apiConfig
        { Get-LabApiParameterSet ($script:apiConfig | ConvertTo-Json -Depth 8) } | Should -Throw
    }

    It 'rejects duplicate and case-conflicting JSON members' {
        { Get-LabApiParameterSet ($script:apiSample.Replace('"schemaVersion": "1.0"',
                    '"schemaVersion": "1.0", "SchemaVersion": "1.0"')) } | Should -Throw
    }

    It 'writes a new external file once and never overwrites an existing handoff' {
        $inputPath = Join-Path $TestDrive 'api-input.json'
        $outputPath = Join-Path $TestDrive 'api-output.json'
        [IO.File]::WriteAllText($inputPath, $script:apiSample)
        (New-LabApiParameterFile $inputPath $outputPath).code | Should -BeExactly 'LAB_API_PARAMETERS_READY'
        $before = [IO.File]::ReadAllText($outputPath)
        (Read-LabJson $before).parameters.apimName.value | Should -BeExactly 'apim-synthetic'
        (New-LabApiParameterFile $inputPath $outputPath).code | Should -BeExactly 'LAB_API_PARAMETERS_FAILED'
        [IO.File]::ReadAllText($outputPath) | Should -BeExactly $before
    }

    It 'refuses missing input, checkout output, relative paths and declined writes' {
        $inputPath = Join-Path $TestDrive 'valid-api-input.json'
        $outputPath = Join-Path $TestDrive 'refused-api-output.json'
        [IO.File]::WriteAllText($inputPath, $script:apiSample)
        (New-LabApiParameterFile (Join-Path $TestDrive 'absent.json') $outputPath).state | Should -BeExactly 'Failed'
        (New-LabApiParameterFile 'relative.json' $outputPath).state | Should -BeExactly 'Failed'
        (New-LabApiParameterFile $inputPath (Join-Path $script:apiRepo 'artifacts\refused-api.json')).state |
            Should -BeExactly 'Failed'
        (New-LabApiParameterFile $inputPath $outputPath -WhatIf).code | Should -BeExactly 'LAB_API_PARAMETERS_NOT_WRITTEN'
        (Test-Path -LiteralPath $outputPath) | Should -BeFalse
    }

    It 'prints only a fixed failure status on every command stream' {
        $inputPath = Join-Path $TestDrive 'SYNTHETIC_PRIVATE_CANARY.json'
        $outputPath = Join-Path $TestDrive 'not-written.json'
        [IO.File]::WriteAllText($inputPath, '{"SYNTHETIC_PRIVATE_CANARY":true}')
        $entrypoint = Join-Path $script:apiRepo 'scripts\lab\New-LabApiParameters.ps1'
        $output = & pwsh -NoProfile -File $entrypoint -ConfigPath $inputPath -OutputPath $outputPath *>&1
        $LASTEXITCODE | Should -Be 1
        ($output -join "`n").Trim() | Should -BeExactly 'LAB_API_PARAMETERS_FAILED'
        (Test-Path -LiteralPath $outputPath) | Should -BeFalse
    }
}

Describe 'Evaluated API imports, private policies and inheritance' {
    BeforeAll {
        $version = (Import-PowerShellDataFile (Join-Path $script:apiRepo 'scripts\DevDependencies.psd1')).Bicep
        $executable = if ($IsWindows) { 'bicep.exe' } else { 'bicep' }
        $bicep = Join-Path $script:apiRepo ".tools\bicep\$version\$executable"
        $work = Join-Path $TestDrive 'synthetic-apis'
        New-Item -ItemType Directory -Path $work | Out-Null
        foreach ($name in @('apis.bicep', 'apis.synthetic.bicepparam', 'apis.sample.json', 'bicepconfig.json')) {
            Copy-Item -LiteralPath (Join-Path $script:apiSource $name) -Destination (Join-Path $work $name)
        }
        foreach ($name in @('policies', 'scenarios')) {
            Copy-Item -LiteralPath (Join-Path $script:apiSource $name) -Destination (Join-Path $work $name) -Recurse
        }
        $source = Join-Path $work 'apis.bicep'
        $compiledPath = Join-Path $work 'apis.json'
        $script:apiBuild = @(& $bicep build $source --outfile $compiledPath 2>&1)
        $LASTEXITCODE | Should -Be 0
        $script:apiLint = @(& $bicep lint $source 2>&1)
        $LASTEXITCODE | Should -Be 0
        $script:apiCompiledText = [IO.File]::ReadAllText($compiledPath)
        $script:apiCompiled = Read-LabJson $script:apiCompiledText
        $snapshotOutput = @(& $bicep snapshot (Join-Path $work 'apis.synthetic.bicepparam') --mode overwrite `
                --tenant-id '11111111-1111-1111-1111-111111111111' `
                --subscription-id '22222222-2222-2222-2222-222222222222' --resource-group rg-synthetic-lab `
                --location eastus2 --deployment-name synthetic-apis 2>&1)
        $LASTEXITCODE | Should -Be 0
        $snapshotOutput | Should -BeNullOrEmpty
        $snapshot = Read-LabJson ([IO.File]::ReadAllText((Join-Path $work 'apis.synthetic.snapshot.json')))
        $snapshot.diagnostics | Should -BeNullOrEmpty
        $script:apiPredicted = @($snapshot.predictedResources)
        $script:apiInventory = Read-LabJson ([IO.File]::ReadAllText((Join-Path $script:apiSource 'scenarios\inventory.json')))
        $script:apiModule = Import-Module (Join-Path $script:apiRepo 'ApimAssessment.psd1') -Force -PassThru

        function Get-TestLabApiResource {
            param([string] $Type, [string] $Name)
            $found = @($script:apiPredicted | Where-Object { $_.type -ceq $Type -and $_.name -ceq $Name })
            $found.Count | Should -Be 1
            return $found[0]
        }
        function Invoke-TestLabApiMerge {
            param([string] $Api, [string] $Operation, [string[]] $Products = @('business'),
                [string] $OverrideOperationPolicy = '')
            $productPolicies = @{}
            foreach ($product in $Products) {
                $productPolicies[$product] = (Get-TestLabApiResource `
                        'Microsoft.ApiManagement/service/products/policies' "apim-synthetic/$product/policy").properties.value
            }
            $fragments = @{}
            foreach ($fragment in $script:apiPredicted | Where-Object type -EQ 'Microsoft.ApiManagement/service/policyFragments') {
                $fragments[$fragment.name.Split('/')[-1]] = $fragment.properties.value
            }
            $parameters = @{
                GlobalPolicy = (Get-TestLabApiResource 'Microsoft.ApiManagement/service/policies' 'apim-synthetic/policy').properties.value
                ProductPolicies = $productPolicies
                ProductNames = $Products
                ApiPolicy = (Get-TestLabApiResource 'Microsoft.ApiManagement/service/apis/policies' "apim-synthetic/$Api/policy").properties.value
                OperationPolicy = if ($OverrideOperationPolicy -cne '') { $OverrideOperationPolicy } else {
                    (Get-TestLabApiResource 'Microsoft.ApiManagement/service/apis/operations/policies' "apim-synthetic/$Api/$Operation/policy").properties.value
                }
                Fragments = $fragments
                ApiName = $Api
                OperationName = $Operation
            }
            return & $script:apiModule { param($values) Merge-ApimPolicy @values } $parameters
        }

        $caller = [xml](Get-TestLabApiResource 'Microsoft.ApiManagement/service/policyFragments' 'apim-synthetic/lab-caller-auth').properties.value
        $commerce = [xml](Get-TestLabApiResource 'Microsoft.ApiManagement/service/apis/policies' 'apim-synthetic/e-commerce/policy').properties.value
        $plm = [xml](Get-TestLabApiResource 'Microsoft.ApiManagement/service/apis/policies' 'apim-synthetic/plm/policy').properties.value
        $expressions = @{}
        foreach ($item in @(
                @{ Name = 'Delegated'; Xml = $caller; Path = '/fragment/choose/when' },
                @{ Name = 'Product'; Xml = $commerce; Path = '/policies/inbound/choose/when' },
                @{ Name = 'Plm'; Xml = $plm; Path = '/policies/inbound/choose[1]/when' }
            )) {
            $condition = $item.Xml.SelectSingleNode($item.Path).GetAttribute('condition')
            $expressions[$item.Name] = $condition.Substring(2, $condition.Length - 3)
        }
        Add-Type -TypeDefinition @"
using System.Collections.Generic;
using System.Linq;
namespace SyntheticLabApiPolicies {
    public sealed class Product { public string Id { get; set; } }
    public sealed class Request { public string IpAddress { get; set; } }
    public sealed class Jwt { public IDictionary<string, string[]> Claims { get; set; } }
    public sealed class Context {
        public Product Product { get; set; }
        public Request Request { get; set; }
        public IDictionary<string, object> Variables { get; set; }
    }
    public static class Guards {
        public static bool Delegated(Context context) { return $($expressions.Delegated); }
        public static bool Product(Context context) { return $($expressions.Product); }
        public static bool Plm(Context context) { return $($expressions.Plm); }
    }
}
"@
        function Get-TestLabApiContext {
            $context = [SyntheticLabApiPolicies.Context]::new()
            $context.Product = [SyntheticLabApiPolicies.Product]::new()
            $context.Product.Id = 'business'
            $context.Request = [SyntheticLabApiPolicies.Request]::new()
            $context.Request.IpAddress = '10.240.1.68'
            $context.Variables = [Collections.Generic.Dictionary[string, object]]::new()
            $context.Variables['labProduct'] = 'business'
            $caller = [SyntheticLabApiPolicies.Jwt]::new()
            $caller.Claims = [Collections.Generic.Dictionary[string, string[]]]::new()
            $caller.Claims['roles'] = @('Lab.Frontend.Invoke', 'Lab.Plm.Invoke')
            $context.Variables['labCaller'] = $caller
            return $context
        }
    }

    It 'compiles and lints without warnings, parent mutation, list calls or root outputs' {
        $script:apiBuild | Should -BeNullOrEmpty
        $script:apiLint | Should -BeNullOrEmpty
        $script:apiCompiled.ContainsKey('outputs') | Should -BeFalse
        $script:apiCompiledText | Should -Not -Match '(?i)\blist(?:Keys|Secrets|Value|Credentials)\s*\('
        $script:apiPredicted.Count | Should -Be 47
        foreach ($resource in $script:apiPredicted) {
            $resource.type | Should -Match '^Microsoft\.ApiManagement/service/(apis|backends|policies|policyFragments|products|subscriptions)(/|$)'
        }
    }

    It 'imports exactly the five original contracts and binds only HTTPS private backend origins' {
        @($script:apiPredicted | Where-Object type -EQ 'Microsoft.ApiManagement/service/apis').Count | Should -Be 5
        foreach ($api in $script:apiInventory.apis) {
            $resource = Get-TestLabApiResource 'Microsoft.ApiManagement/service/apis' "apim-synthetic/$($api.apiId)"
            $resource.properties.path | Should -BeExactly $api.path
            $resource.properties.protocols | Should -Be @('https')
            $resource.properties.subscriptionRequired | Should -BeTrue
            $resource.properties.format | Should -BeExactly 'openapi+json'
            $document = Read-LabJson $resource.properties.value
            $original = Read-LabJson ([IO.File]::ReadAllText((Join-Path $script:apiSource "scenarios\$($api.document)")))
            ($document.paths | ConvertTo-Json -Depth 40 -Compress) | Should -BeExactly ($original.paths | ConvertTo-Json -Depth 40 -Compress)
            ($document.components | ConvertTo-Json -Depth 40 -Compress) | Should -BeExactly ($original.components | ConvertTo-Json -Depth 40 -Compress)
            $document.servers[0].url | Should -BeExactly "https://backend.synthetic.invalid/$($api.path)"
            $resource.properties.serviceUrl | Should -BeExactly $document.servers[0].url
            $apiPolicy = [xml](Get-TestLabApiResource 'Microsoft.ApiManagement/service/apis/policies' "apim-synthetic/$($api.apiId)/policy").properties.value
            $apiPolicy.SelectSingleNode('//set-backend-service').GetAttribute('backend-id') | Should -BeExactly "lab-$($api.apiId)"
            $backend = Get-TestLabApiResource 'Microsoft.ApiManagement/service/backends' "apim-synthetic/lab-$($api.apiId)"
            $backend.properties.url | Should -BeExactly $document.servers[0].url
            $backend.properties.tls.validateCertificateChain | Should -BeTrue
            $backend.properties.tls.validateCertificateName | Should -BeTrue
            $backend.properties.credentials | Should -BeNullOrEmpty
            $backend.properties.proxy | Should -BeNullOrEmpty
        }
        ($script:apiInventory.apis | Where-Object apiId -EQ 'plm').publication | Should -BeExactly 'privateOnly'
        ($script:apiInventory.apis | Where-Object apiId -EQ 'manufacturing').initialTraffic | Should -BeExactly 'none'
    }

    It 'creates only the seven declared memberships and two tracing-disabled product subscriptions' {
        $memberships = @($script:apiPredicted | Where-Object type -EQ 'Microsoft.ApiManagement/service/products/apis')
        $memberships.Count | Should -Be 7
        foreach ($product in @('business', 'partner')) {
            $resource = Get-TestLabApiResource 'Microsoft.ApiManagement/service/products' "apim-synthetic/$product"
            $resource.properties.subscriptionRequired | Should -BeTrue
            $resource.properties.approvalRequired | Should -BeTrue
            $expected = @($script:apiInventory.apis | Where-Object { $product -cin $_.productIds } |
                    ForEach-Object { "apim-synthetic/$product/$($_.apiId)" } | Sort-Object)
            @($memberships | Where-Object { $_.name.StartsWith("apim-synthetic/$product/") } |
                ForEach-Object name | Sort-Object) | Should -Be $expected
            $subscription = Get-TestLabApiResource 'Microsoft.ApiManagement/service/subscriptions' "apim-synthetic/lab-$product"
            $subscription.properties.scope | Should -BeExactly "/products/$product"
            $subscription.properties.allowTracing | Should -BeFalse
            $subscription.properties.state | Should -BeExactly 'active'
            $subscription.properties.primaryKey | Should -BeNullOrEmpty
            $subscription.properties.secondaryKey | Should -BeNullOrEmpty
            $subscription.properties.ownerId | Should -BeNullOrEmpty
        }
    }

    It 'attaches all sixteen operation policies using normalized imported IDs without extra endpoints' {
        $operationPolicies = @($script:apiPredicted | Where-Object type -EQ 'Microsoft.ApiManagement/service/apis/operations/policies')
        $operationPolicies.Count | Should -Be 16
        foreach ($api in $script:apiInventory.apis) {
            $document = Read-LabJson (Get-TestLabApiResource 'Microsoft.ApiManagement/service/apis' "apim-synthetic/$($api.apiId)").properties.value
            $count = 0
            foreach ($path in $document.paths.Values) {
                foreach ($method in $path.Keys | Where-Object { $_ -in @('get', 'post', 'patch') }) {
                    $operation = $path[$method].operationId.ToLowerInvariant()
                    $null = Get-TestLabApiResource 'Microsoft.ApiManagement/service/apis/operations/policies' "apim-synthetic/$($api.apiId)/$operation/policy"
                    $count++
                }
            }
            $count | Should -Be $api.operationCount
        }
    }

    It 'preserves all inherited authentication, product and scope markers across all 23 product-operation paths' {
        $count = 0
        foreach ($api in $script:apiInventory.apis) {
            $policies = @($script:apiPredicted | Where-Object {
                    $_.type -ceq 'Microsoft.ApiManagement/service/apis/operations/policies' -and
                    $_.name.StartsWith("apim-synthetic/$($api.apiId)/")
                })
            foreach ($policy in $policies) {
                $operation = $policy.name.Split('/')[2]
                $results = @(Invoke-TestLabApiMerge $api.apiId $operation $api.productIds)
                $results.Count | Should -Be $api.productIds.Count
                foreach ($result in $results) {
                    $result.baseMissing | Should -BeNullOrEmpty
                    $result.fragmentIssues | Should -BeNullOrEmpty
                    $xml = [xml]$result.effectiveXml
                    $xml.SelectNodes('//base|//include-fragment').Count | Should -Be 0
                    $xml.SelectSingleNode('//validate-azure-ad-token').GetAttribute('data-scope') | Should -BeExactly 'fragment:lab-caller-auth'
                    $xml.SelectSingleNode('//authentication-managed-identity').GetAttribute('resource') |
                        Should -BeExactly 'api://33333333-3333-3333-3333-333333333333'
                    $xml.SelectSingleNode('//authentication-managed-identity').GetAttribute('ignore-error') | Should -BeExactly 'false'
                    $xml.SelectSingleNode('//set-header[@name="Authorization"]').GetAttribute('exists-action') | Should -BeExactly 'delete'
                    $xml.SelectSingleNode('//set-header[@name="Ocp-Apim-Subscription-Key"]').GetAttribute('exists-action') | Should -BeExactly 'delete'
                    $xml.SelectSingleNode('//set-query-parameter[@name="subscription-key"]').GetAttribute('exists-action') | Should -BeExactly 'delete'
                    $xml.SelectSingleNode('//forward-request').GetAttribute('follow-redirects') | Should -BeExactly 'false'
                    foreach ($marker in @('Global', 'Product', 'Api', 'Operation')) {
                        $xml.SelectNodes("//outbound/set-header[@name='X-Lab-$marker']").Count | Should -Be 1
                    }
                    $xml.SelectSingleNode('//set-header[@name="X-Lab-Product"]/value').InnerText | Should -BeExactly $result.product
                    @($xml.SelectNodes('//set-header[@name="X-Lab-Policy"]/value'))[-1].InnerText | Should -BeExactly 'operation'
                    $count++
                }
            }
        }
        $count | Should -Be 23
    }

    It 'detects a synthetic missing outbound base instead of treating lost parent markers as inherited' {
        $policy = [xml](Get-TestLabApiResource 'Microsoft.ApiManagement/service/apis/operations/policies' 'apim-synthetic/plm/getpartrevision/policy').properties.value
        $outbound = $policy.SelectSingleNode('/policies/outbound')
        $null = $outbound.RemoveChild($outbound.SelectSingleNode('base'))
        $result = Invoke-TestLabApiMerge 'plm' 'getpartrevision' @('business') $policy.OuterXml
        $result.baseMissing.Count | Should -Be 1
        $result.baseMissing[0].section | Should -BeExactly 'outbound'
        $xml = [xml]$result.effectiveXml
        $xml.SelectNodes('//set-header[@name="X-Lab-Global"]').Count | Should -Be 0
        $xml.SelectNodes('//validate-azure-ad-token').Count | Should -Be 1
    }

    It 'requires the exact Entra tenant, v2 audience, worker application and frontend role' {
        $xml = [xml](Get-TestLabApiResource 'Microsoft.ApiManagement/service/policyFragments' 'apim-synthetic/lab-caller-auth').properties.value
        $policy = $xml.fragment.'validate-azure-ad-token'
        $policy.'tenant-id' | Should -BeExactly '11111111-1111-1111-1111-111111111111'
        $policy.audiences.audience | Should -BeExactly '55555555-5555-5555-5555-555555555555'
        $policy.'client-application-ids'.'application-id' | Should -BeExactly '66666666-6666-6666-6666-666666666666'
        $policy.'required-claims'.claim.Count | Should -Be 4
        ($policy.'required-claims'.claim | Where-Object name -EQ 'ver').value | Should -BeExactly '2.0'
        ($policy.'required-claims'.claim | Where-Object name -EQ 'tid').value | Should -BeExactly '11111111-1111-1111-1111-111111111111'
        ($policy.'required-claims'.claim | Where-Object name -EQ 'azp').value | Should -BeExactly '66666666-6666-6666-6666-666666666666'
        ($policy.'required-claims'.claim | Where-Object name -EQ 'roles').value | Should -BeExactly 'Lab.Frontend.Invoke'
        $policy.'failed-validation-httpcode' | Should -BeExactly '401'
    }

    It 'accepts genuine business/partner context and rejects absent, wrong or unexecuted product policy context' {
        foreach ($product in @('business', 'partner')) {
            $context = Get-TestLabApiContext
            $context.Product.Id = $product
            $context.Variables['labProduct'] = $product
            [SyntheticLabApiPolicies.Guards]::Product($context) | Should -BeFalse
        }
        $context = Get-TestLabApiContext
        $context.Product = $null
        [SyntheticLabApiPolicies.Guards]::Product($context) | Should -BeTrue
        $context = Get-TestLabApiContext
        $context.Product.Id = 'unapproved'
        [SyntheticLabApiPolicies.Guards]::Product($context) | Should -BeTrue
        $context = Get-TestLabApiContext
        $context.Variables.Remove('labProduct') | Out-Null
        [SyntheticLabApiPolicies.Guards]::Product($context) | Should -BeTrue
        $context = Get-TestLabApiContext
        $context.Variables['labProduct'] = 'partner'
        [SyntheticLabApiPolicies.Guards]::Product($context) | Should -BeTrue
    }

    It 'rejects delegated callers even when the delegated scope is empty' {
        $context = Get-TestLabApiContext
        [SyntheticLabApiPolicies.Guards]::Delegated($context) | Should -BeFalse
        foreach ($scope in @('', 'synthetic.read')) {
            $context.Variables['labCaller'].Claims['scp'] = @($scope)
            [SyntheticLabApiPolicies.Guards]::Delegated($context) | Should -BeTrue
        }
    }

    It 'permits PLM only for the exact private worker source with the additional role' {
        $context = Get-TestLabApiContext
        [SyntheticLabApiPolicies.Guards]::Plm($context) | Should -BeFalse
        $context.Request.IpAddress = '10.240.0.4'
        [SyntheticLabApiPolicies.Guards]::Plm($context) | Should -BeTrue
        $context.Request.IpAddress = '192.0.2.10'
        [SyntheticLabApiPolicies.Guards]::Plm($context) | Should -BeTrue
        $context = Get-TestLabApiContext
        $context.Variables['labCaller'].Claims['roles'] = @('Lab.Frontend.Invoke')
        [SyntheticLabApiPolicies.Guards]::Plm($context) | Should -BeTrue
        $context.Variables['labCaller'].Claims.Remove('roles') | Out-Null
        [SyntheticLabApiPolicies.Guards]::Plm($context) | Should -BeTrue
    }
}
