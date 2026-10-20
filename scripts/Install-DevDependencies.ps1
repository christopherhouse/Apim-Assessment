#Requires -Version 7.4
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$dependencies = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'DevDependencies.psd1')

foreach ($name in $dependencies.Keys | Sort-Object) {
    $version = $dependencies[$name]
    if ($name -eq 'Bicep') {
        & (Join-Path $PSScriptRoot 'Install-Bicep.ps1')
        continue
    }
    if ($name -eq 'KustoLanguage') {
        $toolPath = Join-Path (Split-Path $PSScriptRoot -Parent) ".tools/kusto/$version"
        $assemblyPath = Join-Path $toolPath 'lib/net6.0/Kusto.Language.dll'
        if (-not (Test-Path -LiteralPath $assemblyPath -PathType Leaf)) {
            [IO.Directory]::CreateDirectory($toolPath) | Out-Null
            $packagePath = Join-Path $toolPath 'kusto.nupkg'
            try {
                Invoke-WebRequest -Uri (
                    "https://www.nuget.org/api/v2/package/Microsoft.Azure.Kusto.Language/$version"
                ) -OutFile $packagePath -ErrorAction Stop
                [IO.Compression.ZipFile]::ExtractToDirectory($packagePath, $toolPath, $true)
            }
            finally {
                if (Test-Path -LiteralPath $packagePath -PathType Leaf) {
                    Remove-Item -LiteralPath $packagePath -Force
                }
            }
        }
        if (-not (Test-Path -LiteralPath $assemblyPath -PathType Leaf)) {
            throw 'Pinned Kusto parser assembly is unavailable.'
        }
        continue
    }
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
