$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Counts-only organization inventory' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:organizationRepository = $Repository

        BeforeAll { $script:organizationArm = ${function:Invoke-ApimArm} }
        BeforeEach {
            $config = Import-PowerShellDataFile (Join-Path $script:organizationRepository 'config/sample.psd1')
            $config.Output.Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $script:organizationEnvironment = $config.Environments[0]
            $script:organizationRun = New-ApimRun -Config $config -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000010' -Operator Synthetic `
                -RunId synthetic-organization
            Mock Invoke-ApimArm {
                if ($Uri -match '/users\?') {
                    $user = [pscustomobject]@{
                        name = 'SYNTHETIC_USER_ID_CANARY'
                        properties = [pscustomobject]@{
                            state = 'active'; email = 'SYNTHETIC_EMAIL_CANARY@example.invalid'
                            firstName = 'SYNTHETIC_IDENTITY_CANARY'
                            identities = @(
                                @{ provider = 'aad'; id = 'SYNTHETIC_SUBJECT_CANARY' }
                                @{ provider = 'aad'; id = 'SYNTHETIC_SUBJECT_CANARY' }
                                @{ provider = 'SYNTHETIC_PROVIDER_CANARY' }
                            )
                        }
                    }
                    return [pscustomobject]@{ value = @($user, $user) }
                }
                $properties = [pscustomobject]@{
                    type = 'custom'; builtIn = $false; versioningScheme = 'Segment'
                    value = '<policies>SYNTHETIC_XML_SECRET_CANARY</policies>'
                    description = 'SYNTHETIC_DESCRIPTION_CANARY'; unknown = 'SYNTHETIC_SECRET_CANARY'
                }
                [pscustomobject]@{ value = @(
                    [pscustomobject]@{ name = 'synthetic-z'; properties = $properties }
                    [pscustomobject]@{ name = 'synthetic-a'; properties = $properties }
                ); unknown = 'SYNTHETIC_SECRET_CANARY' }
            }
        }

        It 'writes seven deterministic closed outputs without identities, provider strings or fragment XML' {
            $paths = @(Invoke-ApimOrganizationCollector -RunPath $script:organizationRun.Path `
                -Environment $script:organizationEnvironment)
            $paths.Count | Should -Be 7
            $record = (Get-RunManifest $script:organizationRun.Path).collectors |
                Where-Object name -CEQ Organization
            $record.status | Should -Be Completed
            $record.items | Should -Be 13
            $record.files | Should -Be @((Get-ApimOrganizationEndpoint).File)
            Test-ApimCollectorOutput -RunPath $script:organizationRun.Path `
                -Environment $script:organizationEnvironment -Collector $record
            $summary = Read-ApimSmokeOutputJson $script:organizationRun.Path raw/users.summary.json
            $summary.total | Should -Be 1
            $summary.byState.active | Should -Be 1
            $summary.byProvider.aad | Should -Be 1
            $summary.byProvider.Unknown | Should -Be 1
            foreach ($endpoint in @(Get-ApimOrganizationEndpoint | Where-Object Kind -CNE users)) {
                $payload = Read-ApimSmokeOutputJson $script:organizationRun.Path $endpoint.File
                $payload.value.name | Should -Be @('synthetic-a', 'synthetic-z')
            }
            $before = @($paths | ForEach-Object { Get-Content -LiteralPath $_ -Raw })
            $null = Invoke-ApimOrganizationCollector -RunPath $script:organizationRun.Path `
                -Environment $script:organizationEnvironment
            @($paths | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) | Should -Be $before
            $persisted = (Get-ChildItem $script:organizationRun.Path -Recurse -File |
                ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
            $persisted | Should -Not -Match 'CANARY|<policies>|identities|firstName|email'
            Should -Invoke Invoke-ApimArm -Exactly -Times 14 -ParameterFilter {
                $Method -ceq 'GET' -and $Uri -match '\?api-version=2024-05-01$' -and
                $Uri -notmatch 'listSecrets|listValue|listKeys|/secrets|token'
            }
        }

        It 'counts known empty inventories as zero, not as unavailable' {
            Mock Invoke-ApimArm { [pscustomobject]@{ value = @() } }
            $null = Invoke-ApimOrganizationCollector -RunPath $script:organizationRun.Path `
                -Environment $script:organizationEnvironment
            $record = (Get-RunManifest $script:organizationRun.Path).collectors |
                Where-Object name -CEQ Organization
            $record.status | Should -Be Completed
            $record.items | Should -Be 0
            Test-ApimCollectorOutput -RunPath $script:organizationRun.Path `
                -Environment $script:organizationEnvironment -Collector $record
        }

        It 'preserves independent evidence when <Kind> fails with <Status>' -ForEach @(
            @{ Kind = 'groups'; Status = 403 }
            @{ Kind = 'workspaces'; Status = 404 }
            @{ Kind = 'users'; Status = 503 }
            @{ Kind = 'policyFragments'; Status = 403 }
        ) {
            $script:organizationFailedKind = $Kind
            $script:organizationFailureStatus = $Status
            Mock Invoke-ApimArm {
                throw (Get-ApimArmFailure -StatusCode $script:organizationFailureStatus -Attempts 1)
            } -ParameterFilter { $Uri -match "/$script:organizationFailedKind\?" }
            { Invoke-ApimOrganizationCollector -RunPath $script:organizationRun.Path `
                    -Environment $script:organizationEnvironment } | Should -Throw '*incomplete*'
            $record = (Get-RunManifest $script:organizationRun.Path).collectors |
                Where-Object name -CEQ Organization
            $record.status | Should -Be Partial
            $record.errors | Should -Be 1
            $record.files.Count | Should -Be 6
            $missing = (Get-ApimOrganizationEndpoint | Where-Object Kind -CEQ $Kind).File
            $record.files | Should -Not -Contain $missing
            Test-Path (Join-Path $script:organizationRun.Path $missing) | Should -BeFalse
            Test-ApimCollectorOutput -RunPath $script:organizationRun.Path `
                -Environment $script:organizationEnvironment -Collector $record
        }

        It 'does not turn malformed or conflicting users into a zero summary (<Kind>)' -ForEach @(
            @{ Kind = 'conflict' }; @{ Kind = 'identities' }; @{ Kind = 'collection' }
        ) {
            $script:organizationMalformedKind = $Kind
            Mock Invoke-ApimArm {
                if ($script:organizationMalformedKind -ceq 'collection') {
                    return [pscustomobject]@{ value = $null }
                }
                $identities = if ($script:organizationMalformedKind -ceq 'identities') { 'SYNTHETIC_CANARY' }
                    else { @() }
                [pscustomobject]@{ value = @(
                    [pscustomobject]@{ name = 'SYNTHETIC_CANARY'; properties = @{ state = 'active'; identities = $identities } }
                    [pscustomobject]@{ name = 'SYNTHETIC_CANARY'; properties = @{ state = 'blocked'; identities = @() } }
                ) }
            } -ParameterFilter { $Uri -match '/users\?' }
            { Invoke-ApimOrganizationCollector -RunPath $script:organizationRun.Path `
                    -Environment $script:organizationEnvironment } | Should -Throw '*incomplete*'
            Test-Path (Join-Path $script:organizationRun.Path raw/users.summary.json) | Should -BeFalse
        }

        It 'rejects saved identity fields, unknown metadata and inconsistent counts (<Kind>)' -ForEach @(
            @{ Kind = 'userField' }; @{ Kind = 'fragmentField' }; @{ Kind = 'count' }
        ) {
            $null = Invoke-ApimOrganizationCollector -RunPath $script:organizationRun.Path `
                -Environment $script:organizationEnvironment
            $file = if ($Kind -ceq 'fragmentField') { 'raw/policyFragments.json' }
                else { 'raw/users.summary.json' }
            $payload = Read-ApimSmokeOutputJson $script:organizationRun.Path $file
            switch ($Kind) {
                userField { $payload | Add-Member NoteProperty identities @('SYNTHETIC_CANARY') }
                fragmentField { $payload.value[0].properties | Add-Member NoteProperty value 'SYNTHETIC_CANARY' }
                count { $payload.total = 2 }
            }
            $null = Write-RunFile -RunPath $script:organizationRun.Path -RelativePath $file -InputObject $payload
            $record = (Get-RunManifest $script:organizationRun.Path).collectors |
                Where-Object name -CEQ Organization
            { Test-ApimCollectorOutput -RunPath $script:organizationRun.Path `
                    -Environment $script:organizationEnvironment -Collector $record } | Should -Throw
        }

        It 'aggregates users across guarded ARM pages without persisting individual responses' {
            Mock Invoke-ApimArm {
                & $script:organizationArm -Method $Method -Uri $Uri -LogPath $LogPath
            } -ParameterFilter { $Uri -match '/users\?' }
            Mock Start-Sleep {}
            Mock Invoke-ApimArmRequest {
                $name = if ($Uri -match '\$skip=1') { 'SYNTHETIC_USER_TWO_CANARY' }
                    else { 'SYNTHETIC_USER_ONE_CANARY' }
                $body = @{ value = @(@{ name = $name; properties = @{
                    state = 'pending'; identities = @(@{ provider = 'basic'; id = 'SYNTHETIC_CANARY' })
                } }) }
                if ($Uri -notmatch '\$skip=1') {
                    $body.nextLink = $Uri + '&$skip=1'
                }
                [pscustomobject]@{ StatusCode = 200; Headers = @{}
                    Content = ConvertTo-Json $body -Depth 10 -Compress }
            }
            $null = Invoke-ApimOrganizationCollector -RunPath $script:organizationRun.Path `
                -Environment $script:organizationEnvironment
            $summary = Read-ApimSmokeOutputJson $script:organizationRun.Path raw/users.summary.json
            $summary.total | Should -Be 2
            $summary.byState.pending | Should -Be 2
            $summary.byProvider.basic | Should -Be 2
            Should -Invoke Invoke-ApimArmRequest -Exactly -Times 2
        }
    }
}
