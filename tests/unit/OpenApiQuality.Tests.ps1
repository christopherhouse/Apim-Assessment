BeforeAll {
    $script:qualityRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    . (Join-Path $script:qualityRoot 'src/Model/OpenApiQuality.ps1')
    $script:qualityJson = '{"openapi":"3.0.3","info":{"title":"Synthetic API","version":"1.0","description":"Synthetic description","contact":{"name":"Synthetic maintainer"}},"servers":[{"url":"https://example.invalid"}],"tags":[{"name":"synthetic","description":"Synthetic tag"}],"paths":{"/items":{"get":{"operationId":"listItems","tags":["synthetic"],"description":"List synthetic items","responses":{"200":{"description":"Synthetic success"},"default":{"description":"Synthetic error"}}}}}}'
    function Get-QualityTestApi {
        return [pscustomobject]@{ apiId = 'synthetic-api'; apiType = 'http'; operationCount = 2; openApiScore = $null }
    }
    function Get-QualityTestOperation {
        return @(
            [pscustomobject]@{ apiId = 'synthetic-api'; operationId = 'one'; hasDescription = $true },
            [pscustomobject]@{ apiId = 'synthetic-api'; operationId = 'two'; hasDescription = $false }
        )
    }
}

Describe 'Pure OpenAPI quality builder and model contract' {
    BeforeEach {
        $script:qualityApi = Get-QualityTestApi
        $script:qualityOperations = Get-QualityTestOperation
        Mock Get-ApimSpectralTool { @{ version = '6.17.0'; executable = 'unused'; entryPoint = 'unused' } }
        Mock Invoke-ApimSpectral { @{ succeeded = $true; errorCount = 2; warningCount = 3 } }
    }

    It 'scores exactly once with fixed source/ruleset bindings and schema-valid closed fields' {
        $rows = @(Get-ApimOpenApiQuality -Api $qualityApi -Operations $qualityOperations -Json $qualityJson)
        $rows.Count | Should -Be 1
        $row = $rows[0]
        $row.status | Should -BeExactly 'Scored'
        $row.score | Should -Be 74
        $row.descriptionCoverage | Should -Be 50
        $row.describedOperationCount | Should -Be 1
        $row.modelStatus | Should -BeExactly 'Complete'
        $row.missingInputs.Count | Should -Be 0
        $row.rulesetSha256 | Should -BeExactly (Get-ApimOpenApiRulesetHash)
        $row.sourceSha256 | Should -BeExactly ([Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($qualityJson))).ToLowerInvariant())
        ConvertTo-Json -InputObject $rows -Depth 10 |
            Test-Json -SchemaFile (Join-Path $qualityRoot 'schemas/openApiQuality.schema.json') | Should -BeTrue
        $qualityApi.openApiScore = $row.score
        Test-ApimOpenApiQualityModel -Quality $rows -Apis @($qualityApi) -Operations $qualityOperations | Should -BeTrue
        Should -Invoke Invoke-ApimSpectral -Times 1 -Exactly
    }

    It 'clamps scoring at zero and permits explicitly zero penalties' {
        (Get-ApimOpenApiQuality $qualityApi $qualityOperations $qualityJson -ErrorPenalty 100 -WarningPenalty 100).score |
            Should -Be 0
        (Get-ApimOpenApiQuality $qualityApi $qualityOperations $qualityJson -ErrorPenalty 0 -WarningPenalty 0).score |
            Should -Be 100
        { Get-ApimOpenApiQuality $qualityApi $qualityOperations $qualityJson -ErrorPenalty 101 } | Should -Throw
        { Get-ApimOpenApiQuality $qualityApi $qualityOperations $qualityJson -WarningPenalty -1 } | Should -Throw
    }

    It 'retains qualified coverage with no installed tool, without claiming a pass' {
        Mock Get-ApimSpectralTool { $null }
        $row = Get-ApimOpenApiQuality $qualityApi $qualityOperations $qualityJson
        $row.status | Should -BeExactly 'ToolUnavailable'
        $row.score | Should -BeNullOrEmpty
        $row.errorCount | Should -BeNullOrEmpty
        $row.warningCount | Should -BeNullOrEmpty
        $row.descriptionCoverage | Should -Be 50
        $row.modelStatus | Should -BeExactly 'Partial'
        $row.missingInputs | Should -Be @('ToolUnavailable')
        Test-ApimOpenApiQualityModel @($row) @($qualityApi) $qualityOperations | Should -BeTrue
        Should -Invoke Invoke-ApimSpectral -Times 0
    }

    It 'distinguishes unavailable HTTP exports and unsupported API types' {
        $row = Get-ApimOpenApiQuality $qualityApi $qualityOperations -Json $null
        $row.status | Should -BeExactly 'ExportUnavailable'
        $row.sourceSha256 | Should -BeNullOrEmpty
        $qualityApi.apiType = 'graphql'
        $row = Get-ApimOpenApiQuality $qualityApi $qualityOperations -Json $null
        $row.status | Should -BeExactly 'UnsupportedApi'
        $row.descriptionCoverage | Should -Be 50
        Test-ApimOpenApiQualityModel @($row) @($qualityApi) $qualityOperations | Should -BeTrue
        Should -Invoke Get-ApimSpectralTool -Times 0
    }

    It 'does not promote partial or no-operation evidence to perfect coverage' {
        $row = Get-ApimOpenApiQuality $qualityApi @($qualityOperations[0]) $qualityJson
        $row.descriptionCoverage | Should -BeNullOrEmpty
        $row.missingInputs | Should -Be @('OperationsIncomplete')
        $qualityApi.openApiScore = $row.score
        Test-ApimOpenApiQualityModel @($row) @($qualityApi) @($qualityOperations[0]) | Should -BeTrue
        $qualityApi.operationCount = 0
        $row = Get-ApimOpenApiQuality $qualityApi @() $qualityJson
        $row.descriptionCoverage | Should -BeNullOrEmpty
        $row.describedOperationCount | Should -Be 0
        $row.missingInputs | Should -Be @('NoOperations')
        Test-ApimOpenApiQualityModel @($row) @($qualityApi) @() | Should -BeTrue
    }

    It 'records failed adapters and exceptions without persisting diagnostics' {
        Mock Invoke-ApimSpectral { throw 'synthetic-sensitive-diagnostic-path' }
        $row = Get-ApimOpenApiQuality $qualityApi $qualityOperations $qualityJson
        $row.status | Should -BeExactly 'ExecutionFailed'
        $row.score | Should -BeNullOrEmpty
        ($row | ConvertTo-Json -Depth 10) | Should -Not -Match 'synthetic-sensitive'
        Mock Invoke-ApimSpectral { @{ succeeded = $false; errorCount = $null; warningCount = $null } }
        (Get-ApimOpenApiQuality $qualityApi $qualityOperations $qualityJson).status | Should -BeExactly 'ExecutionFailed'
    }

    It 'rejects unsafe reference and alternate resolution entrypoints before tool discovery: <Member>' -TestCases @(
        @{ Member = '"$ref":"https://example.invalid/spec.json"' },
        @{ Member = '"$ref":"file:///synthetic.json"' },
        @{ Member = '"$ref":"../synthetic.json"' },
        @{ Member = '"$ref":"/synthetic.json"' },
        @{ Member = '"$dynamicRef":"https://example.invalid/schema"' },
        @{ Member = '"$id":"https://example.invalid/base"' },
        @{ Member = '"id":"https://example.invalid/base"' },
        @{ Member = '"$schema":"https://example.invalid/schema"' },
        @{ Member = '"$recursiveRef":"#"' },
        @{ Member = '"jsonSchemaDialect":"https://example.invalid/dialect"' },
        @{ Member = '"$ref":false' }
    ) {
        param($Member)
        $json = $qualityJson.Substring(0, $qualityJson.Length - 1) + ',"x-nested":{"items":[{' + $Member + '}]}}'
        $row = Get-ApimOpenApiQuality $qualityApi $qualityOperations $json
        $row.status | Should -BeExactly 'UnsupportedReference'
        $row.score | Should -BeNullOrEmpty
        Should -Invoke Get-ApimSpectralTool -Times 0
        Should -Invoke Invoke-ApimSpectral -Times 0
    }

    It 'allows same-document anchors without external resolution' {
        $json = $qualityJson.Substring(0, $qualityJson.Length - 1) + ',"components":{"schemas":{"Item":{"type":"object"},"List":{"$ref":"#/components/schemas/Item"}}}}'
        (Get-ApimOpenApiQuality $qualityApi $qualityOperations $json).status | Should -BeExactly 'Scored'
    }

    It 'fails invalid, duplicate, unsupported shape and bounded documents before process invocation' {
        foreach ($json in @('{', '[]', '{}', '{"openapi":"3.0.3","info":{},"paths":{},"info":{}}',
                '{"openapi":"3.0.3","info":{},"paths":{},"x":{"a":1,"\u0061":2}}',
                ('{"openapi":"3.0.3","info":{},"paths":{},"x":"' + ('x' * 8388608) + '"}'),
                ('{"openapi":"3.0.3","info":{},"paths":{},"x":' + ('[' * 66) + '0' + (']' * 66) + '}'))) {
            (Get-ApimOpenApiQuality $qualityApi $qualityOperations $json).status | Should -BeExactly 'ExecutionFailed'
        }
        Should -Invoke Invoke-ApimSpectral -Times 0
    }

    It 'validates Swagger 2.0 and OpenAPI 3.1 independently' {
        Test-ApimOpenApiDocument '{"swagger":"2.0","info":{},"paths":{}}' | Should -BeExactly 'Supported'
        Test-ApimOpenApiDocument '{"openapi":"3.1.0","info":{},"paths":{}}' | Should -BeExactly 'Supported'
        Test-ApimOpenApiDocument '{"openapi":"4.0.0","info":{},"paths":{}}' | Should -BeExactly 'ExecutionFailed'
    }

    It 'rejects duplicate operations and foreign operations' {
        { Get-ApimOpenApiQuality $qualityApi @($qualityOperations[0], $qualityOperations[0]) $qualityJson } | Should -Throw
        $qualityOperations[0].apiId = 'foreign'
        { Get-ApimOpenApiQuality $qualityApi $qualityOperations $qualityJson } | Should -Throw
    }

    It 'rejects semantic mutations of score, coverage, closed fields and reasons' {
        $row = Get-ApimOpenApiQuality $qualityApi $qualityOperations $qualityJson
        $qualityApi.openApiScore = $row.score
        foreach ($mutation in @(
                @{ score = 100 }, @{ errorCount = -1 }, @{ errorCount = 2.5 },
                @{ describedOperationCount = 2 }, @{ descriptionCoverage = 100 },
                @{ operationCount = 3 }, @{ missingInputs = @('NoOperations') },
                @{ modelStatus = 'Partial' }, @{ toolVersion = '0.0.0' }, @{ toolVersion = @('6.17.0') },
                @{ schemaVersion = @('1.0') }, @{ status = @('Scored') },
                @{ sourceSha256 = $null }, @{ rulesetSha256 = 'bad' },
                @{ errorPenalty = 101 }, @{ extra = 'rejected' }, @{ status = 'Unknown' }
            )) {
            $copy = $row | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
            foreach ($key in $mutation.Keys) { $copy[$key] = $mutation[$key] }
            Test-ApimOpenApiQualityModel @($copy) @($qualityApi) $qualityOperations | Should -BeFalse
        }
        Test-ApimOpenApiQualityModel @($row, $row) @($qualityApi) $qualityOperations | Should -BeFalse
        Test-ApimOpenApiQualityModel @($row) @() @() | Should -BeFalse
        $qualityApi.openApiScore = 99
        Test-ApimOpenApiQualityModel @($row) @($qualityApi) $qualityOperations | Should -BeFalse
    }
}

Describe 'Bounded Spectral process adapter' {
    It 'does not echo a process startup error' {
        $result = Invoke-ApimQualityProcess -Executable 'synthetic-nonexistent-executable' -Arguments @('--version')
        $result.succeeded | Should -BeFalse
        $result.stdout | Should -BeNullOrEmpty
    }

    It 'drains stdout and stderr without forwarding either stream' {
        $node = (Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($null -eq $node) { Set-ItResult -Skipped -Because 'Optional Node not installed.'; return }
        $result = Invoke-ApimQualityProcess -Executable $node.Source -Arguments @('-e',
            'process.stdout.write("synthetic-output"); process.stderr.write("synthetic-error")')
        $result.succeeded | Should -BeTrue
        $result.stdout | Should -BeExactly 'synthetic-output'
        $result.hasStderr | Should -BeTrue
    }

    It 'bounds stdout and stderr floods and times out a stalled process' {
        $node = (Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($null -eq $node) { Set-ItResult -Skipped -Because 'Optional Node not installed.'; return }
        foreach ($stream in @('stdout', 'stderr')) {
            $result = Invoke-ApimQualityProcess -Executable $node.Source -Arguments @('-e',
                "process.$stream.write('x'.repeat(100000));setInterval(()=>{},1000)") -MaxOutputBytes 1024 -TimeoutSeconds 3
            $result.succeeded | Should -BeFalse
            $result.stdout | Should -BeNullOrEmpty
        }
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-ApimQualityProcess -Executable $node.Source -Arguments @('-e', 'setInterval(()=>{},1000)') -TimeoutSeconds 1
        $result.succeeded | Should -BeFalse
        $timer.Elapsed.TotalSeconds | Should -BeLessThan 6
    }

    It 'accepts findings exit 1 but not malformed output, resolver failures or contradictory exits' {
        $tool = @{ version = '6.17.0'; executable = 'unused'; entryPoint = 'unused' }
        Mock Invoke-ApimQualityProcess {
            @{ succeeded = $true; exitCode = 1; stdout = '[{"code":"synthetic","severity":0},{"code":"synthetic","severity":1},{"code":"synthetic","severity":2}]'; hasStderr = $false }
        }
        $result = Invoke-ApimSpectral -Json $qualityJson -Tool $tool
        $result.succeeded | Should -BeTrue
        $result.errorCount | Should -Be 1
        $result.warningCount | Should -Be 1
        foreach ($case in @(
                @{ succeeded = $true; exitCode = 2; stdout = '[]'; hasStderr = $false },
                @{ succeeded = $true; exitCode = 1; stdout = '[]'; hasStderr = $false },
                @{ succeeded = $true; exitCode = 0; stdout = '{}'; hasStderr = $false },
                @{ succeeded = $true; exitCode = 0; stdout = 'invalid'; hasStderr = $false },
                @{ succeeded = $true; exitCode = 0; stdout = '[]'; hasStderr = $true },
                @{ succeeded = $true; exitCode = 1; stdout = '[{"code":"invalid-ref","severity":0}]'; hasStderr = $false },
                @{ succeeded = $true; exitCode = 1; stdout = '[{"code":"synthetic","severity":9}]'; hasStderr = $false }
            )) {
            $script:mockQualityProcess = $case
            Mock Invoke-ApimQualityProcess { $script:mockQualityProcess }
            (Invoke-ApimSpectral -Json $qualityJson -Tool $tool).succeeded | Should -BeFalse
        }
    }
}

Describe 'Installed pinned tool synthetic acceptance' -Tag 'OptionalTool' {
    It 'uses the installed real pinned CLI with synthetic JSON and fixed shipped rules' {
        $tool = Get-ApimSpectralTool
        if ($null -eq $tool) {
            if ($env:APIM_REQUIRE_SPECTRAL -eq '1') { throw 'Pinned optional tool acceptance requires installed supported Spectral.' }
            Set-ItResult -Skipped -Because 'Install scripts/Install-OptionalTools.ps1 for real optional tool acceptance.'
            return
        }
        $tool.version | Should -BeExactly '6.17.0'
        $api = Get-QualityTestApi
        $operations = Get-QualityTestOperation
        $good = Get-ApimOpenApiQuality $api $operations $qualityJson
        $good.status | Should -BeExactly 'Scored'
        $good.errorCount | Should -Be 0
        $good.warningCount | Should -Be 0
        $good.score | Should -Be 100
        $badJson = $qualityJson.Replace('"operationId":"listItems",', '"operationId":"Bad-name",').
            Replace('"version":"1.0",', '').
            Replace('"description":"List synthetic items",', '').
            Replace(',"default":{"description":"Synthetic error"}', '')
        $bad = Get-ApimOpenApiQuality $api $operations $badJson
        $bad.status | Should -BeExactly 'Scored'
        $bad.errorCount | Should -BeGreaterThan 0
        $bad.warningCount | Should -BeGreaterThan 0
        $bad.score | Should -Be ([Math]::Max(0, 100 - 10 * $bad.errorCount - 2 * $bad.warningCount))
        $api.openApiScore = $bad.score
        Test-ApimOpenApiQualityModel @($bad) @($api) $operations | Should -BeTrue
        $again = Get-ApimOpenApiQuality $api $operations $badJson
        ($again | ConvertTo-Json -Depth 10 -Compress) | Should -BeExactly ($bad | ConvertTo-Json -Depth 10 -Compress)
        $localJson = $qualityJson.Substring(0, $qualityJson.Length - 1) +
            ',"components":{"schemas":{"Item":{"type":"object"},"List":{"$ref":"#/components/schemas/Item"}}}}'
        (Get-ApimOpenApiQuality $api $operations $localJson).status | Should -BeExactly 'Scored'
        $brokenRef = $qualityJson.Substring(0, $qualityJson.Length - 1) +
            ',"components":{"schemas":{"List":{"$ref":"#/components/schemas/Missing"}}}}'
        (Get-ApimOpenApiQuality $api $operations $brokenRef).status | Should -BeExactly 'ExecutionFailed'
    }
}
