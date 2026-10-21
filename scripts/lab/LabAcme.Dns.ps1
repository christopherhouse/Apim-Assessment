#Requires -Version 7.4
Set-StrictMode -Version Latest

function Get-LabAcmeServiceStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord] $Record)
    $exception = $Record.Exception
    for ($index = 0; $null -ne $exception -and $index -lt 8; $index++) {
        if ($exception.PSObject.Properties['Response'] -and $null -ne $exception.Response -and
            $exception.Response.PSObject.Properties['StatusCode']) {
            return [int]$exception.Response.StatusCode
        }
        if ($exception.PSObject.Properties['Status'] -and $exception.Status -is [int]) {
            return [int]$exception.Status
        }
        $exception = $exception.InnerException
    }
    return 0
}

function Get-LabAcmeDnsRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Session,
        [Parameter(Mandatory)][string] $Name
    )
    Assert-LabAcmeContext $Session
    try {
        return Get-AzDnsRecordSet -Name $Name -RecordType TXT -ZoneName $Session.config.challengeZoneName `
            -ResourceGroupName $Session.config.labResourceGroup -DefaultProfile $Session.context -ErrorAction Stop
    }
    catch {
        if ((Get-LabAcmeServiceStatus $_) -eq 404) { return $null }
        throw
    }
}

function Get-LabAcmeDnsJournal {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Config)
    $file = Get-LabAcmePrivateFile $Config 'dns-journal.json'
    if (-not (Test-Path -LiteralPath $file)) {
        return @{ schemaVersion = '1.0'; configSha256 = Get-LabObjectDigest $Config; entries = @() }
    }
    $journal = Read-LabAcmePrivateJson $file
    Assert-LabAcmeShape $journal @('schemaVersion', 'configSha256', 'entries')
    Assert-LabAcmeStringMember $journal @('schemaVersion', 'configSha256')
    Assert-LabCondition ($journal.schemaVersion -ceq '1.0' -and
        $journal.configSha256 -ceq (Get-LabObjectDigest $Config) -and $journal.entries -is [array] -and
        $journal.entries.Count -le 12)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $journal.entries) {
        Assert-LabAcmeShape $entry @('name', 'value')
        Assert-LabAcmeStringMember $entry @('name', 'value')
        Assert-LabCondition ($entry.name -cin @('gateway', 'apim', 'backend') -and
            $entry.value -cmatch '^[A-Za-z0-9_-]{43}$' -and $seen.Add("$($entry.name)|$($entry.value)"))
    }
    return $journal
}

function Save-LabAcmeDnsJournal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Config,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Journal
    )
    Write-LabAcmePrivateJson (Get-LabAcmePrivateFile $Config 'dns-journal.json') $Journal
}

function Invoke-LabAcmeDnsTxt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Session,
        [Parameter(Mandatory)][string] $Operation,
        [Parameter(Mandatory)][string] $RecordName,
        [Parameter(Mandatory)][string] $Value
    )
    Assert-LabCondition ($Operation -cin @('Add', 'Remove') -and $Value -cmatch '^[A-Za-z0-9_-]{43}$')
    $names = @{
        "gateway.$($Session.config.challengeZoneName)" = 'gateway'
        "apim.$($Session.config.challengeZoneName)" = 'apim'
        "backend.$($Session.config.challengeZoneName)" = 'backend'
    }
    $canonical = $RecordName.TrimEnd('.').ToLowerInvariant()
    Assert-LabCondition ($names.ContainsKey($canonical))
    $name = $names[$canonical]
    $journal = Get-LabAcmeDnsJournal $Session.config
    $owned = @($journal.entries | Where-Object { $_.name -ceq $name -and $_.value -ceq $Value })
    if ($Operation -ceq 'Remove' -and $owned.Count -eq 0) { return }
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        Assert-LabAcmeWriteWindow $Session
        try {
            $record = Get-LabAcmeDnsRecord $Session $name
            $present = $false
            if ($null -ne $record) {
                Assert-LabCondition ($record.Metadata['apimAssessmentLab'] -ceq $Session.config.labId -and
                    $record.Name -ceq $name -and $record.ZoneName -ieq $Session.config.challengeZoneName)
                foreach ($txt in $record.Records) {
                    if (($txt.Value -join '') -ceq $Value) { $present = $true }
                }
            }
            if ($Operation -ceq 'Add') {
                if ($present) { return }
                if ($owned.Count -eq 0) {
                    Assert-LabCondition ($journal.entries.Count -lt 12)
                    $journal.entries += @{ name = $name; value = $Value }
                    Save-LabAcmeDnsJournal $Session.config $journal
                    $owned = @(@{ name = $name; value = $Value })
                }
                Assert-LabAcmeWriteWindow $Session
                if ($null -eq $record) {
                    $dns = New-AzDnsRecordConfig -Value $Value -ErrorAction Stop
                    $null = New-AzDnsRecordSet -Name $name -RecordType TXT -ZoneName $Session.config.challengeZoneName `
                        -ResourceGroupName $Session.config.labResourceGroup -Ttl 60 -DnsRecords $dns `
                        -Metadata @{ apimAssessmentLab = $Session.config.labId } `
                        -DefaultProfile $Session.context -ErrorAction Stop
                }
                else {
                    $record = Add-AzDnsRecordConfig -RecordSet $record -Value $Value -ErrorAction Stop
                    $null = Set-AzDnsRecordSet -RecordSet $record -DefaultProfile $Session.context -ErrorAction Stop
                }
            }
            else {
                if ($present) {
                    Assert-LabAcmeWriteWindow $Session
                    $record = Remove-AzDnsRecordConfig -RecordSet $record -Value $Value -ErrorAction Stop
                    $null = Set-AzDnsRecordSet -RecordSet $record -DefaultProfile $Session.context -ErrorAction Stop
                }
                $journal.entries = @($journal.entries | Where-Object { $_.name -cne $name -or $_.value -cne $Value })
                Save-LabAcmeDnsJournal $Session.config $journal
            }
            return
        }
        catch {
            $status = Get-LabAcmeServiceStatus $_
            if ($attempt -eq 2 -or $status -notin @(409, 412, 429, 500, 502, 503, 504)) { throw }
            Start-Sleep -Seconds ($attempt + 1)
        }
    }
}

function Clear-LabAcmeDnsJournal {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Session)
    $journal = Get-LabAcmeDnsJournal $Session.config
    foreach ($entry in $journal.entries) {
        Invoke-LabAcmeDnsTxt $Session 'Remove' "$($entry.name).$($Session.config.challengeZoneName)" $entry.value
    }
}

function Register-LabAcmeDnsDispatch {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Session)
    $boundSession = $Session
    $source = $PSScriptRoot
    $dispatch = {
        param([string] $Operation, [string] $Name, [string] $Value, [string] $Nonce)
        . (Join-Path $source 'LabAcme.Core.ps1')
        . (Join-Path $source 'LabAcme.Transport.ps1')
        . (Join-Path $source 'LabAcme.Dns.ps1')
        Assert-LabCondition ($Nonce -ceq $boundSession.nonce)
        Invoke-LabAcmeDnsTxt $boundSession $Operation $Name $Value
    }.GetNewClosure()
    [AppDomain]::CurrentDomain.SetData('ApimAssessment.LabAcme.DnsDispatch', $dispatch)
}
