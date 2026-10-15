$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll { Remove-Module ApimAssessment -Force -ErrorAction SilentlyContinue }

Describe 'Offline portal model and five portal rules' {
    InModuleScope ApimAssessment -Parameters @{ Repository = $repoRoot } {
        param($Repository)
        $script:portalRepository = $Repository
        BeforeAll {
            . (Join-Path $script:portalRepository 'tests/helpers/New-AnalysisTestRun.ps1')
            $script:portalConfig = Import-PowerShellDataFile (
                Join-Path $script:portalRepository 'config/sample.psd1'
            )
            $script:portalConfig.Output.Root = Join-Path $TestDrive 'restricted'
            $run = New-ApimRun -Config $script:portalConfig -EnvironmentName Prod `
                -TenantId '00000000-0000-0000-0000-000000000002' -Operator Synthetic -RunId 'portal-rules'
            $script:portalManifest = Get-RunManifest -RunPath $run.Path
            $script:portalRules = @(& (Join-Path $script:portalRepository 'rules/Portal.rules.ps1'))
            function Get-PortalTestArgument {
                return @{
                    ServicePayload = @{ properties = @{
                            developerPortalStatus = 'Enabled'; legacyPortalStatus = 'Disabled'
                            hostnameConfigurations = @(@{ type = 'DeveloperPortal'; hostName = 'portal.example.invalid' })
                        } }
                    PortalPayloads = @{
                        config = @{ properties = @{ enableBasicAuth = $false; signin = @{ require = $true }
                                delegation = @{ delegateRegistration = $false; delegateSubscription = $false } } }
                        signin = @{ properties = @{ enabled = $true } }
                        signup = @{ properties = @{ enabled = $false } }
                        delegation = @{ properties = @{
                                userRegistration = @{ enabled = $false }; subscriptions = @{ enabled = $false }
                            } }
                        revisions = @{ value = @(@{ name = 'current'; properties = @{ isCurrent = $true; status = 'completed' } }) }
                    }
                    IdentityProvidersPayload = @{ value = @(@{ name = 'aad'; properties = @{ type = 'aad' } }) }
                    ProductsPayload = @{ value = @(@{ name = 'private' }) }
                    ProductGroups = @{ private = @{ value = @(@{ name = 'partners' }) } }
                    ProductVisibility = @(@{ ProductId = 'private'; IsPublic = $false; IntendedGroupIds = @('partners') })
                }
            }
            function Invoke-PortalTestRule {
                param([string] $Id, [System.Collections.IDictionary] $Models)
                return @(Invoke-ApimRuleEngine -Rules @($script:portalRules | Where-Object Id -CEQ $Id) `
                        -Models $Models -Manifest $script:portalManifest -Config $script:portalConfig)
            }
        }

        It 'builds a closed complete model with direct detection, domains, publication and exact intent' {
            $arguments = Get-PortalTestArgument
            $portal = Get-ApimPortalModel @arguments
            $portal.modelStatus | Should -Be Complete
            $portal.missingInputs.Count | Should -Be 0
            $portal.basicAuthEnabled | Should -BeFalse
            $portal.basicAuthEvidence | Should -Be Direct
            $portal.published | Should -BeTrue
            $portal.customDomains[0].hostName | Should -Be 'portal.example.invalid'
            $portal.productVisibility[0].visibilityMismatch | Should -BeFalse
            $path = Join-Path $TestDrive 'closed-model'
            $null = Write-ApimModelSet -RunPath $path -Models @{ portal = $portal }
            $portal | Add-Member unexpected 'NEVER_COPY'
            { Write-ApimModelSet -RunPath $path -Models @{ portal = $portal } } | Should -Throw '*schema validation*'
        }

        It 'emits no findings for passing evidence for all four portal-scoped rules' {
            $arguments = Get-PortalTestArgument
            $models = @{ portal = Get-ApimPortalModel @arguments }
            foreach ($id in @('APIM-POR-001', 'APIM-POR-002', 'APIM-POR-003', 'APIM-POR-005')) {
                @(Invoke-PortalTestRule $id $models).Count | Should -Be 0
            }
        }

        It 'retains a known positive despite unrelated missing facts for <Id>' -ForEach @(
            @{ Id = 'APIM-POR-001'; Field = 'developerPortalStatus'; Value = 'Disabled' }
            @{ Id = 'APIM-POR-002'; Field = 'signupEnabled'; Value = $true }
            @{ Id = 'APIM-POR-005'; Field = 'legacyPortalStatus'; Value = 'Enabled' }
        ) {
            $portal = Get-ApimPortalModel -PortalPayloads @{}
            $portal.$Field = $Value
            $finding = @(Invoke-PortalTestRule $Id @{ portal = $portal })
            $finding.Count | Should -Be 1
            $finding[0].evaluation | Should -Be Evaluated
            $finding[0].scope | Should -Be portal
            $finding[0].usage | Should -Be NotApplicable
        }

        It 'emits one Info/NotEvaluated for each portal rule when evidence is absent' {
            foreach ($id in @('APIM-POR-001', 'APIM-POR-002', 'APIM-POR-003', 'APIM-POR-005')) {
                $finding = @(Invoke-PortalTestRule $id @{})
                $finding.Count | Should -Be 1
                $finding[0].severity | Should -Be Info
                $finding[0].evaluation | Should -Be NotEvaluated
                $finding = @(Invoke-PortalTestRule $id @{ portal = Get-ApimPortalModel -PortalPayloads @{} })
                $finding.Count | Should -Be 1
                $finding[0].evaluation | Should -Be NotEvaluated
            }
        }

        It 'does not infer basic auth disabled from Entra-only providers or a missing setting' {
            $arguments = Get-PortalTestArgument
            $arguments.PortalPayloads.config.properties.Remove('enableBasicAuth')
            $portal = Get-ApimPortalModel @arguments
            $portal.basicAuthEnabled | Should -BeNullOrEmpty
            $portal.basicAuthEvidence | Should -Be Unknown
            @(Invoke-PortalTestRule APIM-POR-002 @{ portal = $portal })[0].evaluation |
                Should -Be NotEvaluated
            $portal.missingInputs = @()
            @(Invoke-PortalTestRule APIM-POR-002 @{ portal = $portal })[0].evaluation |
                Should -Be NotEvaluated
            $arguments.PortalPayloads.config.properties.enableBasicAuth = 'false'
            { Get-ApimPortalModel @arguments } | Should -Throw '*non-Boolean*'
        }

        It 'flags direct basic authentication and non-Entra identities independently' {
            $arguments = Get-PortalTestArgument
            $arguments.PortalPayloads.config.properties.enableBasicAuth = $true
            @(Invoke-PortalTestRule APIM-POR-002 @{ portal = Get-ApimPortalModel @arguments })[0].evaluation |
                Should -Be Evaluated
            $arguments.PortalPayloads.config.properties.enableBasicAuth = $false
            $arguments.IdentityProvidersPayload.value[0].properties.type = 'google'
            @(Invoke-PortalTestRule APIM-POR-002 @{ portal = Get-ApimPortalModel @arguments })[0].evaluation |
                Should -Be Evaluated
        }

        It 'requires a current completed revision, preserving missing and empty publication evidence' {
            $arguments = Get-PortalTestArgument
            $arguments.PortalPayloads.revisions.value[0].properties.status = 'failed'
            (Get-ApimPortalModel @arguments).published | Should -BeFalse
            $arguments.PortalPayloads.revisions.value[0].properties.isCurrent = $false
            $arguments.PortalPayloads.revisions.value[0].properties.status = 'completed'
            (Get-ApimPortalModel @arguments).published | Should -BeFalse
            $arguments.PortalPayloads.revisions.value = @()
            (Get-ApimPortalModel @arguments).published | Should -BeFalse
            $arguments.PortalPayloads.Remove('revisions')
            (Get-ApimPortalModel @arguments).published | Should -BeNullOrEmpty
        }

        It 'qualifies conflicting publication, incomplete provider types and unknown custom domains' {
            $arguments = Get-PortalTestArgument
            $arguments.PortalPayloads.revisions.value += @{
                name = 'conflicting'; properties = @{ isCurrent = $true; status = 'completed' }
            }
            (Get-ApimPortalModel @arguments).published | Should -BeNullOrEmpty
            $arguments.IdentityProvidersPayload.value[0].properties.type = $null
            $arguments.ServicePayload.properties.Remove('hostnameConfigurations')
            $portal = Get-ApimPortalModel @arguments
            $portal.nonEntraProviderEnabled | Should -BeNullOrEmpty
            $portal.customDomains | Should -BeNullOrEmpty
            $portal.missingInputs | Should -Contain customDomains
            $portal.missingInputs | Should -Contain identityProviderTypes
            $arguments.ServicePayload.properties.hostnameConfigurations = @()
            $portal = Get-ApimPortalModel @arguments
            $portal.customDomains -is [array] | Should -BeTrue
            $portal.customDomains.Count | Should -Be 0
        }

        It 'retains unknown conflicting delegation and does not replace an unresolved target with a pass' {
            $arguments = Get-PortalTestArgument
            $arguments.PortalPayloads.config.properties.delegation.delegateRegistration = $true
            $arguments.ProductVisibility[0].ProductId = 'unresolved'
            $portal = Get-ApimPortalModel @arguments
            $portal.delegatedRegistration | Should -BeNullOrEmpty
            $portal.missingInputs | Should -Contain delegatedRegistration
            $portal.productVisibility[0].productFound | Should -BeFalse
            @(Invoke-PortalTestRule APIM-POR-003 @{ portal = $portal })[0].evaluation |
                Should -Be NotEvaluated
            $arguments.ProductsPayload = $null
            $portal = Get-ApimPortalModel @arguments
            $portal.productVisibility[0].productId | Should -Be unresolved
            $portal.productVisibility[0].productFound | Should -BeNullOrEmpty
        }

        It 'flags guests only for explicit nonpublic intent and detects missing intended membership' {
            $arguments = Get-PortalTestArgument
            $arguments.ProductGroups.private.value = @(@{ name = 'guests' }, @{ name = 'partners' })
            @(Invoke-PortalTestRule APIM-POR-003 @{ portal = Get-ApimPortalModel @arguments })[0].evaluation |
                Should -Be Evaluated
            $arguments.ProductVisibility[0].IsPublic = $true
            @(Invoke-PortalTestRule APIM-POR-003 @{ portal = Get-ApimPortalModel @arguments }).Count | Should -Be 0
            $arguments.ProductGroups.private.value = @(@{ name = 'guests' })
            @(Invoke-PortalTestRule APIM-POR-003 @{ portal = Get-ApimPortalModel @arguments })[0].evaluation |
                Should -Be Evaluated
            $arguments.ProductVisibility = @()
            @(Invoke-PortalTestRule APIM-POR-003 @{ portal = Get-ApimPortalModel @arguments })[0].evaluation |
                Should -Be NotEvaluated
        }

        It 'applies exact documentation and score boundaries and qualifies empty operation evidence' {
            $root = Join-Path $script:portalRepository 'tests/fixtures/synthetic-reference/model'
            $api = @(Get-Content (Join-Path $root 'apis.exposure.json') -Raw | ConvertFrom-Json)[0]
            $template = @(Get-Content (Join-Path $root 'operations.json') -Raw | ConvertFrom-Json)[0]
            $api.operationCount = 5
            $operations = @(1..5 | ForEach-Object {
                    $row = $template.PSObject.Copy()
                    $row.apiId = $api.apiId; $row.operationId = "operation-$_"; $row.hasDescription = $_ -le 4
                    $row
                })
            $models = @{ apis = @($api); operations = $operations }
            @(Invoke-PortalTestRule APIM-POR-004 $models).Count | Should -Be 0
            $operations[3].hasDescription = $false
            @(Invoke-PortalTestRule APIM-POR-004 $models)[0].evaluation | Should -Be Evaluated
            $operations[3].hasDescription = $true
            $api.openApiScore = 70
            @(Invoke-PortalTestRule APIM-POR-004 $models).Count | Should -Be 0
            $api.openApiScore = 69
            @(Invoke-PortalTestRule APIM-POR-004 $models)[0].evaluation | Should -Be Evaluated
            $api.openApiScore = $null; $api.operationCount = 0; $models.operations = @()
            @(Invoke-PortalTestRule APIM-POR-004 $models)[0].evaluation | Should -Be NotEvaluated
        }

        It 'round-trips optional intent in restricted settings and preserves old snapshots' {
            $config = $script:portalConfig.Clone()
            $environment = $config.Environments[0]
            $runPath = Join-Path $config.Output.Root 'portal-rules'
            $snapshot = Get-ApimRunSettingSnapshot -RunPath $runPath -Config $config -Environment $environment
            $snapshot.Contains('portalProductVisibility') | Should -BeFalse
            $config.Portal = @{ ProductVisibility = @(
                    @{ ProductId = 'private'; IsPublic = $false; IntendedGroupIds = @('partners') }
                ) }
            Save-ApimRunSetting -RunPath $runPath -Config $config -Environment $environment
            $saved = Get-ApimRunSetting -RunPath $runPath
            $saved.Config.Portal.ProductVisibility[0].ProductId | Should -Be private
            $saved.Config.Portal.ProductVisibility[0].IsPublic | Should -BeFalse
            $json = ConvertTo-Json -InputObject $saved.Settings -Depth 20
            $duplicate = $saved.Settings.portalProductVisibility[0]
            $saved.Settings.portalProductVisibility += $duplicate
            { Test-ApimRunSetting -Json (ConvertTo-Json $saved.Settings -Depth 20) `
                    -Manifest $script:portalManifest } | Should -Throw '*duplicate product*'
            $json | Should -Not -Match 'clientSecret|password'
        }

        It 'retains a documentation positive when another API has incomplete operation evidence' {
            $root = Join-Path $script:portalRepository 'tests/fixtures/synthetic-reference/model'
            $apis = @(Get-Content (Join-Path $root 'apis.exposure.json') -Raw | ConvertFrom-Json)
            $apis[0].openApiScore = 69
            $models = @{ apis = $apis; operations = @() }
            $findings = @(Invoke-PortalTestRule APIM-POR-004 $models)
            $findings.Count | Should -Be 1
            $findings[0].evaluation | Should -Be Evaluated
            $findings[0].scope | Should -Be "api:$($apis[0].apiId)"
        }

        It 'projects portal findings to package 1.3 without restricted fields or extra entity kinds' {
            $run = New-AnalysisTestRun -Root (Join-Path $TestDrive 'portal-package') `
                -Repository $script:portalRepository
            $arguments = Get-PortalTestArgument
            $arguments.PortalPayloads.config.properties.enableBasicAuth = $true
            $arguments.ServicePayload.properties.developerPortalStatus = 'Disabled'
            $arguments.ServicePayload.properties.legacyPortalStatus = 'Enabled'
            $arguments.ProductGroups.private.value = @(@{ name = 'guests' })
            $portal = Get-ApimPortalModel @arguments
            $portal.modelStatus = 'Partial'
            $portal.missingInputs = @('signinRequired')
            $run.Models.portal = $portal
            $null = Write-ApimModelSet -RunPath $run.RunPath -Models $run.Models
            $rules = @(Get-ApimRuleCatalog -CatalogPath (Join-Path $script:portalRepository 'rules'))
            $findings = @(Invoke-ApimRuleEngine -Rules $rules -Models $run.Models `
                    -Manifest (Get-RunManifest -RunPath $run.RunPath) -Config $run.Config)
            $null = Write-ApimFindingSet -RunPath $run.RunPath -Findings $findings
            $candidate = New-ApimAnalysisPackage -RunPath $run.RunPath -Config $run.Config
            $path = Join-Path $run.RunPath "restricted/candidates/$($candidate.candidateId)/analysis-package.json"
            $json = Get-Content -LiteralPath $path -Raw
            $attestation = Test-ApimAnalysisPackage -CandidatePath $path
            $attestation.packageSchemaVersion | Should -Be '1.3'
            $package = ConvertFrom-Json $json -AsHashtable
            $portalFindings = @($package.findings | Where-Object {
                    $_.ruleId -clike 'APIM-POR-*' -and $_.evaluation -ceq 'Evaluated'
                })
            $portalFindings.Count | Should -Be 4
            @($portalFindings.subjectAlias | Select-Object -Unique) | Should -Be @('service-001')
            $portalFacts = @($package.facts | Where-Object factId -In $portalFindings.factRefs)
            @($portalFacts.confidence | Select-Object -Unique) | Should -Be @('Medium')
            $package.entities.kind | Should -Not -Contain Portal
            $json | Should -Not -Match 'portal.example|"private"|"partners"|"guests"|"identityProviderTypes"|"basicAuthEnabled"|"productVisibility"'
            Test-ApimClaimFact -Claim WeakCallerAuthentication -Fact (
                $portalFacts | Where-Object value -CEQ PortalAuthenticationWeak
            ) | Should -BeTrue
            Test-ApimClaimFact -Claim GovernanceGap -Fact (
                $portalFacts | Where-Object value -CEQ ProductVisibilityMismatch
            ) | Should -BeTrue
            Save-ApimRunSetting -RunPath $run.RunPath -Config $run.Config `
                -Environment $run.Config.Environments[0]
            Set-RunStageStatus -RunPath $run.RunPath -Stage analyze -Status Completed
            (Invoke-ApimReport -RunFolder $run.RunPath).ExitCode | Should -Be 0
            $reports = Get-ApimRenderedPath -RunPath $run.RunPath
            $workbook = Open-ExcelPackage -Path $reports.workbook
            try {
                $headerRow = $workbook.Workbook.Worksheets['Finding Details'].Tables['tblFindings'].Address.Start.Row
            }
            finally { $workbook.Dispose() }
            $detail = @(Import-Excel -Path $reports.workbook -WorksheetName 'Finding Details' -StartRow $headerRow)
            $detail.'Rule ID' | Should -Contain APIM-POR-001
            $detail.'Rule ID' | Should -Contain APIM-POR-002
            $detail.'Rule ID' | Should -Contain APIM-POR-003
            $detail.'Rule ID' | Should -Contain APIM-POR-005
            $html = Get-Content -LiteralPath $reports.html -Raw
            $html | Should -Match 'APIM-POR-002|Username/password'
            foreach ($version in @('1.0', '1.1', '1.2')) {
                { Test-ApimAnalysisContract -Kind AnalysisPackage `
                        -Json ($json -replace '"schemaVersion"\s*:\s*"1.3"', "`"schemaVersion`":`"$version`"") } |
                    Should -Throw
            }
            { Test-ApimAnalysisContract -Kind AnalysisPackage `
                    -Json ($json.Replace('PortalAuthenticationWeak', 'UNAPPROVED_PROVIDER_DETAIL')) } | Should -Throw
            $portalFacts[0].value = 'LegacyTlsEnabled'
            { Test-ApimAnalysisContract -Kind AnalysisPackage `
                    -Json (ConvertTo-Json $package -Depth 30) } | Should -Throw '*portal condition binding*'
        }
    }
}
