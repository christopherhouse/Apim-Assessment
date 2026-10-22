#Requires -Version 7.4
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$path = Join-Path (Split-Path $PSScriptRoot -Parent) 'infra/live-validation-lab/acme.dependencies.psd1'
$dependencies = Import-PowerShellDataFile $path
foreach ($name in $dependencies.Keys | Sort-Object) {
    if (-not (Get-Module -ListAvailable -Name $name |
            Where-Object Version -EQ ([version]$dependencies[$name]))) {
        Install-Module -Name $name -RequiredVersion $dependencies[$name] -Repository PSGallery `
            -Scope CurrentUser -AcceptLicense -ErrorAction Stop
    }
}
