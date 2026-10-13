#Requires -Version 7.4

function Format-ApimSmokeConsoleLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Header', 'Preparing', 'Ready', 'Running',
            'Completed', 'Partial', 'Failed', 'Skipped', 'Summary')]
        [string] $State,

        [ValidatePattern('^[A-Za-z][A-Za-z0-9 ]{0,39}$')]
        [string] $Name = 'Collection smoke',

        [ValidateRange(0, 1000)]
        [int] $Index = 0,

        [ValidateRange(0, 1000)]
        [int] $Total = 0,

        [ValidatePattern('^(ARM_HTTP_[1-5][0-9]{2}|ARM_(NO_RESPONSE|AUTH_ERROR|COMMAND_ERROR|NETWORK_ERROR|TIMEOUT)|LOCAL_IO_ERROR|UNKNOWN_FAILURE)$')]
        [string] $FailureCode,

        [ValidateSet('Completed', 'Partial')]
        [string] $SummaryStatus,

        [switch] $Color
    )

    if ($State -in @('Running', 'Completed', 'Partial', 'Failed', 'Skipped') -and
        ($Total -lt 1 -or $Index -lt 1 -or $Index -gt $Total)) {
        throw 'Smoke check position was invalid.'
    }

    $symbols = if ($Color) {
        @{
            Header = [char]::ConvertFromUtf32(0x1F680)
            Preparing = [char]::ConvertFromUtf32(0x1F50D)
            Ready = [char]::ConvertFromUtf32(0x2705)
            Running = [char]::ConvertFromUtf32(0x1F504)
            Completed = [char]::ConvertFromUtf32(0x2705)
            Partial = ([string][char]0x26A0 + [char]0xFE0F)
            Failed = [char]::ConvertFromUtf32(0x274C)
            Skipped = ([string][char]0x23ED + [char]0xFE0F)
            Summary = [char]::ConvertFromUtf32(0x1F3C1)
        }
    }
    else {
        @{
            Header = '[SMOKE]'; Preparing = '[CHECK]'; Ready = '[READY]'
            Running = '[RUN]'; Completed = '[OK]'; Partial = '[PARTIAL]'
            Failed = '[FAIL]'; Skipped = '[SKIP]'; Summary = '[SMOKE]'
        }
    }

    $position = if ($Total -gt 0) {
        $filled = [int] [math]::Floor(10 * $Index / $Total)
        $fill = if ($Color) { [string][char]0x2588 } else { '#' }
        $empty = if ($Color) { [string][char]0x2591 } else { '-' }
        "[{0}{1}] {2}/{3}" -f ($fill * $filled), ($empty * (10 - $filled)),
            $Index, $Total
    }
    else {
        ''
    }
    $description = switch ($State) {
        'Header' { 'APIM COLLECTION SMOKE - read-only'; break }
        'Preparing' { "Checking $Name..."; break }
        'Ready' { "$Name ready."; break }
        'Running' { "$position $Name - collecting..."; break }
        'Skipped' { "$position $Name - Skipped (prerequisite not complete)."; break }
        'Summary' { "Collection smoke: $SummaryStatus"; break }
        default {
            $detail = if ($FailureCode) {
                $hint = switch -Regex ($FailureCode) {
                    '^ARM_HTTP_(401|403)$' { 'Check test-resource access locally.'; break }
                    '^ARM_HTTP_404$' { 'Verify the test target locally.'; break }
                    '^ARM_HTTP_(429|5[0-9]{2})$' {
                        'Retry later; inspect the restricted run locally.'; break
                    }
                    '^ARM_HTTP_' { 'Inspect the restricted run locally.'; break }
                    '^ARM_AUTH_ERROR$' { 'Check the local Az login and Reader access.'; break }
                    '^ARM_COMMAND_ERROR$' { 'Check the locally installed Az modules.'; break }
                    '^ARM_NETWORK_ERROR$' { 'Check local ARM connectivity.'; break }
                    '^ARM_TIMEOUT$' { 'Check connectivity and retry locally.'; break }
                    '^ARM_NO_RESPONSE$' { 'Inspect the restricted run locally.'; break }
                    '^LOCAL_IO_ERROR$' { 'Check restricted storage locally.'; break }
                    '^UNKNOWN_FAILURE$' { 'Inspect the restricted run locally.'; break }
                }
                " ($FailureCode) - $hint"
            }
            else {
                ''
            }
            "$position $Name - $State$detail"
        }
    }
    $line = "$($symbols[$State]) $description"
    if (-not $Color) {
        return $line
    }
    $shade = switch ($State) {
        'Header' { $PSStyle.Foreground.Magenta }
        'Preparing' { $PSStyle.Foreground.Cyan }
        'Ready' { $PSStyle.Foreground.Green }
        'Running' { $PSStyle.Foreground.Cyan }
        'Completed' { $PSStyle.Foreground.Green }
        'Partial' { $PSStyle.Foreground.Yellow }
        'Failed' { $PSStyle.Foreground.Red }
        'Skipped' { $PSStyle.Foreground.BrightBlack }
        'Summary' {
            if ($SummaryStatus -eq 'Completed') {
                $PSStyle.Foreground.Green
            }
            else {
                $PSStyle.Foreground.Yellow
            }
        }
    }
    return "$shade$line$($PSStyle.Reset)"
}

function Write-ApimSmokeConsoleLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Line,

        [switch] $Color
    )

    if (-not $Color) {
        [Console]::Out.WriteLine($Line)
        return
    }

    $previousEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        [Console]::Out.WriteLine($Line)
    }
    finally {
        [Console]::OutputEncoding = $previousEncoding
    }
}
