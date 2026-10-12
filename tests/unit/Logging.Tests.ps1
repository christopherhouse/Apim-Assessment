BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:module = Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') `
        -Force -PassThru
}

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Run logging' {
    It 'writes one JSON object per line with the required fields' {
        $path = Join-Path $TestDrive 'logs/run.log'

        & $script:module {
            param($LogPath)
            Write-RunLog -Path $LogPath -Level Info -Collector Config `
                -Message 'Configuration loaded.'
        } $path

        $lines = @(Get-Content -LiteralPath $path)
        $lines.Count | Should -Be 1
        $record = $lines[0] | ConvertFrom-Json
        $record.ts | Should -Not -BeNullOrEmpty
        $record.level | Should -Be 'Info'
        $record.collector | Should -Be 'Config'
        $record.message | Should -Be 'Configuration loaded.'
    }

    It 'appends records without corrupting existing JSON lines' {
        $path = Join-Path $TestDrive 'append.log'

        & $script:module {
            param($LogPath)
            Write-RunLog -Path $LogPath -Level Info -Collector One -Message 'first'
            Write-RunLog -Path $LogPath -Level Warning -Collector Two -Message 'second'
        } $path

        $records = @(Get-Content -LiteralPath $path | ForEach-Object {
                $_ | ConvertFrom-Json
            })
        $records.Count | Should -Be 2
        $records[0].message | Should -Be 'first'
        $records[1].message | Should -Be 'second'
    }

    It 'redacts planted credentials from messages and URLs' {
        $path = Join-Path $TestDrive 'redacted.log'
        $jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signaturevalue'
        $message = "Authorization: Bearer bearer-value password=hunter2 token $jwt"
        $url = 'https://example.invalid/path?sig=signature-value&safe=true'

        & $script:module {
            param($LogPath, $LogMessage, $LogUrl)
            Write-RunLog -Path $LogPath -Level Error -Collector ARM `
                -Message $LogMessage -Url $LogUrl
        } $path $message $url

        $content = Get-Content -LiteralPath $path -Raw
        foreach ($secret in @(
                'bearer-value',
                'hunter2',
                $jwt,
                'signature-value',
                'safe=true'
            )) {
            $content | Should -Not -Match ([regex]::Escape($secret))
        }
        $content | Should -Match '\*\*\*REDACTED\*\*\*'
        { $content | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'escapes multiline messages into a single physical line' {
        $path = Join-Path $TestDrive 'multiline.log'

        & $script:module {
            param($LogPath)
            Write-RunLog -Path $LogPath -Level Info -Collector Test `
                -Message "first`nsecond"
        } $path

        @(Get-Content -LiteralPath $path).Count | Should -Be 1
        (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).message |
            Should -Be "first`nsecond"
    }

    It 'uses Write-Progress without writing host output' {
        InModuleScope ApimAssessment {
            Mock Write-Progress

            Write-RunProgress -Activity 'Collect' -Status 'Running' `
                -PercentComplete 50

            Should -Invoke Write-Progress -Times 1 -Exactly -ParameterFilter {
                $Activity -eq 'Collect' -and
                $Status -eq 'Running' -and
                $PercentComplete -eq 50
            }
        }
    }
}
