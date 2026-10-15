#Requires -Version 7.4

Set-StrictMode -Version Latest

# REST 2024-05-01: sign-in-settings/get, sign-up-settings/get,
# delegation-settings/get, portal-config/get, portal-revision/list-by-service.
# Simple resources always contain name (nullable) and properties; collections
# require unique nonempty names. Missing optional Boolean/enum facts stay null,
# never REST documented defaults. These are restricted evidence, not models.
function ConvertTo-ApimPortalResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Resource,
        [Parameter(Mandatory)]
        [ValidateSet('signin', 'signup', 'delegation', 'config', 'revisions')]
        [string] $Kind
    )

    Assert-ApimAuthObject -Value $Resource
    $name = ConvertTo-ApimAuthName -Value (
        Get-ApimAuthProperty -InputObject $Resource -Name name
    ) -Optional:($Kind -ne 'revisions')
    $properties = Get-ApimAuthProperty -InputObject $Resource -Name properties
    Assert-ApimAuthObject -Value $properties
    $safe = [ordered]@{}
    switch ($Kind) {
        { $_ -in @('signin', 'signup') } {
            $safe.enabled = ConvertTo-ApimAuthBoolean -Value (
                Get-ApimAuthProperty -InputObject $properties -Name enabled
            )
        }
        delegation {
            foreach ($field in @('userRegistration', 'subscriptions')) {
                $setting = Get-ApimAuthProperty -InputObject $properties -Name $field
                if ($null -ne $setting) { Assert-ApimAuthObject -Value $setting }
                $safe[$field] = [pscustomobject][ordered]@{
                    enabled = ConvertTo-ApimAuthBoolean -Value (
                        Get-ApimAuthProperty -InputObject $setting -Name enabled
                    )
                }
            }
        }
        config {
            $safe.enableBasicAuth = ConvertTo-ApimAuthBoolean -Value (
                Get-ApimAuthProperty -InputObject $properties -Name enableBasicAuth
            )
            foreach ($field in @('signin', 'delegation')) {
                $setting = Get-ApimAuthProperty -InputObject $properties -Name $field
                if ($null -ne $setting) { Assert-ApimAuthObject -Value $setting }
                $nested = [ordered]@{}
                $fields = if ($field -eq 'signin') { @('require') }
                    else { @('delegateRegistration', 'delegateSubscription') }
                foreach ($nestedField in $fields) {
                    $nested[$nestedField] = ConvertTo-ApimAuthBoolean -Value (
                        Get-ApimAuthProperty -InputObject $setting -Name $nestedField
                    )
                }
                $safe[$field] = [pscustomobject]$nested
            }
        }
        revisions {
            $safe.isCurrent = ConvertTo-ApimAuthBoolean -Value (
                Get-ApimAuthProperty -InputObject $properties -Name isCurrent
            )
            $safe.status = ConvertTo-ApimAuthEnum -Value (
                Get-ApimAuthProperty -InputObject $properties -Name status
            ) -Allowed @('pending', 'publishing', 'completed', 'failed')
        }
    }
    return [pscustomobject][ordered]@{ name = $name; properties = [pscustomobject]$safe }
}

function Get-ApimPortalEndpoint {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject]@{ Kind = 'signin'; Endpoint = 'portalsettings/signin'; File = 'raw/portal/signin.json' }
        [pscustomobject]@{ Kind = 'signup'; Endpoint = 'portalsettings/signup'; File = 'raw/portal/signup.json' }
        [pscustomobject]@{ Kind = 'delegation'; Endpoint = 'portalsettings/delegation'; File = 'raw/portal/delegation.json' }
        [pscustomobject]@{ Kind = 'config'; Endpoint = 'portalconfigs/default'; File = 'raw/portal/config.json' }
        [pscustomobject]@{ Kind = 'revisions'; Endpoint = 'portalRevisions'; File = 'raw/portal/revisions.json' }
    )
}

function Invoke-ApimPortalCollector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Environment
    )

    Invoke-ApimAuthEndpointCollection -RunPath $RunPath -Environment $Environment `
        -Name Portal -Endpoints @(Get-ApimPortalEndpoint)
}
