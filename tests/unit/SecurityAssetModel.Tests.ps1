$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'APIM security asset models' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)

        $script:securityModelRepoRoot = $RepoRoot

        BeforeAll {
            $script:securityModelFixtureRoot = Join-Path (
                $script:securityModelRepoRoot
            ) 'tests/fixtures/synthetic-reference'
            $script:securityModelSchemas = @{
                namedValues = Join-Path $script:securityModelRepoRoot (
                    'schemas/namedValues.schema.json'
                )
                backends = Join-Path $script:securityModelRepoRoot (
                    'schemas/backends.schema.json'
                )
                certificates = Join-Path $script:securityModelRepoRoot (
                    'schemas/certificates.schema.json'
                )
            }

            function Read-SecurityModelFixture {
                param(
                    [Parameter(Mandatory)]
                    [string] $RelativePath
                )

                return Get-Content -LiteralPath (
                    Join-Path $script:securityModelFixtureRoot $RelativePath
                ) -Raw | ConvertFrom-Json -Depth 100 -NoEnumerate
            }

            function Get-SecurityModelInput {
                return @{
                    NamedValuesPayload = Read-SecurityModelFixture (
                        'raw/namedValues.json'
                    )
                    BackendsPayload = Read-SecurityModelFixture (
                        'raw/backends.json'
                    )
                    CertificatesPayload = Read-SecurityModelFixture (
                        'raw/certificates.json'
                    )
                }
            }

        }

        It 'matches deterministic named-value, backend, and certificate fixtures' {
            $inputData = Get-SecurityModelInput
            $model = Get-ApimSecurityAssetModel @inputData

            $model.namedValues.Count | Should -Be 3
            $model.backends.Count | Should -Be 2
            $model.certificates.Count | Should -Be 2
            foreach ($name in @('namedValues', 'backends', 'certificates')) {
                $expected = Get-Content -LiteralPath (
                    Join-Path $script:securityModelFixtureRoot `
                        "model/$name.json"
                ) -Raw
                $actual = ConvertTo-Json -InputObject $model.$name -Depth 100
                ($actual -replace "`r`n?", "`n").Trim() |
                    Should -Be (($expected -replace "`r`n?", "`n").Trim())
            }
        }

        It 'derives structural risks without carrying URLs or secret values' {
            $inputData = Get-SecurityModelInput
            $model = Get-ApimSecurityAssetModel @inputData
            $plainText = $model.namedValues |
                Where-Object namedValueId -EQ 'partner-api-key'
            $httpsBackend = $model.backends |
                Where-Object backendId -EQ 'orders-backend'
            $httpBackend = $model.backends |
                Where-Object backendId -EQ 'status-backend'
            $serialized = ConvertTo-Json -InputObject $model -Depth 100
            $plainText.plainTextSecretLike | Should -BeTrue
            $plainText.plainTextSecretLike | Should -BeTrue
            $plainText.secretPatternLocations -join ',' |
                Should -Be 'displayName,value'
            $httpsBackend.scheme | Should -Be 'https'
            $httpsBackend.credentialConfigured | Should -BeTrue
            $httpBackend.scheme | Should -Be 'http'
            $httpBackend.tlsValidationChain | Should -BeNullOrEmpty
            $httpBackend.tlsValidationName | Should -BeNullOrEmpty
            $serialized | Should -Not -Match (
                '(?i)synthetic\\.invalid|secretIdentifier|' +
                'authorizationScheme|headerNames|queryParameterNames'
            )
        }

        It 'marks incomplete Key Vault and HTTPS TLS facts Partial' {
            $inputData = Get-SecurityModelInput
            $inputData.NamedValuesPayload.value[0].properties.keyVault.
                secretIdentifier = $null
            $inputData.BackendsPayload.value[0].properties.tls.
                validateCertificateName = $null
            $inputData.CertificatesPayload.value[0].properties.
                expirationDate = $null

            $model = Get-ApimSecurityAssetModel @inputData
            $namedValue = $model.namedValues |
                Where-Object namedValueId -EQ 'key-vault-reference'
            $backend = $model.backends |
                Where-Object backendId -EQ 'orders-backend'
            $certificate = $model.certificates |
                Where-Object certificateId -EQ 'key-vault-certificate'

            $namedValue.keyVaultBacked | Should -BeNullOrEmpty
            $namedValue.missingInputs | Should -Contain 'keyVaultReference'
            $backend.tlsValidationName | Should -BeNullOrEmpty
            $backend.missingInputs | Should -Contain 'tlsValidationName'
            $certificate.expirationDate | Should -BeNullOrEmpty
            $certificate.missingInputs | Should -Contain 'expirationDate'
        }

        It 'rejects malformed collected security metadata' -TestCases @(
            @{ Kind = 'named-value' }
            @{ Kind = 'backend' }
            @{ Kind = 'certificate' }
        ) {
            param($Kind)

            $inputData = Get-SecurityModelInput
            switch ($Kind) {
                'named-value' {
                    $inputData.NamedValuesPayload.value[0].properties.secret =
                        'true'
                }
                'backend' {
                    $inputData.BackendsPayload.value[0].properties.tls.
                        validateCertificateChain = 'true'
                }
                'certificate' {
                    $inputData.CertificatesPayload.value[0].properties.
                        expirationDate = 'not-a-date'
                }
            }

            {
                Get-ApimSecurityAssetModel @inputData
            } | Should -Throw
        }

        It 'writes all three arrays only after every closed schema validates' {
            $inputData = Get-SecurityModelInput
            $model = Get-ApimSecurityAssetModel @inputData
            $firstRun = Join-Path $TestDrive 'security-model-first'
            $secondRun = Join-Path $TestDrive 'security-model-second'

            $firstPaths = @(Write-ApimSecurityAssetModel `
                    -RunPath $firstRun -Model $model)
            Write-ApimSecurityAssetModel -RunPath $secondRun -Model $model

            $firstPaths.Count | Should -Be 3
            foreach ($name in @('namedValues', 'backends', 'certificates')) {
                $firstJson = Get-Content -LiteralPath (
                    Join-Path $firstRun "model/$name.json"
                ) -Raw
                $secondJson = Get-Content -LiteralPath (
                    Join-Path $secondRun "model/$name.json"
                ) -Raw
                $firstJson | Should -Be $secondJson
                ($firstJson | Test-Json `
                        -SchemaFile $script:securityModelSchemas[$name]) |
                    Should -BeTrue
            }
        }

        It 'fails before writing when any pending model is invalid' {
            $inputData = Get-SecurityModelInput
            $model = Get-ApimSecurityAssetModel @inputData
            $model.backends[0] | Add-Member -NotePropertyName unexpected `
                -NotePropertyValue $true
            $runPath = Join-Path $TestDrive 'invalid-security-model'

            {
                Write-ApimSecurityAssetModel -RunPath $runPath -Model $model
            } | Should -Throw
            Test-Path -LiteralPath $runPath | Should -BeFalse
        }
    }
}
