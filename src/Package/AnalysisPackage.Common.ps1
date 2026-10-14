#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ApimAnalysisDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][byte[]] $Bytes)

    return [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($Bytes)
    ).ToLowerInvariant()
}

function Read-ApimAnalysisSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    Test-ConfigPathLink -Path $Path -Context 'Analysis artifact'
    $file = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($file.PSIsContainer -or $file.Length -gt 16MB -or $file.Length -eq 0) {
        throw 'ANALYSIS_INPUT_REJECTED'
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -gt 16MB -or $bytes.Length -eq 0) {
        throw 'ANALYSIS_INPUT_REJECTED'
    }
    return ,$bytes
}

function Resolve-ApimAnalysisRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    if (-not [System.IO.Path]::IsPathFullyQualified($Path) -or
        $Path -match '(?:^|[\\/])\.{1,2}(?:[\\/]|$)' -or
        $Path -match '(?:^|[\\/])[^\\/]*[. ](?:[\\/]|$)' -or
        $Path -match '[\x00-\x1f]' -or
        ($IsWindows -and ($Path -match '^[\\/]{2}' -or
                $Path.Substring(2).Contains(':') -or
                $Path -match '~[0-9]+(?:[.\\/]|$)' -or
                $Path -match '(?i)(?:^|[\\/])(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|[\\/]|$)'))) {
        throw 'ANALYSIS_PATH_REJECTED'
    }
    $resolved = Resolve-ConfigPath -Path $Path -Context 'Analysis root'
    if ($resolved -eq [System.IO.Path]::GetPathRoot($resolved)) {
        throw 'ANALYSIS_PATH_REJECTED'
    }
    Test-ConfigPathLink -Path $resolved -Context 'Analysis root'
    return $resolved
}

function ConvertTo-ApimAnalysisJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Value)

    return ConvertTo-Json -InputObject $Value -Depth 32 -Compress `
        -WarningAction Stop -ErrorAction Stop
}
