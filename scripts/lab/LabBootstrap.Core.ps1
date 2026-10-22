#Requires -Version 7.4
Set-StrictMode -Version Latest

function Assert-LabCondition {
    [CmdletBinding()]
    param([Parameter(Mandatory)][bool] $Condition)
    if (-not $Condition) { throw [System.InvalidOperationException]::new('LAB_STATE_CONFLICT') }
}

function ConvertTo-LabCanonicalValue {
    [CmdletBinding()]
    param([AllowNull()][object] $Value)
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        [string[]]$keys = @($Value.Keys)
        [Array]::Sort($keys, [System.StringComparer]::Ordinal)
        foreach ($key in $keys) { $result[$key] = ConvertTo-LabCanonicalValue $Value[$key] }
        return $result
    }
    if ($Value -is [array] -or $Value -is [System.Collections.IList]) {
        $result = @(
            foreach ($item in $Value) { ConvertTo-LabCanonicalValue $item }
        )
        return ,$result
    }
    return $Value
}

function Get-LabDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
}

function Get-LabObjectDigest {
    [CmdletBinding()]
    param([AllowNull()][object] $Value)
    return Get-LabDigest (ConvertTo-Json (ConvertTo-LabCanonicalValue $Value) -Depth 40 -Compress)
}

function Assert-LabOwnerContext {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Config)
    $context = Get-LabOwnerContext
    Assert-LabCondition ($context.tenant -ceq $Config.tenantId -and
        $context.subscription -ceq $Config.subscriptionId -and $context.cloud -ceq 'AzureCloud' -and
        $context.accountType -ceq 'User')
}

function Read-LabJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Text)
    $document = $null
    try {
        $options = [System.Text.Json.JsonDocumentOptions]::new()
        $options.MaxDepth = 40
        $document = [System.Text.Json.JsonDocument]::Parse($Text, $options)
        $stack = [System.Collections.Generic.Stack[System.Text.Json.JsonElement]]::new()
        $stack.Push($document.RootElement)
        while ($stack.Count -gt 0) {
            $element = $stack.Pop()
            if ($element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
                $names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                foreach ($property in $element.EnumerateObject()) {
                    if (-not $names.Add($property.Name)) { throw 'DuplicateJsonMember' }
                    $stack.Push($property.Value)
                }
            }
            elseif ($element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
                foreach ($item in $element.EnumerateArray()) { $stack.Push($item) }
            }
        }
        return ConvertFrom-Json $Text -AsHashtable -Depth 40 -ErrorAction Stop
    }
    finally { if ($null -ne $document) { $document.Dispose() } }
}

function Get-LabPrivatePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    if (-not [System.IO.Path]::IsPathFullyQualified($Path)) { throw 'PrivatePathRequired' }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetFullPath((Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $separator = [System.IO.Path]::DirectorySeparatorChar
    if ($fullPath.Equals($root, $comparison) -or $fullPath.StartsWith("$root$separator", $comparison) -or
        $root.StartsWith("$fullPath$separator", $comparison)) { throw 'PrivatePathOverlapsRepository' }
    $current = $fullPath
    while (-not [string]::IsNullOrEmpty($current)) {
        if (Test-Path -LiteralPath $current -ErrorAction Stop) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'LinkedPrivatePath'
            }
        }
        $current = [System.IO.Path]::GetDirectoryName($current)
    }
    if (-not (Test-Path -LiteralPath ([System.IO.Path]::GetDirectoryName($fullPath)) -PathType Container)) {
        throw 'PrivateDirectoryRequired'
    }
    return $fullPath
}

function Read-LabPrivateText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    $file = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($file.PSIsContainer -or $file.Length -gt 1048576) { throw 'PrivateFileInvalid' }
    return [System.IO.File]::ReadAllText($Path)
}

function Get-LabTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Config)
    $subscription = "/subscriptions/$($Config.subscriptionId)"
    $lab = "$subscription/resourceGroups/$($Config.labResourceGroup)"
    $identityGroup = "$subscription/resourceGroups/$($Config.identityResourceGroup)"
    $identity = "$identityGroup/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$($Config.deploymentIdentityName)"
    return @{
        subscription = $subscription; lab = $lab; identityGroup = $identityGroup; identity = $identity
        federation = "$identity/federatedIdentityCredentials/github-lab"
        repository = "repos/$($Config.repository)"
        environment = "repos/$($Config.repository)/environments/lab"
        subject = "repo:$($Config.repository):environment:lab"
    }
}

function Get-LabArmCollection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    $original = [uri]"https://management.azure.com$Path"
    $next = $Path
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $items = [System.Collections.Generic.List[object]]::new()
    for ($page = 0; $page -lt 50; $page++) {
        Assert-LabCondition ($seen.Add($next))
        $response = Invoke-LabArmRequest -Method GET -Path $next -Body $null
        Assert-LabCondition ($null -ne $response -and $response.value -is [array])
        foreach ($item in $response.value) { $items.Add($item) }
        Assert-LabCondition ($items.Count -le 5000)
        if (-not $response.Contains('nextLink') -or [string]::IsNullOrEmpty($response.nextLink)) {
            return $items.ToArray()
        }
        $link = [uri]$response.nextLink
        Assert-LabCondition ($link.IsAbsoluteUri -and $link.Scheme -ceq 'https' -and
            $link.Host -ceq 'management.azure.com' -and $link.Port -eq 443 -and
            $link.UserInfo -ceq '' -and $link.Fragment -ceq '' -and
            $link.AbsolutePath -ceq $original.AbsolutePath)
        $query = @{}
        foreach ($part in $link.Query.TrimStart('?').Split('&')) {
            $pair = $part.Split('=', 2)
            $key = [uri]::UnescapeDataString($pair[0])
            Assert-LabCondition ($pair.Count -eq 2 -and -not $query.ContainsKey($key) -and
                $key -cin @('api-version', '$filter', '$skiptoken'))
            $query[$key] = [uri]::UnescapeDataString($pair[1].Replace('+', ' '))
        }
        foreach ($part in $original.Query.TrimStart('?').Split('&')) {
            $pair = $part.Split('=', 2)
            $key = [uri]::UnescapeDataString($pair[0])
            Assert-LabCondition ($query.ContainsKey($key) -and
                $query[$key] -ceq [uri]::UnescapeDataString($pair[1].Replace('+', ' ')))
        }
        if (-not $original.Query.Contains('$filter')) { Assert-LabCondition (-not $query.ContainsKey('$filter')) }
        $next = $link.PathAndQuery
    }
    throw [System.InvalidOperationException]::new('LAB_STATE_CONFLICT')
}

function Assert-LabOwnedResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Resource,
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][string] $Type,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Config,
        [switch] $GlobalLocation
    )
    Assert-LabCondition ($Resource.id -ieq $Id -and $Resource.type -ieq $Type -and
        $Resource.tags -is [System.Collections.IDictionary] -and
        $Resource.tags['apimAssessmentLab'] -ceq $Config.labId)
    $expectedLocation = if ($GlobalLocation) { 'global' } else { $Config.location }
    Assert-LabCondition ($Resource.location -ieq $expectedLocation)
}

function Get-LabEnvironmentDefinition {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Config)
    return @{
        wait_timer = 0; prevent_self_review = $true; reviewers = @($Config.reviewers)
        can_admins_bypass = $false
        deployment_branch_policy = @{ protected_branches = $false; custom_branch_policies = $true }
    }
}

function Assert-LabEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Environment,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Config
    )
    Assert-LabCondition ($Environment.name -ceq 'lab' -and
        $Environment.can_admins_bypass -is [bool] -and -not $Environment.can_admins_bypass -and
        $Environment.deployment_branch_policy.protected_branches -is [bool] -and
        -not $Environment.deployment_branch_policy.protected_branches -and
        $Environment.deployment_branch_policy.custom_branch_policies -is [bool] -and
        $Environment.deployment_branch_policy.custom_branch_policies)
    $rules = @($Environment.protection_rules | Where-Object type -CEQ 'required_reviewers')
    Assert-LabCondition ($rules.Count -eq 1 -and $rules[0].prevent_self_review -is [bool] -and
        $rules[0].prevent_self_review)
    $actual = @($rules[0].reviewers | ForEach-Object { "$($_.type):$($_.reviewer.id)" } | Sort-Object)
    $expected = @($Config.reviewers | ForEach-Object { "$($_.type):$($_.id)" } | Sort-Object)
    Assert-LabCondition ((Get-LabObjectDigest $actual) -ceq (Get-LabObjectDigest $expected))
    foreach ($rule in $Environment.protection_rules) {
        Assert-LabCondition ($rule.type -cin @('required_reviewers', 'wait_timer', 'branch_policy'))
        if ($rule.type -ceq 'wait_timer') { Assert-LabCondition ($rule.wait_timer -eq 0) }
    }
}

function Assert-LabBranchPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Policies)
    Assert-LabCondition ($Policies.total_count -eq 1 -and @($Policies.branch_policies).Count -eq 1 -and
        $Policies.branch_policies[0].name -ceq 'main' -and $Policies.branch_policies[0].type -ceq 'branch')
}

function Get-LabPrincipalRole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Principal,
        [Parameter(Mandatory)][string] $Subscription
    )
    Assert-LabCondition ($Principal -cmatch '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$')
    $filter = [uri]::EscapeDataString("principalId eq '$Principal'")
    $roles = @(Get-LabArmCollection "$Subscription/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&`$filter=$filter")
    return @(
        foreach ($role in $roles) {
            Assert-LabCondition ($role.properties.principalId -ieq $Principal -and
                $role.properties.principalType -ceq 'ServicePrincipal')
            if ($role.properties.Contains('condition')) {
                Assert-LabCondition ([string]::IsNullOrEmpty($role.properties.condition))
            }
            @{
                scope = $role.properties.scope.ToLowerInvariant()
                role = $role.properties.roleDefinitionId.ToLowerInvariant()
                principal = $Principal
            }
        }
    )
}

function Add-LabRoleAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Principal,
        [Parameter(Mandatory)][string] $Subscription,
        [Parameter(Mandatory)][object[]] $Expected,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]] $Actions
    )
    $actual = @(Get-LabPrincipalRole -Principal $Principal -Subscription $Subscription)
    $allowed = @($Expected | ForEach-Object { "$($_.scope.ToLowerInvariant())|$($_.role.ToLowerInvariant())" })
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($role in $actual) {
        $key = "$($role.scope)|$($role.role)"
        Assert-LabCondition ($key -cin $allowed -and $seen.Add($key))
    }
    foreach ($role in $Expected) {
        $key = "$($role.scope.ToLowerInvariant())|$($role.role.ToLowerInvariant())"
        if ($seen.Contains($key)) { continue }
        $hash = Get-LabDigest "$Principal|$key"
        $assignment = [guid]::ParseExact($hash.Substring(0, 32), 'N').ToString()
        $Actions.Add(@{
                code = 'CreateRole'; system = 'arm'; method = 'PUT'
                path = "$($role.scope)/providers/Microsoft.Authorization/roleAssignments/$assignment`?api-version=2022-04-01"
                body = @{ properties = @{
                        principalId = $Principal; principalType = 'ServicePrincipal'; roleDefinitionId = $role.role
                    } }
            })
    }
    return ,@($actual | Sort-Object scope, role)
}

function Get-LabBootstrapSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Config,
        [Parameter(Mandatory)][ValidateSet('Identity', 'Runtime')][string] $Stage
    )
    $targets = Get-LabTarget $Config
    $actions = [System.Collections.Generic.List[object]]::new()
    $evidence = [ordered]@{}
    Assert-LabOwnerContext $Config
    foreach ($group in @($targets.lab, $targets.identityGroup)) {
        $resource = Invoke-LabArmRequest GET "$group`?api-version=2021-04-01" $null
        if ($null -eq $resource) { throw [System.InvalidOperationException]::new('LAB_NOT_READY') }
        Assert-LabOwnedResource -Resource $resource -Id $group -Type 'Microsoft.Resources/resourceGroups' -Config $Config
    }
    $repository = Invoke-LabGitHubRequest GET $targets.repository $null
    Assert-LabCondition ($null -ne $repository -and $repository.full_name -ceq $Config.repository -and
        $repository.default_branch -ceq 'main' -and $repository.fork -is [bool] -and
        -not $repository.fork -and $repository.permissions.admin -is [bool] -and $repository.permissions.admin -and
        $repository.id -is [long] -and $repository.id -gt 0)
    $evidence.repositoryId = $repository.id
    $environment = Invoke-LabGitHubRequest GET $targets.environment $null
    if ($null -eq $environment) {
        if ($Stage -ceq 'Runtime') { throw [System.InvalidOperationException]::new('LAB_NOT_READY') }
        $actions.Add(@{ code = 'CreateEnvironment'; system = 'github'; method = 'PUT'
                path = $targets.environment; body = Get-LabEnvironmentDefinition $Config })
        $actions.Add(@{ code = 'CreateBranchPolicy'; system = 'github'; method = 'POST'
                path = "$($targets.environment)/deployment-branch-policies"; body = @{ name = 'main'; type = 'branch' } })
        $evidence.environment = 'Absent'
    }
    else {
        Assert-LabEnvironment $environment $Config
        $policies = Invoke-LabGitHubRequest GET "$($targets.environment)/deployment-branch-policies?per_page=100" $null
        Assert-LabBranchPolicy $policies
        $evidence.environment = 'Protected'
    }
    $identity = Invoke-LabArmRequest GET "$($targets.identity)?api-version=2024-11-30" $null
    if ($null -eq $identity) {
        if ($Stage -ceq 'Runtime') { throw [System.InvalidOperationException]::new('LAB_NOT_READY') }
        $actions.Add(@{ code = 'CreateIdentity'; system = 'arm'; method = 'PUT'
                path = "$($targets.identity)?api-version=2024-11-30"
                body = @{ location = $Config.location; tags = @{ apimAssessmentLab = $Config.labId } } })
        $evidence.identity = 'Absent'
        $federations = @()
    }
    else {
        Assert-LabOwnedResource $identity $targets.identity 'Microsoft.ManagedIdentity/userAssignedIdentities' $Config
        Assert-LabCondition ($identity.properties.tenantId -ceq $Config.tenantId -and
            $identity.properties.clientId -cmatch '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$')
        $evidence.identity = @{
            clientId = $identity.properties.clientId; principalId = $identity.properties.principalId
        }
        $federations = @(Get-LabArmCollection "$($targets.identity)/federatedIdentityCredentials?api-version=2024-11-30")
        Assert-LabCondition ($federations.Count -le 1)
        Assert-LabCondition ($federations.Count -eq 0 -or $null -ne $environment)
        foreach ($federation in $federations) {
            Assert-LabCondition ($federation.id -ieq $targets.federation -and
                $federation.properties.issuer -ceq 'https://token.actions.githubusercontent.com' -and
                $federation.properties.subject -ceq $targets.subject -and
                @($federation.properties.audiences).Count -eq 1 -and
                $federation.properties.audiences[0] -ceq 'api://AzureADTokenExchange')
            Assert-LabCondition (-not $federation.properties.Contains('claimsMatchingExpression') -or
                $null -eq $federation.properties.claimsMatchingExpression)
        }
        $contributor = "$($targets.subscription)/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
        $evidence.deploymentRoles = Add-LabRoleAction $identity.properties.principalId $targets.subscription `
            @(@{ scope = $targets.lab; role = $contributor }) $actions
    }
    $evidence.federation = if ($federations.Count -eq 0) { 'Absent' } else { 'Exact' }
    if ($federations.Count -eq 0) {
        if ($Stage -ceq 'Runtime') { throw [System.InvalidOperationException]::new('LAB_NOT_READY') }
        $actions.Add(@{ code = 'CreateFederation'; system = 'arm'; method = 'PUT'
                path = "$($targets.federation)?api-version=2024-11-30"
                body = @{ properties = @{ issuer = 'https://token.actions.githubusercontent.com'
                        subject = $targets.subject; audiences = @('api://AzureADTokenExchange') } } })
    }
    $variables = [ordered]@{
        AZURE_CLIENT_ID = if ($null -eq $identity) { '<created-identity-client-id>' } else { $identity.properties.clientId }
        AZURE_TENANT_ID = $Config.tenantId; AZURE_SUBSCRIPTION_ID = $Config.subscriptionId
        AZURE_LOCATION = $Config.location; LAB_RESOURCE_GROUP = $Config.labResourceGroup; LAB_PROFILE = 'baseline'
    }
    $evidence.variables = [ordered]@{}
    foreach ($name in $variables.Keys) {
        $variable = if ($null -eq $environment) { $null } else {
            Invoke-LabGitHubRequest GET "$($targets.environment)/variables/$name" $null
        }
        if ($null -eq $variable) {
            if ($Stage -ceq 'Runtime') { throw [System.InvalidOperationException]::new('LAB_NOT_READY') }
            $actions.Add(@{ code = 'CreateVariable'; system = 'github'; method = 'POST'
                    path = "$($targets.environment)/variables"; body = @{ name = $name; value = $variables[$name] } })
            $evidence.variables[$name] = 'Absent'
        }
        else {
            Assert-LabCondition ($variable.name -ceq $name -and $variable.value -ceq $variables[$name])
            $evidence.variables[$name] = 'Exact'
        }
    }
    if ($null -eq $identity) {
        $actions.Add(@{ code = 'CreateDeploymentRoleAfterIdentity'; system = 'derived'
                scope = $targets.lab; role = 'b24988ac-6180-42a0-ab88-20f7382dd24c' })
    }
    if ($Stage -ceq 'Runtime') {
        Assert-LabCondition ($actions.Count -eq 0)
        if ($null -eq $Config.runtime) { throw [System.InvalidOperationException]::new('LAB_NOT_READY') }
        $runtime = Get-LabRuntimeSnapshot $Config $targets
        $evidence.runtime = $runtime.evidence
        foreach ($action in $runtime.actions) { $actions.Add($action) }
    }
    return @{ evidence = $evidence; actions = $actions.ToArray() }
}

function Get-LabRuntimeSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Config,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Targets
    )
    $definitions = [ordered]@{
        apim = @('Microsoft.ApiManagement/service', '2024-05-01')
        gatewayIdentity = @('Microsoft.ManagedIdentity/userAssignedIdentities', '2024-11-30')
        workerVm = @('Microsoft.Compute/virtualMachines', '2024-11-01')
        keyVault = @('Microsoft.KeyVault/vaults', '2024-11-01')
        dnsZone = @('Microsoft.Network/dnsZones', '2018-05-01')
        appInsights = @('Microsoft.Insights/components', '2020-02-02')
    }
    $resources = @{}
    $evidence = [ordered]@{}
    foreach ($key in $definitions.Keys) {
        $type, $version = $definitions[$key]
        $id = "$($Targets.lab)/providers/$type/$($Config.runtime[$key])"
        $resource = Invoke-LabArmRequest GET "$id`?api-version=$version" $null
        if ($null -eq $resource) { throw [System.InvalidOperationException]::new('LAB_NOT_READY') }
        Assert-LabOwnedResource -Resource $resource -Id $id -Type $type -Config $Config -GlobalLocation:($key -ceq 'dnsZone')
        $resources[$key] = $resource
        $evidence[$key] = @{ id = $id }
    }
    Assert-LabCondition ($resources.keyVault.properties.tenantId -ceq $Config.tenantId -and
        $resources.keyVault.properties.enableRbacAuthorization -is [bool] -and
        $resources.keyVault.properties.enableRbacAuthorization -and
        $resources.dnsZone.properties.zoneType -ceq 'Public')
    $principals = [ordered]@{}
    foreach ($key in @('apim', 'workerVm')) {
        Assert-LabCondition ($resources[$key].identity.type -ceq 'SystemAssigned' -and
            $resources[$key].identity.tenantId -ceq $Config.tenantId)
        $principals[$key] = $resources[$key].identity.principalId
    }
    Assert-LabCondition ($resources.gatewayIdentity.properties.tenantId -ceq $Config.tenantId)
    $principals.gatewayIdentity = $resources.gatewayIdentity.properties.principalId
    Assert-LabCondition (@($principals.Values | Sort-Object -Unique).Count -eq 3)
    $deploymentId = "$($Targets.identity)?api-version=2024-11-30"
    $deployment = Invoke-LabArmRequest GET $deploymentId $null
    Assert-LabCondition ($deployment.properties.principalId -cnotin @($principals.Values))
    $evidence.principals = $principals
    $roles = @{
        secretsUser = '4633458b-17de-408a-b874-0445c86b69e6'
        certificatesOfficer = 'a4417e6f-fecd-4de8-b567-7b0420556985'
        secretsOfficer = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
        dnsContributor = 'befefa01-2a29-4197-83a8-272ff33ce314'
        metricsPublisher = '3913510d-42f4-4e42-8a64-420c390055eb'
        reader = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
    }
    $assignments = @(
        @('apim', 'keyVault', 'secretsUser'), @('gatewayIdentity', 'keyVault', 'secretsUser'),
        @('apim', 'appInsights', 'metricsPublisher'), @('workerVm', 'keyVault', 'certificatesOfficer'),
        @('workerVm', 'keyVault', 'secretsOfficer'), @('workerVm', 'dnsZone', 'dnsContributor'),
        @('workerVm', 'workerVm', 'reader'), @('workerVm', 'keyVault', 'reader')
    )
    $actions = [System.Collections.Generic.List[object]]::new()
    $evidence.roles = [ordered]@{}
    foreach ($principalKey in $principals.Keys) {
        $expected = @(
            foreach ($assignment in $assignments) {
                if ($assignment[0] -cne $principalKey) { continue }
                @{ scope = $resources[$assignment[1]].id
                    role = "$($Targets.subscription)/providers/Microsoft.Authorization/roleDefinitions/$($roles[$assignment[2]])" }
            }
        )
        $evidence.roles[$principalKey] = Add-LabRoleAction $principals[$principalKey] $Targets.subscription $expected $actions
    }
    return @{ evidence = $evidence; actions = $actions.ToArray() }
}

function Invoke-LabBootstrapAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Config,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Snapshot,
        [Parameter(Mandatory)][long] $ExpiresAt
    )
    $targets = Get-LabTarget $Config
    $identity = $null
    foreach ($action in $Snapshot.actions) {
        Assert-LabCondition ($ExpiresAt -gt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        Assert-LabOwnerContext $Config
        if ($action.code -ceq 'CreateFederation') {
            # No active trust until approval and exact branch protections are read back.
            $environment = Invoke-LabGitHubRequest GET $targets.environment $null
            Assert-LabEnvironment $environment $Config
            $policies = Invoke-LabGitHubRequest GET "$($targets.environment)/deployment-branch-policies?per_page=100" $null
            Assert-LabBranchPolicy $policies
        }
        if ($action.code -ceq 'CreateDeploymentRoleAfterIdentity') {
            $pending = [System.Collections.Generic.List[object]]::new()
            $role = "$($targets.subscription)/providers/Microsoft.Authorization/roleDefinitions/$($action.role)"
            $null = Add-LabRoleAction $identity.properties.principalId $targets.subscription `
                @(@{ scope = $targets.lab; role = $role }) $pending
            foreach ($roleAction in $pending) {
                Invoke-LabArmRequest $roleAction.method $roleAction.path $roleAction.body
            }
            continue
        }
        $body = $action.body
        if ($action.code -ceq 'CreateVariable' -and $action.body.name -ceq 'AZURE_CLIENT_ID' -and
            $null -ne $identity) { $body = @{ name = 'AZURE_CLIENT_ID'; value = $identity.properties.clientId } }
        if ($action.system -ceq 'github') { Invoke-LabGitHubRequest $action.method $action.path $body }
        else { Invoke-LabArmRequest $action.method $action.path $body }
        if ($action.code -ceq 'CreateIdentity') {
            $identity = Invoke-LabArmRequest GET "$($targets.identity)?api-version=2024-11-30" $null
            Assert-LabOwnedResource $identity $targets.identity 'Microsoft.ManagedIdentity/userAssignedIdentities' $Config
            Assert-LabCondition ($identity.properties.tenantId -ceq $Config.tenantId -and
                $identity.properties.clientId -cmatch '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$')
            $pending = [System.Collections.Generic.List[object]]::new()
            $role = "$($targets.subscription)/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
            $null = Add-LabRoleAction $identity.properties.principalId $targets.subscription `
                @(@{ scope = $targets.lab; role = $role }) $pending
        }
    }
}

function Invoke-LabBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ConfigPath,
        [Parameter(Mandatory)][string] $PlanPath,
        [Parameter(Mandatory)][ValidateSet('Preview', 'Apply')][string] $Mode,
        [Parameter(Mandatory)][ValidateSet('Identity', 'Runtime')][string] $Stage,
        [AllowEmptyString()][string] $ApprovedPlanSha256 = '',
        [switch] $OwnerAuthorized,
        [switch] $MicrosoftOwnedTestEnvironment
    )
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $code = 'LAB_CONFIG_INVALID'
    try {
        if (-not $OwnerAuthorized -or -not $MicrosoftOwnedTestEnvironment) {
            return @{ state = 'Refused'; code = 'LAB_OWNER_ACK_REQUIRED' }
        }
        $configFile = Get-LabPrivatePath $ConfigPath
        $planFile = Get-LabPrivatePath $PlanPath
        if ($configFile -ieq $planFile) { throw 'OverlappingPrivateFiles' }
        $configText = Read-LabPrivateText $configFile
        $config = Read-LabJson $configText
        $schema = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'infra\live-validation-lab\bootstrap.config.schema.json'
        $schemaValid = Test-Json -Json $configText -SchemaFile $schema -ErrorAction Stop 2>$null 3>$null 4>$null 5>$null 6>$null
        if (-not $schemaValid) {
            throw 'InvalidConfigSchema'
        }
        if ($config.labResourceGroup -ieq $config.identityResourceGroup) { throw 'IdentityGroupMustBeSeparate' }
        $reviewerKeys = @($config.reviewers | ForEach-Object { "$($_.type):$($_.id)" })
        if (@($reviewerKeys | Sort-Object -Unique).Count -ne $reviewerKeys.Count) { throw 'DuplicateReviewer' }
        $code = 'LAB_APPROVAL_INVALID'
        $now = [DateTimeOffset]::UtcNow
        if ($Mode -ceq 'Apply') {
            if ($ApprovedPlanSha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'ApprovalRequired' }
            $planText = Read-LabPrivateText $planFile
            if ((Get-LabDigest $planText) -cne $ApprovedPlanSha256) { throw 'ApprovalDigestMismatch' }
            $plan = Read-LabJson $planText
            if ((($plan.Keys | Sort-Object) -join '|') -cne
                'actions|configSha256|expiresAt|issuedAt|schemaVersion|snapshotSha256|stage' -or
                $plan.schemaVersion -cne '1.0' -or $plan.stage -cne $Stage -or
                $plan.configSha256 -cne (Get-LabDigest $configText)) { throw 'ApprovalBindingMismatch' }
            if ($plan.issuedAt -isnot [long] -or $plan.expiresAt -isnot [long] -or
                $plan.issuedAt -gt $now.ToUnixTimeSeconds() -or
                $plan.expiresAt -le $now.ToUnixTimeSeconds() -or $plan.expiresAt - $plan.issuedAt -ne 1800) {
                throw 'ApprovalExpired'
            }
        }
        elseif (Test-Path -LiteralPath $planFile) { throw 'PreviewNeverOverwritesPlan' }
        $code = 'LAB_PREFLIGHT_FAILED'
        $snapshot = Get-LabBootstrapSnapshot $config $Stage 2>$null 3>$null 4>$null 5>$null 6>$null
        $snapshotDigest = Get-LabObjectDigest $snapshot
        if ($Mode -ceq 'Preview') {
            $plan = [ordered]@{
                schemaVersion = '1.0'; stage = $Stage; configSha256 = Get-LabDigest $configText
                snapshotSha256 = $snapshotDigest; issuedAt = $now.ToUnixTimeSeconds()
                expiresAt = $now.AddMinutes(30).ToUnixTimeSeconds(); actions = @($snapshot.actions)
            }
            $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json $plan -Depth 40))
            $stream = [System.IO.File]::Open($planFile, [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try { $stream.Write($bytes, 0, $bytes.Length) }
            finally { $stream.Dispose() }
            return @{ state = 'PreviewReady'; code = 'LAB_PREVIEW_READY' }
        }
        if ($snapshotDigest -cne $plan.snapshotSha256 -or
            (Get-LabObjectDigest $snapshot.actions) -cne (Get-LabObjectDigest $plan.actions)) {
            return @{ state = 'Refused'; code = 'LAB_STATE_CHANGED' }
        }
        if ($plan.expiresAt -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) {
            return @{ state = 'Refused'; code = 'LAB_APPROVAL_INVALID' }
        }
        $code = 'LAB_APPLY_INCOMPLETE'
        $null = Invoke-LabBootstrapAction $config $snapshot $plan.expiresAt 2>$null 3>$null 4>$null 5>$null 6>$null
        $final = Get-LabBootstrapSnapshot $config $Stage 2>$null 3>$null 4>$null 5>$null 6>$null
        if (@($final.actions).Count -ne 0) { throw 'ApplyReadbackIncomplete' }
        return @{ state = 'Applied'; code = 'LAB_APPLIED' }
    }
    catch {
        if ($_.Exception.Message -ceq 'LAB_NOT_READY') { return @{ state = 'NotReady'; code = 'LAB_NOT_READY' } }
        return @{ state = 'Refused'; code = $code }
    }
}
