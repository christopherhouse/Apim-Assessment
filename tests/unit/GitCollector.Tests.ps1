$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Committed local Git policy collector' {
    InModuleScope ApimAssessment {
        BeforeAll {
            function Invoke-SyntheticGit {
                param([string[]] $Arguments)
                $result = & git -C $script:source @Arguments 2>&1
                if ($LASTEXITCODE -ne 0) { throw 'Synthetic repository setup failed.' }
                return $result
            }
            function Set-SyntheticPolicy {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                    'PSUseShouldProcessForStateChangingFunctions', '',
                    Justification = 'Writes only synthetic temporary test fixtures.'
                )]
                [CmdletBinding()]
                param([string] $Name, [string] $Xml = '<policies><inbound><base /></inbound></policies>')
                $path = Join-Path $script:source "policies/$Name"
                $null = New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force
                [System.IO.File]::WriteAllText($path, $Xml)
            }
            function Save-SyntheticCommit {
                Invoke-SyntheticGit @('add', '--all') | Out-Null
                Invoke-SyntheticGit @('-c', 'user.name=Synthetic Author',
                    '-c', 'user.email=synthetic@example.invalid', '-c', 'core.hooksPath=',
                    'commit', '--no-gpg-sign', '-m', 'synthetic source text') | Out-Null
            }
        }

        BeforeEach {
            $script:source = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $null = New-Item -ItemType Directory -Path $script:source
            Invoke-SyntheticGit @('init', '--quiet') | Out-Null
            Set-SyntheticPolicy 'policy.xml'
            Set-SyntheticPolicy 'apis/sample/policy.xml'
            Set-SyntheticPolicy 'apis/sample/operations/read/policy.xml'
            Set-SyntheticPolicy 'products/basic/policy.xml'
            Save-SyntheticCommit
            $script:environment = @{
                GitRepoPath = $script:source
                GitPolicyRoot = 'policies'
            }
        }

        It 'uses ordinal closed inventories with deployed formatting and redaction parity' {
            Set-SyntheticPolicy 'policy.xml' @'
<policies>
 <!-- formatting does not matter -->
 <inbound><set-header name="x-api-key"><value>synthetic-secret-canary</value></set-header></inbound>
</policies>
'@
            Save-SyntheticCommit
            $snapshot = Get-ApimGitPolicySnapshot -Environment $script:environment
            Test-ApimGitPolicySnapshot $snapshot
            $snapshot.scopeTypes | Should -Be @('Api', 'Global', 'Operation', 'Product')
            $snapshot.policies.scope | Should -Be @('sample', 'global', 'sample|read', 'basic')
            $expected = Protect-ApimPolicyXml '<policies><inbound><set-header name="x-api-key"><value>different-secret-canary</value></set-header></inbound></policies>'
            $snapshot.policies[1].sha256 | Should -Be (Get-ApimPolicySha256 $expected.Xml)
            $json = $snapshot | ConvertTo-Json -Depth 10
            $json | Should -Not -Match 'canary|Author|example.invalid|source text|policy.xml|GitRepoPath|<policies'
            $json.Contains($script:source) | Should -BeFalse
            @($snapshot.PSObject.Properties.Name) | Should -Be @('schemaVersion', 'commitSha', 'scopeTypes', 'policies')
        }

        It 'changes hashes only for committed policy changes, ignoring dirty and untracked files' {
            $first = Get-ApimGitPolicySnapshot $script:environment
            Set-SyntheticPolicy 'apis/sample/policy.xml' '<policies><inbound><base/><return-response/></inbound></policies>'
            Set-SyntheticPolicy 'unsupported.xml' '<malformed'
            $dirty = Get-ApimGitPolicySnapshot $script:environment
            ($dirty | ConvertTo-Json -Depth 10) | Should -Be ($first | ConvertTo-Json -Depth 10)
            Remove-Item (Join-Path $script:source 'policies/unsupported.xml')
            Save-SyntheticCommit
            $changed = Get-ApimGitPolicySnapshot $script:environment
            $changed.commitSha | Should -Not -Be $first.commitSha
            $changed.policies[0].sha256 | Should -Not -Be $first.policies[0].sha256
        }

        It 'pins HEAD once even when HEAD moves during tree enumeration' {
            $old = Get-ApimGitPolicySnapshot $script:environment
            Set-SyntheticPolicy 'apis/sample/policy.xml' '<policies><outbound/></policies>'
            Save-SyntheticCommit
            $script:newCommit = (Invoke-SyntheticGit @('rev-parse', 'HEAD')).Trim()
            Invoke-SyntheticGit @('reset', '--soft', $old.commitSha) | Out-Null
            $script:realGitRead = (Get-Command Invoke-ApimGitRead).ScriptBlock
            Mock Invoke-ApimGitRead {
                param($Repository, $Arguments, $MaximumBytes)
                if (-not $MaximumBytes) { $MaximumBytes = 8388608 }
                if ($Arguments[0] -eq 'ls-tree') {
                    Invoke-SyntheticGit @('update-ref', 'HEAD', $script:newCommit) | Out-Null
                }
                & $script:realGitRead -Repository $Repository -Arguments $Arguments -MaximumBytes $MaximumBytes
            }
            $pinned = Get-ApimGitPolicySnapshot $script:environment
            $pinned.commitSha | Should -Be $old.commitSha
            $pinned.policies[0].sha256 | Should -Be $old.policies[0].sha256
            Should -Invoke Invoke-ApimGitRead -Times 1 -Exactly -ParameterFilter {
                $Arguments[0] -eq 'rev-parse'
            }
        }

        It 'allows explicitly configured fragment coverage' {
            Set-SyntheticPolicy 'fragments/shared.xml' '<fragment><set-header name="example"><value>ok</value></set-header></fragment>'
            Save-SyntheticCommit
            $script:environment.GitPolicyMappings = @(
                @{ ScopeType = 'Global'; Pattern = 'policy\.xml' }
                @{ ScopeType = 'Api'; Pattern = 'apis/(?<api>[^/]+)/policy\.xml' }
                @{ ScopeType = 'Product'; Pattern = 'products/(?<product>[^/]+)/policy\.xml' }
                @{ ScopeType = 'Operation'; Pattern = 'apis/(?<api>[^/]+)/operations/(?<operation>[^/]+)/policy\.xml' }
                @{ ScopeType = 'Fragment'; Pattern = 'fragments/(?<fragment>[^/]+)\.xml' }
            )
            $snapshot = Get-ApimGitPolicySnapshot $script:environment
            $snapshot.scopeTypes | Should -Be @('Api', 'Fragment', 'Global', 'Operation', 'Product')
            $snapshot.policies[1].scope | Should -Be 'shared'
        }

        It 'handles UTF-8 BOM XML and a slash-normalized root containing spaces' {
            Set-SyntheticPolicy 'policy.xml' ([char]0xfeff + '<policies><inbound><base/></inbound></policies>')
            Save-SyntheticCommit
            $first = Get-ApimGitPolicySnapshot $script:environment
            Move-Item (Join-Path $script:source 'policies') (Join-Path $script:source 'policy root')
            Save-SyntheticCommit
            $script:environment.GitPolicyRoot = 'policy root'
            $moved = Get-ApimGitPolicySnapshot $script:environment
            $moved.policies.sha256 | Should -Be $first.policies.sha256
        }

        It 'rejects malformed or unsupported committed XML: <Name>' -ForEach @(
            @{ Name = 'malformed'; File = 'policy.xml'; Xml = '<policies>broken' }
            @{ Name = 'unsupported'; File = 'unknown.xml'; Xml = '<policies/>' }
            @{ Name = 'invalid root'; File = 'policy.xml'; Xml = '<unknown/>' }
            @{ Name = 'DTD'; File = 'policy.xml'; Xml = '<!DOCTYPE policies [<!ENTITY x SYSTEM "file:///synthetic">]><policies>&x;</policies>' }
            @{ Name = 'unsafe scope'; File = 'apis/unsafe name/policy.xml'; Xml = '<policies/>' }
        ) {
            Set-SyntheticPolicy $File $Xml
            Save-SyntheticCommit
            { Get-ApimGitPolicySnapshot $script:environment } | Should -Throw 'Git policy collection failed.'
        }

        It 'rejects root escape, links, missing roots and invalid repositories' {
            foreach ($badRoot in @('', '../policies', '/policies', 'policies/../policies', 'policies\apis', 'missing')) {
                $script:environment.GitPolicyRoot = $badRoot
                { Get-ApimGitPolicySnapshot $script:environment } | Should -Throw 'Git policy collection failed.'
            }
            $script:environment.GitPolicyRoot = 'policies'
            $script:environment.GitRepoPath = $TestDrive
            { Get-ApimGitPolicySnapshot $script:environment } | Should -Throw 'Git policy collection failed.'
            $script:environment.GitRepoPath = $script:source
            # Build a committed symbolic-link mode without OS symlink privileges.
            $oid = (Invoke-SyntheticGit @('rev-parse', 'HEAD:policies/policy.xml')).Trim()
            Invoke-SyntheticGit @('update-index', '--add', '--cacheinfo', "120000,$oid,policies/link.xml") | Out-Null
            Invoke-SyntheticGit @('-c', 'user.name=Synthetic Author', '-c', 'user.email=synthetic@example.invalid',
                '-c', 'core.hooksPath=', 'commit', '--no-gpg-sign', '-m', 'synthetic link') | Out-Null
            { Get-ApimGitPolicySnapshot $script:environment } | Should -Throw 'Git policy collection failed.'
        }

        It 'rejects committed root links and gitlinks without following them' {
            $oid = (Invoke-SyntheticGit @('rev-parse', 'HEAD:policies/policy.xml')).Trim()
            $commit = (Invoke-SyntheticGit @('rev-parse', 'HEAD')).Trim()
            foreach ($record in @(
                    "120000,$oid,linked-root"
                    "160000,$commit,policies/submodule"
                )) {
                Invoke-SyntheticGit @('update-index', '--add', '--cacheinfo', $record) | Out-Null
            }
            Invoke-SyntheticGit @('-c', 'user.name=Synthetic Author', '-c', 'user.email=synthetic@example.invalid',
                '-c', 'core.hooksPath=', 'commit', '--no-gpg-sign', '-m', 'synthetic links') | Out-Null
            { Get-ApimGitPolicySnapshot $script:environment } | Should -Throw 'Git policy collection failed.'
            $script:environment.GitPolicyRoot = 'linked-root'
            { Get-ApimGitPolicySnapshot $script:environment } | Should -Throw 'Git policy collection failed.'
            $script:environment.GitPolicyRoot = 'linked-root/child'
            { Get-ApimGitPolicySnapshot $script:environment } | Should -Throw 'Git policy collection failed.'
        }

        It 'rejects ambiguous mappings, duplicate identities and invalid mappings' {
            $defaults = @(
                @{ ScopeType = 'Global'; Pattern = 'policy\.xml' }
                @{ ScopeType = 'Api'; Pattern = 'apis/(?<api>[^/]+)/policy\.xml' }
                @{ ScopeType = 'Product'; Pattern = 'products/(?<product>[^/]+)/policy\.xml' }
                @{ ScopeType = 'Operation'; Pattern = 'apis/(?<api>[^/]+)/operations/(?<operation>[^/]+)/policy\.xml' }
            )
            foreach ($bad in @(
                    @{ ScopeType = 'Global'; Pattern = '.*\.xml' }
                    @{ ScopeType = 'Api'; Pattern = 'policy\.xml' }
                    @{ ScopeType = 'Global'; Pattern = 'policy\.xml'; Unknown = 'canary' }
                    @{ ScopeType = 'Global'; Pattern = '[' }
                    @{ ScopeType = 'Global'; Pattern = ('a' * 1025) }
                    @{ ScopeType = 'Global'; Pattern = 'policy\.xml' }
                )) {
                $script:environment.GitPolicyMappings = $defaults + @($bad)
                { Get-ApimGitPolicySnapshot $script:environment } | Should -Throw 'Git policy collection failed.'
            }
            $script:environment.GitPolicyMappings = @(
                @{ ScopeType = 'Global'; Pattern = '.*policy\.xml' }
            )
            { Get-ApimGitPolicySnapshot $script:environment } | Should -Throw 'Git policy collection failed.'
        }

        It 'bounds configured regex evaluation and enforces full-path matches' {
            Set-SyntheticPolicy (('a' * 60) + 'b.xml')
            Save-SyntheticCommit
            $script:environment.GitPolicyMappings = @(
                @{ ScopeType = 'Global'; Pattern = '(a+)+\.xml' }
            )
            { Get-ApimGitPolicySnapshot $script:environment } | Should -Throw 'Git policy collection failed.'
            $script:environment.GitPolicyMappings = @(
                @{ ScopeType = 'Global'; Pattern = 'policy' }
            )
            { Get-ApimGitPolicySnapshot $script:environment } | Should -Throw 'Git policy collection failed.'
        }

        It 'validates mapping configuration without reading any repository' {
            Mock Invoke-ApimGitRead { throw 'Repository must not be read.' }
            $defaults = Get-ApimGitPolicyMappingConfiguration -Environment @{}
            $defaults.ScopeTypes | Should -Be @('Api', 'Global', 'Operation', 'Product')
            $defaults.Mappings.Count | Should -Be 4
            $defaults.Mappings[0].Regex.IsMatch('prefix/policy.xml') | Should -BeFalse
            $defaults.Mappings[0].Regex.MatchTimeout.TotalMilliseconds | Should -Be 100
            $custom = Get-ApimGitPolicyMappingConfiguration -Environment @{
                GitPolicyMappings = @(@{ ScopeType = 'Fragment'; Pattern = '(?<fragment>[^/]+)\.xml' })
            }
            $custom.ScopeTypes | Should -Be @('Fragment')
            foreach ($bad in @(
                    @{ ScopeType = 'Api'; Pattern = 'no-capture' }
                    @{ ScopeType = 'Global'; Pattern = '[' }
                    @{ ScopeType = 'Global'; Pattern = 'policy\.xml'; Unknown = 'canary' }
                )) {
                { Get-ApimGitPolicyMappingConfiguration -Environment @{ GitPolicyMappings = @($bad) } } |
                    Should -Throw 'Git policy mappings rejected.'
            }
            Should -Invoke Invoke-ApimGitRead -Times 0 -Exactly
        }

        It 'independently rejects unknown fields, invalid hashes, coverage and duplicate or unsorted identities' {
            $snapshot = Get-ApimGitPolicySnapshot $script:environment
            foreach ($kind in @('unknown', 'hash', 'coverage', 'duplicate', 'order', 'scope', 'coverageOrder',
                    'unknownPolicyField', 'newlineHash', 'newlineScope', 'newlineCommit')) {
                $copy = $snapshot | ConvertTo-Json -Depth 10 | ConvertFrom-Json
                switch ($kind) {
                    'unknown' { $copy | Add-Member NoteProperty unknown 'synthetic-secret-canary' }
                    'hash' { $copy.commitSha = 'ABC' }
                    'coverage' { $copy.scopeTypes = @('Global') }
                    'duplicate' { $copy.policies += $copy.policies[0] }
                    'order' { [array]::Reverse($copy.policies) }
                    'scope' { $copy.policies[0].scope = '../unsafe' }
                    'coverageOrder' { [array]::Reverse($copy.scopeTypes) }
                    'unknownPolicyField' { $copy.policies[0] | Add-Member NoteProperty path 'synthetic-secret-canary' }
                    'newlineHash' { $copy.policies[0].sha256 += "`n" }
                    'newlineScope' { $copy.policies[0].scope += "`n" }
                    'newlineCommit' { $copy.commitSha += "`n" }
                }
                { Test-ApimGitPolicySnapshot $copy } | Should -Throw 'Git policy snapshot rejected.'
            }
        }

        It 'accepts dictionary snapshots and 64-hex commit IDs with explicit empty coverage inventories' {
            $snapshot = [ordered]@{
                schemaVersion = '1.0'
                commitSha = 'a' * 64
                scopeTypes = @('Fragment')
                policies = @()
            }
            { Test-ApimGitPolicySnapshot $snapshot } | Should -Not -Throw
        }

        It 'bounds Git output and blob sizes without exposing source values' {
            { Invoke-ApimGitRead -Repository $script:source -Arguments @('ls-tree', '-r', 'HEAD') `
                    -MaximumBytes 1 } | Should -Throw 'Git read rejected.'
            Set-SyntheticPolicy 'policy.xml' ('<policies><!--' + ('x' * 1048576) + '--></policies>')
            Save-SyntheticCommit
            { Get-ApimGitPolicySnapshot $script:environment } | Should -Throw 'Git policy collection failed.'
            try {
                Invoke-ApimGitRead -Repository $script:source -Arguments @('cat-file', 'blob', 'synthetic-secret-canary')
                throw 'Expected rejection.'
            }
            catch {
                $_.Exception.Message | Should -Be 'Git read rejected.'
                ($_ | Out-String) | Should -Not -Match 'fatal:|Author|example.invalid'
            }
        }

        It 'does not change source refs, index, config or worktree' {
            Set-SyntheticPolicy 'dirty.xml' '<not-even-xml'
            $before = @(
                Invoke-SyntheticGit @('status', '--porcelain=v1')
                Invoke-SyntheticGit @('show-ref')
                Get-FileHash (Join-Path $script:source '.git/index') | Select-Object -ExpandProperty Hash
                Get-FileHash (Join-Path $script:source '.git/config') | Select-Object -ExpandProperty Hash
            )
            $null = Get-ApimGitPolicySnapshot $script:environment
            $after = @(
                Invoke-SyntheticGit @('status', '--porcelain=v1')
                Invoke-SyntheticGit @('show-ref')
                Get-FileHash (Join-Path $script:source '.git/index') | Select-Object -ExpandProperty Hash
                Get-FileHash (Join-Path $script:source '.git/config') | Select-Object -ExpandProperty Hash
            )
            $after | Should -Be $before
        }

        It 'writes only validated evidence and records Completed with safe logs' {
            Mock Set-RunCollectorStatus {}
            Mock Write-RunLog {}
            Mock Write-RunFile { 'synthetic-output' }
            $result = Invoke-ApimGitCollector -RunPath $TestDrive -Environment $script:environment
            $result | Should -Be 'synthetic-output'
            Should -Invoke Write-RunFile -Times 1 -Exactly -ParameterFilter {
                $RelativePath -eq 'git/policyHashes.json' -and $InputObject.schemaVersion -eq '1.0'
            }
            Should -Invoke Set-RunCollectorStatus -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'Git' -and $Status -eq 'Completed' -and $Items -eq 4
            }
            Should -Invoke Set-RunCollectorStatus -Times 1 -Exactly -ParameterFilter { $Status -eq 'InProgress' }
        }

        It 'records Failed, removes stale evidence, and never writes success-shaped data on failure' {
            Mock Set-RunCollectorStatus {}
            Mock Write-RunLog {}
            Mock Write-RunFile { throw 'Should not write.' }
            $stale = Join-Path $TestDrive 'git/policyHashes.json'
            $null = New-Item -ItemType Directory -Path (Split-Path $stale -Parent) -Force
            [System.IO.File]::WriteAllText($stale, '{"schemaVersion":"1.0"}')
            $script:environment.GitRepoPath = Join-Path $TestDrive 'synthetic-secret-canary'
            { Invoke-ApimGitCollector -RunPath $TestDrive -Environment $script:environment } |
                Should -Throw 'Git policy collection failed.'
            Test-Path -LiteralPath $stale | Should -BeFalse
            Should -Invoke Write-RunFile -Times 0 -Exactly
            Should -Invoke Set-RunCollectorStatus -Times 1 -Exactly -ParameterFilter {
                $Status -eq 'Failed' -and $Errors -eq 1
            }
            Should -Invoke Write-RunLog -Times 1 -Exactly -ParameterFilter {
                $Message -eq 'Git policy collection failed.'
            }
        }

        It 'validates the complete snapshot before writing and sanitizes persistence failures' {
            Mock Set-RunCollectorStatus {}
            Mock Write-RunLog {}
            Mock Get-ApimGitPolicySnapshot {
                [pscustomobject]@{
                    schemaVersion = '1.0'; commitSha = 'a' * 40
                    scopeTypes = @('Global'); policies = @(); unknown = 'synthetic-secret-canary'
                }
            }
            Mock Write-RunFile { throw 'synthetic-secret-canary' }
            { Invoke-ApimGitCollector -RunPath $TestDrive -Environment $script:environment } |
                Should -Throw 'Git policy collection failed.'
            Should -Invoke Write-RunFile -Times 0 -Exactly
            Mock Get-ApimGitPolicySnapshot {
                [pscustomobject]@{
                    schemaVersion = '1.0'; commitSha = 'a' * 40
                    scopeTypes = @('Global'); policies = @()
                }
            }
            { Invoke-ApimGitCollector -RunPath $TestDrive -Environment $script:environment } |
                Should -Throw 'Git policy collection failed.'
            Should -Invoke Write-RunFile -Times 1 -Exactly
            Should -Invoke Set-RunCollectorStatus -Times 2 -Exactly -ParameterFilter { $Status -eq 'Failed' }
            Should -Invoke Set-RunCollectorStatus -Times 0 -Exactly -ParameterFilter { $Status -eq 'Completed' }
        }
    }
}
