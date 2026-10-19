BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:module = Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force -PassThru
}

AfterAll {
    Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Run-anchored telemetry and cost intervals' {
    It 'caps a requested log interval without losing its requested boundary' {
        $window = & $script:module {
            Get-ApimEvidenceWindow -EndUtc '2026-10-15T12:00:00-05:00' `
                -Kind Usage -Length 90 -RetentionDays 30
        }
        $window.endUtc | Should -Be '2026-10-15T17:00:00.0000000+00:00'
        $window.requestedStartUtc | Should -Be '2026-07-17T17:00:00.0000000+00:00'
        $window.startUtc | Should -Be '2026-09-15T17:00:00.0000000+00:00'
        $window.retentionDays | Should -Be 30
        $window.isCapped | Should -BeTrue
    }

    It 'does not extend a shorter requested security window to retention' {
        $window = & $script:module {
            Get-ApimEvidenceWindow -EndUtc '2026-10-15T17:00:00Z' `
                -Kind Security -Length 30 -RetentionDays 90
        }
        $window.startUtc | Should -Be $window.requestedStartUtc
        $window.isCapped | Should -BeFalse
    }

    It 'includes full prior cost months and MTD across a UTC year boundary' {
        $window = & $script:module {
            Get-ApimEvidenceWindow -EndUtc '2025-12-31T21:30:00-05:00' `
                -Kind Cost -Length 6
        }
        $window.startUtc | Should -Be '2025-07-01T00:00:00.0000000+00:00'
        $window.endUtc | Should -Be '2026-01-01T02:30:00.0000000+00:00'
        $window.retentionDays | Should -BeNullOrEmpty
        $window.isCapped | Should -BeFalse
    }

    It 'does not use the current clock to move a saved metric interval' {
        $window = & $script:module {
            Get-ApimEvidenceWindow -EndUtc '2024-03-01T00:00:00Z' -Kind Metric -Length 1
        }
        $window.startUtc | Should -Be '2024-02-29T00:00:00.0000000+00:00'
    }

    It 'rejects applying LA retention to cost or metric evidence' {
        foreach ($kind in @('Cost', 'Metric')) {
            {
                & $script:module {
                    param($Kind)
                    Get-ApimEvidenceWindow -EndUtc '2026-10-15T00:00:00Z' `
                        -Kind $Kind -Length 6 -RetentionDays 30
                } $kind
            } | Should -Throw '*only for Log Analytics*'
        }
    }
}
