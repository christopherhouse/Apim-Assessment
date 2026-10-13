$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Shared model schema gate' {
    InModuleScope ApimAssessment -Parameters @{ RepoRoot = $repoRoot } {
        param($RepoRoot)

        $script:schemaGateRepoRoot = $RepoRoot

        BeforeAll {
            function Get-SchemaGateFixture {
                $root = Join-Path $script:schemaGateRepoRoot (
                    'tests/fixtures/synthetic-reference/model'
                )
                $models = [ordered]@{}
                foreach ($name in @(
                        'apis', 'operations', 'policyMatrix',
                        'subscriptions', 'namedValues', 'backends',
                        'certificates', 'network', 'exposure'
                    )) {
                    $fileName = if ($name -eq 'apis') {
                        'apis.exposure.json'
                    }
                    else {
                        "$name.json"
                    }
                    $models[$name] = Get-Content -LiteralPath (
                        Join-Path $root $fileName
                    ) -Raw | ConvertFrom-Json -Depth 100 -NoEnumerate
                }
                return $models
            }
        }

        It 'round-trips the complete fixture with byte-identical repeated writes' {
            $models = Get-SchemaGateFixture
            $runPath = Join-Path $TestDrive 'complete'
            $paths = @(Write-ApimModelSet -RunPath $runPath -Models $models)
            $paths.Count | Should -Be 9
            $before = @($paths | ForEach-Object {
                    (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash
                })

            $loaded = Get-ApimModelSet -RunPath $runPath
            @($loaded.Keys) | Should -Be @($models.Keys)
            foreach ($name in $models.Keys) {
                (ConvertTo-Json -InputObject $loaded[$name] -Depth 100) |
                    Should -Be (
                        ConvertTo-Json -InputObject $models[$name] -Depth 100
                    )
            }
            $loaded.network.directPublic | Should -BeFalse
            $loaded.subscriptions[0].calls90d | Should -BeNullOrEmpty
            $loaded.subscriptions[0].missingInputs | Should -Contain 'usage'

            $null = Write-ApimModelSet -RunPath $runPath -Models $loaded
            @($paths | ForEach-Object {
                    (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash
                }) | Should -Be $before
        }

        It 'preserves empty and singleton arrays rather than unwrapping them' {
            $models = Get-SchemaGateFixture
            $models.apis = @($models.apis[0])
            $models.operations = @()
            $models.policyMatrix = @()
            $models.subscriptions = @()
            $models.namedValues = @()
            $models.backends = @()
            $models.certificates = @()
            $models.exposure = @()
            $runPath = Join-Path $TestDrive 'array-shapes'
            $null = Write-ApimModelSet -RunPath $runPath -Models $models

            $loaded = Get-ApimModelSet -RunPath $runPath
            $loaded.apis -is [array] | Should -BeTrue
            $loaded.apis.Count | Should -Be 1
            foreach ($name in @(
                    'operations', 'policyMatrix', 'subscriptions',
                    'namedValues', 'backends', 'certificates', 'exposure'
                )) {
                $loaded[$name] -is [array] | Should -BeTrue
                $loaded[$name].Count | Should -Be 0
            }
            $loaded.network -is [array] | Should -BeFalse
        }

        It 'rejects unknown fields in <Name> before creating any model output' `
            -TestCases @(
                @{ Name = 'apis' }
                @{ Name = 'operations' }
                @{ Name = 'policyMatrix' }
                @{ Name = 'subscriptions' }
                @{ Name = 'namedValues' }
                @{ Name = 'backends' }
                @{ Name = 'certificates' }
                @{ Name = 'network' }
                @{ Name = 'exposure' }
            ) {
            param($Name)

            $models = Get-SchemaGateFixture
            $record = if ($Name -eq 'network') {
                $models[$Name]
            }
            else {
                $models[$Name][0]
            }
            $record | Add-Member -NotePropertyName unexpected `
                -NotePropertyValue 'synthetic-private-canary'
            $runPath = Join-Path $TestDrive "unknown-field-$Name"

            {
                Write-ApimModelSet -RunPath $runPath -Models $models
            } | Should -Throw "Model '$Name' failed schema validation."
            Test-Path -LiteralPath $runPath | Should -BeFalse
        }

        It 'rejects the wrong top-level shape for <Name>' -TestCases @(
            @{ Name = 'apis' }
            @{ Name = 'operations' }
            @{ Name = 'policyMatrix' }
            @{ Name = 'subscriptions' }
            @{ Name = 'namedValues' }
            @{ Name = 'backends' }
            @{ Name = 'certificates' }
            @{ Name = 'network' }
            @{ Name = 'exposure' }
        ) {
            param($Name)

            $models = Get-SchemaGateFixture
            if ($Name -eq 'network') {
                $models[$Name] = @($models[$Name])
            }
            else {
                $models[$Name] = $models[$Name][0]
            }
            $runPath = Join-Path $TestDrive "wrong-shape-$Name"
            {
                Write-ApimModelSet -RunPath $runPath -Models $models
            } | Should -Throw "Model '$Name' failed schema validation."
            Test-Path -LiteralPath $runPath | Should -BeFalse
        }

        It 'rejects missing required fields and invalid field types' -TestCases @(
            @{ Kind = 'missing' }
            @{ Kind = 'type' }
            @{ Kind = 'null' }
        ) {
            param($Kind)

            $models = Get-SchemaGateFixture
            switch ($Kind) {
                missing { $models.operations[0].PSObject.Properties.Remove('method') }
                type { $models.operations[0].hasDescription = 'not-a-boolean' }
                null { $models.operations = $null }
            }
            {
                Write-ApimModelSet -RunPath (
                    Join-Path $TestDrive "invalid-field-$Kind"
                ) -Models $models
            } | Should -Throw "Model 'operations' failed schema validation."
        }

        It 'leaves every existing file unchanged when the final model is invalid' {
            $models = Get-SchemaGateFixture
            $runPath = Join-Path $TestDrive 'existing-models'
            $paths = @(Write-ApimModelSet -RunPath $runPath -Models $models)
            $before = @($paths | ForEach-Object {
                    (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash
                })
            $models.exposure[0].confidence = 'unsupported'

            {
                Write-ApimModelSet -RunPath $runPath -Models $models
            } | Should -Throw "Model 'exposure' failed schema validation."
            @($paths | ForEach-Object {
                    (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash
                }) | Should -Be $before
        }

        It 'refuses empty sets and unsupported names before writing' -TestCases @(
            @{ Models = [ordered]@{} }
            @{ Models = [ordered]@{ apis = @(); '../outside' = @() } }
            @{ Models = [ordered]@{ usage = @() } }
            @{ Models = [ordered]@{ Apis = @() } }
        ) {
            param($Models)

            $script:schemaGateInvalidModels = $Models
            Mock Write-RunFile { throw 'Persistence must not be reached.' }
            {
                Write-ApimModelSet -RunPath $TestDrive `
                    -Models $script:schemaGateInvalidModels
            } | Should -Throw
            Should -Invoke Write-RunFile -Times 0 -Exactly
        }

        It 'persists the validated snapshots even if input objects later mutate' {
            $script:schemaGateMutableModels = Get-SchemaGateFixture
            $script:schemaGateSnapshots = @{}
            $expected = ConvertTo-Json `
                -InputObject $script:schemaGateMutableModels.exposure -Depth 100
            Mock Write-RunFile {
                $script:schemaGateSnapshots[$RelativePath] = $InputObject
                $script:schemaGateMutableModels.exposure[0].confidence = 'unsupported'
                return Join-Path $RunPath $RelativePath
            }

            $null = Write-ApimModelSet -RunPath $TestDrive `
                -Models $script:schemaGateMutableModels

            $script:schemaGateSnapshots[(Join-Path 'model' 'exposure.json')] |
                Should -Be $expected
            Should -Invoke Write-RunFile -Times 9 -Exactly `
                -ParameterFilter { $Format -eq 'Text' }
        }

        It 'fails closed if a schema is missing or the validator throws' -TestCases @(
            @{ Kind = 'missing-schema' }
            @{ Kind = 'validator-error' }
        ) {
            param($Kind)

            $models = Get-SchemaGateFixture
            $script:schemaGateOriginalSchema = $script:ApimModelSchemaPaths.exposure
            Mock Write-RunFile { throw 'Persistence must not be reached.' }
            if ($Kind -eq 'missing-schema') {
                $script:ApimModelSchemaPaths.exposure = Join-Path $TestDrive (
                    'missing.schema.json'
                )
                $expectedMessage = "Model schema 'exposure' was unavailable."
            }
            else {
                Mock Test-Json { throw 'synthetic-private-canary' }
                $expectedMessage = "Model 'apis' failed schema validation."
            }
            try {
                {
                    Write-ApimModelSet -RunPath $TestDrive -Models $models
                } | Should -Throw -ExpectedMessage $expectedMessage
                Should -Invoke Write-RunFile -Times 0 -Exactly
            }
            finally {
                $script:ApimModelSchemaPaths.exposure = $script:schemaGateOriginalSchema
            }
        }

        It 'checks every destination for links before writing any output' {
            $models = Get-SchemaGateFixture
            Mock Test-ConfigPathLink {
                throw 'Synthetic linked model path.'
            } -ParameterFilter { $Path -like '*exposure.json' }
            Mock Write-RunFile { throw 'Persistence must not be reached.' }

            {
                Write-ApimModelSet -RunPath $TestDrive -Models $models
            } | Should -Throw 'Synthetic linked model path.'
            Should -Invoke Write-RunFile -Times 0 -Exactly
        }

        It 'returns no models if a required saved file is missing' {
            $models = Get-SchemaGateFixture
            $models.Remove('exposure')
            $runPath = Join-Path $TestDrive 'missing-saved-model'
            $null = Write-ApimModelSet -RunPath $runPath -Models $models
            $output = [System.Collections.Generic.List[object]]::new()

            {
                Get-ApimModelSet -RunPath $runPath |
                    ForEach-Object { $output.Add($_) }
            } | Should -Throw "Required model 'exposure' was unavailable."
            $output.Count | Should -Be 0
        }

        It 'returns no models if the final saved file is invalid' -TestCases @(
            @{ Json = '{broken' }
            @{ Json = '{}' }
            @{ Json = 'null' }
            @{ Json = '' }
        ) {
            param($Json)

            $runPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $null = Write-ApimModelSet -RunPath $runPath `
                -Models (Get-SchemaGateFixture)
            $null = Write-RunFile -RunPath $runPath `
                -RelativePath (Join-Path 'model' 'exposure.json') `
                -InputObject $Json -Format Text
            $output = [System.Collections.Generic.List[object]]::new()

            {
                Get-ApimModelSet -RunPath $runPath |
                    ForEach-Object { $output.Add($_) }
            } | Should -Throw "Model 'exposure' failed schema validation."
            $output.Count | Should -Be 0
        }

        It 'loads only registered models and never includes other run artifacts' {
            $runPath = Join-Path $TestDrive 'allowlisted-load'
            $null = Write-ApimModelSet -RunPath $runPath `
                -Models (Get-SchemaGateFixture)
            $null = Write-RunFile -RunPath $runPath `
                -RelativePath (Join-Path 'model' 'unregistered.json') `
                -InputObject @{ unexpected = 'synthetic-private-canary' }

            $loaded = Get-ApimModelSet -RunPath $runPath
            $loaded.Count | Should -Be 9
            $loaded.Contains('unregistered') | Should -BeFalse
        }
    }
}
