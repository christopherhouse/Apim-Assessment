#Requires -Version 7.4

Set-StrictMode -Version Latest

function Test-ApimSavedFindingReplay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunPath
    )

    $context = Get-ApimRunSetting -RunPath $RunPath
    if ($context.Manifest.stages.analyze -cne 'Completed') {
        throw 'Completed analysis is required.'
    }
    $models = Get-ApimModelSet -RunPath $RunPath
    $rules = @(Get-ApimRuleCatalog -CatalogPath $script:ApimReportRuleCatalogPath)
    $replayed = @(Invoke-ApimRuleEngine -Rules $rules -Models $models `
            -Manifest $context.Manifest -Config $context.Config)
    $saved = @(Get-ApimFindingSet -RunPath $RunPath)
    $replayMap = ConvertFrom-Json -InputObject (
        ConvertTo-Json -InputObject @{ findings = $replayed } -Depth 100
    ) -Depth 100 -AsHashtable
    $savedMap = ConvertFrom-Json -InputObject (
        ConvertTo-Json -InputObject @{ findings = $saved } -Depth 100
    ) -Depth 100 -AsHashtable
    if ((Get-ApimConfigDigest -Config $replayMap) -cne
        (Get-ApimConfigDigest -Config $savedMap)) {
        throw 'Saved findings do not match deterministic replay.'
    }
}

function Invoke-ApimReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RunFolder,

        [string] $PreviousReport
    )

    try {
        Test-ApimSavedFindingReplay -RunPath $RunFolder
        Set-RunStageStatus -RunPath $RunFolder -Stage report -Status InProgress
        $arguments = @{ RunPath = $RunFolder }
        if ($PSBoundParameters.ContainsKey('PreviousReport')) {
            $arguments.PreviousReport = $PreviousReport
        }
        $workbook = Export-ApimActionPlan @arguments
        $null = Export-ApimExecutiveHtml -RunPath $RunFolder -WorkbookPath $workbook
        $null = Write-RunFile -RunPath $RunFolder -RelativePath 'restricted/latest-reports.json' `
            -InputObject @{ schemaVersion = '1.0'
            workbook                      = [IO.Path]::GetRelativePath([IO.Path]::GetFullPath($RunFolder), $workbook)
            html                          = [IO.Path]::GetRelativePath([IO.Path]::GetFullPath($RunFolder), [IO.Path]::ChangeExtension($workbook, '.html'))
        }
        Set-RunStageStatus -RunPath $RunFolder -Stage report -Status Completed
        return [pscustomobject]@{ Status = 'Completed'; ExitCode = 0; ErrorCode = $null }
    }
    catch {
        $recorded = Set-ApimStageFailure -RunPath $RunFolder -Stage report
        return [pscustomobject]@{
            Status = 'Failed'; ExitCode = 4
            ErrorCode = if ($recorded) { 'REPORT_FAILED' } else { 'RUN_STATE_FAILED' }
        }
    }
}

function Get-ApimRenderedPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $RunPath)
    $path = Resolve-RunFilePath -RunPath $RunPath -RelativePath 'restricted/latest-reports.json'
    $json = [Text.UTF8Encoding]::new($false, $true).GetString((Read-ApimAnalysisSnapshot -Path $path))
    $record = ConvertFrom-ApimBrokerJson -Json $json
    if ($record.Count -ne 3 -or $record.schemaVersion -cne '1.0' -or
        $record.workbook -cnotmatch '^report[/\\][^/\\]+\.xlsx\z' -or
        $record.html -cnotmatch '^report[/\\][^/\\]+\.html\z' -or
        [IO.Path]::ChangeExtension($record.workbook, '.html') -cne $record.html) {
        throw 'REPORT_OUTPUT_REJECTED'
    }
    $result = @{}
    foreach ($kind in @('workbook', 'html')) {
        $file = Resolve-RunFilePath -RunPath $RunPath -RelativePath $record[$kind]
        Test-ConfigPathLink -Path $file -Context 'Local report'
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'REPORT_OUTPUT_REJECTED' }
        $result.Add($kind, $file)
    }
    return $result
}
