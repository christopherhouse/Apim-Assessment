$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Parallel collector helper' {
    InModuleScope ApimAssessment {
        BeforeAll {
            $script:parallelProbePath = Join-Path $TestDrive 'ParallelProbe.psm1'
            Set-Content -LiteralPath $script:parallelProbePath -Value @'
function Invoke-ApimArm {
    param([string] $Uri, [string] $LogPath)
    Start-Sleep -Milliseconds 75
    if ($Uri -like '*failure*') {
        throw 'synthetic.private.identifier.invalid'
    }
    [pscustomobject]@{
        uri        = $Uri
        runspaceId = [runspace]::DefaultRunspace.Id
    }
}
'@
        }

        It 'honors the parallel throttle and preserves request order' {
            $requests = @(
                for ($index = 0; $index -lt 6; $index++) {
                    [pscustomobject]@{
                        Index = $index
                        Uri = "/synthetic/$index"
                        RelativePath = "raw/synthetic/$index.json"
                    }
                }
            )

            $results = @(Invoke-ApimParallelArmRequest -Requests $requests `
                    -ThrottleLimit 2 -LogPath (Join-Path $TestDrive 'run.log') `
                    -ModulePath $script:parallelProbePath)

            $results.Count | Should -Be 6
            ($results.index -join ',') | Should -Be '0,1,2,3,4,5'
            @($results.payload.runspaceId | Sort-Object -Unique).Count |
                Should -BeLessOrEqual 2
        }

        It 'does not expose parallel transport failure details' {
            $request = [pscustomobject]@{
                Index = 0
                Uri = '/synthetic/failure'
                RelativePath = 'raw/synthetic/failure.json'
            }

            {
                Invoke-ApimParallelArmRequest -Requests @($request) `
                    -ThrottleLimit 1 -LogPath (Join-Path $TestDrive 'run.log') `
                    -ModulePath $script:parallelProbePath
            } | Should -Throw '*parallel ARM requests failed*'
        }

        It 'encodes ARM and file path segments safely' {
            ConvertTo-ApimResourceSegment -Value 'api name' |
                Should -Be 'api%20name'
            ConvertTo-ApimResourceSegment -Value '..' |
                Should -Be '%2E%2E'
        }
    }
}
