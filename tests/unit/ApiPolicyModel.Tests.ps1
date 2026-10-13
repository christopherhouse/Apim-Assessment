$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'API and policy matrix models' {
    InModuleScope ApimAssessment -Parameters @{
        RepoRoot = $repoRoot
    } {
        param($RepoRoot)

        $script:modelRepoRoot = $RepoRoot

        BeforeAll {
            $script:modelFixtureRoot = Join-Path $script:modelRepoRoot (
                'tests/fixtures/synthetic-reference'
            )
            $script:modelSchemas = @{
                apis = Join-Path $script:modelRepoRoot 'schemas/apis.schema.json'
                operations = Join-Path $script:modelRepoRoot (
                    'schemas/operations.schema.json'
                )
                policyMatrix = Join-Path $script:modelRepoRoot (
                    'schemas/policyMatrix.schema.json'
                )
            }

            function Read-ModelFixtureJson {
                param(
                    [Parameter(Mandatory)]
                    [string] $RelativePath
                )

                return Get-Content -LiteralPath (
                    Join-Path $script:modelFixtureRoot $RelativePath
                ) -Raw | ConvertFrom-Json -Depth 100
            }

            function Get-SyntheticModelInput {
                $apis = Read-ModelFixtureJson 'raw/apis.json'
                $products = Read-ModelFixtureJson 'raw/products.json'
                $operations = @{}
                $revisions = @{}
                $tags = @{}
                foreach ($api in @($apis.value)) {
                    $apiName = [string] $api.name
                    $operations[$apiName] = Read-ModelFixtureJson (
                        "raw/operations/$apiName.json"
                    )
                    $revisions[$apiName] = Read-ModelFixtureJson (
                        "raw/apiRevisions/$apiName.json"
                    )
                    $tags[$apiName] = Read-ModelFixtureJson (
                        "raw/apiTags/$apiName.json"
                    )
                }

                $productApis = @{}
                foreach ($product in @($products.value)) {
                    $productName = [string] $product.name
                    $productApis[$productName] = Read-ModelFixtureJson (
                        "raw/productApis/$productName.json"
                    )
                }

                $policyFlags = @(
                    foreach ($entry in @(
                            (Read-ModelFixtureJson (
                                'model/policyFlags.json'
                            )).policies
                        )) {
                        $record = [ordered]@{
                            product = $entry.product
                            apiId = $entry.apiId
                            operationId = $entry.operationId
                            evaluationStatus = $entry.evaluationStatus
                        }
                        foreach ($property in $entry.flags.PSObject.Properties) {
                            $record[$property.Name] = $property.Value
                        }
                        [pscustomobject] $record
                    }
                )

                return @{
                    ApisPayload = $apis
                    OperationsByApi = $operations
                    RevisionsByApi = $revisions
                    TagsByApi = $tags
                    ProductsPayload = $products
                    ProductApisByProduct = $productApis
                    PolicyFlags = $policyFlags
                }
            }

            function ConvertTo-ModelTestJson {
                param(
                    [Parameter(Mandatory)]
                    [AllowEmptyCollection()]
                    [object[]] $Records
                )

                return ConvertTo-Json -InputObject $Records -Depth 100 `
                    -Compress
            }

            function Copy-ModelTestObject {
                param(
                    [Parameter(Mandatory)]
                    [object] $InputObject
                )

                return $InputObject | ConvertTo-Json -Depth 100 |
                    ConvertFrom-Json -Depth 100
            }
        }

        It 'matches the deterministic synthetic model fixtures' {
            $inputData = Get-SyntheticModelInput
            $inputData.ApisPayload.value = @(
                $inputData.ApisPayload.value |
                    Sort-Object name -Descending
            )
            $inputData.PolicyFlags = @(
                $inputData.PolicyFlags |
                    Sort-Object apiId, product -Descending
            )

            $actual = Get-ApimApiPolicyModel @inputData

            $actual.apis.Count | Should -Be 2
            $actual.operations.Count | Should -Be 2
            $actual.policyMatrix.Count | Should -Be 2
            foreach ($name in @('apis', 'operations', 'policyMatrix')) {
                $expected = @(Read-ModelFixtureJson "model/$name.json")
                ConvertTo-ModelTestJson $actual.$name |
                    Should -Be (ConvertTo-ModelTestJson $expected)
            }
        }

        It 'aggregates multi-product controls conservatively' {
            $inputData = Get-SyntheticModelInput
            $model = Get-ApimApiPolicyModel @inputData
            $operation = $model.operations |
                Where-Object operationId -EQ 'get-orders'
            $matrix = $model.policyMatrix |
                Where-Object apiId -EQ 'orders-v1'

            $operation.products | Should -Be @('internal', 'partner')
            $operation.callerAuthJwt | Should -BeTrue
            $operation.throttling | Should -BeTrue
            $operation.throttlingAllPaths | Should -BeFalse
            $operation.hardcodedSecret | Should -BeTrue
            $matrix.callerAuth | Should -Be 'Pass'
            $matrix.rateLimit | Should -Be 'Fail'
            $matrix.noHardcodedSecret | Should -Be 'Fail'
            $matrix.basePresent | Should -Be 'Fail'
            $matrix.backendAuth | Should -Be 'NA'
        }

        It 'derives subscription fallback, paths, revisions, and tags' {
            $inputData = Get-SyntheticModelInput
            $model = Get-ApimApiPolicyModel @inputData
            $api = $model.apis | Where-Object apiId -EQ 'status-v1'
            $operation = $model.operations |
                Where-Object apiId -EQ 'status-v1'

            $api.subscriptionRequired | Should -BeTrue
            $api.callerAuth | Should -Be 'SubscriptionKeyOnly'
            $api.revisionCount | Should -Be 2
            $api.nonCurrentOnlineRevisions | Should -Be 1
            $api.tags | Should -Be @('platform')
            $api.ownerTag | Should -BeNullOrEmpty
            $operation.fullPath | Should -Be '/status'
        }

        It 'uses authoritative backend credentials for matrix controls' {
            $inputData = Get-SyntheticModelInput
            $inputData.BackendCredentialByApi = @{
                'orders-v1' = $true
                'status-v1' = $false
            }

            $model = Get-ApimApiPolicyModel @inputData
            $orders = $model.policyMatrix |
                Where-Object apiId -EQ 'orders-v1'
            $status = $model.policyMatrix |
                Where-Object apiId -EQ 'status-v1'
            $ordersOperation = $model.operations |
                Where-Object apiId -EQ 'orders-v1'

            $orders.backendAuth | Should -Be 'Pass'
            $orders.evaluationStatus | Should -Be 'Complete'
            $status.backendAuth | Should -Be 'Fail'
            $ordersOperation.backendAuthAllPaths | Should -BeTrue
            $ordersOperation.missingInputs | Should -Be @('usage')
        }

        It 'uses null and NA when unresolved fragments prevent a decision' {
            $inputData = Get-SyntheticModelInput
            $statusFlag = $inputData.PolicyFlags |
                Where-Object apiId -EQ 'status-v1'
            $statusFlag.evaluationStatus = 'Partial'
            $statusFlag.hardcodedSecret = $true

            $model = Get-ApimApiPolicyModel @inputData
            $api = $model.apis | Where-Object apiId -EQ 'status-v1'
            $matrix = $model.policyMatrix |
                Where-Object apiId -EQ 'status-v1'

            $api.callerAuth | Should -BeNullOrEmpty
            $api.throttling | Should -BeNullOrEmpty
            $api.hardcodedSecret | Should -BeTrue
            $api.missingInputs | Should -Contain 'policyFragments'
            $matrix.callerAuth | Should -Be 'NA'
            $matrix.rateLimit | Should -Be 'NA'
            $matrix.corsSafe | Should -Be 'NA'
            $matrix.noHardcodedSecret | Should -Be 'Fail'
            $matrix.evaluationStatus | Should -Be 'Partial'
        }

        It 'supports an API with no operations without inventing results' {
            $inputData = Get-SyntheticModelInput
            $inputData.ApisPayload.value = @(
                $inputData.ApisPayload.value |
                    Where-Object name -EQ 'status-v1'
            )
            $inputData.OperationsByApi = @{
                'status-v1' = [pscustomobject] @{ value = @() }
            }
            $inputData.RevisionsByApi = @{
                'status-v1' = $inputData.RevisionsByApi['status-v1']
            }
            $inputData.TagsByApi = @{
                'status-v1' = $inputData.TagsByApi['status-v1']
            }
            $inputData.ProductApisByProduct = @{
                internal = [pscustomobject] @{ value = @() }
                partner = [pscustomobject] @{ value = @() }
            }
            $inputData.PolicyFlags = @()
            $inputData.ApisPayload.value[0].properties.apiVersion = $null

            $model = Get-ApimApiPolicyModel @inputData

            $model.operations.Count | Should -Be 0
            $model.apis[0].products.Count | Should -Be 0
            $model.apis[0].version | Should -BeNullOrEmpty
            $model.apis[0].callerAuth | Should -BeNullOrEmpty
            $model.apis[0].throttling | Should -BeNullOrEmpty
            $model.policyMatrix[0].callerAuth | Should -Be 'NA'
            $model.policyMatrix[0].noHardcodedSecret | Should -Be 'NA'
        }

        It 'matches a null product path for an API outside all products' {
            $inputData = Get-SyntheticModelInput
            $inputData.ApisPayload.value = @(
                $inputData.ApisPayload.value |
                    Where-Object name -EQ 'status-v1'
            )
            $inputData.OperationsByApi = @{
                'status-v1' = $inputData.OperationsByApi['status-v1']
            }
            $inputData.RevisionsByApi = @{
                'status-v1' = $inputData.RevisionsByApi['status-v1']
            }
            $inputData.TagsByApi = @{
                'status-v1' = $inputData.TagsByApi['status-v1']
            }
            $inputData.ProductApisByProduct = @{
                internal = [pscustomobject] @{ value = @() }
                partner = [pscustomobject] @{ value = @() }
            }
            $flag = $inputData.PolicyFlags |
                Where-Object apiId -EQ 'status-v1'
            $flag.product = $null
            $inputData.PolicyFlags = @($flag)

            $model = Get-ApimApiPolicyModel @inputData

            $model.operations[0].products.Count | Should -Be 0
            $model.operations[0].operationId | Should -Be 'get-status'
        }

        It 'clears a catalog backend host when policy overrides the target' {
            $inputData = Get-SyntheticModelInput
            $statusFlag = $inputData.PolicyFlags |
                Where-Object apiId -EQ 'status-v1'
            $statusFlag.backendOverride = $true

            $model = Get-ApimApiPolicyModel @inputData
            $api = $model.apis | Where-Object apiId -EQ 'status-v1'

            $api.backendHost | Should -BeNullOrEmpty
            $api.missingInputs | Should -Contain 'backendTarget'
        }

        It 'writes all arrays only after every closed schema validates' {
            $inputData = Get-SyntheticModelInput
            $model = Get-ApimApiPolicyModel @inputData
            $runPath = Join-Path $TestDrive 'valid-model'
            $null = New-Item -ItemType Directory -Path $runPath

            $paths = @(Write-ApimApiPolicyModel -RunPath $runPath `
                    -Model $model)

            $paths.Count | Should -Be 3
            foreach ($name in @('apis', 'operations', 'policyMatrix')) {
                $path = Join-Path $runPath "model/$name.json"
                Test-Path -LiteralPath $path | Should -BeTrue
                $json = Get-Content -LiteralPath $path -Raw
                ($json | Test-Json -SchemaFile $script:modelSchemas[$name]) |
                    Should -BeTrue
                ($json | ConvertFrom-Json).Count |
                    Should -Be $model.$name.Count
            }
        }

        It 'writes schema-valid empty arrays' {
            $runPath = Join-Path $TestDrive 'empty-model'
            $null = New-Item -ItemType Directory -Path $runPath
            $model = [pscustomobject] @{
                apis = @()
                operations = @()
                policyMatrix = @()
            }

            $null = Write-ApimApiPolicyModel -RunPath $runPath -Model $model

            foreach ($name in @('apis', 'operations', 'policyMatrix')) {
                $json = Get-Content -LiteralPath (
                    Join-Path $runPath "model/$name.json"
                ) -Raw
                $json.Trim() | Should -Be '[]'
                ($json | Test-Json -SchemaFile $script:modelSchemas[$name]) |
                    Should -BeTrue
            }
        }

        It 'fails closed before writing when any model is invalid' {
            $inputData = Get-SyntheticModelInput
            $model = Get-ApimApiPolicyModel @inputData
            $invalidOperation = Copy-ModelTestObject $model.operations[0]
            $invalidOperation | Add-Member -NotePropertyName unexpected `
                -NotePropertyValue $true
            $model.operations[0] = $invalidOperation
            $runPath = Join-Path $TestDrive 'invalid-model'
            $null = New-Item -ItemType Directory -Path $runPath

            {
                Write-ApimApiPolicyModel -RunPath $runPath -Model $model
            } | Should -Throw
            Test-Path -LiteralPath (Join-Path $runPath 'model') |
                Should -BeFalse
        }

        It 'rejects incomplete API payload maps' {
            $inputData = Get-SyntheticModelInput
            $inputData.OperationsByApi.Remove('status-v1')

            {
                Get-ApimApiPolicyModel @inputData
            } | Should -Throw '*missing an API*'
        }

        It 'rejects duplicate policy paths' {
            $inputData = Get-SyntheticModelInput
            $inputData.PolicyFlags = @(
                $inputData.PolicyFlags
                Copy-ModelTestObject $inputData.PolicyFlags[0]
            )

            {
                Get-ApimApiPolicyModel @inputData
            } | Should -Throw '*duplicate product path*'
        }

        It 'rejects policy paths for unknown operations' {
            $inputData = Get-SyntheticModelInput
            $extraFlag = Copy-ModelTestObject $inputData.PolicyFlags[0]
            $extraFlag.operationId = 'unknown-operation'
            $inputData.PolicyFlags = @(
                $inputData.PolicyFlags
                $extraFlag
            )

            {
                Get-ApimApiPolicyModel @inputData
            } | Should -Throw '*unknown API or operation path*'
        }

        It 'rejects duplicate catalog resources' {
            $inputData = Get-SyntheticModelInput
            $inputData.ApisPayload.value = @(
                $inputData.ApisPayload.value
                Copy-ModelTestObject $inputData.ApisPayload.value[0]
            )

            {
                Get-ApimApiPolicyModel @inputData
            } | Should -Throw '*duplicate resource name*'
        }
    }
}
