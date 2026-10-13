$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'APIM network model' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)

        $script:networkModelFixtureRoot = Join-Path $RepoRoot (
            'tests/fixtures/synthetic-reference'
        )
        $script:networkSchemaPath = Join-Path $RepoRoot (
            'schemas/network.schema.json'
        )

        BeforeAll {
            function Read-NetworkModelFixture {
                param(
                    [Parameter(Mandatory)]
                    [string] $RelativePath
                )

                return Get-Content -LiteralPath (
                    Join-Path $script:networkModelFixtureRoot $RelativePath
                ) -Raw | ConvertFrom-Json -Depth 100
            }

            function Copy-NetworkModelObject {
                param(
                    [Parameter(Mandatory)]
                    [object] $InputObject
                )

                return $InputObject | ConvertTo-Json -Depth 100 |
                    ConvertFrom-Json -Depth 100
            }

            function Get-SyntheticNetworkModelInput {
                return @{
                    Service = Read-NetworkModelFixture 'raw/service.json'
                    AppGateways = @(
                        Read-NetworkModelFixture (
                            'raw/network/appgw.agw-synthetic-prod.json'
                        )
                    )
                    WafPolicies = @(
                        Read-NetworkModelFixture (
                            'raw/network/wafPolicy.waf-synthetic-prod.json'
                        )
                    )
                    ApimSubnetPayload = Read-NetworkModelFixture (
                        'raw/network/apimSubnet.json'
                    )
                    NsgPayload = Read-NetworkModelFixture (
                        'raw/network/nsgs.json'
                    )
                    PublicIpPayload = Read-NetworkModelFixture (
                        'raw/network/publicIps.json'
                    )
                    FrontDoorPayload = Read-NetworkModelFixture (
                        'raw/network/frontDoors.json'
                    )
                }
            }

            function ConvertTo-NetworkModelJson {
                param(
                    [Parameter(Mandatory)]
                    [object] $InputObject
                )

                return ConvertTo-Json -InputObject $InputObject `
                    -Depth 100 -Compress
            }
        }

        It 'matches the deterministic restricted Internal VNet fixture' {
            $inputData = Get-SyntheticNetworkModelInput
            $actual = Get-ApimNetworkModel @inputData
            $expected = Read-NetworkModelFixture 'model/network.json'

            ConvertTo-NetworkModelJson $actual |
                Should -Be (ConvertTo-NetworkModelJson $expected)
            $actual.directPublic | Should -BeFalse
            $actual.nsgEvaluation | Should -Be 'Restricted'
            $actual.wafState | Should -Be 'Disabled'
            $actual.appGatewayTlsPolicy | Should -Be 'Strong'
            $actual.modelStatus | Should -Be 'Complete'
        }

        It 'marks an effective broad Internet allow as DirectPublic' {
            $inputData = Get-SyntheticNetworkModelInput
            $broadRule = [pscustomobject]@{
                name = 'allow-internet-https'
                properties = [pscustomobject]@{
                    priority = 90
                    direction = 'Inbound'
                    access = 'Allow'
                    protocol = 'Tcp'
                    sourceAddressPrefix = 'Internet'
                    destinationAddressPrefix = '*'
                    destinationPortRange = '443'
                }
            }
            $nsg = $inputData.NsgPayload.value[0]
            $nsg.properties.securityRules = @(
                $broadRule
                $nsg.properties.securityRules
            )

            $actual = Get-ApimNetworkModel @inputData

            $actual.nsgEvaluation | Should -Be 'Broad'
            $actual.directPublic | Should -BeTrue
            $actual.directPublicReasons | Should -Be @('BroadNsg443')
        }

        It 'detects another public front door targeting APIM' {
            $inputData = Get-SyntheticNetworkModelInput
            $inputData.FrontDoorPayload.value = @(
                [pscustomobject]@{
                    id = '/synthetic/frontdoors/secondary'
                    name = 'secondary-front-door'
                    targetsApim = $true
                    properties = [pscustomobject]@{}
                }
            )

            $actual = Get-ApimNetworkModel @inputData

            $actual.directPublic | Should -BeTrue
            $actual.directPublicReasons | Should -Be @('OtherFrontDoor')
            $actual.otherFrontDoors | Should -Be @('secondary-front-door')
        }

        It 'detects a public IP explicitly linked to APIM' {
            $inputData = Get-SyntheticNetworkModelInput
            $publicIp = $inputData.PublicIpPayload.value[0]
            $publicIp.targetClassification = 'TargetsApim'

            $actual = Get-ApimNetworkModel @inputData

            $actual.directPublic | Should -BeTrue
            $actual.directPublicReasons | Should -Be @('PublicIpRoute')
            $actual.otherPublicIpRoutes |
                Should -Be @('pip-agw-synthetic-prod')
        }

        It 'keeps DirectPublic unknown for unclassified public IP routes' {
            $inputData = Get-SyntheticNetworkModelInput
            $publicIp = $inputData.PublicIpPayload.value[0]
            $publicIp.targetClassification = 'Unknown'

            $actual = Get-ApimNetworkModel @inputData

            $actual.directPublic | Should -BeNullOrEmpty
            $actual.modelStatus | Should -Be 'Partial'
            $actual.missingInputs | Should -Be @(
                'directPublicEvidence',
                'publicIpRoutes'
            )
        }

        It 'uses null rather than false when required NSG evidence is missing' {
            $inputData = Get-SyntheticNetworkModelInput
            $inputData.NsgPayload = $null

            $actual = Get-ApimNetworkModel @inputData

            $actual.directPublic | Should -BeNullOrEmpty
            $actual.nsgEvaluation | Should -Be 'Unknown'
            $actual.modelStatus | Should -Be 'Partial'
            $actual.missingInputs | Should -Be @(
                'directPublicEvidence',
                'nsgs'
            )
        }

        It 'preserves null for unavailable collection arrays' {
            $inputData = Get-SyntheticNetworkModelInput
            $inputData.AppGateways = $null
            $inputData.PublicIpPayload = $null
            $inputData.FrontDoorPayload = $null

            $actual = Get-ApimNetworkModel @inputData
            $json = ConvertTo-Json -InputObject $actual -Depth 100

            $actual.appGateways | Should -BeNullOrEmpty
            $actual.otherFrontDoors | Should -BeNullOrEmpty
            $actual.otherPublicIpRoutes | Should -BeNullOrEmpty
            $actual.modelStatus | Should -Be 'Partial'
            ($json | Test-Json -SchemaFile $script:networkSchemaPath) |
                Should -BeTrue
        }

        It 'detects weak TLS and enabled Detection-mode legacy WAF' {
            $inputData = Get-SyntheticNetworkModelInput
            $gateway = $inputData.AppGateways[0]
            $gateway.properties.sslPolicy.policyName = 'AppGwSslPolicy20170401'
            $gateway.properties.sslPolicy.minProtocolVersion = 'TLSv1_0'
            $gateway.properties.PSObject.Properties.Remove('firewallPolicy')
            $gateway.properties |
                Add-Member -NotePropertyName webApplicationFirewallConfiguration `
                    -NotePropertyValue ([pscustomobject]@{
                        enabled = $true
                        firewallMode = 'Detection'
                    })
            $inputData.WafPolicies = @()

            $actual = Get-ApimNetworkModel @inputData

            $actual.appGatewayTlsPolicy | Should -Be 'Weak'
            $actual.wafState | Should -Be 'Enabled'
            $actual.wafMode | Should -Be 'Detection'
        }

        It 'writes a closed schema-valid single network object' {
            $inputData = Get-SyntheticNetworkModelInput
            $record = Get-ApimNetworkModel @inputData
            $runPath = Join-Path $TestDrive 'network-model'
            $null = New-Item -ItemType Directory -Path $runPath

            $path = Write-ApimNetworkModel `
                -RunPath $runPath -Record $record
            $json = Get-Content -LiteralPath $path -Raw

            ($json | Test-Json -SchemaFile $script:networkSchemaPath) |
                Should -BeTrue
            (ConvertFrom-Json -InputObject $json).directPublic |
                Should -BeFalse
        }

        It 'fails closed before writing an invalid model' {
            $inputData = Get-SyntheticNetworkModelInput
            $record = Get-ApimNetworkModel @inputData
            $invalid = Copy-NetworkModelObject $record
            $invalid | Add-Member -NotePropertyName unexpected `
                -NotePropertyValue $true
            $runPath = Join-Path $TestDrive 'invalid-network-model'
            $null = New-Item -ItemType Directory -Path $runPath

            {
                Write-ApimNetworkModel `
                    -RunPath $runPath -Record $invalid
            } | Should -Throw
            Test-Path -LiteralPath (
                Join-Path $runPath 'model/network.json'
            ) | Should -BeFalse
        }
    }
}
