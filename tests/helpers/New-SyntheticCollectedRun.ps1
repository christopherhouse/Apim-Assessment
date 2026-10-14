function New-SyntheticCollectedRun {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $OutputRoot,
        [string] $RunId = 'synthetic-operational'
    )

    if (-not $PSCmdlet.ShouldProcess($OutputRoot, 'Create synthetic collected run')) {
        return
    }
    $config = Import-PowerShellDataFile (Join-Path $RepoRoot 'config/sample.psd1')
    $config.Output.Root = $OutputRoot
    $config.Environments[0].ApimName = 'apim-synthetic-prod'
    $config.Environments[0].AppGateways = @(
        @{ Name = 'agw-synthetic-prod'; ResourceGroup = 'rg-synthetic-prod' }
    )
    $config.Network.AppGwSubnetCidrs = @('10.20.1.0/24')
    $run = New-ApimRun -Config $config -EnvironmentName Prod `
        -TenantId '00000000-0000-0000-0000-000000000010' -Operator Synthetic `
        -RunId $RunId -StartedUtc '2026-10-14T12:00:00Z'
    $fixture = Join-Path $RepoRoot 'tests/fixtures/synthetic-reference'
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $fixture 'raw') `
            -Recurse -File -Filter '*.json') {
        $relative = [IO.Path]::GetRelativePath($fixture, $file.FullName)
        $null = Write-RunFile -RunPath $run.Path -RelativePath $relative `
            -InputObject (Get-Content -LiteralPath $file.FullName -Raw) -Format Text
    }
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $fixture 'policies') -File) {
        if ($file.Extension -notin @('.xml', '.json')) { continue }
        $relative = Join-Path 'policies' $file.Name
        $null = Write-RunFile -RunPath $run.Path -RelativePath $relative `
            -InputObject (Get-Content -LiteralPath $file.FullName -Raw) -Format Text
    }
    $diagnostics = (Read-ApimSmokeOutputJson -RunPath $run.Path `
            -RelativePath 'raw/loggers.json' -Collection).value.Count +
        (Read-ApimSmokeOutputJson -RunPath $run.Path `
            -RelativePath 'raw/diagnostics.json' -Collection).value.Count
    foreach ($api in @('orders-v1', 'status-v1')) {
        $diagnostics += (Read-ApimSmokeOutputJson -RunPath $run.Path `
                -RelativePath "raw/apiDiagnostics/$api.json" -Collection).value.Count
    }
    $counts = @{
        Service = 1; Apis = 2; Products = 2; Subscriptions = 6
        SecurityAssets = 7; Diagnostics = $diagnostics; Policies = 8; Network = 9
    }
    foreach ($name in $counts.Keys) {
        Set-RunCollectorStatus -RunPath $run.Path -Name $name -Status Completed `
            -Items $counts[$name]
    }
    Save-ApimRunSetting -RunPath $run.Path -Config $config `
        -Environment $config.Environments[0]
    $null = Write-RunFile -RunPath $run.Path `
        -RelativePath 'restricted/collection-context.json' -InputObject (
            [ordered]@{ schemaVersion = '1.0'; configSha256 = Get-ApimConfigDigest -Config $config }
        )
    Set-RunStageStatus -RunPath $run.Path -Stage collect -Status Completed
    Complete-ApimRun -RunPath $run.Path
    return [pscustomobject]@{ Run = $run; Config = $config }
}
