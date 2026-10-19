#Requires -Version 7.4

Set-StrictMode -Version Latest

function Test-ApimSmokeContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SubscriptionId
    )

    if ($null -eq $Context -or
        $null -eq $Context.PSObject.Properties['Subscription'] -or
        $null -eq $Context.PSObject.Properties['Tenant'] -or
        $null -eq $Context.Subscription -or
        $null -eq $Context.Tenant -or
        $null -eq $Context.Subscription.PSObject.Properties['Id'] -or
        $null -eq $Context.Tenant.PSObject.Properties['Id'] -or
        $Context.Subscription.Id -ne $SubscriptionId -or
        [string]::IsNullOrWhiteSpace([string] $Context.Tenant.Id)) {
        throw 'Active Azure context does not match the selected test subscription.'
    }
    return [string] $Context.Tenant.Id
}

function Get-ApimSmokeFailureCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $exception = $ErrorRecord.Exception
    if ($exception.Data['ApimArmFailure'] -is [bool] -and
        $exception.Data['ApimArmFailure']) {
        $status = $exception.Data['StatusCode']
        if ($status -is [int] -and $status -ge 100 -and $status -le 599) {
            return "ARM_HTTP_$status"
        }
        switch ($exception.Data['TransportKind']) {
            'AUTH' { return 'ARM_AUTH_ERROR' }
            'COMMAND' { return 'ARM_COMMAND_ERROR' }
            'NETWORK' { return 'ARM_NETWORK_ERROR' }
            'TIMEOUT' { return 'ARM_TIMEOUT' }
        }
        return 'ARM_NO_RESPONSE'
    }
    if ($exception -is [System.InvalidOperationException] -and
        $exception.Data['ApimPolicyXmlRejected'] -is [bool] -and
        $exception.Data['ApimPolicyXmlRejected']) {
        return 'POLICY_XML_REJECTED'
    }
    if ($exception -is [System.IO.IOException] -or
        $exception -is [System.UnauthorizedAccessException]) {
        return 'LOCAL_IO_ERROR'
    }
    return 'UNKNOWN_FAILURE'
}

function Get-ApimCollectorRegistry {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject]@{ Name = 'Service'; Function = 'Invoke-ApimServiceCollector'; Requires = @(); Throttled = $false }
        [pscustomobject]@{ Name = 'Apis'; Function = 'Invoke-ApimApiCatalogCollector'; Requires = @('Service'); Throttled = $true }
        [pscustomobject]@{ Name = 'Products'; Function = 'Invoke-ApimProductCollector'; Requires = @('Service'); Throttled = $true }
        [pscustomobject]@{ Name = 'Subscriptions'; Function = 'Invoke-ApimSubscriptionCollector'; Requires = @('Service'); Throttled = $false }
        [pscustomobject]@{ Name = 'SecurityAssets'; Function = 'Invoke-ApimSecurityAssetCollector'; Requires = @('Service'); Throttled = $false }
        [pscustomobject]@{ Name = 'Diagnostics'; Function = 'Invoke-ApimDiagnosticsCollector'; Requires = @('Service', 'Apis'); Throttled = $true }
        [pscustomobject]@{ Name = 'Policies'; Function = 'Invoke-ApimPolicyCollector'; Requires = @('Service', 'Apis', 'Products'); Throttled = $true }
        [pscustomobject]@{ Name = 'Network'; Function = 'Invoke-ApimNetworkCollector'; Requires = @('Service'); Throttled = $false }
        [pscustomobject]@{ Name = 'Identity'; Function = 'Invoke-ApimIdentityCollector'; Requires = @('Service'); Throttled = $false }
        [pscustomobject]@{ Name = 'Portal'; Function = 'Invoke-ApimPortalCollector'; Requires = @('Service'); Throttled = $false }
        [pscustomobject]@{ Name = 'OpenApi'; Function = 'Invoke-ApimOpenApiCollector'; Requires = @('Service', 'Apis'); Throttled = $true }
        [pscustomobject]@{ Name = 'Organization'; Function = 'Invoke-ApimOrganizationCollector'; Requires = @('Service'); Throttled = $false }
    )
}

function Invoke-ApimSmoke {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Config,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $EnvironmentName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TenantId,

        [ValidateRange(1, 64)]
        [int] $ThrottleLimit = 6,

        [AllowNull()]
        [scriptblock] $OnProgress
    )

    Test-ApimCountOnlyPrivacy -Config $Config
    $telemetryNames = @((Get-ApimTelemetryCollectorRegistry).Name)
    $checks = @(Get-ApimCollectorRegistry) + @(Get-ApimTelemetryCollectorRegistry)

    foreach ($check in $checks) {
        if ($null -eq (Get-Command -Name $check.Function `
                    -CommandType Function -ErrorAction SilentlyContinue)) {
            throw 'A registered smoke check is unavailable.'
        }
    }

    $runId = '{0}_{1}' -f (
        [datetimeoffset]::UtcNow.ToString('yyyy-MM-dd_HHmmss')
    ), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $run = New-ApimRun -Config $Config -EnvironmentName $EnvironmentName `
        -TenantId $TenantId -Operator 'LocalMaintainer' -RunId $runId -IncludeTelemetry
    $environment = Get-ApimEnvironmentConfig -Config $Config `
        -EnvironmentName $EnvironmentName
    Save-ApimRunSetting -RunPath $run.Path -Config $Config `
        -Environment $environment -IncludeObservedRoutes
    $statuses = [ordered]@{}
    $failureCodes = @{}

    for ($index = 0; $index -lt $checks.Count; $index++) {
        $check = $checks[$index]
        $unmet = @($check.Requires | Where-Object {
                $statuses[$_] -ne 'Completed'
            })
        if ($unmet.Count -gt 0) {
            Set-RunCollectorStatus -RunPath $run.Path -Name $check.Name `
                -Status Skipped
            Add-RunWarning -RunPath $run.Path `
                -Message "$($check.Name) smoke check skipped after a prerequisite failure."
            $statuses[$check.Name] = 'Skipped'
        }
        else {
            if ($null -ne $OnProgress) {
                $null = & $OnProgress ([pscustomobject]@{
                        Phase = 'Running'
                        Name = $check.Name
                        Index = $index + 1
                        Total = $checks.Count
                        Status = $null
                        FailureCode = $null
                    })
            }
            $arguments = @{
                RunPath = $run.Path
                Environment = $environment
            }
            if ($check.Throttled) {
                $arguments.ThrottleLimit = $ThrottleLimit
            }
            try {
                $null = & $check.Function @arguments
                $record = @((
                        Get-RunManifest -RunPath $run.Path
                    ).collectors | Where-Object { $_.name -eq $check.Name })
                if ($record.Count -ne 1 -or
                    ($record[0].status -cne 'Completed' -and
                        -not ($check.Name -cin $telemetryNames -and
                            $record[0].status -cin @('Partial', 'Skipped')))) {
                    throw 'Smoke collector did not report completion.'
                }
                $statuses[$check.Name] = $record[0].status
            }
            catch {
                $failureCodes[$check.Name] = Get-ApimSmokeFailureCode -ErrorRecord $_
                $record = @((
                        Get-RunManifest -RunPath $run.Path
                    ).collectors | Where-Object { $_.name -eq $check.Name })
                if ($record.Count -ne 1 -or
                    $record[0].status -notin @('Failed', 'Partial')) {
                    Set-RunCollectorStatus -RunPath $run.Path -Name $check.Name `
                        -Status Failed -Errors 1
                    Add-RunWarning -RunPath $run.Path `
                        -Message "$($check.Name) smoke check failed; see the restricted run log."
                    $statuses[$check.Name] = 'Failed'
                }
                else {
                    $statuses[$check.Name] = $record[0].status
                }
            }
        }
        if ($null -ne $OnProgress) {
            $null = & $OnProgress ([pscustomobject]@{
                    Phase = 'Finished'
                    Name = $check.Name
                    Index = $index + 1
                    Total = $checks.Count
                    Status = $statuses[$check.Name]
                    FailureCode = $failureCodes[$check.Name]
                })
        }
    }

    $status = if (@($checks | Where-Object {
                $statuses[$_.Name] -cne 'Completed' -and
                -not ($_.Name -cin @('LogAnalytics', 'Cost', 'LogicApps') -and
                    $statuses[$_.Name] -ceq 'Skipped')
            }).Count) {
        'Partial'
    }
    else {
        'Completed'
    }
    Set-RunStageStatus -RunPath $run.Path -Stage collect -Status $status
    Complete-ApimRun -RunPath $run.Path

    return [pscustomobject]@{
        RunId = $runId
        Status = $status
        Checks = @(
            foreach ($check in $checks) {
                [pscustomobject]@{
                    Name = $check.Name
                    Status = $statuses[$check.Name]
                    FailureCode = $failureCodes[$check.Name]
                }
            }
        )
    }
}
