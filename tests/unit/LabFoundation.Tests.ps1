BeforeAll {
    $script:foundationRepo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:foundationSource = Join-Path $script:foundationRepo 'infra\live-validation-lab'
    . (Join-Path $script:foundationRepo 'scripts\lab\LabBootstrap.Core.ps1')
    . (Join-Path $script:foundationRepo 'scripts\lab\LabFoundation.Core.ps1')
    $script:foundationSample = [System.IO.File]::ReadAllText(
        (Join-Path $script:foundationSource 'foundation.sample.json'))

    function Get-TestFoundationResource {
        param([string] $Type, [string] $Name = '')
        $found = @($script:predicted | Where-Object {
                $_.type -ceq $Type -and ($Name -ceq '' -or $_.name -ceq $Name)
            })
        $found.Count | Should -Be 1
        return $found[0]
    }
}

Describe 'Private foundation configuration and parameter handoff' {
    BeforeEach {
        $script:foundationConfig = Read-LabJson $script:foundationSample
    }

    It 'produces only the closed ARM parameter contract with explicit budgets' {
        $result = Get-LabFoundationParameterSet $script:foundationSample
        @($result.parameters.Keys) | Should -Be @('labId', 'location', 'names', 'publisherEmail',
            'publisherName', 'network', 'observability')
        $result.parameters.network.value.vnetCidr | Should -BeExactly '10.240.0.0/22'
        $result.parameters.observability.value.dailyQuotaGb | Should -Be 1
    }

    It 'accepts a different, contained RFC1918 layout without silently replacing it' {
        $script:foundationConfig.network.vnetCidr = '172.20.0.0/22'
        $script:foundationConfig.network.gatewayCidr = '172.20.0.0/24'
        $script:foundationConfig.network.apimCidr = '172.20.1.0/26'
        $script:foundationConfig.network.workerCidr = '172.20.1.64/27'
        $script:foundationConfig.network.privateEndpointCidr = '172.20.1.96/27'
        $result = Get-LabFoundationParameterSet ($script:foundationConfig | ConvertTo-Json -Depth 10)
        $result.parameters.network.value.workerCidr | Should -BeExactly '172.20.1.64/27'
    }

    It 'rejects unknown fields, case-conflicting members and unsupported versions' {
        $script:foundationConfig['clientSecret'] = 'SYNTHETIC_PRIVATE_CANARY'
        { Get-LabFoundationParameterSet ($script:foundationConfig | ConvertTo-Json -Depth 10) } | Should -Throw
        { Get-LabFoundationParameterSet ($script:foundationSample.Replace('"schemaVersion": "1.0"',
                    '"schemaVersion": "1.0", "SchemaVersion": "1.0"')) } | Should -Throw
        { Get-LabFoundationParameterSet ($script:foundationSample.Replace('"schemaVersion": "1.0"',
                    '"schemaVersion": "2.0"')) } | Should -Throw
    }

    It 'rejects a missing required field and nested arbitrary settings' {
        $script:foundationConfig.network.Remove('workerHttpsEgressCidrs')
        { Get-LabFoundationParameterSet ($script:foundationConfig | ConvertTo-Json -Depth 10) } | Should -Throw
        $script:foundationConfig = Read-LabJson $script:foundationSample
        $script:foundationConfig.names['roleAssignment'] = 'Owner'
        { Get-LabFoundationParameterSet ($script:foundationConfig | ConvertTo-Json -Depth 10) } | Should -Throw
    }

    It 'rejects malformed or noncanonical IPv4 CIDR <Cidr>' -ForEach @(
        @{ Cidr = '10.240.1.1/26' }, @{ Cidr = '010.240.1.0/26' }, @{ Cidr = '10.240.256.0/26' },
        @{ Cidr = '10.240.1.0/33' }, @{ Cidr = '10.240.1.0/026' }, @{ Cidr = '2001:db8::/64' },
        @{ Cidr = '10.240.1/26' }, @{ Cidr = '10.240.1.0' }
    ) {
        $script:foundationConfig.network.apimCidr = $Cidr
        { Get-LabFoundationParameterSet ($script:foundationConfig | ConvertTo-Json -Depth 10) } | Should -Throw
    }

    It 'rejects overlap even when both subnets are contained' {
        $script:foundationConfig.network.privateEndpointCidr = '10.240.1.64/27'
        { Get-LabFoundationParameterSet ($script:foundationConfig | ConvertTo-Json -Depth 10) } | Should -Throw
    }

    It 'rejects a subnet outside the VNet and insufficient <Field> capacity' -ForEach @(
        @{ Field = 'gatewayCidr'; Cidr = '10.240.0.0/25' },
        @{ Field = 'apimCidr'; Cidr = '10.240.1.0/27' },
        @{ Field = 'workerCidr'; Cidr = '10.240.1.64/28' },
        @{ Field = 'privateEndpointCidr'; Cidr = '10.240.1.96/28' },
        @{ Field = 'workerCidr'; Cidr = '10.240.4.0/27' },
        @{ Field = 'vnetCidr'; Cidr = '10.240.0.0/23' },
        @{ Field = 'vnetCidr'; Cidr = '192.0.0.0/16' }
    ) {
        $script:foundationConfig.network[$Field] = $Cidr
        { Get-LabFoundationParameterSet ($script:foundationConfig | ConvertTo-Json -Depth 10) } | Should -Throw
    }

    It 'rejects empty, duplicate, unrestricted or nonpublic internet lists' {
        foreach ($name in @('approvedCallerCidrs', 'workerHttpsEgressCidrs')) {
            foreach ($list in @(@(), @('0.0.0.0/0'), @('10.0.0.0/8'), @('127.0.0.1/32'),
                    @('192.0.2.10/32', '192.0.2.10/32'))) {
                $script:foundationConfig = Read-LabJson $script:foundationSample
                $script:foundationConfig.network[$name] = $list
                { Get-LabFoundationParameterSet ($script:foundationConfig | ConvertTo-Json -Depth 10) } | Should -Throw
            }
        }
    }

    It 'rejects unbounded observability and malformed resource/contact inputs' {
        foreach ($mutation in @(
                { param($c) $c.observability.dailyQuotaGb = -1 },
                { param($c) $c.observability.retentionDays = 1 },
                { param($c) $c.observability.samplingPercentage = 0 },
                { param($c) $c.names.keyVault = 'kv--synthetic' },
                { param($c) $c.publisherEmail = "operator@synthetic.invalid`nSYNTHETIC_PRIVATE_CANARY" }
            )) {
            $config = Read-LabJson $script:foundationSample
            & $mutation $config
            { Get-LabFoundationParameterSet ($config | ConvertTo-Json -Depth 10) } | Should -Throw
        }
    }

    It 'writes a new external private file once and refuses overwrite without leaking details' {
        $inputPath = Join-Path $TestDrive 'foundation-input.json'
        $outputPath = Join-Path $TestDrive 'foundation-parameters.json'
        [System.IO.File]::WriteAllText($inputPath, $script:foundationSample)
        $result = New-LabFoundationParameterFile $inputPath $outputPath
        $result.state | Should -BeExactly 'ParametersReady'
        $before = [System.IO.File]::ReadAllText($outputPath)
        (Read-LabJson $before).parameters.names.value.apim | Should -BeExactly 'apim-synthetic'
        $repeat = New-LabFoundationParameterFile $inputPath $outputPath
        $repeat.state | Should -BeExactly 'Failed'
        ($repeat | ConvertTo-Json -Compress) | Should -Not -Match ([regex]::Escape($outputPath))
        [System.IO.File]::ReadAllText($outputPath) | Should -BeExactly $before
    }

    It 'refuses missing input, checkout output and relative paths without success-shaped files' {
        $inputPath = Join-Path $TestDrive 'valid-input.json'
        [System.IO.File]::WriteAllText($inputPath, $script:foundationSample)
        $outputPath = Join-Path $TestDrive 'not-created.json'
        (New-LabFoundationParameterFile (Join-Path $TestDrive 'SYNTHETIC_PRIVATE_CANARY.json') $outputPath).state |
            Should -BeExactly 'Failed'
        (Test-Path -LiteralPath $outputPath) | Should -BeFalse
        (New-LabFoundationParameterFile $inputPath (Join-Path $script:foundationRepo 'artifacts\refused.json')).state |
            Should -BeExactly 'Failed'
        (New-LabFoundationParameterFile 'relative.json' $outputPath).state | Should -BeExactly 'Failed'
    }

    It 'does not create a parameter file when ShouldProcess declines the write' {
        $inputPath = Join-Path $TestDrive 'whatif-input.json'
        $outputPath = Join-Path $TestDrive 'whatif-output.json'
        [System.IO.File]::WriteAllText($inputPath, $script:foundationSample)
        $result = New-LabFoundationParameterFile $inputPath $outputPath -WhatIf
        $result.code | Should -BeExactly 'LAB_FOUNDATION_PARAMETERS_NOT_WRITTEN'
        (Test-Path -LiteralPath $outputPath) | Should -BeFalse
    }

    It 'emits only fixed status on every CLI stream for invalid private input' {
        $inputPath = Join-Path $TestDrive 'canary-input.json'
        $outputPath = Join-Path $TestDrive 'canary-output.json'
        [System.IO.File]::WriteAllText($inputPath, '{"SYNTHETIC_PRIVATE_CANARY":true}')
        $entryPoint = Join-Path $script:foundationRepo 'scripts\lab\New-LabFoundationParameters.ps1'
        $output = & pwsh -NoProfile -File $entryPoint -ConfigPath $inputPath -OutputPath $outputPath *>&1
        $LASTEXITCODE | Should -Be 1
        ($output -join "`n").Trim() | Should -BeExactly 'LAB_FOUNDATION_PARAMETERS_FAILED'
        (Test-Path -LiteralPath $outputPath) | Should -BeFalse
    }
}

Describe 'Pinned Bicep build, lint and evaluated synthetic topology' {
    BeforeAll {
        $version = (Import-PowerShellDataFile (Join-Path $script:foundationRepo 'scripts\DevDependencies.psd1')).Bicep
        $executable = if ($IsWindows) { 'bicep.exe' } else { 'bicep' }
        $script:bicep = Join-Path $script:foundationRepo ".tools\bicep\$version\$executable"
        if (-not (Test-Path -LiteralPath $script:bicep -PathType Leaf)) {
            throw 'Install the pinned compiler with scripts/Install-DevDependencies.ps1.'
        }
        $work = Join-Path $TestDrive 'synthetic-foundation'
        New-Item -ItemType Directory -Path $work | Out-Null
        foreach ($name in @('foundation.bicep', 'network.bicep', 'bicepconfig.json',
                'foundation.sample.json', 'foundation.synthetic.bicepparam')) {
            Copy-Item -LiteralPath (Join-Path $script:foundationSource $name) -Destination (Join-Path $work $name)
        }
        $source = Join-Path $work 'foundation.bicep'
        $compiled = Join-Path $work 'foundation.json'
        $script:buildDiagnostics = @(& $script:bicep build $source --outfile $compiled 2>&1)
        $LASTEXITCODE | Should -Be 0
        $script:lintDiagnostics = @(& $script:bicep lint $source 2>&1)
        $LASTEXITCODE | Should -Be 0
        $script:compiledText = [System.IO.File]::ReadAllText($compiled)
        $script:compiled = ConvertFrom-Json $script:compiledText -AsHashtable -Depth 100
        $snapshotDiagnostics = @(& $script:bicep snapshot (Join-Path $work 'foundation.synthetic.bicepparam') `
                --mode overwrite --tenant-id '11111111-1111-1111-1111-111111111111' `
                --subscription-id '22222222-2222-2222-2222-222222222222' --resource-group 'rg-synthetic-lab' `
                --location eastus2 --deployment-name synthetic-foundation 2>&1)
        $LASTEXITCODE | Should -Be 0
        $snapshotDiagnostics | Should -BeNullOrEmpty
        $snapshot = Read-LabJson ([System.IO.File]::ReadAllText(
                (Join-Path $work 'foundation.synthetic.snapshot.json')))
        $snapshot.diagnostics | Should -BeNullOrEmpty
        $script:predicted = @($snapshot.predictedResources)
    }

    It 'compiles and lints without warnings, credentials, list operations or root output' {
        $script:buildDiagnostics | Should -BeNullOrEmpty
        $script:lintDiagnostics | Should -BeNullOrEmpty
        $script:compiledText | Should -Not -Match '(?i)\blist(?:Keys|Secrets|Value|Credentials)\s*\('
        $script:compiled.ContainsKey('outputs') | Should -BeFalse
        $configuration = Read-LabJson ([System.IO.File]::ReadAllText(
                (Join-Path $script:foundationSource 'bicepconfig.json')))
        $configuration.cloud.credentialPrecedence | Should -BeNullOrEmpty
    }

    It 'creates exactly one internal classic Developer unit with only its system identity' {
        $apim = Get-TestFoundationResource 'Microsoft.ApiManagement/service'
        $apim.sku.name | Should -BeExactly 'Developer'
        $apim.sku.capacity | Should -Be 1
        $apim.properties.virtualNetworkType | Should -BeExactly 'Internal'
        $apim.properties.publicNetworkAccess | Should -BeExactly 'Enabled'
        $apim.properties.virtualNetworkConfiguration.subnetResourceId | Should -Match '/subnets/apim$'
        $apim.identity.type | Should -BeExactly 'SystemAssigned'
        $apim.properties.developerPortalStatus | Should -BeExactly 'Disabled'
        $apim.properties.publicIpAddressId | Should -BeNullOrEmpty
        $apim.properties.hostnameConfigurations | Should -BeNullOrEmpty
        foreach ($property in $apim.properties.customProperties.Keys) {
            $apim.properties.customProperties[$property] | Should -BeExactly 'False'
        }
    }

    It 'creates all four sized subnets, four attached NSGs and no APIM delegation' {
        $subnets = @($script:predicted | Where-Object type -EQ 'Microsoft.Network/virtualNetworks/subnets')
        $subnets.Count | Should -Be 4
        @($script:predicted | Where-Object type -EQ 'Microsoft.Network/networkSecurityGroups').Count | Should -Be 4
        $expected = @{'gateway' = '10.240.0.0/24'; 'apim' = '10.240.1.0/26'
            'worker' = '10.240.1.64/27'; 'private-endpoints' = '10.240.1.96/27' }
        foreach ($subnet in $subnets) {
            $expected[$subnet.name.Split('/')[-1]] | Should -BeExactly $subnet.properties.addressPrefix
            $subnet.properties.networkSecurityGroup.id | Should -Match '/networkSecurityGroups/vnet-synthetic-.+-nsg$'
            $subnet.properties.delegations | Should -BeNullOrEmpty
        }
        $vnet = Get-TestFoundationResource 'Microsoft.Network/virtualNetworks'
        $vnet.properties.addressSpace.addressPrefixes | Should -Be @('10.240.0.0/22')
    }

    It 'uses an explicit static NAT IPv4 egress only on the private worker subnet' {
        $subnet = Get-TestFoundationResource 'Microsoft.Network/virtualNetworks/subnets' 'vnet-synthetic/worker'
        $subnet.properties.defaultOutboundAccess | Should -BeFalse
        $nat = Get-TestFoundationResource 'Microsoft.Network/natGateways'
        $subnet.properties.natGateway.id | Should -BeExactly $nat.id
        $pip = Get-TestFoundationResource 'Microsoft.Network/publicIPAddresses'
        $pip.properties.publicIPAllocationMethod | Should -BeExactly 'Static'
        $nat.properties.publicIpAddresses[0].id | Should -BeExactly $pip.id
    }

    It 'limits APIM HTTPS callers to the gateway and worker without suppressing platform traffic' {
        $nsg = Get-TestFoundationResource 'Microsoft.Network/networkSecurityGroups' 'vnet-synthetic-apim-nsg'
        $rules = @($nsg.properties.securityRules)
        $https = @($rules | Where-Object {
                $_.properties.direction -ceq 'Inbound' -and $_.properties.access -ceq 'Allow' -and
                $_.properties.destinationPortRange -ceq '443'
            })
        @($https.properties.sourceAddressPrefix | Sort-Object) | Should -Be @('10.240.0.0/24', '10.240.1.64/27')
        @($rules | Where-Object name -EQ 'ApiManagementControlPlane')[0].properties.sourceAddressPrefix |
            Should -BeExactly 'ApiManagement'
        @($rules | Where-Object name -EQ 'LoadBalancerHealth')[0].properties.sourceAddressPrefix |
            Should -BeExactly 'AzureLoadBalancer'
        @($rules | Where-Object name -EQ 'DenyOtherInbound')[0].properties.priority | Should -Be 4096
        foreach ($destination in @('Storage', 'Sql', 'AzureKeyVault', 'AzureActiveDirectory', 'AzureMonitor')) {
            @($rules | Where-Object {
                    $_.properties.direction -ceq 'Outbound' -and $_.properties.access -ceq 'Allow' -and
                    $_.properties.destinationAddressPrefix -ceq $destination
                }).Count | Should -BeGreaterThan 0
        }
    }

    It 'retains standard gateway platform requirements but allows callers only on HTTPS' {
        $nsg = Get-TestFoundationResource 'Microsoft.Network/networkSecurityGroups' 'vnet-synthetic-gateway-nsg'
        $rules = @($nsg.properties.securityRules)
        @($rules | Where-Object { $_.properties.direction -ceq 'Outbound' -and $_.properties.access -ceq 'Deny' }) |
            Should -BeNullOrEmpty
        $caller = @($rules | Where-Object name -EQ 'CallerHttps-0')[0].properties
        $caller.sourceAddressPrefix | Should -BeExactly '192.0.2.10/32'
        $caller.destinationPortRange | Should -BeExactly '443'
        @($rules | Where-Object name -EQ 'GatewayManager')[0].properties.destinationPortRange |
            Should -BeExactly '65200-65535'
        @($rules | Where-Object name -EQ 'AzureLoadBalancer')[0].properties.destinationPortRange | Should -BeExactly '*'
        @($rules | Where-Object name -EQ 'WorkerNatHttps')[0].properties.sourceAddressPrefix | Should -Match '/32$'
        @($rules | Where-Object name -LIKE 'GatewayHealth*').Count | Should -Be 3
    }

    It 'denies worker SSH and unspecified outbound traffic while retaining private and approved HTTPS paths' {
        $nsg = Get-TestFoundationResource 'Microsoft.Network/networkSecurityGroups' 'vnet-synthetic-worker-nsg'
        $rules = @($nsg.properties.securityRules)
        $inbound = @($rules | Where-Object {
                $_.properties.direction -ceq 'Inbound' -and $_.properties.access -ceq 'Allow'
            })
        @($inbound.properties.destinationPortRange | Select-Object -Unique) | Should -Be @('443')
        @($rules | Where-Object {
                $_.properties.direction -ceq 'Outbound' -and $_.properties.access -ceq 'Allow' -and
                $_.properties.destinationAddressPrefix -cin @('Internet', '*', '0.0.0.0/0')
            }) | Should -BeNullOrEmpty
        @($rules | Where-Object name -EQ 'ApprovedHttps-0')[0].properties.destinationAddressPrefix |
            Should -BeExactly '198.51.100.10/32'
        @($rules | Where-Object name -EQ 'DenyOtherOutbound')[0].properties.priority | Should -Be 4096
        @($rules | Where-Object name -EQ 'ManagedIdentityMetadata')[0].properties.destinationAddressPrefix |
            Should -BeExactly '169.254.169.254'
    }

    It 'protects the empty vault with RBAC, soft delete, purge protection and default-deny firewall' {
        $vault = Get-TestFoundationResource 'Microsoft.KeyVault/vaults'
        $vault.properties.enableRbacAuthorization | Should -BeTrue
        $vault.properties.enableSoftDelete | Should -BeTrue
        $vault.properties.enablePurgeProtection | Should -BeTrue
        $vault.properties.softDeleteRetentionInDays | Should -Be 90
        $vault.properties.accessPolicies | Should -BeNullOrEmpty
        $vault.properties.networkAcls.defaultAction | Should -BeExactly 'Deny'
        $vault.properties.publicNetworkAccess | Should -BeExactly 'Enabled'
        $vault.properties.networkAcls.bypass | Should -BeExactly 'AzureServices'
        $vault.properties.networkAcls.ipRules | Should -BeNullOrEmpty
        $vault.properties.networkAcls.virtualNetworkRules[0].id | Should -Match '/subnets/apim$'
        $apimSubnet = Get-TestFoundationResource 'Microsoft.Network/virtualNetworks/subnets' 'vnet-synthetic/apim'
        @($apimSubnet.properties.serviceEndpoints.service) | Should -Contain 'Microsoft.KeyVault'
    }

    It 'connects the vault private endpoint and linked private DNS with enforced subnet policies' {
        $pe = Get-TestFoundationResource 'Microsoft.Network/privateEndpoints'
        $pe.properties.subnet.id | Should -Match '/subnets/private-endpoints$'
        $pe.properties.privateLinkServiceConnections[0].properties.groupIds | Should -Be @('vault')
        $vault = Get-TestFoundationResource 'Microsoft.KeyVault/vaults'
        $pe.properties.privateLinkServiceConnections[0].properties.privateLinkServiceId | Should -BeExactly $vault.id
        $dns = Get-TestFoundationResource 'Microsoft.Network/privateDnsZones'
        $dns.name | Should -BeExactly 'privatelink.vaultcore.azure.net'
        $link = Get-TestFoundationResource 'Microsoft.Network/privateDnsZones/virtualNetworkLinks'
        $link.properties.registrationEnabled | Should -BeFalse
        $link.properties.virtualNetwork.id | Should -Match '/virtualNetworks/vnet-synthetic$'
        $group = Get-TestFoundationResource 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups'
        $group.properties.privateDnsZoneConfigs[0].properties.privateDnsZoneId | Should -BeExactly $dns.id
        $subnet = Get-TestFoundationResource 'Microsoft.Network/virtualNetworks/subnets' 'vnet-synthetic/private-endpoints'
        $subnet.properties.privateEndpointNetworkPolicies | Should -BeExactly 'NetworkSecurityGroupEnabled'
    }

    It 'links workspace-based Entra-only masked-IP App Insights and bounds workspace ingestion' {
        $workspace = Get-TestFoundationResource 'Microsoft.OperationalInsights/workspaces'
        $workspace.properties.retentionInDays | Should -Be 30
        $workspace.properties.workspaceCapping.dailyQuotaGb | Should -Be 1
        $workspace.properties.features.disableLocalAuth | Should -BeTrue
        $insights = Get-TestFoundationResource 'Microsoft.Insights/components'
        $insights.properties.WorkspaceResourceId | Should -BeExactly $workspace.id
        $insights.properties.DisableLocalAuth | Should -BeTrue
        $insights.properties.DisableIpMasking | Should -BeFalse
    }

    It 'configures independent dedicated gateway logs and managed-identity App Insights credentials' {
        $gateway = @($script:predicted | Where-Object {
                $_.type -ceq 'Microsoft.Insights/diagnosticSettings' -and $_.name -ceq 'lab-gateway-logs'
            })
        $gateway.Count | Should -Be 1
        $gateway[0].properties.logAnalyticsDestinationType | Should -BeExactly 'Dedicated'
        $gateway[0].properties.logs[0].category | Should -BeExactly 'GatewayLogs'
        $gateway[0].properties.logs[0].enabled | Should -BeTrue
        $workspace = Get-TestFoundationResource 'Microsoft.OperationalInsights/workspaces'
        $gateway[0].properties.workspaceId | Should -BeExactly $workspace.id
        $logger = Get-TestFoundationResource 'Microsoft.ApiManagement/service/loggers'
        $logger.properties.loggerType | Should -BeExactly 'applicationInsights'
        $credentials = $script:compiled.resources.apim.properties.parameters.loggers.value[0].credentials
        $credentials.identityClientId | Should -BeExactly 'SystemAssigned'
        $credentials.connectionString | Should -BeExactly "[reference('appInsights').outputs.connectionString.value]"
        $credentials.ContainsKey('instrumentationKey') | Should -BeFalse
    }

    It 'applies all-API sampling and error controls with zero bodies, headers and client-IP capture' {
        $diagnostic = Get-TestFoundationResource 'Microsoft.ApiManagement/service/diagnostics'
        $diagnostic.properties.alwaysLog | Should -BeExactly 'allErrors'
        $diagnostic.properties.sampling.percentage | Should -Be 100
        $diagnostic.properties.logClientIp | Should -BeFalse
        $diagnostic.properties.operationNameFormat | Should -BeExactly 'Name'
        foreach ($side in @('frontend', 'backend')) {
            foreach ($message in @('request', 'response')) {
                $diagnostic.properties[$side][$message].body.bytes | Should -Be 0
                $diagnostic.properties[$side][$message].headers | Should -BeNullOrEmpty
            }
        }
    }

    It 'preserves ownership/runtime contracts without creating later-slice resources or role grants' {
        $identity = Get-TestFoundationResource 'Microsoft.ManagedIdentity/userAssignedIdentities'
        $identity.name | Should -BeExactly 'id-synthetic-gateway'
        $zone = Get-TestFoundationResource 'Microsoft.Network/dnsZones'
        $zone.name | Should -BeExactly 'challenge.synthetic.invalid'
        $zone.location | Should -BeExactly 'global'
        foreach ($resource in $script:predicted | Where-Object { $_.ContainsKey('tags') }) {
            $resource.tags.apimAssessmentLab | Should -BeExactly 'synthetic-lab'
        }
        @($script:predicted | Where-Object {
                $_.type -match '^Microsoft.Authorization/' -or
                $_.type -match '^Microsoft.Compute/' -or
                $_.type -match '^Microsoft.KeyVault/vaults/(secrets|keys|certificates)$' -or
                $_.type -match '^Microsoft.ApiManagement/service/(apis|subscriptions|namedValues|policies)$' -or
                $_.type -ceq 'Microsoft.Network/applicationGateways'
            }) | Should -BeNullOrEmpty
    }
}
