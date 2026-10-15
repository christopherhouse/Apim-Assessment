@{
    RootModule        = 'ApimAssessment.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'eb9e71f4-2e87-43e7-8cfa-f29d73198c73'
    Author            = 'APIM Assessment Toolkit contributors'
    Description       = 'Read-only Azure API Management assessment with offline deterministic analysis and reporting.'
    PowerShellVersion = '7.4'
    CompatiblePSEditions = @('Core')
    FunctionsToExport = @(
        'Invoke-ApimCollect', 'Invoke-ApimAnalyze', 'Invoke-ApimReport',
        'Invoke-ApimAssessment', 'Compare-ApimRun'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags = @('Azure', 'APIM', 'Assessment', 'ReadOnly')
        }
    }
}
