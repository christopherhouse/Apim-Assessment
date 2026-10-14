$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

Describe 'Safe secret candidate console table' {
    BeforeAll {
        . (Join-Path $repoRoot 'scripts/Write-ApimSecretScanTable.ps1')
    }

    It 'renders candidate aliases and positions without adding private location details' {
        $rows = @(
            [pscustomobject]@{
                row = 1; artifactId = 'artifact-0001'; kind = 'CredentialAssignment'
                line = 2; column = 5
            }
            [pscustomobject]@{
                row = 2; artifactId = 'artifact-0002'; kind = 'JsonCredentialValue'
                line = $null; column = $null
            }
        )
        $original = [Console]::Out
        $writer = [System.IO.StringWriter]::new()
        try {
            [Console]::SetOut($writer)
            Write-ApimSecretScanTable -Rows $rows
            $text = $writer.ToString()
        }
        finally {
            [Console]::SetOut($original)
            $writer.Dispose()
        }
        $text | Should -Match '#\s+Artifact\s+Match\s+Line\s+Column'
        $text | Should -Match '1\s+artifact-0001\s+CredentialAssignment\s+2\s+5'
        $text | Should -Match '2\s+artifact-0002\s+JsonCredentialValue\s+-\s+-'
        $text | Should -Match 'candidates, not confirmed credentials'
        $text | Should -Match 'secret-scan-locations\.json'
    }

    It 'rejects unsafe or malformed rows before printing anything' -ForEach @(
        @{ Fault = 'extra-field' }
        @{ Fault = 'private-artifact' }
        @{ Fault = 'unknown-kind' }
        @{ Fault = 'invalid-position' }
        @{ Fault = 'wrong-row' }
    ) {
        $row = [pscustomobject]@{
            row = 1; artifactId = 'artifact-0001'; kind = 'JsonCredentialValue'
            line = $null; column = $null
        }
        switch ($Fault) {
            extra-field { $row | Add-Member -NotePropertyName file -NotePropertyValue 'synthetic-private.json' }
            private-artifact { $row.artifactId = 'synthetic-private.json' }
            unknown-kind { $row.kind = 'synthetic-planted-value' }
            invalid-position { $row.line = -1 }
            wrong-row { $row.row = 2 }
        }
        $original = [Console]::Out
        $writer = [System.IO.StringWriter]::new()
        try {
            [Console]::SetOut($writer)
            { Write-ApimSecretScanTable -Rows @($row) } | Should -Throw
            $writer.ToString() | Should -BeNullOrEmpty
        }
        finally {
            [Console]::SetOut($original)
            $writer.Dispose()
        }
    }
}
