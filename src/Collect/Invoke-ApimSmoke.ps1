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
        [int] $ThrottleLimit = 6
    )

    $checks = @(
        [pscustomobject]@{
            Name = 'Service'
            Function = 'Invoke-ApimServiceCollector'
            Requires = @()
            Throttled = $false
        }
        [pscustomobject]@{
            Name = 'Apis'
            Function = 'Invoke-ApimApiCatalogCollector'
            Requires = @('Service')
            Throttled = $true
        }
        [pscustomobject]@{
            Name = 'Products'
            Function = 'Invoke-ApimProductCollector'
            Requires = @('Service')
            Throttled = $true
        }
        [pscustomobject]@{
            Name = 'Subscriptions'
            Function = 'Invoke-ApimSubscriptionCollector'
            Requires = @('Service')
            Throttled = $false
        }
        [pscustomobject]@{
            Name = 'Policies'
            Function = 'Invoke-ApimPolicyCollector'
            Requires = @('Service', 'Apis', 'Products')
            Throttled = $true
        }
        [pscustomobject]@{
            Name = 'Network'
            Function = 'Invoke-ApimNetworkCollector'
            Requires = @('Service')
            Throttled = $false
        }
    )

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
        -TenantId $TenantId -Operator 'LocalMaintainer' -RunId $runId
    $environment = Get-ApimEnvironmentConfig -Config $Config `
        -EnvironmentName $EnvironmentName
    $statuses = [ordered]@{}

    foreach ($check in $checks) {
        $unmet = @($check.Requires | Where-Object {
                $statuses[$_] -ne 'Completed'
            })
        if ($unmet.Count -gt 0) {
            Set-RunCollectorStatus -RunPath $run.Path -Name $check.Name `
                -Status Skipped
            Add-RunWarning -RunPath $run.Path `
                -Message "$($check.Name) smoke check skipped after a prerequisite failure."
            $statuses[$check.Name] = 'Skipped'
            continue
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
            if ($record.Count -ne 1 -or $record[0].status -ne 'Completed') {
                throw 'Smoke collector did not report completion.'
            }
            $statuses[$check.Name] = 'Completed'
        }
        catch {
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

    $status = if (@($statuses.Values | Where-Object { $_ -ne 'Completed' }).Count) {
        'Partial'
    }
    else {
        'Completed'
    }
    Set-RunStageStatus -RunPath $run.Path -Stage collect -Status $status
    Complete-ApimRun -RunPath $run.Path

    return [pscustomobject]@{
        Status = $status
        Checks = @(
            foreach ($check in $checks) {
                [pscustomobject]@{
                    Name = $check.Name
                    Status = $statuses[$check.Name]
                }
            }
        )
    }
}
