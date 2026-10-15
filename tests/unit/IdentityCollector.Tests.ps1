$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Secret-safe Identity collector' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)
        $script:identityRepo = $RepoRoot

        BeforeAll { $script:identityArm = ${function:Invoke-ApimArm} }

        BeforeEach {
            $config = Import-PowerShellDataFile (Join-Path $script:identityRepo 'config/sample.psd1')
            $config.Output.Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $script:identityEnv = $config.Environments[0]
            $script:identityRun = New-ApimRun -Config $config -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000010' -Operator Synthetic `
                -RunId synthetic-identity
            Mock Invoke-ApimArm {
                $properties = switch -Regex ($Uri) {
                    '/identityProviders\?' {
                        @{ type = 'aad'; clientId = 'secret-canary'; clientSecret = 'secret-canary'
                            signinTenant = 'secret-canary'; allowedTenants = @('secret-canary') }
                    }
                    '/authorizationServers\?' {
                        @{ authorizationMethods = @('POST', 'GET'); clientAuthenticationMethod = @()
                            grantTypes = @('authorizationCode'); bearerTokenSendingMethods = $null
                            supportState = $false; useInApiDocumentation = $true
                            clientSecret = 'secret-canary'; clientId = 'secret-canary'
                            authorizationEndpoint = 'https://secret-canary.invalid'
                            tokenBodyParameters = @(@{ name = 'secret-canary'; value = 'secret-canary' })
                            resourceOwnerPassword = 'secret-canary' }
                    }
                    '/openidConnectProviders\?' {
                        @{ useInApiDocumentation = $false; useInTestConsole = $true
                            metadataEndpoint = 'https://secret-canary.invalid'
                            clientId = 'secret-canary'; clientSecret = 'secret-canary' }
                    }
                    '/authorizationProviders\?' {
                        @{ identityProvider = 'secret-canary'
                            oauth2 = @{ grantTypes = @{
                                authorizationCode = @{ clientSecret = 'secret-canary' }
                                clientCredentials = @{}
                            }; redirectUrl = 'https://secret-canary.invalid' } }
                    }
                    default { throw 'Unexpected endpoint.' }
                }
                $properties.unknown = 'secret-canary'
                [pscustomobject]@{ value = @([pscustomobject]@{
                    name = 'synthetic-provider'; properties = [pscustomobject]$properties
                    unknown = 'secret-canary'; id = 'secret-canary'
                }); unknown = 'secret-canary' }
            }
        }

        It 'writes all four closed collections with structural metadata only' {
            $paths = @(Invoke-ApimIdentityCollector -RunPath $script:identityRun.Path -Environment $script:identityEnv)
            $paths.Count | Should -Be 4
            foreach ($path in $paths) {
                Get-Content $path -Raw | Should -Not -Match 'secret-canary|clientId|clientSecret|unknown|Endpoint'
            }
            $record = (Get-RunManifest $script:identityRun.Path).collectors | Where-Object name -EQ Identity
            $record.status | Should -Be Completed
            $record.items | Should -Be 4
            $record.files | Should -Be @('raw/identityProviders.json', 'raw/authorizationServers.json',
                'raw/openidConnectProviders.json', 'raw/authorizationProviders.json')
            Test-ApimCollectorOutput -RunPath $script:identityRun.Path -Environment $script:identityEnv -Collector $record
            $server = Read-ApimSmokeOutputJson $script:identityRun.Path raw/authorizationServers.json
            $server.value[0].properties.authorizationMethods | Should -Be @('GET', 'POST')
            $server.value[0].properties.clientAuthenticationMethod.Count | Should -Be 0
            $server.value[0].properties.bearerTokenSendingMethods | Should -BeNullOrEmpty
            $server.value[0].properties.supportState | Should -BeFalse
            $server.value[0].properties.useInTestConsole | Should -BeNullOrEmpty
            $auth = Read-ApimSmokeOutputJson $script:identityRun.Path raw/authorizationProviders.json
            $auth.value[0].properties.authorizationCodeConfigured | Should -BeTrue
            $auth.value[0].properties.clientCredentialsConfigured | Should -BeTrue
            Should -Invoke Invoke-ApimArm -Times 4 -Exactly -ParameterFilter {
                $Method -ceq 'GET' -and $Uri -match '\?api-version=2024-05-01$' -and
                $Uri -notmatch 'listSecrets|listValue|listKeys|/users|/secrets|token'
            }
        }

        It 'preserves legitimate empty collections and counts zero items' {
            Mock Invoke-ApimArm { [pscustomobject]@{ value = @() } }
            @(Invoke-ApimIdentityCollector -RunPath $script:identityRun.Path -Environment $script:identityEnv).Count |
                Should -Be 4
            $record = (Get-RunManifest $script:identityRun.Path).collectors | Where-Object name -EQ Identity
            $record.items | Should -Be 0
            Test-ApimCollectorOutput -RunPath $script:identityRun.Path -Environment $script:identityEnv -Collector $record
        }

        It 'isolates each failed endpoint while retaining other validated files (<Kind>)' -TestCases @(
            @{ Kind = 'identityProviders' }, @{ Kind = 'authorizationServers' },
            @{ Kind = 'openidConnectProviders' }, @{ Kind = 'authorizationProviders' }
        ) {
            param($Kind)
            $script:failedIdentityKind = $Kind
            Mock Invoke-ApimArm { throw 'secret-canary' } -ParameterFilter {
                $Uri -match "/$script:failedIdentityKind\?"
            }
            { Invoke-ApimIdentityCollector -RunPath $script:identityRun.Path -Environment $script:identityEnv } |
                Should -Throw 'Identity collection incomplete.'
            $record = (Get-RunManifest $script:identityRun.Path).collectors | Where-Object name -EQ Identity
            $record.status | Should -Be Partial
            $record.items | Should -Be 3
            $record.errors | Should -Be 1
            $record.files.Count | Should -Be 3
            $record.files | Should -Not -Contain "raw/$Kind.json"
            Test-ApimCollectorOutput -RunPath $script:identityRun.Path -Environment $script:identityEnv -Collector $record
            Test-Path (Join-Path $script:identityRun.Path "raw/$Kind.json") | Should -BeFalse
            (Get-ChildItem (Join-Path $script:identityRun.Path raw) -File).Count | Should -Be 3
            (Get-Content (Join-Path $script:identityRun.Path logs/run.log) -Raw) | Should -Not -Match 'secret-canary'
        }

        It 'records Failed without synthesizing empty success files' {
            Mock Invoke-ApimArm { throw (Get-ApimArmFailure -StatusCode 403 -Attempts 1) }
            { Invoke-ApimIdentityCollector -RunPath $script:identityRun.Path -Environment $script:identityEnv } |
                Should -Throw 'Identity collection incomplete.'
            $record = (Get-RunManifest $script:identityRun.Path).collectors | Where-Object name -EQ Identity
            $record.status | Should -Be Failed
            $record.items | Should -Be 0
            $record.errors | Should -Be 4
            $record.files.Count | Should -Be 0
            @(Get-ChildItem (Join-Path $script:identityRun.Path raw) -File).Count | Should -Be 0
        }

        It 'rejects malformed resource/collection facts before any persistence (<Kind>)' -TestCases @(
            @{ Kind = 'null' }, @{ Kind = 'no-value' }, @{ Kind = 'null-value' },
            @{ Kind = 'object-value' }, @{ Kind = 'null-item' }, @{ Kind = 'no-properties' },
            @{ Kind = 'duplicate' }, @{ Kind = 'bad-type' }, @{ Kind = 'bad-boolean' }
        ) {
            param($Kind)
            $script:badIdentityKind = $Kind
            Mock Invoke-ApimArm {
                $resource = [pscustomobject]@{ name = 'synthetic'; properties = [pscustomobject]@{} }
                switch ($script:badIdentityKind) {
                    null { return $null }
                    no-value { return [pscustomobject]@{} }
                    null-value { return [pscustomobject]@{ value = $null } }
                    object-value { return [pscustomobject]@{ value = $resource } }
                    null-item { return [pscustomobject]@{ value = @($null) } }
                    no-properties { return [pscustomobject]@{ value = @([pscustomobject]@{ name = 'synthetic' }) } }
                    duplicate { return [pscustomobject]@{ value = @($resource, $resource) } }
                    bad-type { $resource.properties | Add-Member type 'secret-canary' }
                    bad-boolean { $resource.properties | Add-Member useInTestConsole 'false' }
                }
                [pscustomobject]@{ value = @($resource) }
            }
            { Invoke-ApimIdentityCollector -RunPath $script:identityRun.Path -Environment $script:identityEnv } |
                Should -Throw 'Identity collection incomplete.'
            $record = (Get-RunManifest $script:identityRun.Path).collectors | Where-Object name -EQ Identity
            $record.status | Should -BeIn @('Partial', 'Failed')
            (Get-Content (Join-Path $script:identityRun.Path logs/run.log) -Raw) | Should -Not -Match 'secret-canary'
        }

        It 'uses the existing ARM paginator and sorts records deterministically' {
            Mock Invoke-ApimArm {
                & $script:identityArm -Method $Method -Uri $Uri -LogPath $LogPath
            }

            Mock Invoke-ApimArmRequest {
                if ($Uri -match '\$skip=1') {
                    return [pscustomobject]@{ StatusCode = 200; Headers = @{}; Content = '{"value":[{"name":"a","properties":{}}]}' }
                }
                $next = $Uri + '&$skip=1'
                return [pscustomobject]@{ StatusCode = 200; Headers = @{}; Content = (
                    @{ value = @(@{ name = 'z'; properties = @{} }); nextLink = $next } |
                    ConvertTo-Json -Depth 10 -Compress
                ) }
            }
            $null = Invoke-ApimIdentityCollector -RunPath $script:identityRun.Path -Environment $script:identityEnv
            $record = (Get-RunManifest $script:identityRun.Path).collectors | Where-Object name -EQ Identity
            $record.items | Should -Be 8
            $payload = Read-ApimSmokeOutputJson $script:identityRun.Path raw/identityProviders.json
            $payload.value.name | Should -Be @('a', 'z')
            Should -Invoke Invoke-ApimArmRequest -Times 8 -Exactly -ParameterFilter { $Method -ceq 'GET' }
        }

        It 'retains only official provider type enums (<ProviderType>)' -TestCases @(
            @{ ProviderType = 'aad' }, @{ ProviderType = 'aadB2C' },
            @{ ProviderType = 'facebook' }, @{ ProviderType = 'google' },
            @{ ProviderType = 'microsoft' }, @{ ProviderType = 'twitter' }
        ) {
            param($ProviderType)
            $safe = ConvertTo-ApimIdentityResource -Kind identityProviders `
                -Resource ([pscustomobject]@{ name = 'synthetic'; properties = @{ type = $ProviderType } })
            $safe.properties.type | Should -BeExactly $ProviderType
        }

        It 'rejects invented or wrong-case enums and invalid enum-array types' -TestCases @(
            @{ Field = 'type'; Kind = 'identityProviders'; Value = 'nonEntra' },
            @{ Field = 'type'; Kind = 'identityProviders'; Value = 'Aad' },
            @{ Field = 'grantTypes'; Kind = 'authorizationServers'; Value = @('unknown') },
            @{ Field = 'authorizationMethods'; Kind = 'authorizationServers'; Value = 'GET' },
            @{ Field = 'clientAuthenticationMethod'; Kind = 'authorizationServers'; Value = @($null) },
            @{ Field = 'bearerTokenSendingMethods'; Kind = 'authorizationServers'; Value = @('secret-canary') }
        ) {
            param($Field, $Kind, $Value)
            $arguments = @{
                Kind = $Kind
                Resource = [pscustomobject]@{ name = 'synthetic'; properties = @{ $Field = $Value } }
            }
            { ConvertTo-ApimIdentityResource @arguments } | Should -Throw
        }

        It 'rejects tampered saved allowlists and count mismatches (<Kind>)' -TestCases @(
            @{ Kind = 'unknown' }, @{ Kind = 'nested' }, @{ Kind = 'count' }, @{ Kind = 'missing' }
        ) {
            param($Kind)
            $null = Invoke-ApimIdentityCollector -RunPath $script:identityRun.Path -Environment $script:identityEnv
            $record = (Get-RunManifest $script:identityRun.Path).collectors | Where-Object name -EQ Identity
            $payload = Read-ApimSmokeOutputJson $script:identityRun.Path raw/identityProviders.json
            switch ($Kind) {
                unknown { $payload | Add-Member unknown 'secret-canary' }
                nested { $payload.value[0].properties | Add-Member clientSecret 'secret-canary' }
                count { $record.items++ }
                missing { Remove-Item (Join-Path $script:identityRun.Path raw/authorizationServers.json) }
            }
            $null = Write-RunFile -RunPath $script:identityRun.Path -RelativePath raw/identityProviders.json -InputObject $payload
            { Test-ApimCollectorOutput -RunPath $script:identityRun.Path -Environment $script:identityEnv -Collector $record } |
                Should -Throw
        }
    }
}
