BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:branchGuard = Join-Path $repoRoot 'scripts/Test-DevelopmentBranch.ps1'
}

Describe 'Development branch policy' {
    It 'accepts <Branch> branches' -TestCases @(
        @{ Branch = 'feature/bootstrap-repository' }
        @{ Branch = 'chore/release-0.2.0' }
        @{ Branch = 'bugfix/policy-inheritance' }
    ) {
        { & $script:branchGuard -BranchName $Branch } | Should -Not -Throw
    }

    It 'rejects <Label>' -TestCases @(
        @{ Branch = 'main'; Label = 'main' }
        @{ Branch = 'develop'; Label = 'an unapproved long-lived branch' }
        @{ Branch = 'copilot/task'; Label = 'an unapproved prefix' }
        @{ Branch = 'feature/'; Label = 'an empty feature slug' }
        @{ Branch = 'feature/Has Spaces'; Label = 'nonportable names' }
        @{ Branch = ''; Label = 'detached HEAD' }
    ) {
        { & $script:branchGuard -BranchName $Branch } | Should -Throw '*not allowed*'
    }
}
