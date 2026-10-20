BeforeAll {
    $script:labRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    . (Join-Path $script:labRoot 'scripts\lab\LabBootstrap.Transport.ps1')
    . (Join-Path $script:labRoot 'scripts\lab\LabBootstrap.Core.ps1')

    function Get-TestLabResource {
        param($Id, $Type, $Location = 'eastus2')
        return @{ id = $Id; type = $Type; location = $Location; tags = @{ apimAssessmentLab = 'synthetic-lab' } }
    }

    function Initialize-TestLabEnvironment {
        $script:github[$script:target.environment] = @{
            name = 'lab'; can_admins_bypass = $false
            deployment_branch_policy = @{ protected_branches = $false; custom_branch_policies = $true }
            protection_rules = @(@{ type = 'required_reviewers'; prevent_self_review = $true
                    reviewers = @(@{ type = 'Team'; reviewer = @{ id = 12345L } }) })
        }
        $script:github["$($script:target.environment)/deployment-branch-policies"] = @{
            total_count = 1; branch_policies = @(@{ name = 'main'; type = 'branch' })
        }
    }

    function Initialize-TestLabIdentity {
        $resource = Get-TestLabResource $script:target.identity 'Microsoft.ManagedIdentity/userAssignedIdentities'
        $resource.properties = @{
            tenantId = $script:configuration.tenantId
            clientId = '33333333-3333-3333-3333-333333333333'
            principalId = '44444444-4444-4444-4444-444444444444'
        }
        $script:arm[$script:target.identity] = $resource
    }

    function Initialize-TestLabComplete {
        Initialize-TestLabEnvironment
        Initialize-TestLabIdentity
        $script:federations = @(@{ id = $script:target.federation
                properties = @{ issuer = 'https://token.actions.githubusercontent.com'
                    subject = $script:target.subject; audiences = @('api://AzureADTokenExchange') } })
        $script:roles.Add(@{ properties = @{
                    principalId = '44444444-4444-4444-4444-444444444444'; principalType = 'ServicePrincipal'
                    roleDefinitionId = "$($script:target.subscription)/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
                    scope = $script:target.lab
                } })
        $values = @{
            AZURE_CLIENT_ID = '33333333-3333-3333-3333-333333333333'
            AZURE_TENANT_ID = $script:configuration.tenantId
            AZURE_SUBSCRIPTION_ID = $script:configuration.subscriptionId
            AZURE_LOCATION = 'eastus2'; LAB_RESOURCE_GROUP = 'rg-synthetic-lab'; LAB_PROFILE = 'baseline'
        }
        foreach ($name in $values.Keys) {
            $script:github["$($script:target.environment)/variables/$name"] = @{ name = $name; value = $values[$name] }
        }
    }

    function Initialize-TestLabRuntime {
        $script:configuration.runtime = @{
            apim = 'apim-synthetic'; gatewayIdentity = 'id-synthetic-gateway'; workerVm = 'vm-synthetic-worker'
            keyVault = 'kv-synthetic'; dnsZone = 'challenge.synthetic.invalid'; appInsights = 'ai-synthetic'
        }
        $types = @{
            apim = 'Microsoft.ApiManagement/service'; gatewayIdentity = 'Microsoft.ManagedIdentity/userAssignedIdentities'
            workerVm = 'Microsoft.Compute/virtualMachines'; keyVault = 'Microsoft.KeyVault/vaults'
            dnsZone = 'Microsoft.Network/dnsZones'; appInsights = 'Microsoft.Insights/components'
        }
        $index = 5
        foreach ($key in $types.Keys) {
            $id = "$($script:target.lab)/providers/$($types[$key])/$($script:configuration.runtime[$key])"
            $location = if ($key -ceq 'dnsZone') { 'global' } else { 'eastus2' }
            $resource = Get-TestLabResource $id $types[$key] $location
            $principal = ("{0}{0}{0}{0}{0}{0}{0}{0}-{0}{0}{0}{0}-{0}{0}{0}{0}-{0}{0}{0}{0}-{0}{0}{0}{0}{0}{0}{0}{0}{0}{0}{0}{0}" -f $index.ToString('x'))
            if ($key -cin @('apim', 'workerVm')) {
                $resource.identity = @{ type = 'SystemAssigned'; tenantId = $script:configuration.tenantId; principalId = $principal }
            }
            if ($key -ceq 'gatewayIdentity') {
                $resource.properties = @{ tenantId = $script:configuration.tenantId; principalId = $principal }
            }
            if ($key -ceq 'keyVault') {
                $resource.properties = @{ tenantId = $script:configuration.tenantId; enableRbacAuthorization = $true }
            }
            if ($key -ceq 'dnsZone') { $resource.properties = @{ zoneType = 'Public' } }
            $script:arm[$id] = $resource
            $index++
        }
        $script:configuration | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:configPath
    }

    function Invoke-TestLabPreview {
        param($Stage = 'Identity')
        $script:parameters.Stage = $Stage
        $null = Get-LabBootstrapSnapshot $script:configuration $Stage
        $result = Invoke-LabBootstrap @script:parameters -Mode Preview
        $result.code | Should -BeExactly 'LAB_PREVIEW_READY'
        return Get-LabDigest ([System.IO.File]::ReadAllText($script:planPath))
    }
}

Describe 'Owner-only synthetic lab bootstrap' {
    BeforeEach {
        $script:configuration = Get-Content -LiteralPath (Join-Path $script:labRoot 'infra\live-validation-lab\bootstrap.sample.json') -Raw |
            ConvertFrom-Json -AsHashtable
        $script:target = Get-LabTarget $script:configuration
        $script:privateRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:privateRoot | Out-Null
        $script:configPath = Join-Path $script:privateRoot 'private-config.json'
        $script:planPath = Join-Path $script:privateRoot 'private-plan.json'
        $script:configuration | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:configPath
        $script:parameters = @{
            ConfigPath = $script:configPath; PlanPath = $script:planPath; Stage = 'Identity'
            OwnerAuthorized = $true; MicrosoftOwnedTestEnvironment = $true
        }
        $script:context = @{
            tenant = $script:configuration.tenantId; subscription = $script:configuration.subscriptionId
            cloud = 'AzureCloud'; accountType = 'User'
        }
        $script:arm = @{}
        $script:github = @{}
        $script:federations = @()
        $script:roles = [System.Collections.Generic.List[object]]::new()
        $script:writes = [System.Collections.Generic.List[object]]::new()
        $script:ignoreBypass = $false
        $script:failNextWrite = $false
        foreach ($group in @($script:target.lab, $script:target.identityGroup)) {
            $script:arm[$group] = Get-TestLabResource $group 'Microsoft.Resources/resourceGroups'
        }
        $script:github[$script:target.repository] = @{
            id = 123L; full_name = $script:configuration.repository; default_branch = 'main'
            fork = $false; permissions = @{ admin = $true }
        }
        Mock Get-LabOwnerContext { return $script:context }
        Mock Invoke-LabArmRequest {
            param($Method, $Path, $Body)
            $bare = $Path.Split('?')[0]
            if ($Method -ceq 'GET') {
                if ($bare.EndsWith('/providers/Microsoft.Authorization/roleAssignments')) {
                    $decoded = [uri]::UnescapeDataString($Path)
                    $principal = [regex]::Match($decoded, "principalId eq '([^']+)'").Groups[1].Value
                    return @{ value = @($script:roles | Where-Object { $_.properties.principalId -ceq $principal }) }
                }
                if ($bare.EndsWith('/federatedIdentityCredentials')) { return @{ value = @($script:federations) } }
                return $script:arm[$bare]
            }
            $script:writes.Add(@{ system = 'arm'; path = $Path; body = $Body })
            if ($script:failNextWrite) { $script:failNextWrite = $false; throw 'SYNTHETIC_PRIVATE_CANARY' }
            if ($bare -ceq $script:target.identity) { Initialize-TestLabIdentity; return }
            if ($bare -ceq $script:target.federation) {
                $script:federations = @(@{ id = $bare; properties = $Body.properties }); return
            }
            if ($bare.Contains('/providers/Microsoft.Authorization/roleAssignments/')) {
                $scope = $bare.Split('/providers/Microsoft.Authorization/roleAssignments/')[0]
                $properties = @{} + $Body.properties
                $properties.scope = $scope
                $script:roles.Add(@{ properties = $properties })
                return
            }
            throw 'UnexpectedSyntheticArmWrite'
        }
        Mock Invoke-LabGitHubRequest {
            param($Method, $Path, $Body)
            $bare = $Path.Split('?')[0]
            if ($Method -ceq 'GET') { return $script:github[$bare] }
            $script:writes.Add(@{ system = 'github'; path = $Path; body = $Body })
            if ($script:failNextWrite) { $script:failNextWrite = $false; throw 'SYNTHETIC_PRIVATE_CANARY' }
            if ($bare -ceq $script:target.environment) {
                Initialize-TestLabEnvironment
                $script:github["$bare/deployment-branch-policies"] = @{ total_count = 0; branch_policies = @() }
                $script:github[$bare].can_admins_bypass = $script:ignoreBypass
                return
            }
            if ($bare.EndsWith('/deployment-branch-policies')) {
                $script:github[$bare] = @{ total_count = 1; branch_policies = @(@{ name = $Body.name; type = $Body.type }) }
                return
            }
            if ($bare.EndsWith('/variables')) { $script:github["$bare/$($Body.name)"] = @{} + $Body; return }
            throw 'UnexpectedSyntheticGitHubWrite'
        }
    }

    It 'previews without writes, binds an approval and creates only exact desired grants/trust' {
        $digest = Invoke-TestLabPreview
        $script:writes.Count | Should -Be 0
        $plan = Get-Content -LiteralPath $script:planPath -Raw | ConvertFrom-Json -AsHashtable
        $plan.actions.code | Should -Contain 'CreateDeploymentRoleAfterIdentity'
        $federation = @($plan.actions | Where-Object code -CEQ 'CreateFederation')[0]
        $federation.body.properties.subject | Should -BeExactly 'repo:synthetic-org/synthetic-lab:environment:lab'
        $federation.body.properties.audiences | Should -Be @('api://AzureADTokenExchange')
        $result = Invoke-LabBootstrap @script:parameters -Mode Apply -ApprovedPlanSha256 $digest
        $null = Get-LabBootstrapSnapshot $script:configuration Identity
        $result.code | Should -BeExactly 'LAB_APPLIED'
        $script:roles.Count | Should -Be 1
        $script:roles[0].properties.scope | Should -BeExactly $script:target.lab
        $script:roles[0].properties.roleDefinitionId | Should -Match '/b24988ac-6180-42a0-ab88-20f7382dd24c$'
        @($script:github.Keys | Where-Object { $_ -match '/variables/' }).Count | Should -Be 6
        $script:github["$($script:target.environment)/variables/AZURE_CLIENT_ID"].value |
            Should -BeExactly '33333333-3333-3333-3333-333333333333'
    }

    It 'makes a repeated fresh preview/apply a no-op without duplicate roles or federation' {
        Initialize-TestLabComplete
        $digest = Invoke-TestLabPreview
        (Invoke-LabBootstrap @script:parameters -Mode Apply -ApprovedPlanSha256 $digest).code | Should -BeExactly 'LAB_APPLIED'
        $script:writes.Count | Should -Be 0
        $script:roles.Count | Should -Be 1
        $script:federations.Count | Should -Be 1
    }

    It 'does not overwrite a private preview' {
        $null = Invoke-TestLabPreview
        $before = [System.IO.File]::ReadAllText($script:planPath)
        (Invoke-LabBootstrap @script:parameters -Mode Preview).code | Should -BeExactly 'LAB_APPROVAL_INVALID'
        [System.IO.File]::ReadAllText($script:planPath) | Should -BeExactly $before
        $script:writes.Count | Should -Be 0
    }

    It 'refuses missing owner acknowledgement before external calls' {
        $script:parameters.OwnerAuthorized = $false
        (Invoke-LabBootstrap @script:parameters -Mode Preview).code | Should -BeExactly 'LAB_OWNER_ACK_REQUIRED'
        Should -Invoke Get-LabOwnerContext -Times 0
    }

    It 'refuses an unapproved, tampered or expired plan' -ForEach @(
        @{ Case = 'unapproved' }, @{ Case = 'tampered' }, @{ Case = 'expired' }
    ) {
        $digest = Invoke-TestLabPreview
        if ($Case -ceq 'unapproved') { $digest = '0' * 64 }
        if ($Case -ceq 'tampered') { Add-Content -LiteralPath $script:planPath -Value ' ' }
        if ($Case -ceq 'expired') {
            $plan = Get-Content -LiteralPath $script:planPath -Raw | ConvertFrom-Json -AsHashtable
            $plan.issuedAt = [DateTimeOffset]::UtcNow.AddHours(-2).ToUnixTimeSeconds()
            $plan.expiresAt = $plan.issuedAt + 1800
            $plan | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $script:planPath
            $digest = Get-LabDigest ([System.IO.File]::ReadAllText($script:planPath))
        }
        (Invoke-LabBootstrap @script:parameters -Mode Apply -ApprovedPlanSha256 $digest).code | Should -BeExactly 'LAB_APPROVAL_INVALID'
        $script:writes.Count | Should -Be 0
    }

    It 'refuses a changed configuration, stage or fresh state' -ForEach @(
        @{ Case = 'config' }, @{ Case = 'stage' }, @{ Case = 'state' }
    ) {
        $digest = Invoke-TestLabPreview
        if ($Case -ceq 'config') { Add-Content -LiteralPath $script:configPath -Value ' ' }
        if ($Case -ceq 'stage') { $script:parameters.Stage = 'Runtime' }
        if ($Case -ceq 'state') { Initialize-TestLabIdentity }
        $result = Invoke-LabBootstrap @script:parameters -Mode Apply -ApprovedPlanSha256 $digest
        $result.code | Should -BeIn @('LAB_APPROVAL_INVALID', 'LAB_STATE_CHANGED')
        $script:writes.Count | Should -Be 0
    }

    It 'rejects unknown fields, duplicate JSON, credentials, wrong environment and overlapping groups' -ForEach @(
        @{ Case = 'unknown' }, @{ Case = 'duplicate' }, @{ Case = 'secret' },
        @{ Case = 'environment' }, @{ Case = 'sameGroup' }, @{ Case = 'repositoryPath' }
    ) {
        switch ($Case) {
            'unknown' { $script:configuration.customRoles = @('Owner') }
            'secret' { $script:configuration.clientSecret = 'SYNTHETIC_PRIVATE_CANARY' }
            'environment' { $script:configuration.environment = 'production' }
            'sameGroup' { $script:configuration.identityResourceGroup = $script:configuration.labResourceGroup }
            'repositoryPath' { $script:parameters.ConfigPath = Join-Path $script:labRoot 'infra\live-validation-lab\bootstrap.sample.json' }
        }
        $text = $script:configuration | ConvertTo-Json -Depth 10
        if ($Case -ceq 'duplicate') { $text = $text.Replace('"schemaVersion": "1.0"', '"schemaVersion": "1.0", "SchemaVersion": "1.0"') }
        Set-Content -LiteralPath $script:configPath -Value $text
        (Invoke-LabBootstrap @script:parameters -Mode Preview).code | Should -BeExactly 'LAB_CONFIG_INVALID'
        Should -Invoke Get-LabOwnerContext -Times 0
    }

    It 'refuses incorrect tenant, subscription, cloud or non-owner account context' -ForEach @(
        @{ Key = 'tenant'; Value = 'wrong' }, @{ Key = 'subscription'; Value = 'wrong' },
        @{ Key = 'cloud'; Value = 'AzureUSGovernment' }, @{ Key = 'accountType'; Value = 'ServicePrincipal' }
    ) {
        $script:context[$Key] = $Value
        (Invoke-LabBootstrap @script:parameters -Mode Preview).code | Should -BeExactly 'LAB_PREFLIGHT_FAILED'
        $script:writes.Count | Should -Be 0
    }

    It 'refuses mismatched federation, ownership, variables or broader deployment roles' -ForEach @(
        @{ Case = 'subject' }, @{ Case = 'audience' }, @{ Case = 'issuer' }, @{ Case = 'extraTrust' },
        @{ Case = 'ownership' }, @{ Case = 'variable' }, @{ Case = 'broadScope' }, @{ Case = 'broadRole' }
    ) {
        Initialize-TestLabComplete
        switch ($Case) {
            'subject' { $script:federations[0].properties.subject = 'repo:synthetic-org/synthetic-lab:pull_request' }
            'audience' { $script:federations[0].properties.audiences += 'wrong' }
            'issuer' { $script:federations[0].properties.issuer = 'https://issuer.invalid' }
            'extraTrust' { $script:federations += $script:federations[0] }
            'ownership' { $script:arm[$script:target.identity].tags.apimAssessmentLab = 'unrelated' }
            'variable' { $script:github["$($script:target.environment)/variables/LAB_PROFILE"].value = 'wrong' }
            'broadScope' { $script:roles[0].properties.scope = $script:target.subscription }
            'broadRole' { $script:roles[0].properties.roleDefinitionId = "$($script:target.subscription)/providers/Microsoft.Authorization/roleDefinitions/8e3af657-a8ff-443c-a75c-2fe8c4bcb635" }
        }
        (Invoke-LabBootstrap @script:parameters -Mode Preview).code | Should -BeExactly 'LAB_PREFLIGHT_FAILED'
        $script:writes.Count | Should -Be 0
    }

    It 'refuses weak or unsupported environment protection and nonexact branches' -ForEach @(
        @{ Case = 'selfReview' }, @{ Case = 'bypass' }, @{ Case = 'missingBypass' },
        @{ Case = 'reviewer' }, @{ Case = 'tag' }, @{ Case = 'wildcard' }, @{ Case = 'extraBranch' }
    ) {
        Initialize-TestLabComplete
        $environment = $script:github[$script:target.environment]
        $policies = $script:github["$($script:target.environment)/deployment-branch-policies"]
        switch ($Case) {
            'selfReview' { $environment.protection_rules[0].prevent_self_review = $false }
            'bypass' { $environment.can_admins_bypass = $true }
            'missingBypass' { $environment.Remove('can_admins_bypass') }
            'reviewer' { $environment.protection_rules[0].reviewers[0].reviewer.id = 54321L }
            'tag' { $policies.branch_policies[0].type = 'tag' }
            'wildcard' { $policies.branch_policies[0].name = '*' }
            'extraBranch' { $policies.total_count = 2; $policies.branch_policies += @{ name = 'feature'; type = 'branch' } }
        }
        (Invoke-LabBootstrap @script:parameters -Mode Preview).code | Should -BeExactly 'LAB_PREFLIGHT_FAILED'
        $script:writes.Count | Should -Be 0
    }

    It 'never activates federation when GitHub ignores the no-admin-bypass control' {
        $digest = Invoke-TestLabPreview
        $script:ignoreBypass = $true
        (Invoke-LabBootstrap @script:parameters -Mode Apply -ApprovedPlanSha256 $digest).code |
            Should -BeExactly 'LAB_APPLY_INCOMPLETE'
        $script:federations.Count | Should -Be 0
        $script:roles.Count | Should -Be 0
    }

    It 'reports incomplete mutation with only a fixed outcome and permits a fresh retry' {
        $digest = Invoke-TestLabPreview
        $script:failNextWrite = $true
        $output = @(Invoke-LabBootstrap @script:parameters -Mode Apply -ApprovedPlanSha256 $digest *>&1)
        ($output | ConvertTo-Json -Depth 10) | Should -Not -Match 'SYNTHETIC_PRIVATE_CANARY'
        $output[0].code | Should -BeExactly 'LAB_APPLY_INCOMPLETE'
        $script:parameters.PlanPath = Join-Path $script:privateRoot 'retry-plan.json'
        (Invoke-LabBootstrap @script:parameters -Mode Preview).code | Should -BeExactly 'LAB_PREVIEW_READY'
    }

    It 'suppresses external warning, information, verbose, debug, error and unexpected success streams' {
        Mock Get-LabOwnerContext {
            Write-Warning 'SYNTHETIC_PRIVATE_CANARY'
            Write-Information 'SYNTHETIC_PRIVATE_CANARY' -InformationAction Continue
            Write-Verbose 'SYNTHETIC_PRIVATE_CANARY' -Verbose
            Write-Debug 'SYNTHETIC_PRIVATE_CANARY' -Debug
            Write-Error 'SYNTHETIC_PRIVATE_CANARY' -ErrorAction Continue
            'SYNTHETIC_PRIVATE_CANARY'
            throw 'SYNTHETIC_PRIVATE_CANARY'
        }
        $output = @(Invoke-LabBootstrap @script:parameters -Mode Preview *>&1)
        $output.Count | Should -Be 1
        $output[0].code | Should -BeExactly 'LAB_PREFLIGHT_FAILED'
        ($output | ConvertTo-Json -Depth 10) | Should -Not -Match 'SYNTHETIC_PRIVATE_CANARY'
        $script:writes.Count | Should -Be 0
    }

    It 'returns NotReady rather than passing a missing owner prerequisite or future foundation' -ForEach @(
        @{ Case = 'group' }, @{ Case = 'runtimeConfig' }, @{ Case = 'runtimeResource' }
    ) {
        if ($Case -ceq 'group') { $script:arm.Remove($script:target.lab) }
        else {
            Initialize-TestLabComplete
            $script:parameters.Stage = 'Runtime'
            if ($Case -ceq 'runtimeResource') { Initialize-TestLabRuntime; $script:arm.Remove("$($script:target.lab)/providers/Microsoft.Compute/virtualMachines/vm-synthetic-worker") }
        }
        (Invoke-LabBootstrap @script:parameters -Mode Preview).code | Should -BeExactly 'LAB_NOT_READY'
        $script:writes.Count | Should -Be 0
    }

    It 'previews and applies six fixed resource-scoped runtime roles, then makes repeat apply a no-op' {
        Initialize-TestLabComplete
        Initialize-TestLabRuntime
        $digest = Invoke-TestLabPreview Runtime
        $plan = Get-Content -LiteralPath $script:planPath -Raw | ConvertFrom-Json -AsHashtable
        $plan.actions.Count | Should -Be 6
        foreach ($action in $plan.actions) {
            $action.code | Should -BeExactly 'CreateRole'
            $action.path | Should -Match '/providers/(Microsoft.KeyVault/vaults|Microsoft.Network/dnsZones|Microsoft.Insights/components)/'
            $action.body.properties.roleDefinitionId | Should -Not -Match 'b24988ac|8e3af657|00482a5a'
        }
        (Invoke-LabBootstrap @script:parameters -Mode Apply -ApprovedPlanSha256 $digest).code | Should -BeExactly 'LAB_APPLIED'
        $script:roles.Count | Should -Be 7
        $script:parameters.PlanPath = Join-Path $script:privateRoot 'runtime-repeat.json'
        $script:planPath = $script:parameters.PlanPath
        $digest = Invoke-TestLabPreview Runtime
        $before = $script:writes.Count
        (Invoke-LabBootstrap @script:parameters -Mode Apply -ApprovedPlanSha256 $digest).code | Should -BeExactly 'LAB_APPLIED'
        $script:writes.Count | Should -Be $before
    }

    It 'refuses unowned runtime resources, shared principals and access-policy vaults' -ForEach @(
        @{ Case = 'ownership' }, @{ Case = 'principal' }, @{ Case = 'vault' }, @{ Case = 'broadRuntimeRole' }
    ) {
        Initialize-TestLabComplete
        Initialize-TestLabRuntime
        $script:parameters.Stage = 'Runtime'
        $vault = $script:arm["$($script:target.lab)/providers/Microsoft.KeyVault/vaults/kv-synthetic"]
        switch ($Case) {
            'ownership' { $vault.tags.apimAssessmentLab = 'unrelated' }
            'vault' { $vault.properties.enableRbacAuthorization = $false }
            'principal' {
                $script:arm["$($script:target.lab)/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-synthetic-gateway"].properties.principalId =
                    $script:arm["$($script:target.lab)/providers/Microsoft.Compute/virtualMachines/vm-synthetic-worker"].identity.principalId
            }
            'broadRuntimeRole' {
                $script:roles.Add(@{ properties = @{
                            principalId = $script:arm["$($script:target.lab)/providers/Microsoft.ApiManagement/service/apim-synthetic"].identity.principalId
                            principalType = 'ServicePrincipal'; scope = $script:target.lab
                            roleDefinitionId = "$($script:target.subscription)/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
                        } })
            }
        }
        (Invoke-LabBootstrap @script:parameters -Mode Preview).code | Should -BeExactly 'LAB_PREFLIGHT_FAILED'
        $script:writes.Count | Should -Be 0
    }

    It 'rejects a foreign or cross-scope ARM paging link without following it' {
        Mock Invoke-LabArmRequest {
            return @{ value = @(); nextLink = 'https://foreign.invalid/subscriptions/anything?api-version=2022-04-01' }
        }
        { Get-LabArmCollection "$($script:target.subscription)/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" } |
            Should -Throw 'LAB_STATE_CONFLICT'
        Should -Invoke Invoke-LabArmRequest -Times 1
    }

    It 'follows bounded same-scope ARM paging without dropping the principal filter' {
        $script:collectionPath = "$($script:target.subscription)/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&`$filter=principalId%20eq%20%2744444444-4444-4444-4444-444444444444%27"
        Mock Invoke-LabArmRequest {
            param($Path)
            if ($Path.Contains('$skiptoken')) { return @{ value = @(@{ id = 'second' }) } }
            return @{ value = @(@{ id = 'first' }); nextLink = "https://management.azure.com$($script:collectionPath)&`$skiptoken=next" }
        }
        @(Get-LabArmCollection $script:collectionPath).id | Should -Be @('first', 'second')
        Should -Invoke Invoke-LabArmRequest -Times 2
    }

    It 'refuses an approval after a runtime principal is replaced' {
        Initialize-TestLabComplete
        Initialize-TestLabRuntime
        $digest = Invoke-TestLabPreview Runtime
        $script:arm["$($script:target.lab)/providers/Microsoft.Compute/virtualMachines/vm-synthetic-worker"].identity.principalId =
            'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
        (Invoke-LabBootstrap @script:parameters -Mode Apply -ApprovedPlanSha256 $digest).code |
            Should -BeExactly 'LAB_STATE_CHANGED'
        $script:writes.Count | Should -Be 0
    }

    It 'rejects a private file link before reading configuration or making external calls' {
        Mock Get-Item { return @{ Attributes = [System.IO.FileAttributes]::ReparsePoint } } `
            -ParameterFilter { $LiteralPath -ceq $script:configPath }
        (Invoke-LabBootstrap @script:parameters -Mode Preview).code | Should -BeExactly 'LAB_CONFIG_INVALID'
        Should -Invoke Get-LabOwnerContext -Times 0
    }

    It 'refuses expiry or a changed owner context immediately before a write' -ForEach @(
        @{ Case = 'expired' }, @{ Case = 'context' }
    ) {
        $snapshot = Get-LabBootstrapSnapshot $script:configuration Identity
        $expires = [DateTimeOffset]::UtcNow.AddMinutes(30).ToUnixTimeSeconds()
        if ($Case -ceq 'expired') { $expires = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToUnixTimeSeconds() }
        else { $script:context.subscription = 'wrong' }
        { Invoke-LabBootstrapAction $script:configuration $snapshot $expires } | Should -Throw 'LAB_STATE_CONFLICT'
        $script:writes.Count | Should -Be 0
    }
}

Describe 'Bootstrap transport output boundary' {
    BeforeAll {
        function Invoke-AzRestMethod {
            param($Path, $Method, $Payload)
            $null = $Path, $Method, $Payload
            throw 'UnmockedAzureForbidden'
        }
    }

    It 'parses gh HTTP responses without emitting stderr and returns missing resources only for 404' {
        Mock Invoke-LabGhProcess {
            return @{ exitCode = 0; stdout = "HTTP/2.0 200 OK`r`ncontent-type: application/json`r`n`r`n{`"id`":123}" }
        }
        (Invoke-LabGitHubRequest GET 'repos/synthetic-org/synthetic-lab' $null).id | Should -Be 123
        Mock Invoke-LabGhProcess { return @{ exitCode = 1; stdout = "HTTP/2.0 404 Not Found`n`n{}" } }
        Invoke-LabGitHubRequest GET 'repos/synthetic-org/synthetic-lab/environments/lab' $null | Should -BeNullOrEmpty
        Mock Invoke-LabGhProcess { return @{ exitCode = 1; stdout = "HTTP/2.0 403 Forbidden`n`nSYNTHETIC_PRIVATE_CANARY" } }
        { Invoke-LabGitHubRequest GET 'repos/synthetic-org/synthetic-lab' $null } | Should -Throw 'LAB_GITHUB_FAILED'
    }

    It 'refuses secret URLs before invoking ARM' -ForEach @(
        @{ Suffix = 'listSecrets' }, @{ Suffix = 'listValue' }, @{ Suffix = 'listKeys' },
        @{ Suffix = 'secrets/value' }, @{ Suffix = 'regenerate' }, @{ Suffix = 'token' }
    ) {
        Mock Invoke-AzRestMethod { throw 'MustNotRun' }
        { Invoke-LabArmRequest GET "/subscriptions/22222222-2222-2222-2222-222222222222/$Suffix" $null } |
            Should -Throw 'LAB_ARM_FAILED'
        Should -Invoke Invoke-AzRestMethod -Times 0
    }

    It 'suppresses every non-success Az stream and never forwards exception text' {
        Mock Invoke-AzRestMethod {
            Write-Warning 'SYNTHETIC_PRIVATE_CANARY'
            Write-Information 'SYNTHETIC_PRIVATE_CANARY' -InformationAction Continue
            Write-Verbose 'SYNTHETIC_PRIVATE_CANARY' -Verbose
            Write-Debug 'SYNTHETIC_PRIVATE_CANARY' -Debug
            Write-Error 'SYNTHETIC_PRIVATE_CANARY' -ErrorAction Continue
            throw 'SYNTHETIC_PRIVATE_CANARY'
        }
        $output = try {
            Invoke-LabArmRequest GET '/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-synthetic-lab?api-version=2021-04-01' $null *>&1
        }
        catch { $_.Exception.Message }
        @($output).Count | Should -Be 1
        $output | Should -BeExactly 'LAB_ARM_FAILED'
    }

    It 'selects the first application match, bounds native streams and discards stderr without live network access' {
        $script:testPwsh = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
        Mock Get-Command {
            return @(@{ Source = $script:testPwsh }, @{ Source = 'unused-synthetic-application' })
        } -ParameterFilter { $Name -ceq 'gh' }
        $output = @(Invoke-LabGhProcess -Arguments @('-NoProfile', '-Command',
                '[Console]::Error.WriteLine("SYNTHETIC_PRIVATE_CANARY"); [Console]::Out.Write("safe")') -InputText $null *>&1)
        $output.Count | Should -Be 1
        $output[0].stdout | Should -BeExactly 'safe'
        ($output | ConvertTo-Json) | Should -Not -Match 'SYNTHETIC_PRIVATE_CANARY'
        { Invoke-LabGhProcess -Arguments @('-NoProfile', '-Command',
                '[Console]::Error.Write("x" * 20000)') -InputText $null -MaxOutputBytes 128 } |
            Should -Throw 'LAB_GITHUB_FAILED'
        { Invoke-LabGhProcess -Arguments @('-NoProfile', '-Command', 'Start-Sleep -Seconds 20') `
                -InputText $null -TimeoutSeconds 1 } | Should -Throw 'LAB_GITHUB_FAILED'
    }

    It 'emits only a fixed refusal and nonzero exit from the owner entry point without consent' {
        $script:testPwsh = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
        Mock Get-Command { return @{ Source = $script:testPwsh } } -ParameterFilter { $Name -ceq 'gh' }
        $entry = Join-Path $script:labRoot 'scripts\lab\Invoke-LabBootstrap.ps1'
        $result = Invoke-LabGhProcess -Arguments @('-NoProfile', '-File', $entry,
            '-ConfigPath', (Join-Path $TestDrive 'never-read.json'), '-PlanPath', (Join-Path $TestDrive 'never-write.json')) -InputText $null
        $result.exitCode | Should -Be 1
        $result.stdout.Trim() | Should -BeExactly 'LAB_OWNER_ACK_REQUIRED'
    }
}
