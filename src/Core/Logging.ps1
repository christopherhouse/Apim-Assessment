#Requires -Version 7.4

Set-StrictMode -Version Latest

function Protect-RunLogText {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [Parameter(Mandatory)]
        [string] $Value
    )

    $protected = $Value
    $patterns = @(
        @{
            Pattern = '(?i)\b(bearer\s+)[A-Za-z0-9._~+/=-]+'
            Replacement = '$1***REDACTED***'
        },
        @{
            Pattern = '(?i)\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\b'
            Replacement = '***REDACTED***'
        },
        @{
            Pattern = '(?i)([?&](?:sig|token|code|key|password|pwd|secret|api[-_]?key|subscription[-_]?key)=)[^&\s]+'
            Replacement = '$1***REDACTED***'
        },
        @{
            Pattern = @'
(?ix)\b((?:client[-_ ]?)?secret|password|pwd|api[-_ ]?key|subscription[-_ ]?key|accountkey|connectionstring)\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^,;\s]+)
'@.Trim()
            Replacement = '$1=***REDACTED***'
        }
    )

    foreach ($entry in $patterns) {
        $protected = [regex]::Replace(
            $protected,
            $entry.Pattern,
            $entry.Replacement
        )
    }

    return $protected
}

function Protect-RunLogUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    $queryIndex = $Value.IndexOf('?')
    $fragmentIndex = $Value.IndexOf('#')
    $cutIndex = @($queryIndex, $fragmentIndex) |
        Where-Object { $_ -ge 0 } |
        Measure-Object -Minimum |
        Select-Object -ExpandProperty Minimum
    if ($null -ne $cutIndex) {
        return "$($Value.Substring(0, $cutIndex))?***REDACTED***"
    }

    return Protect-RunLogText -Value $Value
}

function Write-RunLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidateSet('Debug', 'Info', 'Warning', 'Error')]
        [string] $Level,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Collector,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Message,

        [string] $Url
    )

    $directory = [System.IO.Path]::GetDirectoryName(
        [System.IO.Path]::GetFullPath($Path)
    )
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    }

    $record = [ordered]@{
        ts        = [datetime]::UtcNow.ToString('O')
        level     = $Level
        collector = Protect-RunLogText -Value $Collector
        message   = Protect-RunLogText -Value $Message
    }
    if ($PSBoundParameters.ContainsKey('Url') -and
        -not [string]::IsNullOrWhiteSpace($Url)) {
        $record.url = Protect-RunLogUrl -Value $Url
    }

    $json = $record | ConvertTo-Json -Compress -Depth 5
    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::AppendAllText(
        [System.IO.Path]::GetFullPath($Path),
        "$json$([Environment]::NewLine)",
        $encoding
    )
}

function Write-RunProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Activity,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Status,

        [ValidateRange(0, 100)]
        [int] $PercentComplete,

        [switch] $Completed
    )

    $progress = @{
        Activity = $Activity
        Status   = $Status
    }
    if ($Completed) {
        $progress.Completed = $true
    }
    elseif ($PSBoundParameters.ContainsKey('PercentComplete')) {
        $progress.PercentComplete = $PercentComplete
    }

    Write-Progress @progress
}
