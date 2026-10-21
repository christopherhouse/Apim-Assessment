BeforeAll {
    $script:workerRepo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:workerSource = Join-Path $script:workerRepo 'infra\live-validation-lab'
    . (Join-Path $script:workerRepo 'scripts\lab\LabBootstrap.Core.ps1')
    . (Join-Path $script:workerRepo 'scripts\lab\LabFoundation.Core.ps1')
    . (Join-Path $script:workerRepo 'scripts\lab\LabWorker.Core.ps1')
    $script:workerSample = [IO.File]::ReadAllText((Join-Path $script:workerSource 'worker.sample.json'))
}

Describe 'Closed private VM worker parameter handoff' {
    BeforeEach { $script:workerConfig = Read-LabJson $script:workerSample }

    It 'returns only the bounded VM contract, not validation-only subnet data' {
        $result = Get-LabWorkerParameterSet $script:workerSample
        @($result.parameters.Keys) | Should -Be @('labId', 'location', 'vnetName', 'workerVmName',
            'workerPrivateIp', 'sshPublicKey', 'vmSize', 'ubuntuImageVersion', 'availabilityZone')
        $result.parameters.workerPrivateIp.value | Should -BeExactly '10.240.1.68'
        $result.parameters.availabilityZone.value | Should -Be 1
    }

    It 'rejects Azure-reserved, public, noncanonical or out-of-subnet address <Address>' -ForEach @(
        @{ Address = '10.240.1.64' }, @{ Address = '10.240.1.65' }, @{ Address = '10.240.1.66' },
        @{ Address = '10.240.1.67' }, @{ Address = '10.240.1.95' }, @{ Address = '10.240.1.96' },
        @{ Address = '192.0.2.10' }, @{ Address = '010.240.1.68' }
    ) {
        $script:workerConfig.workerPrivateIp = $Address
        { Get-LabWorkerParameterSet ($script:workerConfig | ConvertTo-Json -Depth 10) } | Should -Throw
    }

    It 'rejects public/undersized subnets and unbounded SKU, zone or image choices' {
        foreach ($mutation in @(
                { param($c) $c.workerCidr = '192.0.2.0/24'; $c.workerPrivateIp = '192.0.2.10' },
                { param($c) $c.workerCidr = '10.240.1.64/28' },
                { param($c) $c.vmSize = 'Standard_D64s_v5' },
                { param($c) $c.availabilityZone = 0 },
                { param($c) $c.ubuntuImageVersion = 'arbitrary/image' }
            )) {
            $config = Read-LabJson $script:workerSample
            & $mutation $config
            { Get-LabWorkerParameterSet ($config | ConvertTo-Json -Depth 10) } | Should -Throw
        }
    }

    It 'rejects unknown fields, case duplicates, missing fields and unsupported versions' {
        $script:workerConfig['clientSecret'] = 'SYNTHETIC_PRIVATE_CANARY'
        { Get-LabWorkerParameterSet ($script:workerConfig | ConvertTo-Json -Depth 10) } | Should -Throw
        { Get-LabWorkerParameterSet ($script:workerSample.Replace('"schemaVersion": "1.0"',
                    '"schemaVersion": "1.0", "SchemaVersion": "1.0"')) } | Should -Throw
        $script:workerConfig = Read-LabJson $script:workerSample
        $script:workerConfig.Remove('sshPublicKey')
        { Get-LabWorkerParameterSet ($script:workerConfig | ConvertTo-Json -Depth 10) } | Should -Throw
        { Get-LabWorkerParameterSet ($script:workerSample.Replace('"1.0"', '"2.0"')) } | Should -Throw
    }

    It 'rejects malformed and non-RSA provisioning keys instead of accepting base64 text' {
        foreach ($key in @('ssh-rsa ' + ('A' * 400), 'ssh-ed25519 ' + ('A' * 400),
                'ssh-rsa SYNTHETIC_PRIVATE_CANARY')) {
            $script:workerConfig.sshPublicKey = $key
            { Get-LabWorkerParameterSet ($script:workerConfig | ConvertTo-Json -Depth 10) } | Should -Throw
        }
    }

    It 'writes new private parameters exclusively and refuses overwrite or checkout paths' {
        $inputFile = Join-Path $TestDrive 'worker-config.json'
        $outputFile = Join-Path $TestDrive 'worker-parameters.json'
        [IO.File]::WriteAllText($inputFile, $script:workerSample)
        (New-LabWorkerParameterFile $inputFile $outputFile).state | Should -BeExactly 'ParametersReady'
        $before = [IO.File]::ReadAllText($outputFile)
        (New-LabWorkerParameterFile $inputFile $outputFile).state | Should -BeExactly 'Failed'
        [IO.File]::ReadAllText($outputFile) | Should -BeExactly $before
        (New-LabWorkerParameterFile $inputFile (Join-Path $script:workerRepo 'artifacts\refused-worker.json')).state |
            Should -BeExactly 'Failed'
        (New-LabWorkerParameterFile 'relative.json' $outputFile).state | Should -BeExactly 'Failed'
    }

    It 'does not write when ShouldProcess declines and leaks no private CLI data on any stream' {
        $inputFile = Join-Path $TestDrive 'worker-declined.json'
        $outputFile = Join-Path $TestDrive 'worker-not-created.json'
        [IO.File]::WriteAllText($inputFile, $script:workerSample)
        (New-LabWorkerParameterFile $inputFile $outputFile -WhatIf).code | Should -BeExactly 'LAB_WORKER_PARAMETERS_NOT_WRITTEN'
        (Test-Path -LiteralPath $outputFile) | Should -BeFalse
        [IO.File]::WriteAllText($inputFile, '{"SYNTHETIC_PRIVATE_CANARY":true}')
        $entry = Join-Path $script:workerRepo 'scripts\lab\New-LabWorkerParameters.ps1'
        $output = & pwsh -NoProfile -File $entry -ConfigPath $inputFile -OutputPath $outputFile *>&1
        $LASTEXITCODE | Should -Be 1
        ($output -join "`n").Trim() | Should -BeExactly 'LAB_WORKER_PARAMETERS_FAILED'
        (Test-Path -LiteralPath $outputFile) | Should -BeFalse
    }

    It 'validates the documented app/job samples and rejects arbitrary script or URL jobs' {
        $app = Join-Path $script:workerSource 'worker'
        Test-Json -Json ([IO.File]::ReadAllText((Join-Path $app 'config.sample.json'))) `
            -SchemaFile (Join-Path $app 'config.schema.json') | Should -BeTrue
        Test-Json -Json ([IO.File]::ReadAllText((Join-Path $app 'job.sample.json'))) `
            -SchemaFile (Join-Path $app 'job.schema.json') | Should -BeTrue
        foreach ($invalid in @(
                '{"schemaVersion":"1.0","kind":"readiness","url":"https://canary.invalid"}',
                '{"schemaVersion":"1.0","kind":"shell","command":"canary"}',
                '{"schemaVersion":"1.0","kind":"traffic","profile":"manufacturing","requestCount":1,"intervalMilliseconds":250}'
            )) {
            Test-Json -Json $invalid -SchemaFile (Join-Path $app 'job.schema.json') -ErrorAction SilentlyContinue |
                Should -BeFalse
        }
    }
}

Describe 'Evaluated private worker VM topology' {
    BeforeAll {
        $version = (Import-PowerShellDataFile (Join-Path $script:workerRepo 'scripts\DevDependencies.psd1')).Bicep
        $binary = if ($IsWindows) { 'bicep.exe' } else { 'bicep' }
        $bicep = Join-Path $script:workerRepo ".tools\bicep\$version\$binary"
        $work = Join-Path $TestDrive 'synthetic-worker-topology'
        New-Item -ItemType Directory -Path (Join-Path $work 'worker') -Force | Out-Null
        foreach ($name in @('worker.bicep', 'worker.synthetic.bicepparam', 'worker.sample.json', 'bicepconfig.json',
                'worker\cloud-init.yaml')) {
            Copy-Item -LiteralPath (Join-Path $script:workerSource $name) -Destination (Join-Path $work $name)
        }
        $compiled = Join-Path $work 'worker.json'
        $script:workerBuild = @(& $bicep build (Join-Path $work 'worker.bicep') --outfile $compiled 2>&1)
        $LASTEXITCODE | Should -Be 0
        $script:workerLint = @(& $bicep lint (Join-Path $work 'worker.bicep') 2>&1)
        $LASTEXITCODE | Should -Be 0
        $script:workerCompiledText = [IO.File]::ReadAllText($compiled)
        $snapshotOutput = @(& $bicep snapshot (Join-Path $work 'worker.synthetic.bicepparam') `
                --mode overwrite --tenant-id '11111111-1111-1111-1111-111111111111' `
                --subscription-id '22222222-2222-2222-2222-222222222222' --resource-group 'rg-synthetic-lab' `
                --location eastus2 --deployment-name synthetic-worker 2>&1)
        $LASTEXITCODE | Should -Be 0
        $snapshotOutput | Should -BeNullOrEmpty
        $snapshot = Read-LabJson ([IO.File]::ReadAllText((Join-Path $work 'worker.synthetic.snapshot.json')))
        $snapshot.diagnostics | Should -BeNullOrEmpty
        $script:workerPredicted = @($snapshot.predictedResources)
        $script:workerVm = @($script:workerPredicted | Where-Object type -CEQ 'Microsoft.Compute/virtualMachines')[0]
        $script:workerNic = @($script:workerPredicted | Where-Object type -CEQ 'Microsoft.Network/networkInterfaces')[0]
    }

    It 'builds/lints without diagnostics, key retrieval, public endpoint resources or outputs' {
        $script:workerBuild | Should -BeNullOrEmpty
        $script:workerLint | Should -BeNullOrEmpty
        $script:workerPredicted.Count | Should -Be 2
        @($script:workerPredicted | Where-Object type -Match 'publicIPAddresses|roleAssignments|extensions|runCommands').Count |
            Should -Be 0
        $script:workerCompiledText | Should -Not -Match '(?i)\blist(?:Keys|Secrets|Value|Credentials)\s*\('
        (Read-LabJson $script:workerCompiledText).ContainsKey('outputs') | Should -BeFalse
    }

    It 'uses only a static private worker-subnet NIC with no public IP or forwarding' {
        $ip = $script:workerNic.properties.ipConfigurations[0].properties
        $ip.privateIPAddress | Should -BeExactly '10.240.1.68'
        $ip.privateIPAllocationMethod | Should -BeExactly 'Static'
        $ip.subnet.id | Should -Match '/virtualNetworks/vnet-synthetic/subnets/worker$'
        $ip.publicIPAddress | Should -BeNullOrEmpty
        $script:workerNic.properties.enableIPForwarding | Should -BeFalse
    }

    It 'uses a small Trusted Launch Linux VM with only system identity and no password login' {
        $vm = $script:workerVm
        $vm.identity.type | Should -BeExactly 'SystemAssigned'
        $vm.properties.hardwareProfile.vmSize | Should -BeExactly 'Standard_B2ls_v2'
        $vm.properties.osProfile.linuxConfiguration.disablePasswordAuthentication | Should -BeTrue
        $vm.properties.osProfile.linuxConfiguration.provisionVMAgent | Should -BeTrue
        $vm.properties.securityProfile.securityType | Should -BeExactly 'TrustedLaunch'
        $vm.properties.securityProfile.uefiSettings.secureBootEnabled | Should -BeTrue
        $vm.properties.securityProfile.uefiSettings.vTpmEnabled | Should -BeTrue
        $vm.properties.storageProfile.osDisk.diskSizeGB | Should -Be 32
        $vm.properties.storageProfile.dataDisks | Should -BeNullOrEmpty
        $vm.properties.diagnosticsProfile.bootDiagnostics.enabled | Should -BeFalse
    }

    It 'masks guest SSH and waits for private binary/TLS/config delivery before service start' {
        $cloudInit = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($script:workerVm.properties.osProfile.customData))
        $cloudInit | Should -Match 'systemctl, mask, --now, ssh.service, ssh.socket'
        $cloudInit | Should -Match 'root, -g, apimlab, -m, "2750", /var/lib/apim-lab-worker\]'
        $cloudInit | Should -Not -Match '(?i)https?://|curl|wget|github.runner|systemctl, (?:start|enable)'
        $unit = [IO.File]::ReadAllText((Join-Path $script:workerSource 'worker\apim-lab-worker.service'))
        $unit | Should -Match 'User=apimlab'
        $unit | Should -Match 'NoNewPrivileges=true'
        $unit | Should -Match 'ExecStart=/opt/apim-lab-worker/LabWorker serve'
        $unit | Should -Not -Match 'SSH|token=|Authorization'
    }
}

Describe 'Real synthetic TLS, JWT, backend and bounded private job execution' {
    It 'builds/publishes pinned locked code and passes runtime acceptance without live dependencies' {
        $work = Join-Path $TestDrive 'synthetic-runtime-repository'
        $application = Join-Path $work 'infra\live-validation-lab\worker'
        $scenarios = Join-Path $work 'infra\live-validation-lab\scenarios'
        $harness = Join-Path $work 'tests\lab-worker'
        foreach ($directory in @($application, $scenarios, $harness)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        foreach ($name in @('LabWorker.csproj', 'Contracts.cs', 'Backend.cs', 'Jobs.cs', 'Program.cs',
                'global.json', 'NuGet.Config', 'packages.lock.json')) {
            Copy-Item -LiteralPath (Join-Path $script:workerSource "worker\$name") -Destination (Join-Path $application $name)
        }
        foreach ($name in @('e-commerce', 'manufacturing', 'plm', 'service-management', 'supply-chain')) {
            Copy-Item -LiteralPath (Join-Path $script:workerSource "scenarios\$name.openapi.json") -Destination $scenarios
        }
        foreach ($name in @('LabWorker.Tests.csproj', 'Program.cs', 'packages.lock.json')) {
            Copy-Item -LiteralPath (Join-Path $script:workerRepo "tests\lab-worker\$name") -Destination (Join-Path $harness $name)
        }
        $sdk = (Import-PowerShellDataFile (Join-Path $script:workerRepo 'scripts\DevDependencies.psd1')).DotNetSdk
        $executable = if ($IsWindows) { 'dotnet.exe' } else { 'dotnet' }
        $dotnet = Join-Path $script:workerRepo ".tools\dotnet\$sdk\$executable"
        if (-not (Test-Path -LiteralPath $dotnet -PathType Leaf)) {
            $dotnet = @(Get-Command dotnet -CommandType Application -ErrorAction Stop)[0].Source
        }
        $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
        $env:DOTNET_NOLOGO = '1'
        Push-Location $application
        try {
            $project = Join-Path $harness 'LabWorker.Tests.csproj'
            $restore = @(& $dotnet restore $project --configfile (Join-Path $application 'NuGet.Config') `
                    --locked-mode --verbosity quiet 2>&1)
            $LASTEXITCODE | Should -Be 0 -Because ($restore -join "`n")
            $build = @(& $dotnet build $project --no-restore --configuration Release --verbosity quiet 2>&1)
            $LASTEXITCODE | Should -Be 0 -Because ($build -join "`n")
            $output = @(& $dotnet (Join-Path $harness 'bin\Release\net10.0\LabWorker.Tests.dll') `
                    (Join-Path $TestDrive 'synthetic-private-inputs') 2>&1)
            $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
            $output[-1] | Should -Match '^LAB_WORKER_TESTS_PASSED:[1-9][0-9]+$'
            Set-Content -LiteralPath (Join-Path $application 'config.json') `
                -Value '{"privateCanary":"SYNTHETIC_PRIVATE_CANARY"}' -Encoding utf8NoBOM
            $publishPath = Join-Path $work 'publish'
            $publish = @(& $dotnet publish (Join-Path $application 'LabWorker.csproj') `
                    --configuration Release --runtime linux-x64 --self-contained true `
                    --output $publishPath -p:RestoreLockedMode=true --verbosity quiet 2>&1)
            $LASTEXITCODE | Should -Be 0 -Because ($publish -join "`n")
            (Test-Path -LiteralPath (Join-Path $publishPath 'LabWorker') -PathType Leaf) | Should -BeTrue
            $jsonFiles = @(Get-ChildItem -LiteralPath $publishPath -Recurse -Filter '*.json' -File |
                    ForEach-Object { [IO.Path]::GetRelativePath($publishPath, $_.FullName).Replace('\', '/') } |
                    Sort-Object)
            ($jsonFiles -join ',') | Should -Be (
                @('LabWorker.deps.json', 'LabWorker.runtimeconfig.json',
                    'scenarios/e-commerce.openapi.json', 'scenarios/manufacturing.openapi.json',
                    'scenarios/plm.openapi.json', 'scenarios/service-management.openapi.json',
                    'scenarios/supply-chain.openapi.json') -join ','
            )
        }
        finally { Pop-Location }
    }
}
