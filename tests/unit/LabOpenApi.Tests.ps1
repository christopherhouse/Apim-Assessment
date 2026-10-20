BeforeAll {
    $script:labRepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:scenarioRoot = Join-Path $script:labRepoRoot 'infra/live-validation-lab/scenarios'
    $script:inventory = Get-Content -LiteralPath (Join-Path $script:scenarioRoot 'inventory.json') -Raw |
        ConvertFrom-Json -AsHashtable
    . (Join-Path $script:labRepoRoot 'src/Model/OpenApiQuality.ps1')
}

Describe 'Synthetic lab business API contracts' {
    It 'contains exactly five uniquely named, self-contained business APIs matching the inventory' {
        $expected = @('e-commerce', 'manufacturing', 'plm', 'service-management', 'supply-chain')
        @($script:inventory.apis.apiId) | Should -Be $expected
        @($script:inventory.apis.document | Sort-Object -Unique).Count | Should -Be 5
        $files = @(Get-ChildItem -LiteralPath $script:scenarioRoot -Filter '*.openapi.json' -File)
        @($files.Name | Sort-Object) | Should -Be @($script:inventory.apis.document | Sort-Object)
        $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($entry in $script:inventory.apis) {
            $entry.document | Should -BeExactly "$($entry.apiId).openapi.json"
            $entry.path | Should -BeExactly $entry.apiId
            $doc = Get-Content -LiteralPath (Join-Path $script:scenarioRoot $entry.document) -Raw |
                ConvertFrom-Json -AsHashtable
            $operations = @(
                foreach ($path in $doc.paths.Values) {
                    foreach ($method in @('get', 'post', 'put', 'patch', 'delete')) {
                        if ($path.ContainsKey($method)) { $path[$method] }
                    }
                }
            )
            $operations.Count | Should -Be $entry.operationCount
            foreach ($operation in $operations) {
                $ids.Add($operation.operationId) | Should -BeTrue
            }
        }
        $ids.Count | Should -Be 16
    }

    It 'retains private, dormant and product-context controls without adding a sixth API' {
        $privateApis = @($script:inventory.apis | Where-Object publication -EQ 'privateOnly')
        $privateApis.Count | Should -Be 1
        $privateApis[0].apiId | Should -BeExactly 'plm'
        $dormantApis = @($script:inventory.apis | Where-Object initialTraffic -EQ 'none')
        $dormantApis.Count | Should -Be 1
        $dormantApis[0].apiId | Should -BeExactly 'manufacturing'
        $dormantApis[0].publication | Should -BeExactly 'gateway'
        $productApis = @($script:inventory.apis | Where-Object { $_.assertions -contains 'productContext' })
        $productApis.Count | Should -Be 2
        foreach ($entry in $productApis) { $entry.productIds | Should -Be @('business', 'partner') }
        $faultApis = @($script:inventory.apis | Where-Object { $_.assertions -contains 'boundedFaultProfile' })
        $faultApis.Count | Should -Be 1
        $faultApis[0].apiId | Should -BeExactly 'service-management'
    }

    Context '<ApiId>' -ForEach @(
        @{ ApiId = 'e-commerce' }
        @{ ApiId = 'manufacturing' }
        @{ ApiId = 'plm' }
        @{ ApiId = 'service-management' }
        @{ ApiId = 'supply-chain' }
    ) {
        BeforeAll {
            $script:apiText = Get-Content -LiteralPath (Join-Path $script:scenarioRoot "$ApiId.openapi.json") -Raw
            $script:apiDocument = $script:apiText | ConvertFrom-Json -AsHashtable
        }

        It 'uses only resolvable local references and a non-routable HTTPS backend placeholder' {
            Test-ApimOpenApiDocument -Json $script:apiText | Should -BeExactly 'Supported'
            foreach ($server in $script:apiDocument.servers) {
                ([uri]$server.url).Scheme | Should -BeExactly 'https'
                ([uri]$server.url).Host | Should -BeExactly 'backend.invalid'
            }
            $nodes = [System.Collections.Generic.Stack[object]]::new()
            $nodes.Push($script:apiDocument)
            while ($nodes.Count -gt 0) {
                $node = $nodes.Pop()
                if ($node -is [System.Collections.IDictionary]) {
                    if ($node.Contains('$ref')) {
                        $node['$ref'] | Should -Match '^#/components/(schemas|responses)/[A-Za-z][A-Za-z0-9]*$'
                        $target = $script:apiDocument
                        foreach ($segment in $node['$ref'].Substring(2).Split('/')) {
                            $target.Contains($segment) | Should -BeTrue
                            $target = $target[$segment]
                        }
                        $target | Should -Not -BeNullOrEmpty
                    }
                    foreach ($value in $node.Values) { $nodes.Push($value) }
                }
                elseif ($node -is [array]) {
                    foreach ($value in $node) { $nodes.Push($value) }
                }
            }
        }

        It 'defines representative request/response bodies, required path bindings and both caller credentials' {
            $script:apiDocument.security.Count | Should -Be 1
            @($script:apiDocument.security[0].Keys | Sort-Object) |
                Should -Be @('entraBearer', 'productSubscription')
            $script:apiDocument.components.securitySchemes.entraBearer.scheme | Should -BeExactly 'bearer'
            $script:apiDocument.components.securitySchemes.productSubscription.in | Should -BeExactly 'header'
            $writes = 0
            foreach ($pathName in $script:apiDocument.paths.Keys) {
                $path = $script:apiDocument.paths[$pathName]
                $expectedParameters = @([regex]::Matches($pathName, '\{([^}]+)\}') |
                    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
                $actualParameters = @()
                if ($path.Contains('parameters')) {
                    $actualParameters = @($path.parameters | Where-Object { $_.in -eq 'path' } | Sort-Object name)
                }
                @($actualParameters | ForEach-Object { $_.name }) | Should -Be $expectedParameters
                foreach ($parameter in $actualParameters) { $parameter.required | Should -BeTrue }
                foreach ($method in @('get', 'post', 'patch')) {
                    if (-not $path.Contains($method)) { continue }
                    $operation = $path[$method]
                    $operation.description | Should -Not -BeNullOrEmpty
                    $operation.Contains('security') | Should -BeFalse
                    $operation.responses.Contains('default') | Should -BeTrue
                    $success = @($operation.responses.Keys | Where-Object { $_ -cmatch '^2\d\d$' })
                    $success.Count | Should -Be 1
                    $operation.responses[$success[0]].content.'application/json'.schema.Contains('$ref') | Should -BeTrue
                    if ($method -in @('post', 'patch')) {
                        $writes++
                        $operation.requestBody.required | Should -BeTrue
                        $operation.requestBody.content.'application/json'.schema.Contains('$ref') | Should -BeTrue
                    }
                }
            }
            $writes | Should -BeGreaterThan 0
        }

        It 'validates every schema example and rejects a missing required business field' {
            foreach ($name in $script:apiDocument.components.schemas.Keys) {
                $definition = $script:apiDocument.components.schemas[$name]
                $definition.Contains('example') | Should -BeTrue
                $schema = @{
                    '$ref' = "#/components/schemas/$name"
                    components = @{ schemas = $script:apiDocument.components.schemas }
                } | ConvertTo-Json -Depth 64
                $example = $definition.example | ConvertTo-Json -Depth 32
                Test-Json -Json $example -Schema $schema | Should -BeTrue
                $invalid = $example | ConvertFrom-Json -AsHashtable
                $invalid.Remove($definition.required[0])
                Test-Json -Json ($invalid | ConvertTo-Json -Depth 32) -Schema $schema -ErrorAction SilentlyContinue |
                    Should -BeFalse
            }
        }

        It 'passes the existing pinned Spectral OpenAPI and APIM rules without errors or warnings' {
            $tool = Get-ApimSpectralTool
            if ($null -eq $tool) {
                Set-ItResult -Skipped -Because 'Optional pinned offline Spectral toolchain is not installed.'
                return
            }
            $result = Invoke-ApimSpectral -Json $script:apiText -Tool $tool
            $result.succeeded | Should -BeTrue
            $result.errorCount | Should -Be 0
            $result.warningCount | Should -Be 0
        }
    }
}
