$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'APIM subscription model' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)

        $script:subscriptionRepoRoot = $RepoRoot

        BeforeAll {
            $script:subscriptionRawPath = Join-Path (
                $script:subscriptionRepoRoot
            ) 'tests/fixtures/synthetic-reference/raw/subscriptions.json'
            $script:subscriptionModelPath = Join-Path (
                $script:subscriptionRepoRoot
            ) 'tests/fixtures/synthetic-reference/model/subscriptions.json'
            $script:subscriptionSchemaPath = Join-Path (
                $script:subscriptionRepoRoot
            ) 'schemas/subscriptions.schema.json'

            function Read-SubscriptionTestJson {
                param(
                    [Parameter(Mandatory)]
                    [string] $Path
                )

                return Get-Content -LiteralPath $Path -Raw |
                    ConvertFrom-Json -Depth 100
            }

            function Copy-SubscriptionTestObject {
                param(
                    [Parameter(Mandatory)]
                    [object] $InputObject
                )

                return $InputObject | ConvertTo-Json -Depth 100 |
                    ConvertFrom-Json -Depth 100
            }

            function ConvertTo-SubscriptionCompactJson {
                param(
                    [Parameter(Mandatory)]
                    [string] $Json
                )

                return [System.Text.Json.Nodes.JsonNode]::Parse(
                    $Json
                ).ToJsonString()
            }
        }

        It 'matches the deterministic synthetic subscription fixture' {
            $payload = Read-SubscriptionTestJson $script:subscriptionRawPath
            $payload.value = @($payload.value | Sort-Object name -Descending)

            $actual = @(Get-ApimSubscriptionModel `
                    -SubscriptionsPayload $payload)
            $actualJson = ConvertTo-Json -InputObject $actual -Depth 100
            $expectedJson = Get-Content -LiteralPath (
                $script:subscriptionModelPath
            ) -Raw

            $actual.Count | Should -Be 6
            ConvertTo-SubscriptionCompactJson $actualJson |
                Should -Be (
                    ConvertTo-SubscriptionCompactJson $expectedJson
                )
        }

        It 'classifies four AllApis subscriptions and their targets' {
            $payload = Read-SubscriptionTestJson $script:subscriptionRawPath
            $model = @(Get-ApimSubscriptionModel `
                    -SubscriptionsPayload $payload)

            @($model | Where-Object scopeType -EQ 'AllApis').Count |
                Should -Be 4
            ($model | Where-Object subscriptionId -EQ 'product-client').
                scopeTarget | Should -Be 'internal'
            ($model | Where-Object subscriptionId -EQ 'api-client').
                scopeTarget | Should -Be 'orders-v1'
        }

        It 'detects the built-in master and stable flags' {
            $payload = Read-SubscriptionTestJson $script:subscriptionRawPath
            $model = @(Get-ApimSubscriptionModel `
                    -SubscriptionsPayload $payload)
            $master = $model | Where-Object subscriptionId -EQ 'master'
            $apiClient = $model |
                Where-Object subscriptionId -EQ 'api-client'

            $master.isBuiltInMaster | Should -BeTrue
            $master.flags | Should -Be @(
                'AllApis',
                'AllowTracing',
                'BuiltInMaster',
                'NoExpiration'
            )
            $apiClient.flags | Should -Be @(
                'AllowTracing',
                'NoExpiration',
                'OwnerMissing'
            )
            $master.calls90d | Should -BeNullOrEmpty
            $master.lastUsed | Should -BeNullOrEmpty
            $master.modelStatus | Should -Be 'Partial'
            $master.missingInputs | Should -Be @('usage')
        }

        It 'writes a closed schema-valid subscription array' {
            $payload = Read-SubscriptionTestJson $script:subscriptionRawPath
            $model = @(Get-ApimSubscriptionModel `
                    -SubscriptionsPayload $payload)
            $runPath = Join-Path $TestDrive 'subscription-model'
            $null = New-Item -ItemType Directory -Path $runPath

            $path = Write-ApimSubscriptionModel `
                -RunPath $runPath -Records $model
            $json = Get-Content -LiteralPath $path -Raw

            ($json | Test-Json `
                    -SchemaFile $script:subscriptionSchemaPath) |
                Should -BeTrue
            ($json | ConvertFrom-Json -Depth 100).Count | Should -Be 6
        }

        It 'writes a schema-valid empty array' {
            $runPath = Join-Path $TestDrive 'empty-subscription-model'
            $null = New-Item -ItemType Directory -Path $runPath

            $path = Write-ApimSubscriptionModel `
                -RunPath $runPath -Records @()
            $json = Get-Content -LiteralPath $path -Raw

            $json.Trim() | Should -Be '[]'
            ($json | Test-Json `
                    -SchemaFile $script:subscriptionSchemaPath) |
                Should -BeTrue
        }

        It 'rejects unsupported scopes' {
            $payload = Read-SubscriptionTestJson $script:subscriptionRawPath
            $payload.value[0].properties.scope += '/operations/get'

            {
                Get-ApimSubscriptionModel -SubscriptionsPayload $payload
            } | Should -Throw '*scope was unsupported*'
        }

        It 'rejects inconsistent built-in ownership' {
            $payload = Read-SubscriptionTestJson $script:subscriptionRawPath
            $master = $payload.value |
                Where-Object name -EQ 'master'
            $master.properties.ownerType = 'User'

            {
                Get-ApimSubscriptionModel -SubscriptionsPayload $payload
            } | Should -Throw '*built-in ownership was inconsistent*'
        }

        It 'rejects invalid state and date values' {
            $invalidState = Read-SubscriptionTestJson (
                $script:subscriptionRawPath
            )
            $invalidState.value[0].properties.state = 'unknown'
            {
                Get-ApimSubscriptionModel `
                    -SubscriptionsPayload $invalidState
            } | Should -Throw '*invalid model property*'

            $invalidDate = Read-SubscriptionTestJson (
                $script:subscriptionRawPath
            )
            $invalidDate.value[0].properties.createdDate = 'not-a-date'
            {
                Get-ApimSubscriptionModel `
                    -SubscriptionsPayload $invalidDate
            } | Should -Throw '*valid date-time*'
        }

        It 'fails closed before writing an invalid model' {
            $payload = Read-SubscriptionTestJson $script:subscriptionRawPath
            $model = @(Get-ApimSubscriptionModel `
                    -SubscriptionsPayload $payload)
            $invalidRecord = Copy-SubscriptionTestObject $model[0]
            $invalidRecord | Add-Member -NotePropertyName unexpected `
                -NotePropertyValue $true
            $model[0] = $invalidRecord
            $runPath = Join-Path $TestDrive 'invalid-subscription-model'
            $null = New-Item -ItemType Directory -Path $runPath

            {
                Write-ApimSubscriptionModel `
                    -RunPath $runPath -Records $model
            } | Should -Throw
            Test-Path -LiteralPath (
                Join-Path $runPath 'model/subscriptions.json'
            ) | Should -BeFalse
        }
    }
}
