#Requires -Version 7.4

Set-StrictMode -Version Latest

function Test-ApimDriftInput {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $InputObject)

    $schema = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) `
        'schemas/drift-inputs.schema.json'
    $json = ConvertTo-Json -InputObject $InputObject -Depth 100 -WarningAction Stop
    if (-not (Test-Json -Json $json -SchemaFile $schema -ErrorAction Stop)) {
        throw 'Drift input contract rejected.'
    }
    $labels = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($source in @($InputObject.current) + @($InputObject.sources)) {
        if (-not $labels.Add($source.environment)) { throw 'Duplicate drift environment.' }
        $keys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($policy in $source.policies) {
            if (-not $keys.Add("$($policy.scopeType)|$($policy.scope)") -or
                $source.scopeTypes -cnotcontains $policy.scopeType -or
                $policy.exists -ne ($null -ne $policy.sha256)) {
                throw 'Drift policy inventory rejected.'
            }
        }
    }
}

function Get-ApimDriftSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $RunPath)

    $context = Get-ApimRunSetting -RunPath $RunPath
    $complete = $true
    foreach ($name in @('Apis', 'Products', 'Policies')) {
        $records = @($context.Manifest.collectors | Where-Object name -CEQ $name)
        if ($records.Count -gt 1) { throw 'Duplicate drift collector.' }
        if ($records.Count -ne 1 -or $records[0].status -cne 'Completed') {
            $complete = $false
            continue
        }
        Test-ApimCollectorOutput -RunPath $RunPath -Environment $context.Environment `
            -Collector $records[0] -CompletePolicyInventory
    }
    $policies = @()
    $apiIds = @()
    if ($complete) {
        $index = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath 'policies/index.json'
        $policies = @($index.policies | Sort-Object scopeType, scope -CaseSensitive |
                ForEach-Object {
                    [ordered]@{ scopeType = $_.scopeType; scope = $_.scope
                        exists = $_.exists; sha256 = $_.sha256 }
                })
        $apis = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath 'raw/apis.json' -Collection
        $apiIds = @($apis.value | Where-Object { $_.properties.isCurrent } |
                ForEach-Object { $_.name } | Sort-Object -Unique -CaseSensitive)
    }
    return [ordered]@{
        kind = 'Environment'; environment = $context.Manifest.environment
        runId = $context.Manifest.runId; resourceId = $context.Manifest.apim.resourceId
        complete = $complete
        scopeTypes = @('Global', 'Product', 'Api', 'Operation', 'Fragment')
        apiIds = $apiIds; policies = $policies
    }
}

function Get-ApimDriftModel {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Inputs)

    Test-ApimDriftInput -InputObject $Inputs
    $current = $Inputs.current
    $rows = [Collections.Generic.List[object]]::new()
    foreach ($source in @($Inputs.sources | ForEach-Object { [pscustomobject] $_ } |
            Sort-Object environment -CaseSensitive)) {
        $before = @{}
        $after = @{}
        foreach ($policy in $source.policies) { $before.Add("$($policy.scopeType)|$($policy.scope)", $policy) }
        foreach ($policy in $current.policies) { $after.Add("$($policy.scopeType)|$($policy.scope)", $policy) }
        $keys = @(@($before.Keys) + @($after.Keys) | Sort-Object -Unique -CaseSensitive)
        if (-not $source.complete -or -not $current.complete) { $keys = @('Inventory') }
        foreach ($key in $keys) {
            $scopeType = $key.Split('|')[0]
            $covered = $source.complete -and $current.complete -and
                $source.scopeTypes -ccontains $scopeType -and
                $current.scopeTypes -ccontains $scopeType
            $a = if ($after.ContainsKey($key)) { $after[$key] } else { $null }
            $b = if ($before.ContainsKey($key)) { $before[$key] } else { $null }
            $presentA = if ($covered) { $null -ne $a -and $a.exists } else { $null }
            $presentB = if ($covered) { $null -ne $b -and $b.exists } else { $null }
            $hashA = if ($covered -and $presentA) { $a.sha256 } else { $null }
            $hashB = if ($covered -and $presentB) { $b.sha256 } else { $null }
            $change = if (-not $covered) { 'Unknown' }
            elseif ($presentA -eq $presentB) {
                if ($hashA -ceq $hashB) { 'All' } else { 'Differs' }
            }
            elseif (($current.environment -ieq 'Prod' -and $presentA) -or
                ($source.environment -ieq 'Prod' -and $presentB)) { 'ProdOnly' }
            elseif ($source.kind -ceq 'Git' -and $presentB) { 'SourceOnly' }
            else { 'Missing' }
            $rows.Add([pscustomobject][ordered]@{
                    category = $source.kind; key = $key
                    environmentA = $current.environment; environmentB = $source.environment
                    presentA = $presentA; presentB = $presentB; hashA = $hashA; hashB = $hashB
                    changeType = $change
                    severity = if ($change -cin @('All', 'Unknown')) { 'Info' }
                    elseif ($source.kind -ceq 'Git') { 'Medium' } else { 'Low' }
                    note = if ($covered) { 'RedactedPolicyComparison' }
                    elseif ($source.complete -and $current.complete) { 'SourceCoverageUnavailable' }
                    else { 'EvidenceIncomplete' }
                    modelStatus = if ($covered) { 'Complete' } else { 'Partial' }
                    missingInputs = @(if (-not $covered) {
                            if ($source.complete -and $current.complete) { 'sourceCoverage' }
                            else { 'comparisonEvidence' }
                        })
                })
        }
        if ($source.kind -ceq 'Environment' -and $source.complete -and $current.complete) {
            foreach ($apiId in @(@($current.apiIds) + @($source.apiIds) | Sort-Object -Unique -CaseSensitive)) {
                $presentA = $current.apiIds -ccontains $apiId
                $presentB = $source.apiIds -ccontains $apiId
                $change = if ($presentA -eq $presentB) { 'All' }
                elseif (($current.environment -ieq 'Prod' -and $presentA) -or
                    ($source.environment -ieq 'Prod' -and $presentB)) { 'ProdOnly' }
                else { 'Missing' }
                $rows.Add([pscustomobject][ordered]@{
                        category = 'Environment'; key = "Catalog|$apiId"
                        environmentA = $current.environment; environmentB = $source.environment
                        presentA = $presentA; presentB = $presentB; hashA = $null; hashB = $null
                        changeType = $change; severity = if ($change -ceq 'All') { 'Info' } else { 'Low' }
                        note = 'CatalogPresenceOnly'; modelStatus = 'Complete'; missingInputs = @()
                    })
            }
        }
    }
    return @($rows.ToArray() | Sort-Object category, environmentB, key -CaseSensitive)
}

function Get-ApimDriftGitSource {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $RunPath)

    $context = Get-ApimRunSetting -RunPath $RunPath
    $git = @($context.Manifest.collectors | Where-Object name -CEQ 'Git')
    if ($git.Count -gt 1) { throw 'Duplicate Git collector.' }
    if ($git.Count -eq 1 -and $git[0].status -ceq 'Completed') {
        $snapshot = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath 'git/policyHashes.json'
        Test-ApimGitPolicySnapshot -Snapshot $snapshot
        if ($git[0].items -ne @($snapshot.policies).Count) {
            throw 'Git policy inventory count rejected.'
        }
        return [ordered]@{
            kind = 'Git'; environment = 'Git'; runId = $null; resourceId = $null
            complete = $true; scopeTypes = @($snapshot.scopeTypes); apiIds = @()
            policies = @($snapshot.policies | ForEach-Object {
                    [ordered]@{ scopeType = $_.scopeType; scope = $_.scope
                        exists = $true; sha256 = $_.sha256 }
                })
        }
    }
}

function Save-ApimDriftModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [string[]] $CompareRuns = @(),
        [switch] $UseSavedInputs
    )

    $inputPath = Resolve-RunFilePath -RunPath $RunPath -RelativePath 'restricted/drift-inputs.json'
    Test-ConfigPathLink -Path $inputPath -Context 'Drift inputs'
    $context = Get-ApimRunSetting -RunPath $RunPath
    $gitSources = @(Get-ApimDriftGitSource -RunPath $RunPath)
    $inputs = $null
    if ($UseSavedInputs -and (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
        $inputs = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath 'restricted/drift-inputs.json'
        Test-ApimDriftInput -InputObject $inputs
        $priorBinding = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath 'restricted/drift-binding.json'
        if (@($priorBinding.PSObject.Properties.Name).Count -ne 3 -or
            $priorBinding.schemaVersion -cne '1.0' -or
            $priorBinding.modelSha256 -cnotmatch '\A[a-f0-9]{64}\z' -or
            $priorBinding.inputsSha256 -cne (Get-ApimLifecycleDigest -Value $inputs)) {
            throw 'Saved drift inputs were modified.'
        }
        $inputs.current = Get-ApimDriftSnapshot -RunPath $RunPath
        $inputs.sources = @(@($inputs.sources | Where-Object kind -CEQ Environment) +
            $gitSources | ForEach-Object { [pscustomobject] $_ } |
                Sort-Object environment -CaseSensitive)
    }
    else {
        $sources = [Collections.Generic.List[object]]::new()
        foreach ($source in $gitSources) { $sources.Add($source) }
        $resourceIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $null = $resourceIds.Add($context.Manifest.apim.resourceId)
        $runIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $null = $runIds.Add($context.Manifest.runId)
        if ($CompareRuns.Count -gt 15) { throw 'Too many comparison inputs.' }
        foreach ($path in $CompareRuns) {
            $other = Get-ApimRunSetting -RunPath $path
            if ($other.Manifest.customer -cne $context.Manifest.customer -or
                $other.Manifest.tenantId -ine $context.Manifest.tenantId -or
                -not $resourceIds.Add($other.Manifest.apim.resourceId) -or
                -not $runIds.Add($other.Manifest.runId)) {
                throw 'Drift comparison scope is incompatible.'
            }
            $sources.Add((Get-ApimDriftSnapshot -RunPath $path))
        }
        $inputs = [ordered]@{
            schemaVersion = '1.0'; current = Get-ApimDriftSnapshot -RunPath $RunPath
            sources = @($sources.ToArray() | ForEach-Object { [pscustomobject] $_ } |
                    Sort-Object environment -CaseSensitive)
        }
    }
    if (@($inputs.sources).Count -eq 0) {
        foreach ($relative in @('restricted/drift-inputs.json', 'restricted/drift-binding.json')) {
            $path = Resolve-RunFilePath -RunPath $RunPath -RelativePath $relative
            Test-ConfigPathLink -Path $path -Context 'Prior drift inputs'
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            }
        }
        return
    }
    Test-ApimDriftInput -InputObject $inputs
    $model = @(Get-ApimDriftModel -Inputs $inputs)
    Test-ApimModelJson -Name drift -Json (ConvertTo-Json -InputObject $model -Depth 100)
    $binding = [ordered]@{ schemaVersion = '1.0'
        inputsSha256 = Get-ApimLifecycleDigest -Value $inputs
        modelSha256 = Get-ApimLifecycleDigest -Value $model }
    $null = Write-RunFile -RunPath $RunPath -RelativePath 'restricted/drift-inputs.json' -InputObject $inputs
    $null = Write-RunFile -RunPath $RunPath -RelativePath 'restricted/drift-binding.json' -InputObject $binding
    return ,$model
}

function Test-ApimSavedDrift {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Models
    )

    $inputPath = Resolve-RunFilePath -RunPath $RunPath -RelativePath 'restricted/drift-inputs.json'
    $bindingPath = Resolve-RunFilePath -RunPath $RunPath -RelativePath 'restricted/drift-binding.json'
    Test-ConfigPathLink -Path $inputPath -Context 'Drift inputs'
    Test-ConfigPathLink -Path $bindingPath -Context 'Drift binding'
    if (-not $Models.Contains('drift') -and
        -not (Test-Path -LiteralPath $inputPath) -and
        -not (Test-Path -LiteralPath $bindingPath)) { return }
    if (-not $Models.Contains('drift')) { throw 'Requested drift model is unavailable.' }
    $inputs = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath 'restricted/drift-inputs.json'
    $binding = Read-ApimSmokeOutputJson -RunPath $RunPath -RelativePath 'restricted/drift-binding.json'
    Test-ApimDriftInput -InputObject $inputs
    if (@($binding.PSObject.Properties.Name).Count -ne 3 -or $binding.schemaVersion -cne '1.0' -or
        $binding.inputsSha256 -cne (Get-ApimLifecycleDigest -Value $inputs) -or
        $binding.modelSha256 -cne (Get-ApimLifecycleDigest -Value $Models.drift) -or
        $binding.modelSha256 -cne (Get-ApimLifecycleDigest -Value @(Get-ApimDriftModel -Inputs $inputs)) -or
        (Get-ApimLifecycleDigest -Value $inputs.current) -cne (
            Get-ApimLifecycleDigest -Value (Get-ApimDriftSnapshot -RunPath $RunPath)
        )) {
        throw 'Saved drift input binding rejected.'
    }
    if ((Get-ApimLifecycleDigest -Value @($inputs.sources | Where-Object kind -CEQ Git)) -cne
        (Get-ApimLifecycleDigest -Value @(Get-ApimDriftGitSource -RunPath $RunPath))) {
        throw 'Saved drift Git evidence binding rejected.'
    }
}
