#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimEvidenceWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetimeoffset] $EndUtc,

        [Parameter(Mandatory)]
        [ValidateSet('Usage', 'Security', 'Metric', 'Cost', 'Ingestion')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [ValidateRange(1, 3650)]
        [int] $Length,

        [ValidateRange(1, 3650)]
        [Nullable[int]] $RetentionDays
    )

    if ($null -ne $RetentionDays -and $Kind -cin @('Metric', 'Cost')) {
        throw 'Retention capping is supported only for Log Analytics windows.'
    }
    $end = $EndUtc.ToUniversalTime()
    $requested = if ($Kind -ceq 'Cost') {
        [datetimeoffset]::new($end.Year, $end.Month, 1, 0, 0, 0,
            [timespan]::Zero).AddMonths(-$Length)
    }
    else {
        $end.AddDays(-$Length)
    }
    $start = $requested
    if ($null -ne $RetentionDays) {
        $retentionStart = $end.AddDays(-[int] $RetentionDays)
        if ($retentionStart -gt $start) { $start = $retentionStart }
    }
    return [pscustomobject][ordered]@{
        requestedStartUtc = $requested.ToString('O')
        startUtc = $start.ToString('O')
        endUtc = $end.ToString('O')
        retentionDays = $RetentionDays
        isCapped = $start -gt $requested
    }
}

    function Get-ApimLogQuery {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateSet('usageByApi', 'usageByRoute', 'usageMonthly', 'tls',
                'noSubscriptionCalls', 'laIngestion', 'schema')]
            [string] $Name,

            [Parameter(Mandatory)]
            [ValidateSet('ResourceSpecific', 'Legacy')]
            [string] $Schema,

            [Parameter(Mandatory)]
            [object] $Window,

            [Parameter(Mandatory)]
            [string] $ResourceId,

            [AllowEmptyCollection()]
            [string[]] $AppGwCidrs = @(),

            [AllowEmptyCollection()]
            [string[]] $InternalCidrs = @()
        )

        $suffix = if ($Schema -ceq 'Legacy' -and
            $Name -cnotin @('schema', 'laIngestion')) { '.azdiag.kql' } else { '.kql' }
        $path = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) (
            "queries/$Name$suffix"
        )
        $text = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        $table = if ($Schema -ceq 'ResourceSpecific') {
            'ApiManagementGatewayLogs'
        }
        else { 'AzureDiagnostics | where Category == "GatewayLogs"' }
        $replacements = [ordered]@{
            '__START__' = ([datetimeoffset] $Window.startUtc).UtcDateTime.ToString('O')
            '__END__' = ([datetimeoffset] $Window.endUtc).UtcDateTime.ToString('O')
            '__RESOURCE__' = ConvertTo-Json -InputObject $ResourceId -Compress
            '__APPGW__' = ConvertTo-Json -InputObject @($AppGwCidrs) -Compress
            '__INTERNAL__' = ConvertTo-Json -InputObject @($InternalCidrs) -Compress
            '__TABLE__' = $table
        }
        foreach ($token in $replacements.Keys) {
            $text = $text.Replace($token, $replacements[$token])
        }
        if ($text -match '__[A-Z]+__') { throw 'Log query contains an unbound parameter.' }
        return $text
    }

    function Invoke-ApimLogQuery {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string] $WorkspaceId,

            [Parameter(Mandatory)]
            [string] $Query
        )

        $response = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceId `
            -Query $Query -ErrorAction Stop
        $errorValue = Get-ApimDiagnosticProperty -InputObject $response `
            -Name Error -Context 'Log query response'
        if ($null -ne $errorValue) {
            throw 'Log query returned incomplete or invalid results.'
        }
        $results = Get-ApimDiagnosticProperty -InputObject $response `
            -Name Results -Context 'Log query response'
        if ($null -eq $results) { throw 'Log query results were unavailable.' }
        return @($results)
    }

    function ConvertTo-ApimTelemetryNumber {
        [CmdletBinding()]
        param(
            [AllowNull()]
            [object] $Value,

            [switch] $Nullable,

            [switch] $Integer,

            [double] $Minimum = 0
        )

        if ($null -eq $Value -or ($Value -is [string] -and $Value.Length -eq 0)) {
            if ($Nullable) { return $null }
            throw 'Required telemetry number is missing.'
        }
        $number = 0.0
        if ($Value -is [bool] -or -not [double]::TryParse(
                [string] $Value, [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture, [ref] $number
            ) -or [double]::IsNaN($number) -or [double]::IsInfinity($number) -or
            $number -lt $Minimum -or
            ($Integer -and ($number -gt 9007199254740991 -or [math]::Floor($number) -ne $number))) {
            throw 'Telemetry number is invalid.'
        }
        if ($Integer) { return [long] $number }
        return $number
    }

    function ConvertTo-ApimLogAggregate {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [object] $Row,

            [Parameter(Mandatory)]
            [ValidateSet('usageByApi', 'usageByRoute', 'usageMonthly', 'tls',
                'noSubscriptionCalls', 'laIngestion', 'schema')]
            [string] $Kind
        )

        $fields = switch ($Kind) {
            usageByApi { @('apiId', 'operationId', 'productId') }
            usageByRoute { @('apiId', 'operationId', 'productId', 'route') }
            usageMonthly { @('apiId', 'month') }
            tls { @('apiId', 'tlsVersion') }
            noSubscriptionCalls { @('apiId') }
            laIngestion { @('dataType', 'day') }
            schema { @() }
        }
        $result = [ordered]@{}
        foreach ($field in $fields) {
            $value = Get-ApimDiagnosticProperty -InputObject $Row -Name $field `
                -Context 'Log aggregate'
            if ($field -cin @('month', 'day')) {
                $date = [datetimeoffset]::MinValue
                if (-not [datetimeoffset]::TryParse([string] $value,
                        [Globalization.CultureInfo]::InvariantCulture,
                        [Globalization.DateTimeStyles]::AssumeUniversal, [ref] $date)) {
                    throw 'Log aggregate date is invalid.'
                }
                $result[$field] = $date.UtcDateTime.ToString('yyyy-MM-dd')
            }
            elseif ($field -ceq 'tlsVersion') {
                $result[$field] = if ([string] $value -cin @(
                        'TLSv1', 'TLSv1.0', 'TLSv1.1', 'TLSv1.2', 'TLSv1.3',
                        '1.0', '1.1', '1.2', '1.3')) { [string] $value } else { 'Unknown' }
            }
            elseif ($field -ceq 'route') {
                if ([string] $value -cnotin @('ViaAppGw', 'Internal', 'Other', 'Unknown')) {
                    throw 'Log route classification is invalid.'
                }
                $result[$field] = [string] $value
            }
            else {
                if ($value -isnot [string] -or $value.Length -gt 256 -or
                    $value -match '[\x00-\x1f\x7f]' -or
                    ($field -ceq 'dataType' -and $value -notmatch '^[A-Za-z][A-Za-z0-9_]{0,127}$')) {
                    throw 'Log aggregate identifier is invalid.'
                }
                $result[$field] = $value
            }
        }
        $measure = if ($Kind -ceq 'laIngestion') { 'gb' } else { 'calls' }
        $result[$measure] = ConvertTo-ApimTelemetryNumber -Value (
            Get-ApimDiagnosticProperty -InputObject $Row -Name $measure -Context 'Log aggregate'
        ) -Integer:($measure -ceq 'calls')
        if ($Kind -cin @('usageByApi', 'usageByRoute')) {
            foreach ($field in @('error4xx', 'error5xx', 'unauthorized', 'subscriptionCount')) {
                $result[$field] = ConvertTo-ApimTelemetryNumber -Integer -Value (
                    Get-ApimDiagnosticProperty -InputObject $Row -Name $field -Context 'Log aggregate'
                )
                if ($field -cne 'subscriptionCount' -and $result[$field] -gt $result.calls) {
                    throw 'Log aggregate count exceeds its request count.'
                }
            }
            foreach ($field in @('totalTimeP50', 'totalTimeP95', 'backendTimeP95')) {
                $result[$field] = ConvertTo-ApimTelemetryNumber -Nullable -Value (
                    Get-ApimDiagnosticProperty -InputObject $Row -Name $field -Context 'Log aggregate'
                )
            }
            if ($result.error4xx + $result.error5xx -gt $result.calls -or
                $result.unauthorized -gt $result.error4xx) {
                throw 'Log aggregate error counts are inconsistent.'
            }
            $last = Get-ApimDiagnosticProperty -InputObject $Row -Name lastCall -Context 'Log aggregate'
            if ([string]::IsNullOrWhiteSpace([string] $last)) {
                throw 'Log aggregate last-call date is missing.'
            }
            $result.lastCall = ([datetimeoffset] $last).UtcDateTime.ToString('O')
        }
        return [pscustomobject] $result
    }

    function Test-ApimLogAggregate {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [object[]] $Rows,

            [Parameter(Mandatory)]
            [object] $Window
        )

        $keys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $start = ([datetimeoffset] $Window.startUtc).UtcDateTime
        $end = ([datetimeoffset] $Window.endUtc).UtcDateTime
        foreach ($row in $Rows) {
            $identity = [ordered]@{}
            foreach ($field in @('apiId', 'operationId', 'productId', 'route', 'month', 'dataType', 'day', 'tlsVersion')) {
                if ($null -ne $row.PSObject.Properties[$field]) { $identity[$field] = $row.$field }
            }
            if (-not $keys.Add((ConvertTo-Json -InputObject $identity -Compress))) {
                throw 'Log aggregates contain duplicate keys.'
            }
            if ($null -ne $row.PSObject.Properties['lastCall']) {
                $date = ([datetimeoffset] $row.lastCall).UtcDateTime
                if ($date -lt $start -or $date -ge $end) {
                    throw 'Log aggregate last-call date is outside its evidence window.'
                }
            }
            foreach ($field in @('month', 'day')) {
                if ($null -eq $row.PSObject.Properties[$field]) { continue }
                $date = [datetime]::ParseExact($row.$field, 'yyyy-MM-dd',
                    [Globalization.CultureInfo]::InvariantCulture)
                $next = if ($field -ceq 'month') { $date.AddMonths(1) } else { $date.AddDays(1) }
                if ($date -ge $end -or $next -le $start -or
                    ($field -ceq 'month' -and $date.Day -ne 1)) {
                    throw 'Log aggregate period is outside its evidence window.'
                }
            }
        }
    }

    function Set-ApimEvidenceWindow {
        [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
        param(
            [Parameter(Mandatory)]
            [string] $RunPath,

            [Parameter(Mandatory)]
            [ValidateSet('Usage', 'Security', 'Metric', 'Cost', 'Ingestion')]
            [string] $Kind,

            [Parameter(Mandatory)]
            [string] $Target,

            [Parameter(Mandatory)]
            [object] $Window,

            [Parameter(Mandatory)]
            [ValidateSet('ResourceSpecific', 'Legacy', 'Mixed', 'None', 'NotApplicable')]
            [string] $Schema,

            [Parameter(Mandatory)]
            [ValidateSet('Completed', 'Partial', 'Failed', 'Skipped')]
            [string] $Status,

            [ValidateSet('None', 'Unconfigured', 'OptOut', 'Unavailable', 'Conflicting')]
            [string] $Reason = 'None'
        )

        if (-not $PSCmdlet.ShouldProcess($RunPath, "Record $Kind evidence coverage")) { return }
        $manifest = Get-RunManifest -RunPath $RunPath
        if ($manifest.schemaVersion -cne '1.2') {
            throw 'Telemetry evidence requires a version 1.2 run.'
        }
        $entry = [ordered]@{
            kind = $Kind; target = $Target; schema = $Schema
            requestedStartUtc = $Window.requestedStartUtc
            startUtc = $Window.startUtc; endUtc = $Window.endUtc
            retentionDays = $Window.retentionDays; isCapped = $Window.isCapped
            status = $Status; reason = $Reason
        }
        $manifest.evidenceWindows = @(
            @($manifest.evidenceWindows | Where-Object {
                    $_.kind -cne $Kind -or $_.target -ine $Target
                }) + @([pscustomobject] $entry) | Sort-Object kind, target
        )
        $null = Save-RunManifest -RunPath $RunPath -Manifest $manifest
    }
