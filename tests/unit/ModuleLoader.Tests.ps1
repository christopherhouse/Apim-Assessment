BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:moduleRoot = Join-Path $TestDrive 'module'
    New-Item -ItemType Directory -Path $moduleRoot | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'ApimAssessment.psd1') -Destination $moduleRoot
    Copy-Item -LiteralPath (Join-Path $repoRoot 'ApimAssessment.psm1') -Destination $moduleRoot
    foreach ($area in @('Core', 'Collect', 'Model', 'Rules', 'Report')) {
        New-Item -ItemType Directory -Path (Join-Path $moduleRoot "src/$area") | Out-Null
    }
    $script:loaderManifestPath = Join-Path $moduleRoot 'ApimAssessment.psd1'
}

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Module source loading' {
    It 'imports the empty scaffold from outside the repository without Azure modules' {
        Push-Location $TestDrive
        try {
            { Import-Module -Name $script:loaderManifestPath -Force -ErrorAction Stop } | Should -Not -Throw
        }
        finally {
            Pop-Location
        }
    }

    It 'loads areas and files in stable dependency order while keeping helpers private' {
        Set-Content -LiteralPath (Join-Path $moduleRoot 'src/Core/z.ps1') `
            -Value '$script:LoadOrder += "Core/z"'
        Set-Content -LiteralPath (Join-Path $moduleRoot 'src/Core/a.ps1') -Value @'
$script:LoadOrder = @("Core/a")
function Get-SyntheticHelper { "synthetic" }
'@
        foreach ($area in @('Collect', 'Model', 'Rules', 'Report')) {
            Set-Content -LiteralPath (Join-Path $moduleRoot "src/$area/area.ps1") `
                -Value ('$script:LoadOrder += "' + $area + '"')
        }

        $module = Import-Module -Name $script:loaderManifestPath -Force -PassThru -ErrorAction Stop
        $order = & $module { $script:LoadOrder }
        ($order -join ',') | Should -Be 'Core/a,Core/z,Collect,Model,Rules,Report'
        (& $module { Get-SyntheticHelper }) | Should -Be 'synthetic'
        Get-Command -Name Get-SyntheticHelper -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty
    }
}
