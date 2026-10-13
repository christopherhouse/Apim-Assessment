# APIM Assessment Toolkit — Technical Specification

| | |
|---|---|
| **Document** | Build specification for a coding agent |
| **Version** | 1.1 (draft) |
| **Date** | 2026-10-12 |
| **Product owners** | Designated maintainers |
| **Validation profile** | Customer-neutral integration APIM, Prod first, then Dev/Test |
| **Companion docs** | `APIM-Assessment-Project-Plan.md`, `APIM-Assessment-Task-Register.md` |

---

## 1. Purpose

Build a reusable, **read-only** PowerShell assessment engine, operated through a constrained GitHub Copilot workflow, that assesses an Azure API Management (APIM) deployment and its network front door in the style of Microsoft's WARA (Well-Architected Reliability Assessment): **Collect → Analyze → Review → Report**.

The toolkit must:

1. Collect APIM configuration, policies, network path, security posture, usage telemetry and cost into versioned JSON.
2. Normalize the raw data into a stable **model** (one file per report sheet).
3. Evaluate a **rule catalog** aligned to the Azure Well-Architected Framework (WAF) pillars and Microsoft Cloud Security Benchmark (MCSB) controls, producing `findings.json`.
4. Build and independently validate a model-safe analysis package that contains only allowlisted, pseudonymized facts; raw and normalized customer data never enter model context.
5. Use specialized Copilot agents to review the validated package for architecture/exposure and security, then synthesize traceable executive observations.
6. Generate an Excel **action plan** and a self-contained HTML executive presentation from deterministic local templates, carrying forward human-entered tracking fields between runs.
7. Diff two runs (new / resolved / persisting findings).

The toolkit is **customer-neutral**. All customer specifics live in a config file.

### 1.1 Goals
- Run end-to-end by a Microsoft CSA with Reader-level access, from a workstation, in < 30 minutes for a ~60-API instance (excluding Cost Management throttling).
- Every finding is traceable to evidence and to the raw source file(s) it came from.
- Analysis and reporting can be re-run offline from a saved run folder.
- Deterministic output: same inputs → same `findings.json` (stable ordering, stable keys).
- No customer-identifying, infrastructure-identifying, raw policy, exact usage/cost, secret-like, or unrestricted free-text values are exposed to an AI model.
- AI-generated observations cite stable findings or model-safe fact IDs and cannot override deterministic findings, evidence, or severity.

### 1.2 Non-goals
- No write/remediation actions against Azure. Ever.
- No reading of secret values (subscription keys, named-value secrets, certificates' private material).
- No assessment of Logic Apps workflow design (cost data only).
- No Cloudflare API integration in v1 (Cloudflare is configured as "assumed reachable").
- AI gateway design is out of scope for the tool (separate advisory workstream).
- No unrestricted Copilot shell/filesystem access to the collection zone or raw/model run folders.
- No model-based collection, redaction, safety validation, rule evaluation, or direct workbook/HTML mutation.

---

## 2. Synthetic reference environment

The defaults and exposure algorithm must handle this wholly synthetic topology
correctly. Customer, engagement, and real-person identifiers remain outside the
repository.

| Item | Value |
|---|---|
| APIM tier | Premium (classic) in Prod, Developer in non-prod |
| Network | APIM **Internal VNet** mode, behind **Application Gateway (WAF v2)** |
| App Gateway routing | **Host-wide forwarding** (basic rule; no path-based allowlist) to APIM gateway hostname |
| Edge | External edge proxy in front of App Gateway; App Gateway allows trusted edge IP ranges; WAF is disabled in the synthetic scenario. Edge config is **not** collected — treated as "assumed reachable". |
| Scale | ~60 APIs, external partner/vendor integrations, data-platform-backed APIs |
| Environments | Dev, Test, Prod (separate resource groups for the integration platform) |
| Access | Reader on integration RGs (granted); Cost data access available |
| Source control | GitHub repos (APIM/IaC) — access in progress |
| Also in RG | Logic Apps cost-visibility scenario — cost-only scope |

Implication encoded in the spec: with Internal VNet + host-wide forwarding, **every API on a published hostname is internet-reachable unless a policy blocks it** (APIM does not scope APIs to hostnames).

---

## 3. Technology and runtime requirements

| Item | Requirement |
|---|---|
| Runtime | PowerShell **7.4+** (cross-platform; Windows primary) |
| Modules | `Az.Accounts`, `Az.ResourceGraph`, `Az.OperationalInsights`, `Az.Monitor`, `ImportExcel`; tests: `Pester` 5.x, `PSScriptAnalyzer` |
| Optional | Node.js + `@stoplight/spectral-cli` for OpenAPI linting; `git` CLI for repo comparison |
| Copilot | GitHub Copilot CLI with repository agents/skills and a narrowly allowlisted local tool broker; the deterministic engine remains usable without Copilot |
| Auth | Existing `Connect-AzAccount` context (interactive or device code). Toolkit never stores tokens. |
| ARM API version | APIM `2024-05-01` (configurable); Cost Management query `2023-11-01` (configurable) |
| Permissions | Reader (APIM + network RGs), Log Analytics Reader (workspaces), Cost Management Reader (subscription or RG) |
| No admin rights | Must run without local admin |

### 3.1 Read-only enforcement
- All ARM calls go through one wrapper (`Invoke-ApimArm`). The wrapper **rejects any method other than GET**, except an explicit allowlist:
  - `POST .../providers/Microsoft.CostManagement/query`
  - Log Analytics query API (via `Invoke-AzOperationalInsightsQuery`)
  - Resource Graph (via `Search-AzGraph`)
- The wrapper must refuse any URL containing `listSecrets`, `listValue`, `listKeys`, `/secrets`, `regenerate`, `token` (denylist; unit-tested).
- Relative URLs must begin with `/`. Absolute URLs must use HTTPS and a known
  Azure Resource Manager host for public, US Government, China, or German clouds;
  every decoded `nextLink` is revalidated before use.

### 3.2 Model-data boundary

The AI boundary is fail-closed and enforced by local code, filesystem/tool isolation, and validation rather than prompt instructions:

1. The **collection zone** contains configuration, raw responses, normalized models, findings, logs, the restricted alias map, and customer-facing reports. For agent-assisted runs it is outside every Copilot trusted/allowed directory; Copilot agents cannot read this zone.
2. `New-AnalysisPackage` constructs a new object from an explicit field allowlist. It must never clone a raw/model object and remove fields afterward.
3. `Test-AnalysisPackage` independently validates the candidate against a closed JSON Schema (`additionalProperties: false` at every object), field-specific value constraints, forbidden-key rules, and recursive prohibited-value scans.
4. Prohibited values include GUIDs, ARM IDs, tenant/subscription/resource/principal identifiers, UPNs/emails, hostnames/FQDNs, URLs, IP addresses/CIDRs, local paths, policy XML, exact costs/usage, JWTs, SAS signatures, connection strings, certificates, long base64/hex strings, high-entropy values, and unrestricted source free text.
5. Unknown fields, unknown types, validator/scanner errors, or ambiguous content reject the package. Validation never repairs and promotes in one step.
6. Only a passing package is copied to a physically separate **analysis zone** that contains no link or traversal path back to the collection zone. The package hash, builder version, validator version, schema version, and validation results are recorded in a local attestation.
7. Specialist agents can access only the analysis zone and narrow read-only tools. They cannot access Azure credentials, raw/model folders, the restricted alias map, collection stdout/stderr, or arbitrary shell/filesystem tools.

The local Copilot broker may start collection using the operator's existing Azure context, but it captures all output and returns only an opaque run ID, coarse stage status, and sanitized error codes. It exposes a validated package only after promotion succeeds. A manual operator-run collection path remains supported.

---

## 4. Repository layout

```
ApimAssessment/
  ApimAssessment.psd1 / .psm1          # module manifest + loader
  Invoke-ApimCollect.ps1               # Stage 1 entry point
  Invoke-ApimAnalyze.ps1               # Stage 2 entry point
  Invoke-ApimReport.ps1                # Stage 3 entry point
  Compare-ApimRun.ps1                  # Run diff
  Invoke-ApimAssessment.ps1            # Convenience: all stages
  src/
    Core/        Invoke-ApimArm.ps1, Write-RunFile.ps1, Get-Config.ps1, Logging.ps1, Retry.ps1
    Collect/     Collect-Service.ps1, Collect-Apis.ps1, Collect-Policies.ps1, Collect-Network.ps1,
                 Collect-Security.ps1, Collect-Logs.ps1, Collect-Metrics.ps1, Collect-Cost.ps1, Collect-Git.ps1
    Model/       Build-ApiModel.ps1, Merge-ApimPolicy.ps1, Get-PolicyFlags.ps1, Build-ExposureModel.ps1,
                 Build-SubscriptionModel.ps1, Build-UsageModel.ps1, Build-CostModel.ps1, Build-DriftModel.ps1
    Rules/       Invoke-RuleEngine.ps1, Get-PriorityScore.ps1
    Package/     New-AnalysisPackage.ps1, Test-AnalysisPackage.ps1, Publish-AnalysisPackage.ps1
    Report/      Export-ActionPlan.ps1, Export-ExecutiveSummary.ps1, Merge-PriorTracking.ps1
  rules/         SEC.rules.ps1, NET.rules.ps1, GOV.rules.ps1, REL.rules.ps1, PERF.rules.ps1, POR.rules.ps1, COST.rules.ps1
  queries/       *.kql (Log Analytics), *.arg.kql (Resource Graph)
  schemas/       *.schema.json (manifest, models, findings, model-safe and agent contracts)
  template/      ApimActionPlan.xlsx, executive-summary/
  config/        sample.psd1, customer.psd1 (gitignored if it contains tenant IDs)
  tests/         unit/, integration/, fixtures/ (synthetic, anonymized)
  docs/          README.md, RUNBOOK.md, RULES.md (generated from rule files)
  .github/
    agents/      APIM architecture/exposure, security, and executive synthesis profiles
    skills/      Assessment orchestration, package analysis, deliverable generation and validation
```

Restricted and model-safe run roots are local runtime data, not repository
directories. They are ignored if a maintainer uses the manual development
defaults, but agent-assisted runs require explicitly resolved external roots and
tool/path isolation.

---

## 5. Configuration

`config/<customer>.psd1` (PowerShell data file):

```powershell
@{
  Customer        = 'Example'
  Environments    = @(
    @{
      Name             = 'Prod'
      SubscriptionId   = '<guid>'
      ApimResourceGroup= 'rg-...-prod'
      ApimName         = 'apim-...-prod'
      NetworkResourceGroups = @('rg-...-prod')
      AppGateways      = @(@{ ResourceGroup='rg-...-prod'; Name='agw-...-prod' })
      LogAnalyticsWorkspaceIds = @('<workspace-guid>')   # APIM + App GW diagnostics
      CostScopes       = @('/subscriptions/<guid>/resourceGroups/rg-...-prod')
      LogicAppResourceGroups = @('rg-...-prod')
      GitRepoPath      = 'C:\src\example-apim'          # optional, local clone
      GitPolicyRoot    = 'apim/policies'                # optional
    }
    # Dev, Test ...
  )
  Edge = @{
    Provider             = 'Cloudflare'
    Mode                 = 'AssumedReachable'            # AssumedReachable | Collected (future)
    TrustedEdgeRanges    = @()                           # populated at run time from config file or manual list
    TrustedEdgeRangesFile= 'config/cloudflare-ranges.txt'
  }
  Network = @{
    AppGwSubnetCidrs     = @('10.x.x.x/27')             # auto-discovered; override here
    InternalCidrs        = @('10.0.0.0/8','172.16.0.0/12','192.168.0.0/16')
  }
  Windows = @{ UsageDays = 90; SecurityLogDays = 30; CostMonths = 6; MetricDays = 90 }
  Scoring = @{
    Severity = @{ High=3; Medium=2; Low=1; Info=0.5 }
    Exposure = @{ DirectPublic=2.5; ExternalInUse=2; ExternalUnintended=2; Restricted=1.5; Internal=1; Platform=1.5; Unknown=1.5 }
    Usage    = @{ InUse=1.5; Unused=1; NotApplicable=1 }
  }
  Thresholds = @{ CertExpiryDays=60; BackendP95Ms=2000; Error5xxPct=1.0; UnusedDays=90; SubscriptionStaleDays=180; MaxWriteRolePrincipals=5 }
  Privacy   = @{ StoreUserIdentities=$false; RedactPolicySecrets=$true }
  AnalysisPackage = @{
    UsageMode='Bucketed'                  # exact values prohibited
    CostMode='RelativeOnly'               # trend/ratio only; exact values prohibited
    UsageBuckets=@(0,1,1000,10000,100000,1000000)
  }
  Output    = @{
    Root='<external-restricted-path>'     # outside every Copilot-visible path
    ModelSafeRoot='<external-analysis-path>' # no overlap/link/traversal to Root
  }
}
```

Validation: `Get-Config` validates required keys and nested types, GUIDs, enums,
positive numeric settings, strictly ascending usage buckets, and absolute
non-overlapping output roots, then returns normalized paths without creating
them. Existing symbolic links/junctions in either root are rejected.
`-AgentAssisted` additionally requires at least one `-CopilotVisiblePath`, rejects
a restricted root that overlaps any supplied visible path, and fails closed if
the broker cannot supply the complete visible-path set. T-319 adds the
promotion-time link/traversal and time-of-check/time-of-use defenses.

---

## 6. Run folder and manifest

```
<RestrictedRoot>/<yyyy-MM-dd_HHmm>_<env>/
  manifest.json
  raw/ ...
  model/ ...
  findings.json
  restricted/alias-map.json
  report/<Customer> APIM Assessment - <Env> - <yyyy-MM-dd>.xlsx
  report/<Customer> APIM Executive Summary - <Env> - <yyyy-MM-dd>.html
  logs/run.log

<ModelSafeRoot>/<opaque-run-id>/
  analysis-package.json
  validation-attestation.json
  expert-observations.architecture.json
  expert-observations.security.json
  executive-summary.json
```

`manifest.json`:

```json
{
  "schemaVersion": "1.0",
  "toolVersion": "0.1.0",
  "customer": "Example",
  "environment": "Prod",
  "runId": "2026-10-19_0930_Prod",
  "startedUtc": "...", "completedUtc": "...",
  "operator": "upn of signed-in account",
  "tenantId": "...", "subscriptionId": "...",
  "apim": { "resourceId": "...", "apiVersion": "2024-05-01" },
  "windows": { "usageDays": 90, "securityLogDays": 30, "costMonths": 6 },
  "edge": { "provider": "Cloudflare", "mode": "AssumedReachable" },
  "stages": { "collect": "Completed", "analyze": "Completed", "report": "Completed" },
  "collectors": [ { "name": "Policies", "status": "Completed|Partial|Failed|Skipped", "items": 612, "errors": 0, "durationSec": 41 } ],
  "modelSafe": { "build": "Completed", "validation": "Passed", "promotion": "Completed", "packageSha256": "..." },
  "warnings": [ "..." ]
}
```

Rules: a collector failure **never** aborts the run; it is recorded as `Failed/Partial` and dependent rules emit `Info` "Not evaluated" findings (see §10.5).

---

## 7. Stage 1 — Collection

### 7.1 Core behaviours
- **Paging**: follow `nextLink` until exhausted.
- **Retry**: on 429/5xx, honour `Retry-After`; exponential backoff (2, 4, 8, 16, 32 s), max 6 attempts.
- **Concurrency**: per-API/per-operation calls use `ForEach-Object -Parallel` with configurable `ThrottleLimit` (default 6).
- **Output**: JSON raw responses are written unchanged (`ConvertTo-Json -Depth
  50`), one file per call type. Policy response envelopes are not persisted;
  policy XML is checked for hard-coded secret candidates, locations are recorded,
  values are redacted, and the sanitized XML plus `policies/index.json` are
  stored.
- **Idempotent**: `-Resume` skips collectors whose output already exists and is valid.
- **Logging**: structured log lines `{ts, level, collector, message, url?}`; known
  credential patterns are redacted and URL query/fragment values are removed;
  callers must never submit raw secret-bearing payloads.

### 7.2 APIM configuration (ARM, base = `/subscriptions/{s}/resourceGroups/{rg}/providers/Microsoft.ApiManagement/service/{name}`)

| Raw file | Endpoint(s) | Key fields consumed |
|---|---|---|
| `service.json` | `{base}` | `sku`, `zones`, `additionalLocations`, `platformVersion`, `virtualNetworkType`, `virtualNetworkConfiguration`, `publicNetworkAccess`, `publicIpAddresses`, `privateIPAddresses`, `hostnameConfigurations[]` (type, hostName, certificateSource, keyVaultId, certificate.expiry, negotiateClientCertificate), `customProperties` (TLS/cipher flags), `apiVersionConstraint.minApiVersion`, `developerPortalStatus`, `legacyPortalStatus`, `disableGateway`, `identity` |
| `apis.json` | `{base}/apis?expandApiVersionSet=true` | `name`, `path`, `protocols`, `serviceUrl`, `subscriptionRequired`, `apiType`, `apiRevision`, `isCurrent`, `apiVersion`, `apiVersionSetId`, `description` |
| `apiRevisions/<api>.json` | `{base}/apis/{api}/revisions` | revision list, `isOnline`, `isCurrent` |
| `operations/<api>.json` | `{base}/apis/{api}/operations` | `method`, `urlTemplate`, `description`, `templateParameters` |
| `apiTags/<api>.json` | `{base}/apis/{api}/tags` | tags |
| `openapi/<api>.json` | `{base}/apis/{api}?export=true&format=openapi+json` (fallback `openapi+json-link` then download) | OpenAPI doc |
| `products.json` | `{base}/products` | `state`, `subscriptionRequired`, `approvalRequired`, `subscriptionsLimit`, `description` |
| `productApis/<product>.json` | `{base}/products/{p}/apis` | API membership |
| `productGroups/<product>.json` | `{base}/products/{p}/groups` | visibility |
| `subscriptions.json` | `{base}/subscriptions` | Allowlisted `name`, `scope`, `state`, derived non-identifying `ownerType`, `createdDate`, `expirationDate`, `allowTracing`, `displayName`. Absent optional display name/tracing/creation date remain null and downstream `missingInputs` records the gap; never infer false tracing. Models accept documented relative `/apis`, `/apis/{id}`, `/products/{id}` and full ARM scopes. Drop `ownerId`, keys, and unknown fields; **never** call `listSecrets`. |
| `namedValues.json` | `{base}/namedValues` | `displayName`, `secret`, `keyVault.secretIdentifier`, `keyVault.lastStatus`, `tags`. Value is only returned for non-secret values — store it only for secret-pattern detection, then **drop it** (`RedactPolicySecrets`) |
| `backends.json` | `{base}/backends` | `url`, `protocol`, `tls.validateCertificateChain`, `tls.validateCertificateName`, `credentials`, `circuitBreaker`, `type`, `pool` |
| `certificates.json` | `{base}/certificates` | `expirationDate`, `keyVault` |
| `identityProviders.json`, `authorizationServers.json`, `openidConnectProviders.json`, `authorizationProviders.json` | respective collections | auth configuration |
| `loggers.json`, `diagnostics.json`, `apiDiagnostics/<api>.json` | `{base}/loggers`, `{base}/diagnostics`, `{base}/apis/{api}/diagnostics` | logger target, `sampling.percentage`, `verbosity`, `logClientIp`, `frontend/backend.request/response.headers[]` and `.body.bytes` |
| `portal/*.json` | `{base}/portalsettings/signin`, `/signup`, `/delegation`, `{base}/portalconfigs`, `{base}/portalRevisions` | portal enablement and publication |
| `groups.json`, `tags.json`, `apiVersionSets.json`, `gateways.json`, `workspaces.json`, `policyFragments.json` | respective collections | organization |
| `users.summary.json` | `{base}/users` | **counts only** by `state` and `identities[].provider` unless `StoreUserIdentities=$true` |

### 7.3 Policies

| Scope | Endpoint (`?format=xml`) | File |
|---|---|---|
| Global | `{base}/policies/policy` | `policies/global.xml` |
| Product | `{base}/products/{p}/policies/policy` | `policies/product.{p}.xml` |
| API | `{base}/apis/{api}/policies/policy` | `policies/api.{api}.xml` |
| Operation | `{base}/apis/{api}/operations/{op}/policies/policy` | `policies/op.{api}.{op}.xml` |
| Fragment | `{base}/policyFragments/{f}?format=xml` | `policies/fragment.{f}.xml` |

404 = "no policy at this scope" (not an error). `policies/index.json` lists every
scope with `scopeType`, `scope`, `file`, `exists`, `sha256` (of normalized,
redacted XML; see §8.4), and `hardcodedSecretLocations`. Secret detection occurs
before persistence; locations are structural XML paths only, values are never
recorded, and stored policy XML replaces detected literals with
`***REDACTED***`.
The collector requests XML-encoded policy content for safe structural parsing.
It rejects malformed XML or prohibited document types before storage. If a
later policy fails after earlier sanitized files were written, collection is
Partial and no complete policy index is written.

### 7.4 Network

| Raw file | Source | Notes |
|---|---|---|
| `network/appgw.<name>.json` | ARM GET App Gateway | `frontendIPConfigurations` (public vs private), `httpListeners` (hostName(s), frontend, protocol, sslCertificate), `requestRoutingRules` (ruleType Basic/PathBasedRouting, priority), `urlPathMaps`, `backendAddressPools`, `backendHttpSettingsCollection` (hostName override, pickHostNameFromBackendAddress, probe), `rewriteRuleSets`, `probes`, `sslPolicy`, `firewallPolicy` link, `webApplicationFirewallConfiguration` (legacy) |
| `network/wafPolicy.<name>.json` | ARM GET WAF policy | `policySettings.state`, `policySettings.mode`, `managedRules`, `customRules` (IP match rules → edge allowlist) |
| `network/apimSubnet.json`, `network/nsgs.json`, `network/publicIps.json`, `network/privateEndpoints.json`, `network/privateDnsZones.json`, `network/routeTables.json` | Resource Graph | APIM subnet NSG rules, App GW subnet, public IPs (detect any other path to APIM) |
| `network/frontDoors.json` | Resource Graph | any Front Door / other App GW whose backend points at APIM hostnames or IPs; three separate single-type queries are deduplicated by resource ID before persistence |

### 7.5 Security posture (Resource Graph)
- `security/defender.json`: `securityresources | where type == "microsoft.security/assessments"` filtered to APIM + App GW resource IDs (`displayName`, `status.code`, `metadata.severity`), plus Defender for APIs sub-assessments where available.
- `security/policyCompliance.json`: `policyresources | where type == "microsoft.policyinsights/policystates"` for APIM/App GW resources.
- `security/roleAssignments.json`: `authorizationresources` role assignments at RG and resource scope (principalId, principalType, roleDefinitionId → resolved role name). Principal display names only if `StoreUserIdentities=$true`.

### 7.6 Logs (Log Analytics)
Detect schema first: if `ApiManagementGatewayLogs` has rows in the window use **resource-specific** queries, else fall back to `AzureDiagnostics` variants (`queries/*.azdiag.kql`). Record which in manifest. Also record workspace retention (`Get-AzOperationalInsightsWorkspace`), and cap windows to retention.

| Raw file | Query (resource-specific form) |
|---|---|
| `logs/usageByApi.json` | Calls, 4xx, 5xx, 401/403, P50/P95 `TotalTime`, P95 `BackendTime`, `dcount(ApimSubscriptionId)`, `LastCall` by `ApiId, OperationId, ProductId` over `UsageDays` |
| `logs/usageByRoute.json` | Same, adding `Route = iif(ipv4_is_in_any_range(CallerIpAddress, appGwCidrs), "ViaAppGw", "Internal")` |
| `logs/usageMonthly.json` | Calls by `ApiId`, month |
| `logs/tls.json` | Calls by `ClientTlsVersion`, `ApiId` over `SecurityLogDays` |
| `logs/noSubscriptionCalls.json` | Calls with empty `ApimSubscriptionId` by `ApiId` |
| `logs/appgwByListener.json` | `AGWAccessLogs`: requests by `ListenerName, RuleName, Host`, `dcount(ClientIp)` |
| `logs/appgwNonEdge.json` | `AGWAccessLogs` where `ClientIp` not in `TrustedEdgeRanges` → by `ClientIp, Host` (only if edge ranges configured) |
| `logs/directNonAppGw.json` | APIM calls whose `CallerIpAddress` is outside App GW subnets **and** outside `InternalCidrs` (should be empty for Internal VNet) |
| `logs/headersLogged.json` | Detection of whether `X-Forwarded-For` / `CF-Connecting-IP` appear in logged headers (informational) |

### 7.7 Metrics (Azure Monitor)
`metrics/apim.json`: `Capacity` (avg, max; PT1H), `Requests` (total; P1D), `Duration`, `BackendDuration` (avg; PT1H) for `MetricDays`. `metrics/appgw.json`: `CapacityUnits`, `Throughput`, `UnhealthyHostCount`.

### 7.8 Cost (Cost Management Query API)
`cost/daily.json`: `type=ActualCost`, `timeframe=Custom` (last `CostMonths` full months + MTD), `granularity=Daily`, aggregation `PreTaxCost` (sum), grouping `ResourceId`, `MeterCategory`, `MeterSubCategory`. One query per `CostScopes` entry. Handle 429 with `x-ms-ratelimit-microsoft.costmanagement-*-retry-after`.

`cost/logicApps.json` (cost-only): inventory of `Microsoft.Logic/workflows` and `Microsoft.Web/sites` (kind contains `workflowapp`) + App Service plan SKU/instance count; metrics `BillableActionExecutions`/`BillableTriggerExecutions` (Consumption) and plan `CpuPercentage`/instance count (Standard). **No workflow definitions are read.**

`cost/laIngestion.json`: `Usage | where TimeGenerated > ago(90d) | summarize GB=sum(Quantity)/1024 by DataType, bin(TimeGenerated, 1d)` on the APIM workspace.

### 7.9 Source control (optional)
If `GitRepoPath` set: enumerate `*.xml` under `GitPolicyRoot`, map to scopes by file-name convention (configurable regex; default supports APIOps extractor layout `apis/<api>/policy.xml`, `apis/<api>/operations/<op>/policy.xml`, `products/<p>/policy.xml`, `policy.xml`). Write `git/policyHashes.json` with normalized hashes and commit SHA.

---

## 8. Stage 2a — Model

All model files are arrays of flat-ish records validated against `schemas/*.schema.json`. Field names are camelCase. Arrays sorted by primary key.

Until all dependent collectors and models are available, records include
`modelStatus` (`Complete` or `Partial`) and a sorted `missingInputs[]`. An
unavailable value is `null`, never a success-shaped false, zero, or empty value.
Policy-matrix controls use `NA` when missing or Partial evidence prevents a
definitive result; a positively detected risk still produces `Fail`. Writers
validate every pending model array against its closed schema before writing any
of them.

The shared model gate currently covers `apis`, `operations`, `policyMatrix`,
`subscriptions`, `network`, and `exposure` (D-19). Pending outputs are serialized
once, validated with `Test-Json -SchemaFile`, and only those validated snapshots
are persisted. The private saved-run loader requires every implemented model
file and validates the complete set before returning anything to downstream
analysis. Missing files, unknown model names, unavailable schemas, and invalid
JSON/schema data fail closed. Future model contracts join the gate with their
builders; public Analyze orchestration remains T-311.

### 8.1 `model/apis.json` (one row per API, current revision)
| Field | Type | Derivation |
|---|---|---|
| `apiId` | string | `apis[].name` |
| `displayName`, `path`, `apiType`, `protocols[]` | | apis |
| `backendHost` | string | host of `serviceUrl` or `set-backend-service` target / backend entity |
| `products[]` | string[] | productApis |
| `ownerTag`, `tags[]` | | apiTags; owner = tag matching `^(owner|team)[:=-]` (configurable) |
| `versionSet`, `version`, `revisionCount`, `nonCurrentOnlineRevisions` | | revisions |
| `operationCount` | int | |
| `subscriptionRequired` | bool | api (or product) |
| `callerAuth` | enum `Entra/JWT`, `mTLS`, `SubscriptionKeyOnly`, `None`, `Mixed` | from effective policy flags across operations |
| `throttling`, `ipFilter`, `corsUnsafe`, `backendAuth`, `hardcodedSecret`, `baseMissing`, `mockOrTrace` | bool | from effective policy flags (any operation) |
| `backendTlsValidation` | bool/null | backend entity tls flags; null if raw URL |
| `bodyLogging`, `sensitiveHeadersLogged` | bool | diagnostics |
| `reachability` | enum (§9) | exposure model |
| `exposure` | enum (§9) | exposure model |
| `calls90d`, `callsViaAppGw`, `callsInternal`, `lastCall`, `p95Ms`, `backendP95Ms`, `pct5xx` | | logs |
| `openApiScore` | int 0–100 / null | Spectral (§8.6) |
| `inGit` | bool/null | git |
| `findingIds[]` | string[] | back-filled after rule evaluation |

### 8.2 `model/operations.json`
One row per operation: `apiId`, `operationId`, `method`, `fullPath` (`/{api.path}/{urlTemplate}` normalized), `hasDescription`, effective policy flags, `calls90d`.

### 8.3 Effective policy merge (`Merge-ApimPolicy`)
Effective policy for an operation in product P = `op ⊕ (api ⊕ (product P ⊕ global))`, where `child ⊕ parent` replaces `<base/>` in each section (`inbound`, `backend`, `outbound`, `on-error`) of the child with the parent's section children. Rules:
- If a child section exists **without** `<base/>`, the parent section is dropped → record `baseMissing=true` with scope and section.
- If the child has no policy, effective = parent.
- If an API is in multiple products, compute per product; flags are OR-ed for "has risk" and AND-ed for "has control" (conservative). If in no product, product layer is empty.
- Expand `<include-fragment fragment-id="x"/>` inline from fragment XML (max depth 5, cycle-safe).
- Preserve original scope attribution on each node (`data-scope` attribute) for evidence.

The merge result contains one record per product path with `product`, `apiId`,
`operationId`, `effectiveXml`, `normalizedXml`, `sha256`, `baseMissing[]`, and
`fragmentIssues[]`. Missing fragments, cycles, and depth-limit failures retain
the unresolved `<include-fragment>` with `data-fragment-status`; analysis must
not silently interpret it as expanded. Conservative cross-product flag
aggregation consumes the per-product flag records produced by §8.4.

### 8.4 Policy flags (`Get-PolicyFlags`) — XPath on effective XML
| Flag | Detection |
|---|---|
| `callerAuthJwt` | `//validate-jwt` or `//validate-azure-ad-token` |
| `callerAuthMtls` | `//validate-client-certificate` or `choose` testing `context.Request.Certificate` |
| `throttling` | `//rate-limit`, `//rate-limit-by-key`, `//quota`, `//quota-by-key`, `//llm-token-limit`, `//azure-openai-token-limit` |
| `ipFilter` | `//ip-filter` (capture action + ranges) |
| `hostRestriction` | `choose/when` conditions referencing `context.Request.OriginalUrl.Host` or `Host` header with `return-response` 403/404 |
| `corsUnsafe` | `//cors[@allow-credentials='true']` with `allowed-origins/origin='*'` |
| `backendAuth` | `//authentication-managed-identity`, `//authentication-certificate`, `//get-authorization-context`, or backend entity credentials |
| `hardcodedSecret` | `set-header`/`set-query-parameter`/`authentication-basic` values not wrapped in `{{...}}` matching secret patterns (`(?i)(key|secret|password|pwd|token|bearer|sig=)`, base64 ≥ 24 chars, JWT shape). Record location only, **never the value**. |
| `backendOverride` | `//set-backend-service` (capture base-url / backend-id; flag `http://`) |
| `mockOrTrace` | `//mock-response`, `//trace` |
| `returnsWithoutBackend` | `//return-response` in inbound not inside a `choose` |
| `baseMissing` | from merge |

The flag result contains `evaluationStatus` (`Complete` or `Partial`), the
Boolean flags above, `backendOverrideHttp`, and deterministic structural detail
arrays for IP filters, 403/404 host restrictions, backend overrides,
hard-coded-secret locations, missing base inheritance, and unresolved fragments.
Host-restriction evidence contains only location, source scope, condition, and
status code. An unresolved fragment makes the result Partial; consumers must not
interpret undetected flags as authoritative negative results on that path.
Backend-entity credentials may be supplied as a separate collected input and set
`backendAuth=true`.

Hard-coded-secret detection supports both pre-redaction policy XML and stored
sanitized XML. In sanitized XML, `***REDACTED***` in a secret-bearing policy
field is a trusted prior-detection marker. Only structural locations are
returned; secret values are never returned or persisted. Collection-time
redaction remains authoritative per D-14, and tests require flag/location parity
before and after synthetic redaction. A secret-bearing HTTP(S) URL retains only
its scheme plus the marker so plain-HTTP risk remains detectable; its host, path,
query, fragment, and credentials are removed.

Normalization for hashing: remove comments, collapse whitespace, sort
attributes, use LF line endings, and then SHA-256. Effective-policy hashes include
the deterministic `data-scope` and unresolved-fragment status attributes.

### 8.5 Other model files
| File | Grain | Key fields |
|---|---|---|
| `policyMatrix.json` | API | `apiId` + one column per control: `callerAuth`, `rateLimit`, `ipFilter`, `corsSafe`, `backendAuth`, `noHardcodedSecret`, `basePresent`, `noMockTrace` with values `Pass`/`Fail`/`NA` |
| `subscriptions.json` | subscription | `subscriptionId`, `displayName`, `scopeType` (`AllApis`/`Product`/`Api`), `scopeTarget`, `state`, `ownerType`, `createdDate`, `expirationDate`, `allowTracing`, `calls90d`, `lastUsed`, `isBuiltInMaster`, `flags[]` |
| `exposure.json` | route × API | stable `routeKey`, `gateway`, `listener`, `listenerHost`, `backendHost`, `frontendType` (Public/Private), `ruleType`, `pattern`, `wafState`, `wafMode`, `edge` (`Cloudflare-Assumed`), `apiId`, `reachability`, `restriction`, `exposure`, `callsViaAppGw`, `callsInternal`, `confidence`, `baseMissingBypass`, `restrictedOperations[]`, completeness metadata |
| `network.json` | single object | APIM VNet mode, public access, NSG evaluation result, other front doors, App GW TLS policy, WAF state, optional operator-attested edge/origin and auxiliary endpoint facts |
| `usage.json` | API × month | calls; plus top-N table |
| `cost.json` | resource × month (and day) | `resourceId`, `resourceType`, `meterCategory`, `cost`, `currency`; derived `costPerMillionCalls` (APIM + App GW) |
| `capacity.json` | day | `capacityAvg`, `capacityMax`, `capacityP95`, `units` |
| `drift.json` | API (and scope) × env | `presentDev/Test/Prod/Git`, `hashDev/Test/Prod/Git`, `matches` (`All`, `ProdOnly`, `Differs`), `note` (requires prior runs for other envs or a multi-env run) |
| `portal.json` | single object | portal status, published revision, sign-in/sign-up settings, identity providers, custom domain, products visible to which groups |
| `openApiQuality.json` | API | Spectral error/warn counts, score |

Subscription scope is derived from a full ARM service resource path or the
documented relative scope: the service root or `/apis` is `AllApis`,
`/products/{id}` is `Product`, and `/apis/{id}` is `Api`.
`scopeTarget` is null for AllApis and the decoded terminal ID otherwise.
`subscriptionId=master` at AllApis scope is the built-in master. Collection
derives `ownerType` in memory and drops `ownerId`; model flags are sorted from
`AllApis`, `AllowTracing`, `BuiltInMaster`, `NoExpiration`, and `OwnerMissing`.
Until usage telemetry is available, `calls90d` and `lastUsed` are null with
`modelStatus=Partial` and `missingInputs=["usage"]`.

`network.json` is a closed-schema single object. It records
`virtualNetworkType`, `publicNetworkAccess`, APIM subnet/NSG identity,
`nsgEvaluation` (`Broad`/`Restricted`/`Missing`/`Unknown`), nullable
`directPublic`, stable `directPublicReasons[]`, configured App Gateways, aggregate
TLS policy strength, aggregate WAF state/mode, other APIM-targeting public front
doors/IP routes, and completeness metadata. NSG evaluation uses the
highest-priority inbound rule matching TCP/any protocol, port 443, and a broad
source (`Internet`, `*`, or an all-address CIDR). Multiple gateways aggregate
conservatively: any weak TLS policy, disabled WAF, or Detection mode wins.
Missing subnet, NSG, front-door, or public-IP routing evidence produces
`directPublic=null` unless another positive condition proves direct reachability;
it never becomes a false/safe default.
Optional `edgeOriginAssessment` is null or a closed object of
`edgeRangesOnly` (Boolean or null), `originAuthentication`
(`Present`/`Absent`/`Unknown`), and `source=OperatorAttestation`. Optional
`auxiliaryRoutes` is null or a complete, sorted, unique-key array with
`routeKey`, `endpointType` (`Portal`/`Management`), `publicListener` Boolean,
`ownerNeed` (`Needed`/`NotNeeded`/`Unknown`), and the same source label.
These facts come only from explicit, operator-corroborated in-memory input;
the network collector does not establish absence of effective origin
authentication or whether a portal/management endpoint is needed. No
attestation means null, not false or an empty inventory; unknown required
facts yield one Info/NotEvaluated finding per dependent rule (D-31). The
private builder rejects additional or malformed attestation fields.

### 8.6 OpenAPI score (optional)
If Spectral is available: run `spectral lint` with ruleset `spectral:oas` + `rulesets/apim-style.yaml` (naming, versioning, descriptions, error responses). Score = `max(0, 100 − 10×errors − 2×warnings)` (configurable). Otherwise `openApiScore=null` and a description-coverage metric from operations is used.

---

## 9. Exposure classification (critical logic)

Inputs: `service.json`, App GW config, WAF policy, NSGs, other front doors, effective policy flags, `usageByRoute`.

### 9.1 Step 1 — Direct reachability (service level)
`DirectPublic = true` if **any**: `virtualNetworkType ∈ {None, External}`; `publicNetworkAccess == 'Enabled'` and VNet type ≠ Internal; any other front door/public IP routes to APIM; APIM subnet NSG allows inbound 443 from `Internet`/`*`. For Internal VNet with NSG restricted to App GW subnet + internal ranges (+ `ApiManagement` service tag on 3443), `DirectPublic = false`.

### 9.2 Step 2 — Published hostnames
For each App GW **public** listener → routing rule → backend pool targeting APIM (private IP or gateway hostname) → resolve the APIM hostname actually used (HTTP settings host override, else listener host, else pool FQDN).
- Rule type `Basic` → pattern `/*` (**host-wide forwarding**).
- Rule type `PathBasedRouting` → patterns from `urlPathMaps.pathRules[].paths` (+ default backend = `/*` if default pool is APIM). Apply rewrite rules that alter path before matching; if a rewrite is conditional or regex-based and cannot be resolved, mark `confidence=Low` and exposure `Unknown`.
- Because APIM serves **all APIs on all gateway hostnames**, any published APIM hostname with `/*` makes **all APIs reachable**.

### 9.3 Step 3 — Reachability per API
`reachability = Reachable` if any public pattern matches the operation `fullPath` (prefix/wildcard match, case-insensitive), else `NotRoutable`. API is Reachable if any operation is Reachable. `DirectPublic` overrides to `Reachable` for all.

### 9.4 Step 4 — Restrictions (effective policy)
`restriction`:
- `IpFilter` if an `ip-filter action="allow"` whose ranges exclude App GW subnet (i.e., blocks traffic arriving via App GW) or `action="forbid"` including App GW subnet.
- `HostCheck` if `hostRestriction` blocks the published hostname.
- `None` otherwise. JWT/mTLS do **not** change exposure (they change risk).
- If the restriction exists only at a scope that a `baseMissing` drops for some operation → `restriction=None` for that operation and add `GOV-010` evidence.

### 9.5 Step 5 — Observed route
From `usageByRoute`: `callsViaAppGw`, `callsInternal`. If App GW also has **private** listeners targeting APIM, `ViaAppGw` is ambiguous → use `appgwByListener` to apportion by `ListenerName` frontend type; else record `confidence=Medium`.

Before route usage is available, reachable unrestricted routes retain
`callsViaAppGw=null`, `callsInternal=null`, `exposure=Unknown`,
`confidence=Medium`, and `missingInputs=["usage"]`; missing telemetry must not
be treated as zero calls. The classifier back-fills each API's aggregate
`reachability` and `exposure` while preserving unrelated missing inputs. Route
records and the updated API array must both pass their closed schemas before
either model file is written.

The pre-telemetry hook consumes complete normalized rows with `apiId`, `route`
(`ViaAppGw` or `Internal`), and non-negative `calls`; operation/product rows are
summed by API and route. The caller must separately attest that the telemetry
query completed before absent rows can be interpreted as zero. Partial query
results remain unavailable and cannot produce `ExternalUnintended`.

### 9.6 Final label
| Condition | `exposure` |
|---|---|
| `DirectPublic` | `DirectPublic` |
| Reachable, restriction None, `callsViaAppGw > 0` | `ExternalInUse` |
| Reachable, restriction None, `callsViaAppGw == 0` | `ExternalUnintended` |
| Reachable, restriction ≠ None | `Restricted` |
| NotRoutable | `Internal` |
| Unresolvable rewrites/overlaps | `Unknown` |

Edge layer: with `Edge.Mode = AssumedReachable`, every public listener is treated as internet-reachable; `exposure.json.edge = "Cloudflare-Assumed"` and the report shows the assumption banner.

**Expected synthetic outcome:** host-wide forwarding ⇒ most/all APIs `ExternalInUse` or `ExternalUnintended`; `NET-004` fires.

---

## 10. Stage 2b — Rules and model-safe review boundary

### 10.1 Rule definition format (`rules/*.rules.ps1` returns an array of hashtables)
```powershell
@{
  Id             = 'APIM-SEC-003'
  Title          = 'Reachable API has no caller authentication beyond subscription key'
  Pillar         = 'Security'                 # Security|Reliability|OperationalExcellence|CostOptimization|PerformanceEfficiency
  Mcsb           = 'IM-1'                     # or 'n/a'
  Severity       = 'High'                     # High|Medium|Low|Info
  Scope          = 'Api'                      # Service|Api|Operation|Subscription|Backend|NamedValue|Certificate|Route|Portal|Cost|Network
  Requires       = @('model/apis.json')       # model inputs; missing → Not evaluated
  Applies        = { param($x, $ctx) $x.reachability -eq 'Reachable' }   # optional pre-filter
  Test           = { param($x, $ctx) $x.callerAuth -in 'SubscriptionKeyOnly','None' }  # $true = finding
  Evidence       = { param($x, $ctx) [ordered]@{ path=$x.path; callerAuth=$x.callerAuth; calls90d=$x.calls90d } }
  EvidenceText   = { param($x, $ctx) "/$($x.path): $($x.callerAuth); $($x.calls90d) calls/90d" }
  Recommendation = 'Validate Entra ID tokens (validate-azure-ad-token / validate-jwt) for external callers; keep subscription keys for metering only.'
  Effort         = 'M'                        # S|M|L
  References     = @()                        # Learn URLs added by maintainers; tool must not invent URLs
  SourceFiles    = @('raw/apis.json','raw/policies/')
  Enabled        = $true
}
```
`$ctx` gives access to config thresholds, all model files, and the manifest.
Until additional model contracts exist, the private engine evaluates only
Service, Api, Operation, Subscription, Route, and Network targets; catalog
entries for other scopes are deferred (D-29). Rules must declare their target
model and any additional model they use in `Requires`.
An optional `DataGaps = { param($ctx) ... }` callback declares unavailable
required facts within valid models using `model/<name>.json#<field>` references
to declared `Requires` files. The engine emits one Info/NotEvaluated finding
per rule for these gaps; undeclared paths fail closed (D-30).

### 10.2 Findings schema (`findings.json`, one record per rule × target)
```json
{
  "findingKey": "APIM-SEC-003|apim-synthetic-prod|api:orders-v1",
  "ruleId": "APIM-SEC-003", "title": "...", "pillar": "Security", "mcsb": "IM-1",
  "severity": "High", "scope": "api:orders-v1", "resource": "apim-synthetic-prod",
  "exposure": "ExternalInUse", "usage": "InUse",
  "priorityScore": 9.0,
  "evidence": { }, "evidenceText": "...",
  "recommendation": "...", "effort": "M",
  "sourceFiles": ["raw/apis.json"],
  "status": "Open", "evaluation": "Evaluated"
}
```
- `findingKey` = `ruleId|resourceName|scope` — stable across runs (no timestamps, no GUIDs that change).
- `evaluation` = `Evaluated` | `NotEvaluated` (missing input; severity forced to `Info`, evidence lists missing files).
- `usage`: `InUse` if `calls90d > 0` for API-scoped; `NotApplicable` for service-level.
- When telemetry is missing, `usage` is null (not `Unused`) and uses a neutral
  1.0 priority multiplier. Missing required model files yield one
  Info/NotEvaluated finding per rule; malformed available models fail closed
  (D-29).
- Sorted by `priorityScore` desc, then `ruleId`, then `scope`.

### 10.3 Priority score
`priorityScore = Severity[sev] × Exposure[exposure or 'Platform' for service-level] × Usage[usage]` (weights from config, defaults §5), rounded to 1 decimal.

### 10.4 Action-plan aggregation
For the report, findings are grouped by `ruleId` into **action items**: `affectedCount`, max priority, top 5 affected scopes, combined recommendation. Instance rows remain in "Finding Details".

### 10.5 Not-evaluated handling
If a rule's `Requires` input is missing/failed, emit one `NotEvaluated` finding per rule (not per target) so gaps are visible in the report.

### 10.6 Model-safe analysis package

`analysis-package.json` is a closed, versioned contract produced only from normalized model/findings data. It contains:

- Opaque aliases matching strict patterns such as `service-001`, `api-017`, `route-003`, and `backend-004`.
- Fixed enums, booleans, bounded counts, configured usage buckets, relative cost trends, confidence, assumptions, and data-gap codes.
- Deterministic findings reduced to model-safe evidence and referenced by stable model-safe finding IDs.
- Topology facts required for assessment reasoning, such as `Internal`, `HostWide`, `WafDisabled`, or `CloudflareAssumed`, without names, addresses, URLs, or raw configuration.

It contains no unrestricted source text. The restricted `alias-map.json` remains in the collection zone and maps aliases to customer-facing labels for local rendering only. `Publish-AnalysisPackage` writes the package into a temporary restricted location, validates it, and atomically promotes it to `ModelSafeRoot` only on success. Rejected candidates are never placed in the analysis zone.

### 10.7 Specialist Copilot analysis

Three repository agent profiles are used:

1. **Architecture and exposure analyst** — reviews topology, policy inheritance/control flags, reachability, reliability, and governance.
2. **Security analyst** — reviews authentication, subscription scope, secrets/control flags, TLS, diagnostics, identity, and confidence-qualified threats.
3. **Executive synthesizer** — reconciles validated findings and specialist observations into audience-appropriate priorities, themes, decisions, and next actions.

Specialist outputs are validated against closed schemas. Every observation includes an observation ID, category, confidence, model-safe finding/fact references, rationale, and bounded recommendation code/text selected from an approved vocabulary. Agents cannot introduce new evidence, replace rule severity, or mark deterministic findings resolved. Unsupported claims fail validation and are excluded from reporting.

---

## 11. Starter rule catalog (v1)

Severity defaults; all thresholds configurable. "Data" = model inputs.

### 11.1 Network & exposure (NET)
| ID | Title | Sev | MCSB | Scope | Logic |
|---|---|---|---|---|---|
| APIM-NET-001 | App Gateway trusts edge IP ranges only; no origin authentication | High | NS-6 | Network | WAF/NSG custom rule allows only edge ranges AND no evidence of origin auth (mTLS client cert on listener / secret header check in rewrite or WAF custom rule / APIM `check-header`). Edge ranges are shared by all edge customers. |
| APIM-NET-002 | WAF disabled or in Detection mode on App Gateway | High | NS-6 | Network | WAF policy `state != Enabled` or `mode == Detection`; evidence notes edge WAF assumed |
| APIM-NET-003 | Traffic reached App Gateway from outside trusted edge ranges | Medium | NS-2 | Network | `appgwNonEdge` non-empty (requires `TrustedEdgeRanges`) |
| APIM-NET-004 | Host-wide forwarding publishes entire APIM catalog | High | NS-2 | Route | Any public listener → APIM with pattern `/*`; evidence: count of `ExternalUnintended` APIs |
| APIM-NET-005 | API reachable from internet but only used internally | Medium | NS-2 | Api | `exposure == ExternalUnintended` |
| APIM-NET-006 | APIM gateway directly reachable (bypasses edge and App Gateway) | High | NS-2 | Service | `DirectPublic` |
| APIM-NET-007 | APIM subnet NSG allows broader inbound than App Gateway + internal | Medium | NS-1 | Network | NSG evaluation |
| APIM-NET-008 | Weak App Gateway TLS policy | Medium | DP-3 | Network | sslPolicy predefined older than `AppGwSslPolicy20220101` or min protocol < TLS1.2 |
| APIM-NET-009 | Developer portal / management hostname published publicly without need | Low | NS-2 | Route | portal/management hostname behind public listener |

All seven T-303 rules have model-backed private catalog entries. NET-001
evaluates only attested edge-only ingress and effective origin authentication;
NET-009 targets attested portal/management routes in the network model
(not API rows in `exposure.json`) and requires owner-confirmed lack of need.
Neither treats missing evidence as absent authentication or unnecessary
publication; both remain NotEvaluated without corroboration (D-30/D-31).

### 11.2 Security (SEC)
| ID | Title | Sev | MCSB | Scope | Logic |
|---|---|---|---|---|---|
| APIM-SEC-001 | Legacy TLS/ciphers enabled (gateway or backend side) | Medium | DP-3 | Service | `customProperties` TLS10/TLS11/SSL30/TripleDes168 true |
| APIM-SEC-002 | Minimum management API version not enforced | Low | AM-1 | Service | `apiVersionConstraint.minApiVersion` null |
| APIM-SEC-003 | Reachable API has no caller auth beyond subscription key | High | IM-1 | Api | Applies reachable; `callerAuth ∈ {SubscriptionKeyOnly}` |
| APIM-SEC-004 | Reachable API requires no subscription and no auth | High | IM-1 | Api | reachable; `subscriptionRequired=false` and no JWT/mTLS |
| APIM-SEC-005 | Subscriptions scoped to All APIs (incl. built-in master) active | High | PA-7 | Subscription | `scopeType=AllApis` and `state=active` |
| APIM-SEC-006 | Stale or non-expiring active subscriptions | Low | PA-7 | Subscription | active, `lastUsed` > `SubscriptionStaleDays` or null, or no `expirationDate` on partner products |
| APIM-SEC-007 | Hard-coded credentials in policy | High | DP-7 | Operation | `hardcodedSecret` |
| APIM-SEC-008 | Secret-like named values stored as plain text | Medium | DP-7 | NamedValue | `secret=false` and name/value matches secret pattern |
| APIM-SEC-009 | Secrets/certificates not Key Vault–backed or Key Vault sync failing | Medium | DP-7 | NamedValue/Certificate | `keyVault` null for secret values / `lastStatus.code != Success` |
| APIM-SEC-010 | Backend TLS certificate validation disabled | Medium | DP-3 | Backend | `validateCertificateChain=false` or `validateCertificateName=false` |
| APIM-SEC-011 | Backend over plain HTTP | Medium | DP-3 | Backend/Api | backend URL or `set-backend-service` base-url `http://` (non-internal service exception configurable) |
| APIM-SEC-012 | Unsafe CORS (wildcard origin with credentials) | Medium | DP-3 | Api | `corsUnsafe` |
| APIM-SEC-013 | No backend authentication (managed identity/cert) | Low | IM-3 | Api | `backendAuth=false` and backend not anonymous by design (configurable allowlist) |
| APIM-SEC-014 | Bodies or sensitive headers logged | Medium | LT-3 | Api/Service | diagnostics `body.bytes > 0` or headers include `Authorization`, `Ocp-Apim-Subscription-Key`, `Cookie` |
| APIM-SEC-015 | Tracing allowed on subscriptions | Medium | LT-3 | Subscription | `allowTracing=true` |
| APIM-SEC-016 | Clients still using TLS < 1.2 | Low | DP-3 | Api | `logs/tls.json` |
| APIM-SEC-017 | Defender for APIs not enabled / open Defender recommendations | Medium | LT-1 | Service | defender.json |
| APIM-SEC-018 | Excess write-capable principals on APIM resource group | Medium | PA-1 | Service | count(Owner/Contributor/API Management Service Contributor) > `MaxWriteRolePrincipals` |
| APIM-SEC-019 | No managed identity on APIM | Low | IM-3 | Service | `identity` null |
| APIM-SEC-020 | Mock or trace policies in production | Medium | n/a | Operation | `mockOrTrace` (env = Prod) |

### 11.3 Governance / Operational Excellence (GOV)
| ID | Title | Sev | Logic |
|---|---|---|---|
| APIM-GOV-001 | APIs not in any product | Medium | `products` empty |
| APIM-GOV-002 | APIs missing owner/team tag | Low | `ownerTag` null |
| APIM-GOV-003 | Products without description/owner or with approval disabled for external products | Low | product fields |
| APIM-GOV-004 | Unused APIs (no calls in window) | Medium | `calls90d == 0` (window capped by retention; evidence states effective window) |
| APIM-GOV-005 | Non-current revisions still online | Low | `nonCurrentOnlineRevisions > 0` |
| APIM-GOV-006 | Single-version version sets / unversioned APIs | Low | version set analysis |
| APIM-GOV-007 | Production policy/API differs from source control | Medium | drift `Differs` or `ProdOnly` |
| APIM-GOV-008 | Inconsistent path/versioning conventions | Low | path pattern clustering (`/v1/`, `/api/v1`, none) — service-level finding with distribution |
| APIM-GOV-009 | Diagnostics/logging not configured or sampling < 100% on critical APIs | Medium | diagnostics |
| APIM-GOV-010 | Policy missing `<base/>` drops inherited controls | Medium | `baseMissing` |
| APIM-GOV-011 | Environment drift (Dev/Test/Prod) | Low | drift across envs |

### 11.4 Reliability (REL) / Performance (PERF)
| ID | Title | Sev | Logic |
|---|---|---|---|
| APIM-REL-001 | Production instance not zone-redundant | Medium | Premium and `zones` empty |
| APIM-REL-002 | Single unit in production | Medium | `sku.capacity < 2` |
| APIM-REL-003 | No circuit breaker / pool for critical backends | Low | backends without `circuitBreaker` (critical list configurable) |
| APIM-REL-004 | App Gateway probe not aligned to APIM status endpoint | Low | probe path ≠ `/status-0123456789abcdef` |
| APIM-REL-005 | Certificate expiring within threshold | Medium | hostname/backends/certs expiry < `CertExpiryDays` |
| APIM-REL-006 | Platform version not stv2 | High | `platformVersion` ∉ {`stv2`, `stv2.1`} |
| APIM-PERF-001 | High 5xx rate | Medium | `pct5xx > Error5xxPct` with calls > 1000 |
| APIM-PERF-002 | Slow backends | Low | `backendP95Ms > BackendP95Ms` |
| APIM-PERF-003 | Capacity pressure | Medium | capacity P95 > 70% or max > 85% |

### 11.5 Developer portal (POR)
| ID | Title | Sev | Logic |
|---|---|---|---|
| APIM-POR-001 | Developer portal not enabled/published | Medium | `developerPortalStatus != Enabled` or no published revision |
| APIM-POR-002 | Username/password sign-in or open sign-up enabled | Medium | sign-up enabled / non-Entra identity paths (**build task: confirm exact property for basic identity**) |
| APIM-POR-003 | Products not visible to intended groups / guests can see products | Low | productGroups includes `guests` for non-public products |
| APIM-POR-004 | Weak API documentation | Low | operation description coverage < 80% or `openApiScore < 70` |
| APIM-POR-005 | Legacy portal still enabled | Low | `legacyPortalStatus == Enabled` |

### 11.6 Cost (COST)
| ID | Title | Sev | Logic |
|---|---|---|---|
| APIM-COST-001 | Premium capacity utilization (informational right-sizing) | Info | capacity P95 and max vs units; recommendation respects zone/HA requirement |
| APIM-COST-002 | Cost per million calls trend | Info | month-over-month |
| APIM-COST-003 | Log Analytics ingestion growth from APIM/App GW | Medium | ingestion ×2 over window or body logging + top data types |
| APIM-COST-004 | Logic Apps cost increase (cost-only) | Medium | month cost > 1.5× first month; evidence: change start date, plan SKU/instance changes; states "workflow review out of scope" |
| APIM-COST-005 | Non-prod on Premium / over-provisioned non-prod | Low | env != Prod and sku Premium |

> Maintainers add Microsoft Learn references to `References` manually. The tool must never generate URLs.

---

## 12. Stage 3 — Report

### 12.1 Template-driven
`template/ApimActionPlan.xlsx` holds all workbook formatting: title rows, navy header band (`#1F3864`, white bold), banding, frozen panes, column widths, conditional formats (severity, Pass/Fail, exposure), **empty Excel tables** with fixed names, and Summary formulas/charts bound to those tables. The report script only writes data (`ImportExcel` `Export-Excel -TableName <name> -StartRow 3`), so charts and formulas grow automatically.

`template/executive-summary/` holds local HTML/CSS/SVG templates. The renderer, not an AI model, combines the validated executive summary with restricted local facts and resolves approved aliases through `alias-map.json`.

### 12.2 Sheets
| Sheet | Table name | Source |
|---|---|---|
| Summary | — (formulas) | KPIs via `COUNTIFS` on `tblFindings`/`tblApis`; pillar × severity matrix; chart; top 5 action items; **assumptions banner** (edge mode, data windows, not-evaluated collectors) |
| Action Plan | `tblActions` | §10.4 aggregation + carried-forward tracking columns `Owner`, `Status` (dropdown: Open/In progress/Done/Accepted risk/Not applicable), `Target Date`, `Notes` |
| Finding Details | `tblFindings` | findings.json |
| API Inventory | `tblApis` | model/apis.json |
| Effective Policy Matrix | `tblPolicy` | model/policyMatrix.json |
| Subscriptions | `tblSubs` | model/subscriptions.json |
| Exposure Map | `tblExposure` | model/exposure.json + network summary block |
| Usage | `tblUsage` | model/usage.json + line chart |
| Cost | `tblCost` | model/cost.json + stacked column chart + cost/M calls |
| Environment Drift | `tblDrift` | model/drift.json |
| Run Info | `tblRun` | manifest (collectors, statuses, windows, versions) |
| Method & Rules | `tblRules`, `tblWeights` | rule catalog + scoring weights (editable cells drive a recalculated `Priority` column formula in Action Plan) |

### 12.3 Carry-forward (`Merge-PriorTracking`)
With `-PreviousReport <path>`: read `Action Plan` and `Finding Details` tracking columns, join on `ruleId` (actions) / `findingKey` (details), copy `Owner/Status/Target Date/Notes`. Unmatched prior rows are listed in a `Resolved Since Last Run` section with their tracking values.

### 12.4 File naming
`<Customer> APIM Assessment - <Env> - <yyyy-MM-dd>.xlsx`. Never overwrite; append `-2`, `-3` if exists.

### 12.5 HTML executive presentation

Generate one self-contained `.html` file with no CDN, remote font, analytics, remote image, or runtime network dependency. It must include:

- Branded title and assessment scope, executive posture, KPI cards, top risks, priority actions, assumptions, confidence/data gaps, and next-step roadmap.
- Accessible color contrast, semantic headings, keyboard navigation, print styles, and reduced-motion support.
- Tasteful use of color, typography, emojis/icons, inline SVG diagrams, risk heatmaps, timelines, and charts.
- A deterministic network/exposure diagram and chart data generated locally from restricted models.
- No active content that transmits data. Any script/CSS/image/font dependency is embedded and release-reviewed.

AI-authored narrative uses only model-safe aliases. During local rendering, aliases may be deterministically replaced with approved customer-facing labels; unresolved aliases fail rendering. Exact customer metrics may be inserted locally into predefined chart/table slots but are never sent back to a model.

---

## 13. Run comparison (`Compare-ApimRun`)
Input two run folders. Output `diff.json` and a `Run Comparison` sheet: `New`, `Resolved`, `Persisting` (with severity change), counts by pillar; KPI deltas (reachable APIs, unused APIs, all-API subscriptions, monthly cost).

---

## 14. CLI

```powershell
# Full run, one environment
./Invoke-ApimAssessment.ps1 -Config config/customer.psd1 -Environment Prod [-PreviousReport <xlsx>] [-SkipCost] [-SkipLogs] [-SkipGit] [-Resume <runFolder>]

# Individual stages
./Invoke-ApimCollect.ps1 -Config ... -Environment Prod            # → runs/<id>/raw + manifest
./Invoke-ApimAnalyze.ps1 -RunFolder runs/<id> [-RulesPath rules/] [-OnlyRules APIM-SEC-*]
./Invoke-ApimReport.ps1  -RunFolder runs/<id> [-PreviousReport <xlsx>]
./Compare-ApimRun.ps1    -Baseline runs/<a> -Current runs/<b>

# Local model-data airlock (normally invoked by the broker)
./New-ApimAnalysisPackage.ps1 -RunFolder runs/<id> -CandidatePath <restricted-temp>
./Test-ApimAnalysisPackage.ps1 -CandidatePath <restricted-temp>/analysis-package.json
./Publish-ApimAnalysisPackage.ps1 -CandidatePath <restricted-temp> -Destination <ModelSafeRoot>

# Multi-env drift
./Invoke-ApimAnalyze.ps1 -RunFolder runs/<prod> -CompareRuns runs/<dev>,runs/<test>
```
Exit codes: 0 success; 1 config error; 2 auth error; 3 completed with collector failures; 4 analysis/report failure.

### 14.1 Copilot orchestration

The operator may select the repository assessment-orchestrator agent/skill. Copilot calls a narrow local broker rather than arbitrary PowerShell:

- `run_assessment(configAlias, environment, options)` → opaque run ID and coarse stage status only.
- `get_assessment_status(runId)` → fixed stage/status/error-code enums only.
- `promote_analysis_package(runId)` → validation/promotion status and package hash only.
- `read_validated_analysis_package(runId)` → package only when attestation is valid and the package hash still matches.
- `render_reports(runId, validatedAgentOutputs)` → output status and local paths represented as opaque artifact IDs to the model.

The broker allowlists operations and arguments, resolves local paths internally, captures/sanitizes stdout and stderr, never returns Azure exceptions verbatim, and has no generic command-execution method.

### 14.2 Manual and degraded operation

Collection, deterministic analysis, Excel, and HTML rendering remain runnable without Copilot. If Copilot, a specialist agent, or model-safe validation is unavailable, the toolkit produces deterministic findings and reports without AI observations. It must never substitute unvalidated model output or silently broaden model access.

---

## 15. Non-functional requirements

| Area | Requirement |
|---|---|
| Security | Read-only (§3.1). No secret values persisted or logged. Policy collection detects secret candidates, records structural locations only, and replaces literals with `***REDACTED***` before persistence. Offline flagging recognizes those trusted markers and must match pre-redaction synthetic flag/location results (D-14). |
| AI data boundary | Raw/model/restricted data never enter model context. Package construction is allowlist-only; validation and physical promotion are fail-closed (§3.2, §10.6). |
| Privacy | User identities not stored by default; principals reported as counts/types unless enabled. |
| Data handling | Runs are written locally; README states runs must be stored in a customer-approved location and deleted after readout. Agent-assisted restricted roots are outside every Copilot-visible path; repository-local manual defaults remain gitignored. |
| Performance | ~60 APIs / ~600 operations: collection < 15 min (excl. Cost throttling); analysis < 2 min; report < 1 min. |
| Reliability | Collector isolation; retries; `-Resume`. |
| Determinism | Stable sort, stable keys; analysis on the same raw folder yields byte-identical `findings.json` (excluding `generatedUtc`). |
| Traceability | Every AI observation cites model-safe findings/facts; deterministic evidence and severity remain authoritative. |
| Observability | `logs/run.log` + console progress; summary table at end of each stage. |
| Quality | PSScriptAnalyzer clean (default rules, no `Write-Host` except progress helper); Pester coverage ≥ 80% for `src/Model` and `src/Rules`. |
| Portability | No hard-coded paths; works on Windows and Linux PowerShell 7. |
| Presentation | Excel and self-contained HTML render locally, contain no remote dependencies, and meet basic accessibility/print requirements. |

---

## 16. Testing

| Level | Content |
|---|---|
| Unit | `Invoke-ApimArm` (method allowlist, URL denylist, paging, 429 retry with mocked responses); `Merge-ApimPolicy` (base present/missing, fragments, multi-product); `Get-PolicyFlags` (each flag positive/negative); exposure classifier (Internal VNet + Basic rule, path-based, rewrite unknown, DirectPublic, private listener ambiguity); each rule ≥ 1 pass + 1 fail fixture; priority scoring; findingKey stability. |
| Fixtures | `tests/fixtures/synthetic-reference/` — synthetic raw folder mirroring §2 topology (60 APIs, Internal VNet, Basic rule, WAF disabled, edge allowlist, 4 all-API subs, 11 unused APIs, 3 missing `<base/>`, 2 hard-coded secrets, etc.). **No real customer data or identifiers.** |
| Integration | Offline: fixtures → analyze → report; assert findings count by rule, workbook tables populated, Summary formulas evaluate (open with ImportExcel and check computed values or validate formula strings). |
| Model-data airlock | Plant synthetic canaries in every source field and encoded/nested variants; assert none occur in package content, fragments, hashes, logs, validation errors, or promoted artifacts. Mutate source schemas to prove unknown fields cannot flow through. |
| Package validation | Closed-schema, forbidden-key/value, entropy, Unicode/encoding, path-overlap, hash/attestation, time-of-check/time-of-use, and fail-closed promotion tests. |
| Agent contracts | Validate architecture/security observations and executive summary; reject unsupported references, invented evidence, unapproved text, and deterministic severity overrides. |
| HTML report | Assert self-contained output, no network URLs/dependencies, all aliases resolved, required sections present, accessible structure/contrast tokens, and print CSS. |
| Live smoke | Against a Microsoft-owned test APIM (Developer tier) before first customer run. |
| Schema | Every model file and findings.json validated with `Test-Json -SchemaFile`. |

Before the full live-smoke acceptance, a maintainer-only collection smoke entry
point may exercise the implemented collectors using the same fixed, cumulative
check list on a Microsoft-owned test instance (D-20). It requires existing
matching Azure context and private external configuration/output, isolates
collector failures, and streams numbered check transitions with fixed statuses,
bounded failure codes, and fixed troubleshooting hints. Interactive UTF-8 emoji
and a compact scorecard replace the running row in place, restoring console
output encoding per write; redirected output or `NO_COLOR` uses readable ASCII
(D-26/D-28). Marked XML parser failures report `POLICY_XML_REJECTED` (D-27).
No raw exception message, stack, identifier, or path enters progress output
(D-25).
Agents and CI run the synthetic/mocked tests, never live Azure collection. A
passing collection smoke
does not satisfy the full-run exit-0 check or G3 customer-run gate.
For a failed check, the maintainer smoke may also print a bounded failure code
derived from a marked ARM wrapper exception (`ARM_HTTP_100` through
`ARM_HTTP_599`, `ARM_AUTH_ERROR`, `ARM_COMMAND_ERROR`,
`ARM_NETWORK_ERROR`, `ARM_TIMEOUT`, or `ARM_NO_RESPONSE`), a local I/O exception
(`LOCAL_IO_ERROR`), a marked XML parser rejection (`POLICY_XML_REJECTED`),
or an unclassified exception (`UNKNOWN_FAILURE`).
Transport classifications use only known exception types and fixed PowerShell
error categories; `ARM_NO_RESPONSE` alone does not prove a network issue.
It never prints exception text, response content, paths, or identifiers (D-21/D-22).

---

## 17. Acceptance criteria (v1)

1. Full run against an authorized customer Prod environment completes with Reader access only; manifest shows all collectors `Completed` or explicitly `Skipped`.
2. No non-GET calls other than the allowlist appear in the run log; denylist unit tests pass.
3. No secret values in any output file (scripted grep for subscription key format, named-value secrets, JWTs returns nothing).
4. Raw/model/restricted data are inaccessible to Copilot agents; the broker exposes no generic shell, path, stdout/stderr, credential, or raw-data operation.
5. Canary and mutation suites prove prohibited customer/infrastructure values and unknown fields cannot enter or be promoted in `analysis-package.json`; attestation/hash checks pass.
6. Exposure map correctly reports host-wide forwarding (`NET-004`) and classifies each API as `ExternalInUse`/`ExternalUnintended`/`Restricted` per §9.
7. Every finding has `evidence`, `sourceFiles`, and stable `findingKey`; re-running analysis produces identical findings.
8. Every specialist/executive observation validates, cites model-safe finding/fact IDs, and leaves deterministic evidence/severity unchanged.
9. Workbook is generated locally from the template with all sheets populated; Summary KPIs match `findings.json`; charts render.
10. HTML executive presentation is self-contained, visually reviewed, accessible/printable, contains no remote dependency, and resolves every approved alias locally.
11. Re-run with `-PreviousReport` preserves Owner/Status/Target Date/Notes.
12. `Compare-ApimRun` correctly reports New/Resolved/Persisting on fixture variants.
13. Dev and Test runs complete with the same config file; drift sheet populated.
14. README + RUNBOOK allow a second CSA to run the deterministic and Copilot-assisted paths without assistance.

---

## 18. Open items / decisions for the build

| # | Item | Default if unresolved |
|---|---|---|
| 1 | Exact ARM property/mechanism to detect username/password identity on the developer portal | Detect via sign-up setting + identity providers; mark POR-002 evidence "heuristic" |
| 2 | Cloudflare origin-auth evidence (Authenticated Origin Pulls / secret header) not visible in Azure if done only via listener mTLS | Check listener SSL profile client-auth + WAF custom rules + APIM `check-header`; else finding with "Confirm with customer" note |
| 3 | Git repo layout | Support APIOps extractor layout; configurable regex |
| 4 | Whether App GW has any private listeners to APIM | Auto-detect; confidence downgrade if present |
| 5 | Log Analytics retention < 90 days | Cap window and state effective window in evidence |
| 6 | PowerPoint/readout deck automation | Out of v1; v1 produces a self-contained HTML executive presentation and keeps PowerPoint manual |
| 7 | AI gateway instance assessment | Same toolkit should run unchanged against it later; add AI rules (token limits, semantic cache, content safety) in v1.1 |
| 8 | Customer/organization approval for model-safe derived assessment facts | Copilot analysis remains disabled; deterministic collection, findings, Excel, and HTML still run locally |
| 9 | Local Copilot broker implementation | Prefer a local stdio MCP tool surface with exact tool/argument allowlists; manual path remains mandatory |
