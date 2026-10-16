BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $dependencies = Import-PowerShellDataFile (Join-Path $repoRoot 'scripts/DevDependencies.psd1')
    $assembly = Join-Path $repoRoot (
        ".tools/kusto/$($dependencies.KustoLanguage)/lib/net6.0/Kusto.Language.dll"
    )
    if (-not (Test-Path -LiteralPath $assembly -PathType Leaf)) {
        throw 'Install the pinned parser with scripts/Install-DevDependencies.ps1.'
    }
    $null = [Reflection.Assembly]::LoadFrom($assembly)
    $script:queryModule = Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force -PassThru
}

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Bound telemetry KQL syntax' {
    It 'rejects invalid KQL with the real parser rather than a text-pattern proxy' {
        $code = [Kusto.Language.KustoCode]::Parse('ApiManagementGatewayLogs | summarize calls=count(')
        @($code.GetSyntaxDiagnostics()).Count | Should -BeGreaterThan 0
    }

    It 'parses both schema variants of <Name>' -ForEach @(
        @{ Name = 'usageByApi' }, @{ Name = 'usageByRoute' }, @{ Name = 'usageMonthly' },
        @{ Name = 'tls' }, @{ Name = 'noSubscriptionCalls' }, @{ Name = 'schema' },
        @{ Name = 'laIngestion' }
    ) {
        foreach ($schema in @('ResourceSpecific', 'Legacy')) {
            $query = & $script:queryModule {
                param($Name, $Schema)
                $window = Get-ApimEvidenceWindow -EndUtc '2026-10-15T22:00:00Z' `
                    -Kind Usage -Length 90 -RetentionDays 30
                Get-ApimLogQuery -Name $Name -Schema $Schema -Window $window `
                    -ResourceId '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-synthetic/providers/Microsoft.ApiManagement/service/apim-synthetic' `
                    -AppGwCidrs @('10.0.0.0/24') -InternalCidrs @('10.0.0.0/8')
            } $Name $schema
            $code = [Kusto.Language.KustoCode]::Parse($query)
            @($code.GetSyntaxDiagnostics()).Message | Should -BeNullOrEmpty
            $query | Should -Not -Match '__[A-Z]+__'
            $query | Should -Match 'TimeGenerated >= datetime\(2026-09-15T22:00:00'
            $query | Should -Match 'TimeGenerated < datetime\(2026-10-15T22:00:00'
        }
    }

    It 'escapes literal values and parses empty route ranges without changing query structure' {
        $query = & $script:queryModule {
            $window = Get-ApimEvidenceWindow -EndUtc '2026-10-15T00:00:00Z' -Kind Usage -Length 30
            Get-ApimLogQuery -Name usageByRoute -Schema ResourceSpecific `
                -Window $window -ResourceId "synthetic`"value\suffix"
        }
        @([Kusto.Language.KustoCode]::Parse($query).GetSyntaxDiagnostics()).Count | Should -Be 0
        $query | Should -Match 'dynamic\(\[\]\)'
        $query | Should -Match 'synthetic\\"value\\\\suffix'
    }
}
