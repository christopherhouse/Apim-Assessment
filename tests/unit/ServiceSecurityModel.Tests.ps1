$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'APIM service security model' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)

        $script:serviceModelRepoRoot = $RepoRoot

        BeforeAll {
            $script:serviceModelFixtureRoot = Join-Path (
                $script:serviceModelRepoRoot
            ) 'tests/fixtures/synthetic-reference'
            $script:serviceModelSchema = Join-Path (
                $script:serviceModelRepoRoot
            ) 'schemas/service.schema.json'

            function Read-ServiceModelFixture {
                param(
                    [Parameter(Mandatory)]
                    [string] $RelativePath
                )

                return Get-Content -LiteralPath (
                    Join-Path $script:serviceModelFixtureRoot $RelativePath
                ) -Raw | ConvertFrom-Json -Depth 100 -NoEnumerate
            }
        }

        It 'matches the deterministic closed service fixture' {
            $payload = Read-ServiceModelFixture 'raw/service.json'
            $actual = Get-ApimServiceSecurityModel -ServicePayload $payload
            $expected = Get-Content -LiteralPath (
                Join-Path $script:serviceModelFixtureRoot 'model/service.json'
            ) -Raw

            $json = ConvertTo-Json -InputObject $actual -Depth 100
            ($json -replace "`r`n?", "`n").Trim() |
                Should -Be (($expected -replace "`r`n?", "`n").Trim())
            $json | Should -Not -Match (
                '(?i)subscriptions/|resourceGroups/|userAssignedIdentities'
            )
        }

        It 'retains explicit legacy TLS enablement despite another unknown control' {
            $payload = Read-ServiceModelFixture 'raw/service.json'
            $payload.properties.customProperties.
                'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10' =
                'True'
            $payload.properties.customProperties.PSObject.Properties.Remove(
                'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11'
            )

            $model = Get-ApimServiceSecurityModel -ServicePayload $payload

            $model.legacyTlsEnabled | Should -BeTrue
            $model.enabledLegacyTlsControls | Should -Be @('GatewayTls10')
            $model.modelStatus | Should -Be 'Partial'
            $model.missingInputs | Should -Be @('legacyTlsControls')
        }

        It 'keeps incomplete legacy TLS evidence unknown rather than safe' {
            $payload = Read-ServiceModelFixture 'raw/service.json'
            $payload.properties.customProperties.PSObject.Properties.Remove(
                'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168'
            )

            $model = Get-ApimServiceSecurityModel -ServicePayload $payload

            $model.legacyTlsEnabled | Should -BeNullOrEmpty
            $model.enabledLegacyTlsControls.Count | Should -Be 0
            $model.modelStatus | Should -Be 'Partial'
            $model.missingInputs | Should -Be @('legacyTlsControls')
        }

        It 'treats absent minimum version and identity as definitive posture' {
            $payload = Read-ServiceModelFixture 'raw/service.json'
            $payload.properties.PSObject.Properties.Remove(
                'apiVersionConstraint'
            )
            $payload.PSObject.Properties.Remove('identity')

            $model = Get-ApimServiceSecurityModel -ServicePayload $payload

            $model.minApiVersion | Should -BeNullOrEmpty
            $model.managedIdentity | Should -Be 'None'
            $model.modelStatus | Should -Be 'Complete'

            $payload = Read-ServiceModelFixture 'raw/service.json'
            $payload.identity.type = 'userassigned, SYSTEMASSIGNED'
            $combined = Get-ApimServiceSecurityModel `
                -ServicePayload $payload
            $combined.managedIdentity |
                Should -Be 'SystemAssignedUserAssigned'
        }

        It 'rejects malformed service security metadata' -TestCases @(
            @{ Kind = 'legacy-tls' }
            @{ Kind = 'legacy-tls-map' }
            @{ Kind = 'identity' }
            @{ Kind = 'identity-map' }
            @{ Kind = 'minimum-version' }
            @{ Kind = 'minimum-version-map' }
        ) {
            param($Kind)

            $payload = Read-ServiceModelFixture 'raw/service.json'
            switch ($Kind) {
                'legacy-tls' {
                    $payload.properties.customProperties.
                        'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10' =
                        'Enabled'
                }
                'legacy-tls-map' {
                    $payload.properties.customProperties = @('invalid')
                }
                identity {
                    $payload.identity.type = 'Unsupported'
                }
                'identity-map' {
                    $payload.identity = 'SystemAssigned'
                }
                'minimum-version' {
                    $payload.properties.apiVersionConstraint.minApiVersion = 1
                }
                'minimum-version-map' {
                    $payload.properties.apiVersionConstraint = '2021-08-01'
                }
            }

            {
                Get-ApimServiceSecurityModel -ServicePayload $payload
            } | Should -Throw
        }

        It 'writes only a closed schema-valid service model' {
            $model = Get-ApimServiceSecurityModel -ServicePayload (
                Read-ServiceModelFixture 'raw/service.json'
            )
            $firstRun = Join-Path $TestDrive 'service-model-first'
            $secondRun = Join-Path $TestDrive 'service-model-second'

            $firstPath = Write-ApimServiceSecurityModel `
                -RunPath $firstRun -Model $model
            $null = Write-ApimServiceSecurityModel `
                -RunPath $secondRun -Model $model
            $firstJson = Get-Content -LiteralPath $firstPath -Raw
            $secondJson = Get-Content -LiteralPath (
                Join-Path $secondRun 'model/service.json'
            ) -Raw

            $firstJson | Should -Be $secondJson
            ($firstJson | Test-Json -SchemaFile $script:serviceModelSchema) |
                Should -BeTrue
        }

        It 'fails closed before writing an invalid service model' {
            $model = Get-ApimServiceSecurityModel -ServicePayload (
                Read-ServiceModelFixture 'raw/service.json'
            )
            $model | Add-Member -NotePropertyName unexpected `
                -NotePropertyValue $true
            $runPath = Join-Path $TestDrive 'invalid-service-model'

            {
                Write-ApimServiceSecurityModel -RunPath $runPath -Model $model
            } | Should -Throw
            Test-Path -LiteralPath $runPath | Should -BeFalse
        }
    }
}
