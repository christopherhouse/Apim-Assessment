#Requires -Version 7.4
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$dependencies = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'DevDependencies.psd1')

foreach ($name in $dependencies.Keys | Sort-Object) {
    $version = $dependencies[$name]
    $installed = Get-Module -ListAvailable -Name $name |
        Where-Object Version -EQ ([version] $version)
    if (-not $installed) {
        Install-Module -Name $name -RequiredVersion $version -Repository PSGallery `
            -Scope CurrentUser -Force -ErrorAction Stop
    }
    if ($name -eq 'ImportExcel') {
        Import-Module -Name $name -RequiredVersion $version -Force `
            -ErrorAction Stop 3>$null
    }
    else {
        Import-Module -Name $name -RequiredVersion $version -Force `
            -ErrorAction Stop
    }
    Write-Verbose "Ready: $name $version"
}
