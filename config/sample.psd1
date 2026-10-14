@{
    Customer     = 'Example'
    Environments = @(
        @{
            Name                     = 'Prod'
            SubscriptionId           = '00000000-0000-0000-0000-000000000001'
            ApimResourceGroup        = 'rg-example-prod'
            ApimName                 = 'apim-example-prod'
            NetworkResourceGroups    = @('rg-example-prod')
            AppGateways              = @(
                @{ ResourceGroup = 'rg-example-prod'; Name = 'agw-example-prod' }
            )
            LogAnalyticsWorkspaceIds = @('00000000-0000-0000-0000-000000000002')
            CostScopes               = @(
                '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-example-prod'
            )
            LogicAppResourceGroups   = @('rg-example-prod')
            GitRepoPath              = ''
            GitPolicyRoot            = 'apim/policies'
        }
    )
    Edge = @{
        Provider              = 'Cloudflare'
        Mode                  = 'AssumedReachable'
        TrustedEdgeRanges     = @()
        TrustedEdgeRangesFile = ''
    }
    Network = @{
        AppGwSubnetCidrs = @()
        InternalCidrs    = @('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')
    }
    Windows = @{ UsageDays = 90; SecurityLogDays = 30; CostMonths = 6; MetricDays = 90 }
    Scoring = @{
        Severity = @{ High = 3; Medium = 2; Low = 1; Info = 0.5 }
        Exposure = @{
            DirectPublic = 2.5; ExternalInUse = 2; ExternalUnintended = 2
            Restricted = 1.5; Internal = 1; Platform = 1.5; Unknown = 1.5
        }
        Usage = @{ InUse = 1.5; Unused = 1; NotApplicable = 1 }
    }
    Thresholds = @{
        CertExpiryDays = 60; BackendP95Ms = 2000; Error5xxPct = 1.0
        UnusedDays = 90; SubscriptionStaleDays = 180; MaxWriteRolePrincipals = 5
    }
    RuleTargets = @{
        CriticalBackendIds = @()
    }
    RuleExceptions = @{
        ApprovedPlainHttpBackendIds = @()
        ApprovedPlainHttpOperationKeys = @()
    }
    Privacy = @{ StoreUserIdentities = $false; RedactPolicySecrets = $true }
    AnalysisPackage = @{
        UsageMode   = 'Bucketed'
        CostMode    = 'RelativeOnly'
        UsageBuckets = @(0, 1, 1000, 10000, 100000, 1000000)
    }
    Output = @{
        Root          = '<absolute-external-restricted-path>'
        ModelSafeRoot = '<absolute-external-analysis-path>'
    }
}
