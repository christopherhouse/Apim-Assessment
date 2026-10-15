#Requires -Version 7.4

Set-StrictMode -Version Latest

function New-AnalysisTestRun {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string] $Repository,
        [System.Collections.IDictionary] $Models
    )

    if (-not $PSCmdlet.ShouldProcess('Synthetic test run', 'Create saved inputs')) { return }
    $config = Import-PowerShellDataFile (Join-Path $Repository 'config/sample.psd1')
    $config.Output.Root = Join-Path $Root 'restricted'
    $config.Output.ModelSafeRoot = Join-Path $Root 'analysis'
    $run = New-ApimRun -Config $config -EnvironmentName Prod `
        -TenantId '00000000-0000-0000-0000-000000000002' -Operator Synthetic `
        -RunId synthetic-airlock -StartedUtc ([datetimeoffset] '2026-10-14T12:00:00Z')
    if ($null -eq $Models) {
        $Models = [ordered]@{}
        foreach ($name in @($script:ApimModelSchemaPaths.Keys | Where-Object { $_ -cnotin @('drift', 'portal', 'openApiQuality') })) {
            $file = if ($name -ceq 'apis') { 'apis.exposure.json' } else { "$name.json" }
            $Models[$name] = Get-Content -LiteralPath (
                Join-Path $Repository "tests/fixtures/synthetic-reference/model/$file"
            ) -Raw | ConvertFrom-Json -Depth 100 -NoEnumerate
        }
    }
    $null = Write-ApimModelSet -RunPath $run.Path -Models $Models
    $Models = Get-ApimModelSet -RunPath $run.Path
    $rules = @(Get-ApimRuleCatalog -CatalogPath (Join-Path $Repository 'rules'))
    $manifest = Get-RunManifest -RunPath $run.Path
    $findings = @(Invoke-ApimRuleEngine -Rules $rules -Models $Models `
            -Manifest $manifest -Config $config)
    $null = Write-ApimFindingSet -RunPath $run.Path -Findings $findings
    return [pscustomobject]@{ RunPath = $run.Path; Config = $config; Models = $Models }
}
