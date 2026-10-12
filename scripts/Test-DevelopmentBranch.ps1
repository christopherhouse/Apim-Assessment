#Requires -Version 7.4
[CmdletBinding()]
param(
    [string] $BranchName
)

$ErrorActionPreference = 'Stop'

if (-not $PSBoundParameters.ContainsKey('BranchName')) {
    $BranchName = git branch --show-current
    if ($LASTEXITCODE -ne 0) {
        throw 'Cannot determine the Git branch. Run this command inside the repository.'
    }
}

if ([string]::IsNullOrWhiteSpace($BranchName) -or
    $BranchName -cnotmatch '^(feature|chore|bugfix)/[a-z0-9][a-z0-9._/-]*$') {
    throw "Development branch '$BranchName' is not allowed. Use feature/<name>, chore/<name>, or bugfix/<name>."
}

Write-Verbose "Development branch accepted: $BranchName"
