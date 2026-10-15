$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Secret-safe Portal collector' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)
        $script:portalRepo = $RepoRoot

        BeforeAll { $script:portalArm = ${function:Invoke-ApimArm} }

        BeforeEach {
            $config = Import-PowerShellDataFile (Join-Path $script:portalRepo 'config/sample.psd1')
            $config.Output.Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $script:portalEnv = $config.Environments[0]
            $script:portalRun = New-ApimRun -Config $config -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000010' -Operator Synthetic `
                -RunId synthetic-portal
            Mock Invoke-ApimArm {
                if ($Uri -match '/portalRevisions\?') {
                    return [pscustomobject]@{ value = @([pscustomobject]@{
                        name = 'synthetic-revision'; properties = [pscustomobject]@{
                            isCurrent = $true; status = 'completed'; statusDetails = 'secret-canary'
                            description = 'secret-canary'; createdDateTime = 'secret-canary'
                        }; unknown = 'secret-canary'
                    }); nextLink = $null; unknown = 'secret-canary' }
                }
                $properties = switch -Regex ($Uri) {
                    '/portalsettings/signin\?' { @{ enabled = $false } }
                    '/portalsettings/signup\?' {
                        @{ enabled = $true; termsOfService = @{ text = 'secret-canary' } }
                    }
                    '/portalsettings/delegation\?' {
                        @{ userRegistration = @{ enabled = $true; unknown = 'secret-canary' }
                            subscriptions = @{ enabled = $false }
                            validationKey = 'secret-canary'; url = 'https://secret-canary.invalid' }
                    }
                    '/portalconfigs/default\?' {
                        @{ enableBasicAuth = $false; signin = @{ require = $true; unknown = 'secret-canary' }
                            delegation = @{ delegateRegistration = $false; delegateSubscription = $true
                                validationKey = 'secret-canary'; delegationUrl = 'https://secret-canary.invalid' }
                            signup = @{ termsOfService = @{ text = 'secret-canary' } } }
                    }
                    default { throw 'Unexpected endpoint.' }
                }
                $properties.unknown = 'secret-canary'
                [pscustomobject]@{ name = 'synthetic-setting'; properties = [pscustomobject]$properties
                    id = 'secret-canary'; unknown = 'secret-canary' }
            }
        }

        It 'writes the exact five contracts and drops nested secret/text/unknown fields' {
            $paths = @(Invoke-ApimPortalCollector -RunPath $script:portalRun.Path -Environment $script:portalEnv)
            $paths.Count | Should -Be 5
            foreach ($path in $paths) {
                Get-Content $path -Raw | Should -Not -Match 'secret-canary|validationKey|Url|termsOfService|unknown|statusDetails'
            }
            $record = (Get-RunManifest $script:portalRun.Path).collectors | Where-Object name -EQ Portal
            $record.status | Should -Be Completed
            $record.items | Should -Be 5
            $record.files | Should -Be @((Get-ApimPortalEndpoint).File)
            Test-ApimCollectorOutput -RunPath $script:portalRun.Path -Environment $script:portalEnv -Collector $record
            $config = Read-ApimSmokeOutputJson $script:portalRun.Path raw/portal/config.json
            $config.properties.enableBasicAuth | Should -BeFalse
            $config.properties.signin.require | Should -BeTrue
            $config.properties.delegation.delegateRegistration | Should -BeFalse
            $config.properties.delegation.delegateSubscription | Should -BeTrue
            $delegation = Read-ApimSmokeOutputJson $script:portalRun.Path raw/portal/delegation.json
            $delegation.properties.userRegistration.enabled | Should -BeTrue
            $delegation.properties.subscriptions.enabled | Should -BeFalse
            Should -Invoke Invoke-ApimArm -Times 5 -Exactly -ParameterFilter {
                $Method -ceq 'GET' -and $Uri -match '\?api-version=2024-05-01$' -and
                $Uri -notmatch 'listSecrets|listKeys|listValue|/users|/secrets|token|/service/[^/]+\?'
            }
        }

        It 'retains explicit nulls without inventing documented defaults or revision records' {
            Mock Invoke-ApimArm {
                if ($Uri -match '/portalRevisions\?') { return [pscustomobject]@{ value = @() } }
                [pscustomobject]@{ properties = [pscustomobject]@{} }
            }
            $null = Invoke-ApimPortalCollector -RunPath $script:portalRun.Path -Environment $script:portalEnv
            $record = (Get-RunManifest $script:portalRun.Path).collectors | Where-Object name -EQ Portal
            $record.items | Should -Be 4
            Test-ApimCollectorOutput -RunPath $script:portalRun.Path -Environment $script:portalEnv -Collector $record
            $config = Read-ApimSmokeOutputJson $script:portalRun.Path raw/portal/config.json
            $config.name | Should -BeNullOrEmpty
            $config.properties.enableBasicAuth | Should -BeNullOrEmpty
            $config.properties.signin.require | Should -BeNullOrEmpty
            $config.properties.delegation.delegateRegistration | Should -BeNullOrEmpty
            $config.properties.delegation.delegateSubscription | Should -BeNullOrEmpty
            $config.PSObject.Properties.Name | Should -Be @('name', 'properties')
        }

        It 'retains true/false/null distinctly for every Boolean (<Value>)' -TestCases @(
            @{ Value = $true }, @{ Value = $false }, @{ Value = $null }
        ) {
            param($Value)
            foreach ($kind in @('signin', 'signup', 'delegation', 'config', 'revisions')) {
                $resource = [pscustomobject]@{ name = 'synthetic'; properties = [pscustomobject]@{
                    enabled = $Value; enableBasicAuth = $Value
                    userRegistration = @{ enabled = $Value }; subscriptions = @{ enabled = $Value }
                    signin = @{ require = $Value }; delegation = @{
                        delegateRegistration = $Value; delegateSubscription = $Value
                    }; isCurrent = $Value; status = $null
                } }
                $safe = ConvertTo-ApimPortalResource -Resource $resource -Kind $kind
                $json = $safe | ConvertTo-Json -Depth 10 -Compress
                if ($null -eq $Value) { $json | Should -Not -Match ':true|:false' }
                elseif ($Value) { $json | Should -Not -Match ':false' }
                else { $json | Should -Not -Match ':true' }
            }
        }

        It 'isolates unsupported/failed endpoints and never treats them as disabled (<Endpoint>)' -TestCases @(
            @{ Endpoint = 'portalsettings/signin' }, @{ Endpoint = 'portalsettings/signup' },
            @{ Endpoint = 'portalsettings/delegation' }, @{ Endpoint = 'portalconfigs/default' },
            @{ Endpoint = 'portalRevisions' }
        ) {
            param($Endpoint)
            $script:failedPortalEndpoint = $Endpoint
            Mock Invoke-ApimArm { throw (Get-ApimArmFailure -StatusCode 404 -Attempts 1) } -ParameterFilter {
                $Uri -match "/$script:failedPortalEndpoint\?"
            }
            { Invoke-ApimPortalCollector -RunPath $script:portalRun.Path -Environment $script:portalEnv } |
                Should -Throw 'Portal collection incomplete.'
            $record = (Get-RunManifest $script:portalRun.Path).collectors | Where-Object name -EQ Portal
            $record.status | Should -Be Partial
            $record.items | Should -Be 4
            $record.errors | Should -Be 1
            $file = (Get-ApimPortalEndpoint | Where-Object Endpoint -EQ $Endpoint).File
            $record.files.Count | Should -Be 4
            $record.files | Should -Not -Contain $file
            Test-ApimCollectorOutput -RunPath $script:portalRun.Path -Environment $script:portalEnv -Collector $record
            Test-Path (Join-Path $script:portalRun.Path $file) | Should -BeFalse
            (Get-ChildItem (Join-Path $script:portalRun.Path raw/portal) -File).Count | Should -Be 4
        }

        It 'records Failed when every endpoint fails, without response data in logs/errors' {
            Mock Invoke-ApimArm { throw 'secret-canary' }
            { Invoke-ApimPortalCollector -RunPath $script:portalRun.Path -Environment $script:portalEnv } |
                Should -Throw 'Portal collection incomplete.'
            $record = (Get-RunManifest $script:portalRun.Path).collectors | Where-Object name -EQ Portal
            $record.status | Should -Be Failed
            $record.errors | Should -Be 5
            $record.items | Should -Be 0
            $record.files.Count | Should -Be 0
            Get-Content (Join-Path $script:portalRun.Path logs/run.log) -Raw | Should -Not -Match 'secret-canary'
            Test-Path (Join-Path $script:portalRun.Path raw/portal) | Should -BeFalse
        }

        It 'rejects invalid booleans, nested shapes and unknown revision status (<Kind>)' -TestCases @(
            @{ Kind = 'boolean' }, @{ Kind = 'nested' }, @{ Kind = 'enum' },
            @{ Kind = 'duplicate' }, @{ Kind = 'missing-properties' }, @{ Kind = 'empty-status' }
        ) {
            param($Kind)
            $script:badPortalKind = $Kind
            Mock Invoke-ApimArm {
                switch ($script:badPortalKind) {
                    boolean { return [pscustomobject]@{ properties = @{ enabled = 'false'; enableBasicAuth = 'false' } } }
                    nested { return [pscustomobject]@{ properties = @{ delegation = 'secret-canary'; userRegistration = 1 } } }
                    missing-properties { return [pscustomobject]@{} }
                    default {
                        $status = if ($script:badPortalKind -eq 'empty-status') { '' } else { 'secret-canary' }
                        $r = [pscustomobject]@{ name = 'synthetic'; properties = @{ isCurrent = $true; status = $status } }
                        if ($script:badPortalKind -eq 'duplicate') {
                            $r.properties.status = 'completed'
                            return [pscustomobject]@{ value = @($r, $r) }
                        }
                        return [pscustomobject]@{ value = @($r) }
                    }
                }
            }
            { Invoke-ApimPortalCollector -RunPath $script:portalRun.Path -Environment $script:portalEnv } |
                Should -Throw 'Portal collection incomplete.'
            (Get-RunManifest $script:portalRun.Path).warnings -join ' ' | Should -Not -Match 'secret-canary'
        }

        It 'paginates revisions using the existing guarded transport and counts all records' {
            Mock Invoke-ApimArm {
                if ($Uri -match '/portalRevisions\?') {
                    return & $script:portalArm -Uri $Uri -Method $Method -LogPath $LogPath
                }
                [pscustomobject]@{ properties = [pscustomobject]@{} }
            }
            Mock Invoke-ApimArmRequest {
                if ($Uri -match '\$skip=1') {
                    return [pscustomobject]@{ StatusCode = 200; Headers = @{}; Content = '{"value":[{"name":"a","properties":{"status":"pending","isCurrent":false}}]}' }
                }
                [pscustomobject]@{ StatusCode = 200; Headers = @{}; Content = (@{
                    value = @(@{ name = 'z'; properties = @{ status = 'completed'; isCurrent = $true } })
                    nextLink = $Uri + '&$skip=1'
                } | ConvertTo-Json -Depth 10 -Compress) }
            }
            $null = Invoke-ApimPortalCollector -RunPath $script:portalRun.Path -Environment $script:portalEnv
            $record = (Get-RunManifest $script:portalRun.Path).collectors | Where-Object name -EQ Portal
            $record.items | Should -Be 6
            $saved = Read-ApimSmokeOutputJson $script:portalRun.Path raw/portal/revisions.json
            $saved.value.name | Should -Be @('a', 'z')
            Test-ApimCollectorOutput -RunPath $script:portalRun.Path -Environment $script:portalEnv -Collector $record
            Should -Invoke Invoke-ApimArmRequest -Times 2 -Exactly -ParameterFilter { $Method -ceq 'GET' }
        }

        It 'rejects saved secret fields, invalid facts, missing files and count drift (<Kind>)' -TestCases @(
            @{ Kind = 'unknown' }, @{ Kind = 'nested' }, @{ Kind = 'boolean' },
            @{ Kind = 'missing' }, @{ Kind = 'count' }
        ) {
            param($Kind)
            $null = Invoke-ApimPortalCollector -RunPath $script:portalRun.Path -Environment $script:portalEnv
            $record = (Get-RunManifest $script:portalRun.Path).collectors | Where-Object name -EQ Portal
            $payload = Read-ApimSmokeOutputJson $script:portalRun.Path raw/portal/config.json
            switch ($Kind) {
                unknown { $payload | Add-Member unknown 'secret-canary' }
                nested { $payload.properties.delegation | Add-Member validationKey 'secret-canary' }
                boolean { $payload.properties.enableBasicAuth = 'false' }
                missing { Remove-Item (Join-Path $script:portalRun.Path raw/portal/revisions.json) }
                count { $record.items++ }
            }

            $null = Write-RunFile -RunPath $script:portalRun.Path -RelativePath raw/portal/config.json -InputObject $payload
            { Test-ApimCollectorOutput -RunPath $script:portalRun.Path -Environment $script:portalEnv -Collector $record } |
                Should -Throw
        }

        It 'rejects untrusted or inconsistent file inventories (<Kind>)' -TestCases @(
            @{ Kind = 'outside' }, @{ Kind = 'duplicate' }, @{ Kind = 'missing-entry' },
            @{ Kind = 'no-inventory' }, @{ Kind = 'partial-empty' }, @{ Kind = 'partial-complete' }
        ) {
            param($Kind)
            $null = Invoke-ApimPortalCollector -RunPath $script:portalRun.Path -Environment $script:portalEnv
            $record = (Get-RunManifest $script:portalRun.Path).collectors | Where-Object name -EQ Portal
            switch ($Kind) {
                outside { $record.files = @('../outside.json') }
                duplicate { $record.files += $record.files[0] }
                missing-entry { $record.files = @($record.files | Select-Object -Skip 1) }
                no-inventory { $record.PSObject.Properties.Remove('files') }
                partial-empty { $record.status = 'Partial'; $record.files = @() }
                partial-complete { $record.status = 'Partial' }
            }
            { Test-ApimCollectorOutput -RunPath $script:portalRun.Path -Environment $script:portalEnv -Collector $record } |
                Should -Throw
        }

        It 'rejects unsafe and duplicate paths before saving a manifest inventory (<File>)' -TestCases @(
            @{ File = '../outside.json' }, @{ File = '/absolute.json' },
            @{ File = 'raw/../outside.json' }, @{ File = 'raw/./config.json' },
            @{ File = 'raw\portal\config.json' }, @{ File = 'raw/portal/config.json' }
        ) {
            param($File)
            $arguments = @{
                RunPath = $script:portalRun.Path; Name = 'Portal'; Status = 'Partial'
                Files = @($File, $File)
            }
            { Set-RunCollectorStatus @arguments } |
                Should -Throw 'Collector file inventory contains an invalid or duplicate relative path.'
            @((Get-RunManifest $script:portalRun.Path).collectors).Count | Should -Be 0
        }
    }
}
