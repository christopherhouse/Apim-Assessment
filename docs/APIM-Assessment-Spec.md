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

The maintainer development lab in section 16.1 is separate test
infrastructure, not an assessment/remediation capability. Its plan does not
authorize deployment or weaken any runtime/data-access constraint above.

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
  RuleTargets = @{
    CriticalBackendIds = @() # exact backend IDs declared critical by an operator
  }
  Governance = @{ # optional explicit intent; omission is Unknown, not a safe default
    Products = @(@{ ProductId='external-product'; HasOwner=$true; IsExternal=$true })
    CriticalApiIds = @('critical-api') # explicit empty array attests no critical APIs
  }
  RuleExceptions = @{
    ApprovedPlainHttpBackendIds = @()
    ApprovedPlainHttpOperationKeys = @() # exact apiId/operationId keys
  }
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
them. The optional `RuleTargets` map accepts only unique, case-insensitive exact
backend IDs; absent or empty `CriticalBackendIds` declares no critical backend
targets. The optional `RuleExceptions` map accepts only non-empty, unique
case-insensitive resource-name segments for exact backend IDs and
`apiId/operationId` keys; absent or empty arrays approve nothing. Existing
symbolic links/junctions in either root are rejected.
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
  "schemaVersion": "1.1",
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
  "scoring": {
    "severity": { "high": 3, "medium": 2, "low": 1, "info": 0.5 },
    "exposure": {
      "directPublic": 2.5, "externalInUse": 2,
      "externalUnintended": 2, "restricted": 1.5, "internal": 1,
      "platform": 1.5, "unknown": 1.5
    },
    "usage": { "inUse": 1.5, "unused": 1, "notApplicable": 1 }
  },
  "stages": { "collect": "Completed", "analyze": "Completed", "report": "Completed" },
  "collectors": [ { "name": "Policies", "status": "Completed|Partial|Failed|Skipped", "items": 612, "errors": 0, "durationSec": 41 } ],
  "modelSafe": { "build": "Completed", "validation": "Passed", "promotion": "Completed", "packageSha256": "..." },
  "warnings": [ "..." ]
}
```

Rules: a collector failure **never** aborts the run; it is recorded as `Failed/Partial` and dependent rules emit `Info` "Not evaluated" findings (see §10.5).
Collector records may additionally contain a closed `files` array of safe relative
paths. Identity/Portal records bind their persisted allowlisted outputs this way;
legacy records without it remain valid. Before Partial ingestion, validate the
listed inventory, closed payload shapes and aggregate item count; never read
unlisted stale files.

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
| `openapi/<api>.json` | `{base}/apis/{api}?export=true&format=openapi+json` (validated `openapi+json-link` fallback) | Validated, secret-candidate-free JSON OpenAPI doc plus closed `openapi/index.json` inventory (D-58) |
| `products.json` | `{base}/products` | `state`, `subscriptionRequired`, `approvalRequired`, `subscriptionsLimit`, `description` |
| `productApis/<product>.json` | `{base}/products/{p}/apis` | API membership |
| `productGroups/<product>.json` | `{base}/products/{p}/groups` | visibility |
| `subscriptions.json` | `{base}/subscriptions` | Allowlisted `name`, `scope`, `state`, derived non-identifying `ownerType`, `createdDate`, `expirationDate`, `allowTracing`, `displayName`. Absent optional display name/tracing/creation date remain null and downstream `missingInputs` records the gap; never infer false tracing. Models accept documented relative `/apis`, `/apis/{id}`, `/products/{id}` and full ARM scopes. Drop `ownerId`, keys, and unknown fields; **never** call `listSecrets`. |
| `namedValues.json` | `{base}/namedValues` | Allowlisted `name`, `displayName`, `secret`, `keyVault.secretIdentifier`, `keyVault.lastStatus.code`, sorted `tags`, and derived `secretPatternLocations` (`displayName`/`value`). Inspect `value` in memory only, then always drop it. |
| `backends.json` | `{base}/backends` | Allowlisted `name`, HTTP(S) `url` with user-info/query/fragment stripped plus `urlSanitized`, `protocol`, nullable TLS validation flags, structural credential summary (`configured`, types, authorization scheme, certificate count, header/query names, unknown-field Boolean), circuit-breaker/pool presence and pool count, and `type`. Never persist credential values or unknown fields. |
| `certificates.json` | `{base}/certificates` | Allowlisted `name`, normalized `expirationDate`, and `keyVault.secretIdentifier`; drop certificate data, passwords, private material, identities, and unknown fields. |
| `identityProviders.json`, `authorizationServers.json`, `openidConnectProviders.json`, `authorizationProviders.json` | respective collections | Closed structural allowlists: provider type enums, authorization-server enum arrays/nullable flags, OIDC usage flags, authorization-provider derived authorization-code/client-credentials configured flags. Drop secrets, client/tenant IDs, URLs, free text and unknown fields before persistence. |
| `loggers.json`, `diagnostics.json`, `apiDiagnostics/<api>.json` | `{base}/loggers`, `{base}/diagnostics`, `{base}/apis/{api}/diagnostics` | Closed allowlists only. Loggers retain `name`, `loggerType`, target `resourceId`, and nullable `isBuffered`. Diagnostics retain `name`, `loggerId`, `alwaysLog`, `samplingType`/percentage, `verbosity`, nullable `logClientIp`, correlation protocol, sorted request/response header names, and nullable body-byte counts for frontend/backend. Missing fields/sections remain null and known empty header lists remain arrays. Drop logger credentials/descriptions, payload samples, data-masking configuration, header values, and unknown fields. Service files may remain with Partial status if bounded per-API collection fails. |
| `portal/signin.json`, `signup.json`, `delegation.json`, `config.json`, `revisions.json` | `{base}/portalsettings/signin`, `/signup`, `/delegation`, `{base}/portalconfigs/default`, `{base}/portalRevisions` | Closed structural sign-in/sign-up/delegation flags, direct enableBasicAuth, require-signin flag and revision current/status. Singleton name may be null; missing settings stay null, never default false. Drop delegation validation keys, URLs, secrets and unknown fields before persistence. |
| `groups.json`, `tags.json`, `apiVersionSets.json`, `gateways.json`, `workspaces.json`, `policyFragments.json` | respective collections | Closed `name`/`properties` projections: only group `type`/nullable `builtIn` and version-set `versioningScheme` survive within properties. Drop display names, descriptions, external identities, fragment XML and unknown fields. |
| `users.summary.json` | `{base}/users` | **Always counts only** (D-59); fixed state/provider categories, no records or identities. `StoreUserIdentities=$true` is rejected before authentication or run creation. |

The Organization collector handles these seven endpoints independently using
guarded GETs. A denied/unsupported/failed endpoint records Partial/Failed with
only successful files listed; it is never persisted as an empty inventory.
Known empty successful collections remain valid. User state categories are
`active`, `blocked`, `pending`, `deleted`, `Unknown`; provider categories are
`basic`, `aad`, `aadB2C`, `facebook`, `google`, `microsoft`, `twitter`, `Unknown`.
Provider counts are per user per category, not identity-record counts; their sum
may exceed total. Repeated user IDs are deduplicated in memory, conflicting
state/provider summaries fail, and IDs never persist. Resume and smoke validate
closed projections/count consistency and do not trust stale unlisted files.

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
- `security/roleAssignments.json`: planned `authorizationresources` role assignments at RG and resource scope (principalId, principalType, roleDefinitionId → resolved role name). Principal display names are not collected; identity-storage opt-in is unsupported under D-59.

### 7.6 Logs (Log Analytics)
Detect schema first: if `ApiManagementGatewayLogs` has rows in the window use **resource-specific** queries, else fall back to `AzureDiagnostics` variants (`queries/*.azdiag.kql`). Record which in manifest. Resolve configured workspace GUIDs through scoped Resource Graph queries, then obtain workspace/table retention through guarded ARM GETs. Cap each log family to its table retention (workspace retention when inherited). Mixed-schema observations and absent APIM observations cannot establish complete usage or zero calls. Manifest 1.2 and settings 1.1 record run-anchored requested/effective windows and explicit targets/opt-outs. New collections use settings 1.2 for the D-63 route capability; legacy settings 1.0/1.1 and resumes retain their prior contracts. Detect `AGWAccessLogs` versus `AzureDiagnostics` independently for configured gateway resource IDs, with separate AppGateway coverage capped to its selected table retention.

| Raw file | Query (resource-specific form) |
|---|---|
| `logs/usageByApi.json` | Calls, 4xx, 5xx, 401/403, P50/P95 `TotalTime`, P95 `BackendTime`, `dcount(ApimSubscriptionId)`, `LastCall` by `ApiId, OperationId, ProductId` over `UsageDays` |
| `logs/usageByRoute.json` | Same, adding `Route = iif(ipv4_is_in_any_range(CallerIpAddress, appGwCidrs), "ViaAppGw", "Internal")` |
| `logs/usageMonthly.json` | Calls by `ApiId`, month |
| `logs/tls.json` | Calls by `ClientTlsVersion`, `ApiId` over `SecurityLogDays` |
| `logs/noSubscriptionCalls.json` | Calls with empty `ApimSubscriptionId` by `ApiId` |
| `logs/appgwByListener.json` | Selected gateway schema: requests and distinct-client counts by configured gateway ID, listener, rule and host; no individual client IPs |
| `logs/appgwNonEdge.json` | Same aggregate grain plus fixed NonEdge/Unknown client class outside configured trusted ranges; no per-IP rows (D-63) |
| `logs/directNonAppGw.json` | Per-API counts outside App GW subnets **and** `InternalCidrs`; unknown/unparseable callers are not asserted direct |
| `logs/headersLogged.json` | Calls, observed-header-bag count, and presence counts for `X-Forwarded-For` / `CF-Connecting-IP`; never header values |

The four route files use closed `observed-route-evidence` 1.0 envelopes with
per-workspace schema/status/reason and matching effective-window/retention
bindings. Gateway queries are resource-scoped; direct/header queries are
APIM-scoped. Failed/Skipped records have no rows; absent header bags remain
distinguishable from observed absence. Non-edge queries without trusted edge
ranges, and direct-call queries without gateway subnet CIDRs, are explicitly
Skipped/Unconfigured. `SkipLogs` excludes all four; `SkipCost` does not.
Settings 1.2 snapshots trusted IPv4 CIDRs, including nonblank/comment-stripped
lines from `TrustedEdgeRangesFile`; unsupported CIDRs reject. Saved replay does
not reopen that file.

### 7.7 Metrics (Azure Monitor)
`metrics/apim.json`: `Capacity` (avg, max; PT1H), `Requests` (total; P1D), `Duration`, `BackendDuration` (avg; PT1H) for `MetricDays`. `metrics/appgw.json`: `CapacityUnits`, `Throughput`, `UnhealthyHostCount`.

### 7.8 Cost (Cost Management Query API)
`cost/daily.json`: `type=ActualCost`, `timeframe=Custom` (last `CostMonths` full months + MTD), `granularity=Daily`, aggregation `PreTaxCost` (sum), with resource/category/subcategory detail. Under D-61 the API's two-group limit requires a ResourceId/MeterCategory query per scope followed by ResourceId/MeterSubCategory queries filtered per observed category; reconcile daily resource/category/currency totals before accepting detail. Bound category expansion. Handle 429 with `x-ms-ratelimit-microsoft.costmanagement-*-retry-after`. Required token-bearing continuation URLs remain prohibited: record incomplete evidence rather than bypassing the guard or interpreting a truncated page as full cost.

`cost/logicApps.json` (cost-only): inventory of `Microsoft.Logic/workflows` and `Microsoft.Web/sites` (kind contains `workflowapp`) + App Service plan SKU/instance count; metrics `BillableActionExecutions`/`BillableTriggerExecutions` (Consumption) and plan `CpuPercentage`/instance count (Standard). **No workflow definitions are read.**

`cost/laIngestion.json`: `Usage | where TimeGenerated > ago(90d) | summarize GB=sum(Quantity)/1024 by DataType, bin(TimeGenerated, 1d)` on the APIM workspace.

### 7.9 Source control (optional)
If `GitRepoPath` is configured, read an immutable committed HEAD snapshot from
that absolute local ordinary-clone path unless `-SkipGit` is set. No configured
repository records Git Skipped without blocking single-run analysis/reporting;
an explicit `-SkipGit:$false` without configuration fails before authentication.
Never clone, fetch, pull, check out, execute source scripts, modify Git config,
or inspect dirty/untracked policy files. Bare repositories, `.git` indirection,
linked worktrees, links, gitlinks, and escaping roots are unsupported.

`GitPolicyRoot` is a safe non-empty slash-separated relative Git path. Default
APIOps mappings are `policy.xml` (Global/global), `products/<p>/policy.xml`,
`apis/<api>/policy.xml`, and `apis/<api>/operations/<op>/policy.xml`.
An optional `GitPolicyMappings` array replaces all defaults with closed
`{ScopeType, Pattern}` maps. Patterns are fully anchored, at most 1,024 characters,
and time out after 100 ms; required named captures are `product`, `api`,
`operation`, and `fragment` as appropriate. At most 32 mappings are accepted.
Scope IDs match deployed policy indexes: `global`, product/API IDs,
`api|operation`, and fragment IDs. Ambiguity, collisions, unmapped XML, malformed
XML, or missing committed roots fail rather than silently reducing coverage.

Protect secret-bearing XML in memory before normalization/hashing, matching
deployed saved policy semantics. Persist only closed version 1.0
`git/policyHashes.json`: `commitSha`, sorted `scopeTypes`, and unique sorted
`{scopeType,scope,sha256}` policies. Never persist source XML, paths, author
identities, remotes, or process stderr. UTF-8 including BOM is supported.
Limits are 15 seconds per process, 8 MiB tree output, 1 MiB/blob, 16 MiB aggregate
XML, and 4,096 policies. Resume compares the committed snapshot before reuse;
changes/failure invalidate downstream stages and package state. Optional Git is
separate from the maintainer smoke checks. See D-56 and the runbook.

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
`subscriptions`, `namedValues`, `backends`, `certificates`, `network`, and
`exposure` (D-19/D-36). Pending outputs are serialized once, validated with
`Test-Json -SchemaFile`, and only those validated snapshots are persisted. The
private saved-run loader requires every implemented model file and validates the
complete set before returning anything to downstream analysis. Missing files,
unknown model names, unavailable schemas, and invalid JSON/schema data fail
closed. Future model contracts join the gate with their builders; public Analyze
orchestration remains T-311.

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
| `bodyLogging`, `sensitiveHeadersLogged` | bool/null | Effective diagnostics using default API-over-all-APIs precedence. A non-empty API-level collection overrides the service collection; an empty API collection inherits it. `bodyLogging=true` when any effective frontend/backend request/response body-byte count is positive. `sensitiveHeadersLogged=true` when effective frontend/backend request headers contain `Authorization`, `Ocp-Apim-Subscription-Key`, or `Cookie` case-insensitively. Missing child evidence or normalized sections remains null and retains `missingInputs=["diagnostics"]` unless a positive fact is already known. |
| `reachability` | enum (§9) | exposure model |
| `exposure` | enum (§9) | exposure model |
| `calls90d`, `callsViaAppGw`, `callsInternal`, `lastCall`, `p95Ms`, `backendP95Ms`, `pct5xx` | | logs |
| `openApiScore` | int 0–100 / null | Spectral (§8.6) |
| `inGit` | bool/null | Remains unavailable for policy-only Git inventory; XML absence does not establish API source-catalog absence |
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
| `service.json` | single object | nullable SKU name/capacity, zones, nullable platform version, normalized hostname-certificate expirations, nullable `legacyTlsEnabled`, `enabledLegacyTlsControls[]`, nullable `minApiVersion`, normalized `managedIdentity`, completeness metadata |
| `policyMatrix.json` | API | `apiId` + one column per control: `callerAuth`, `rateLimit`, `ipFilter`, `corsSafe`, `backendAuth`, `noHardcodedSecret`, `basePresent`, `noMockTrace` with values `Pass`/`Fail`/`NA` |
| `subscriptions.json` | subscription | `subscriptionId`, `displayName`, `scopeType` (`AllApis`/`Product`/`Api`), `scopeTarget`, `state`, `ownerType`, `createdDate`, `expirationDate`, `allowTracing`, `calls90d`, `lastUsed`, `isBuiltInMaster`, `flags[]` |
| `namedValues.json` | named value | `namedValueId`, `secret`, nullable `keyVaultBacked`/`keyVaultStatus`, structural `secretPatternLocations[]`, derived `plainTextSecretLike`, completeness metadata |
| `backends.json` | backend | `backendId`, URL `scheme`, nullable `tlsValidationChain`/`tlsValidationName`, `credentialConfigured`, circuit-breaker/pool flags, completeness metadata |
| `certificates.json` | certificate | `certificateId`, normalized nullable `expirationDate`, nullable `keyVaultBacked`, completeness metadata |
| `exposure.json` | route × API | stable `routeKey`, `gateway`, `listener`, `listenerHost`, `backendHost`, `frontendType` (Public/Private), `ruleType`, `pattern`, `wafState`, `wafMode`, `edge` (`Cloudflare-Assumed`), `apiId`, `reachability`, `restriction`, `exposure`, `callsViaAppGw`, `callsInternal`, `confidence`, `baseMissingBypass`, `restrictedOperations[]`, completeness metadata |
| `network.json` | single object | APIM VNet mode, public access, NSG evaluation result, other front doors, App GW TLS policy, APIM-targeted probe alignment/paths, WAF state, optional operator-attested edge/origin and auxiliary endpoint facts |
| `usage.json` | optional closed object, API × month rows | same-window `calls`, partial boundary-month status; top-ten APIs |
| `cost.json` | optional closed object, resource × day/month | deduplicated daily and monthly `resourceId`, `resourceType`, meter categories, signed `cost`, separate `currency`; normalized APIM + App GW costs/calls, ingestion and cost-only Logic Apps |
| `capacity.json` | optional closed object, day rows + summary | nullable `capacityAvg`, `capacityMax`, nearest-rank hourly-average `capacityP95`, current `units`, actual/expected sample counts |
| `drift.json` | optional policy/catalog × environment pair | `category` (Git/Environment), stable `key`, `environmentA/B`, nullable `presentA/B` and `hashA/B`, `changeType` (All/ProdOnly/Differs/SourceOnly/Missing/Unknown), severity, fixed note, completeness metadata; closed restricted source inventories retain every selected environment |
| `portal.json` | optional single object | nullable modern/legacy status, current-completed publication, direct basic-auth attribution, nullable sign-in/sign-up/delegation settings, provider types, nullable custom-domain inventory, explicit product/group intent and mismatch facts, completeness metadata |
| `products.json` | optional product | `productId`, `productFound`, nullable `hasDescription`, `hasOwner`, `isExternal`, `approvalRequired`, completeness metadata |
| `diagnosticCoverage.json` | optional current API | `apiId`, `apiFound`, nullable `configured`, `loggerResolved`, `samplingPercentage`, `isCritical`, effective `sourceScope`, completeness metadata |
| `openApiQuality.json` | API | Spectral error/warn counts, score |

Product governance and diagnostic coverage are additive under D-59. The ten
required model files and legacy saved-run path are unchanged. Their sources are
the existing validated Completed Products/Apis/Diagnostics collectors, not
Organization success. Missing collector evidence never becomes a safe empty
inventory. Present governance models are closed-schema validated and rebuilt
from saved sources/settings before loading; modified model/source/intent fails
closed. Product text is reduced to description presence, never owner identity.

Under D-60/D-62, manifest 1.2 runs add all three telemetry model objects with
`schemaVersion`, `sourceSha256`, `modelStatus` and fixed `missingInputs`.
Every saved-model load rebuilds them from validated closed evidence and saved
settings and compares the projection; malformed or changed sources/models fail
closed. Legacy ten-model runs retain manifest/settings versions and do not gain
telemetry defaults. Date instants are canonicalized in UTC for stable bindings.

Usage is API-month aggregate evidence, not per-subscription usage or observed-route
exposure. Identical workspace copies/windows count once; differing copies leave
denominators unknown. Complete empty intervals may establish zero; partial,
skipped or failed inputs cannot. Cost deduplicates identical overlapping daily
resource/category/subcategory/currency keys and rejects conflicting amounts.
Currencies never combine. Same-period scoped costs per million APIM calls stay
null for unknown/zero denominators or incomplete cost coverage. Adjacent complete
calendar months alone yield normalization changes; MTD never becomes a full
month. Daily costs remain available in the closed model.

Ingestion uses relevant billable workspace-table totals, not individual-resource
attribution. Logic Apps inventory retains only ARG-projected identities, current
linked Standard-plan SKU/instances and guarded metric evidence. It never requests
workflow definitions; Standard plan cost is shared-plan cost, and historical
plan changes remain null. Capacity P95 is nearest-rank over hourly average
samples, not a native Azure percentile. Units/SKU/zones are current snapshots,
not historical sizing or proof of safe downsizing/savings.

Optional closed `Governance.Products` contains unique exact `ProductId`,
Boolean `HasOwner` and Boolean `IsExternal`; `CriticalApiIds` contains unique
exact current API IDs. Validation rejects unknown fields, duplicate/malformed
IDs, non-Booleans and arrays over 10,000. Intent is snapshotted in restricted
camelCase run settings. Absent intent is Unknown, explicit empty critical IDs
attest none, and unresolved targets retain Partial rows rather than disappearing.
API diagnostics override service diagnostics; service fallback requires a known
empty API collection. Missing collection/settings are not disabled diagnostics.
Logger references resolve only against collected logger IDs. Sampling is a
known fixed percentage in [0,100], never an assumed default; conflicting or
unavailable evidence retains null/qualified gaps.

Portal is additive under D-57, not an eleventh required baseline model.
Existing ten-model runs remain loadable without recollection; offline Analyze
refreshes the expanded catalog with explicit Info/NotEvaluated portal gaps.
Malformed present portal evidence/models fail closed. Analyze reads only
manifest-listed validated Completed/Partial Identity/Portal files; other missing
facts remain null/Unknown. An absent custom-domain inventory is not an empty one.
Publication requires a current revision with completed status; conflicting current
revisions remain Unknown. A nonempty historical revision list is not publication.

`Portal.ProductVisibility` is optional closed configuration: entries contain
`ProductId`, Boolean `IsPublic`, and `IntendedGroupIds[]`. Reject duplicate/malformed
IDs and unknown fields; snapshot the intent in restricted run settings for replay.
Resolve exact resource names against collected products/group memberships.
Missing/unresolved expectations never become safe/public defaults or disappear.
Known positive mismatches remain findings despite unrelated incomplete evidence.
No user enumeration or portal crawling is required.

Drift is optional (D-56), not an eleventh required baseline model. Analyze accepts
up to 15 explicit `-CompareRuns` inputs with matching customer/tenant, supported
saved contracts, distinct case-insensitive environment/resource identities and
distinct run IDs. Different subscription/resource names are allowed. Operators
own environment grouping; no naming-based relationship is inferred. Deployed
policy inventories require complete Apis, Products and Policies collector
evidence; incomplete sources become Unknown, while malformed requested evidence
fails. Environment comparisons also include current API catalog presence, not
full API-definition differences. Git policy XML does not establish API catalog
presence or absence.

Save closed current/source inventories under `restricted/drift-inputs.json`
without external paths; `restricted/drift-binding.json` binds canonical input and
model digests. Reanalysis without CompareRuns reuses validated saved sources;
valid explicit inputs replace environment sources, while empty requests fail.
Reporting/package loading
rebuilds drift and checks input/model digests, current deployed evidence, and
saved Git policy evidence. External source folders are not reopened.
Digest bindings are local integrity checks under operator-owned storage, not
signatures. Tampered/missing requested artifacts fail closed.

Pairwise rows preserve every selected environment's presence/hash values without
hard-coding Dev/Test/Prod columns. `All` means equal available evidence;
`ProdOnly`, `Differs`, `Missing`, and `SourceOnly` describe known differences.
Unmapped Git scope coverage or incomplete inventories yield null values,
`Unknown`, and fixed gap codes, never a pass. Equal policy hashes compare
protected normalized XML, not secret literals. GOV-007 (production Git) and
GOV-011 (environments) each aggregate one service-scoped finding with all known
differences and incomplete-comparison counts; missing evidence alone emits one
Info/NotEvaluated. Known differences survive unrelated unknown comparisons.
Environment Drift uses the existing pairwise table; no-source runs leave it
unpopulated and label coverage explicitly in Run Info. Workbook row limits,
literal cells, template styling, tracking and paired HTML replay remain unchanged.

The closed service-security model recognizes gateway TLS 1.0, TLS 1.1, 3DES,
and backend TLS 1.0/TLS 1.1 custom properties. Any explicit enablement sets
`legacyTlsEnabled=true` and retains only normalized control names. All five
controls must be explicitly disabled to produce false; otherwise, no known
enablement produces null plus `missingInputs=["legacyTlsControls"]`. The model
retains the minimum management API version or null and normalizes service
identity to `None`, `SystemAssigned`, `UserAssigned`, or
`SystemAssignedUserAssigned`; resource IDs and user-assigned identity IDs are
not retained. The same closed object normalizes SKU name/capacity, sorted zones,
lower-case platform version, and hostname-certificate expiration dates for
reliability rules; absent SKU, platform, or configured-hostname expiry facts
remain explicit in `missingInputs` (D-39/D-41).

Subscription scope is derived from a full ARM service resource path or the
documented relative scope: the service root or `/apis` is `AllApis`,
`/products/{id}` is `Product`, and `/apis/{id}` is `Api`.
`scopeTarget` is null for AllApis and the decoded terminal ID otherwise.
`subscriptionId=master` at AllApis scope is the built-in master. Collection
derives `ownerType` in memory and drops `ownerId`; model flags are sorted from
`AllApis`, `AllowTracing`, `BuiltInMaster`, `NoExpiration`, and `OwnerMissing`.
Until usage telemetry is available, `calls90d` and `lastUsed` are null with
`modelStatus=Partial` and `missingInputs=["usage"]`.

The three security-asset arrays are derived only from the closed T-108
collector payloads. Named-value values are never present; SEC-008 uses the
collector's allowlisted `displayName`/`value` pattern locations plus the secret
flag to derive `plainTextSecretLike`. Backend URLs are reduced to scheme and
structural controls. HTTPS certificate-chain and hostname-validation settings
remain Boolean or null; for HTTP backends they are normalized to null because
TLS validation is not applicable. Certificates retain normalized expiry and
whether a complete Key Vault reference is present, never encoded/private
certificate material. Missing Key Vault, HTTPS TLS, or expiry facts produce
Partial records with explicit `missingInputs`, not safe defaults (D-33/D-36).

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

T-105/T-504 implement this as an optional closed `model/openApiQuality.json`
array with one row per current API. Rows retain status, nullable error/warning
counts and score, expected/described operation counts and nullable coverage,
source/ruleset digests, tool version, exact scoring penalties, completeness and
fixed missing-input reasons. Scored rows alone have numerical scores.
Optional root configuration `OpenApiQuality` contains only integer
`ErrorPenalty`/`WarningPenalty` values from 0 through 100 (defaults 10/2);
the restricted run-setting snapshot retains configured values for replay.
Absent configuration does not change legacy settings digests.

Collection uses guarded GET-only ARM export and a credential-free HTTPS download
only for a validated matching Azure Blob api-export target. No redirects,
authorization-failure fallback, signed-link persistence or arbitrary URL fetch
is permitted. Unsupported API types are explicitly skipped. Candidate documents
are parsed strictly and scanned in memory; secret candidates or incomplete
validation prevent persistence rather than introducing OpenAPI redaction.
Mixed collection failures preserve validated manifest-listed Partial files.

Only toolkit-local installed Spectral 6.17.0 under `.tools/spectral`, Node 22.x
or 24+ on PATH, and the trusted shipped local ruleset are used automatically.
Global/PATH Spectral commands and environment overrides are not discovered.
Explicit development setup is separate from assessment
execution; runtime never installs tools. References must remain within the same
document; remote and local-file references are not fetched. Tool absence,
unsupported references or execution failures retain distinct unavailable
statuses and qualified operation-description fallback. Zero/incomplete
operation inventories have null coverage, never synthetic perfect coverage.

Saved quality binds to the manifest-listed exports, trusted ruleset, tool
version and snapshotted penalties through a restricted digest binding. The
saved-run gate validates the closed model and semantic counts/scores plus those
bindings. Reporting replays saved evidence without running a linter. Reanalysis
explicitly regenerates quality; malformed listed evidence fails closed and stale
unlisted exports are ignored. Legacy runs without the optional model remain
usable. Definitions, diagnostics, paths, digests and exact metrics stay restricted;
model-safe package 1.3 reuses only `ApiDocumentationWeak` and existing Api aliases.

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
From complete source-bound `usageByRoute`: `callsViaAppGw`, `callsInternal`.
Use only Completed single-schema evidence across all configured workspaces.
Identical sorted rows and effective UTC windows count once; conflicting or
different overlapping windows withhold counts, never add traffic. Unknown
caller-route calls withhold public attribution while preserving known internal
counts. Retention-capped evidence retains a window gap and Medium confidence.

If matching public and **private** listeners target APIM, `ViaAppGw` alone is
ambiguous. Same-window complete listener evidence may rule out active private
paths when mapped public traffic is positive and matching private traffic is
zero, retaining Medium confidence. Otherwise public counts remain null and
exposure Unknown with `privateListener`. Listener totals cannot identify an API,
so D-63 prohibits proportional per-API allocation. Multiple indistinguishable
public routes similarly withhold attribution. Complete zero ViaAppGw usage can
still establish ExternalUnintended; unresolved rewrites retain Unknown/Low.

Before route usage is available, reachable unrestricted routes retain
`callsViaAppGw=null`, `callsInternal=null`, `exposure=Unknown`,
`confidence=Medium`, and `missingInputs=["usage"]`; missing telemetry must not
be treated as zero calls. The classifier back-fills each API's aggregate
`reachability` and `exposure` while preserving unrelated missing inputs. Route
records and the updated API array must both pass their closed schemas before
either model file is written.

The existing private hook consumes complete normalized rows with `apiId`, `route`
(`ViaAppGw` or `Internal`), and non-negative `calls`; operation/product rows are
summed by API and route. The caller must separately attest that the telemetry
query completed before absent rows can be interpreted as zero. Partial query
results remain unavailable and cannot produce `ExternalUnintended`.
Settings 1.2 analysis connects validated saved evidence to this classifier and
back-fills API counts. Saved-model loading rebuilds network/exposure from
validated restricted collection/settings and rejects changed source/model
bindings before reports or allowlist package construction. Older settings do
not silently opt in. No new package condition or broker operation is needed.

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
  Scope          = 'Api'                      # one implemented scope, or a unique non-empty array for one multi-scope rule ID
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
The private engine evaluates Service, Api, Operation, Subscription, NamedValue,
Backend, Certificate, Route, Network, and Portal targets backed by registered model
contracts. Portal uses neutral platform/not-applicable usage weighting and the
optional closed portal model. COST rules use Service scope and the source-bound
telemetry contracts under D-62. Rules must declare their target model and any additional
model they use in `Requires`. Additive fallback evidence may instead be
declared in `OptionalRequires`: absent/unavailable optional models do not block
evaluation, but present models must validate and are included in finding source
files. Required/optional input names are supported model paths and unique.
POR-004 declares optional quality this way while retaining its required API and
operation models for legacy description fallback.
`Scope` may be a single implemented scope or a non-empty, unique array of
implemented scopes. A multi-scope rule uses the same callbacks for each target,
must require every target model, retains one catalog ID, and still emits only
one Info/NotEvaluated finding when a required model or declared fact is
unavailable. `TargetField` remains restricted to one Route scope (D-37).
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
Manifest schema 1.1 stores the exact validated Severity, Exposure, and Usage
maps used by the run so offline report rendering never reopens external
configuration or silently assumes default weights (D-45).

### 10.4 Action-plan aggregation
For the report, schema-valid findings with valid unique keys are grouped by
`ruleId` into closed, schema-valid **action items**:

- `affectedCount` counts evaluated instance findings only.
- `findingCount` records the number of source finding rows.
- `maxPriorityScore` is the greatest source priority.
- `topAffectedScopes` contains up to five evaluated scopes ordered by priority
  descending, then ordinal scope.
- `recommendation` combines unique source recommendations in ordinal order.
- Rule metadata (`title`, `pillar`, `mcsb`, `severity`, `evaluation`, and
  `effort`) must be invariant inside a group; conflicts fail closed.
- Tracking fields start as `owner=null`, `status=Open`, `targetDate=null`, and
  `notes=null` for later carry-forward.

A rule represented by its single NotEvaluated gap row remains visible with
`affectedCount=0`, `findingCount=1`, and no affected scopes. Action items sort by
maximum priority descending, then ordinal rule ID. Empty findings produce an
empty action array. Instance rows remain separately available for "Finding
Details" (D-42).

### 10.5 Not-evaluated handling
If a rule's `Requires` input is missing/failed, emit one `NotEvaluated` finding per rule (not per target) so gaps are visible in the report.

### 10.6 Model-safe analysis package

`analysis-package.json` is a closed, versioned contract produced only from normalized model/findings data. It contains:

- Opaque aliases matching strict patterns such as `service-001`, `api-017`, `route-003`, and `backend-004`.
- Fixed enums, booleans, bounded counts, configured usage buckets, relative cost trends, confidence, assumptions, and data-gap codes.
- Deterministic findings reduced to model-safe evidence and referenced by stable model-safe finding IDs.
- Topology facts required for assessment reasoning, such as `Internal`, `HostWide`, `WafDisabled`, or `CloudflareAssumed`, without names, addresses, URLs, or raw configuration.

It contains no unrestricted source text. The restricted `alias-map.json` remains in the collection zone and maps aliases to customer-facing labels for local rendering only. `Publish-AnalysisPackage` writes the package into a temporary restricted location, validates it, and atomically promotes it to `ModelSafeRoot` only on success. Rejected candidates are never placed in the analysis zone.

T-317 defines schema version 1.0 in `analysis-package.schema.json`,
`expert-observations.schema.json`, and `executive-summary.schema.json`.
All objects are closed. Entities contain only an opaque alias and fixed kind;
facts contain a stable fact ID, subject alias, approved code, code-specific
value, and confidence. Usage is bucketed and cost is a relative trend; numeric
facts are limited to structural inventory counts from 0 to 10,000. Findings
contain only model-safe finding/rule IDs, subject alias, authoritative severity
and evaluation, a priority bucket, fact references, and data-gap codes.
Missing-evidence findings must retain Info/Unknown and at least one data gap.
The private in-memory contract gate rejects duplicate JSON members and IDs,
alias-kind mismatches, and unsupported references. It never writes or promotes
data and does not replace T-319's independent scanner/attestation gate (D-47).

T-318/T-319 add a private implementation, not public orchestration or an agent
runtime. Package schemas 1.1 and 1.2 are separate self-contained schemas; 1.0
remains supported unchanged. The builder loads all ten required baseline models,
any requested bound drift model, and saved
findings, replays the implemented catalog with the supplied configuration, and
rejects inconsistent keys, severity, evaluation, score, exposure, or usage.
Each evaluated finding cites a newly constructed `AssessmentCondition` fact
whose approved code names that rule's positive deterministic condition
(for example `InheritedControlsDropped` or `CertificateNearExpiry`). This
preserves supported reliability/governance evidence without exporting free-text
evidence or pretending unrelated topology facts explain a finding.
Package 1.2 adds only `SourcePolicyDrift` and `EnvironmentPolicyDrift` approved
condition values for evaluated GOV-007/GOV-011 findings, using existing service
aliases. Contract selection, independent scanner, hash attestation and semantic
claim validation support it explicitly. No Git paths, commit IDs, policy hashes,
XML, external run paths, or environment/resource identities enter the package.
No broker operation, caller-path parameter, or agent permission is added.

Package 1.3 adds only `PortalUnavailable`, `PortalAuthenticationWeak`,
`ProductVisibilityMismatch`, `ApiDocumentationWeak`, and `LegacyPortalEnabled`
for evaluated POR-001 through POR-005. Portal-scoped conditions bind explicitly
to the existing Service alias; documentation conditions bind to the existing Api
alias. Independent schema/scanner/attestation and semantic checks support this
version, reject incorrect condition/subject bindings, and preserve earlier
schemas unchanged. Confidence derives from portal evidence, not the unrelated
service security model. No provider/client/tenant/product/group identifiers,
domains, intent or exact coverage values enter the package.

Package 1.4 adds only `ProductGovernanceWeak` and `ApiDiagnosticsWeak` for
evaluated GOV-003/GOV-009. Facts bind respectively to existing Product/Api entity
kinds and each finding must cite its own subject's matching condition.
Unreferenced collected products receive unique, deterministically sorted aliases;
membership/subscription references do not duplicate them. Diagnostic confidence
comes from coverage evidence rather than an unrelated API model. The independent
scanner, attestation, promotion, broker admission and claim entailment explicitly
support 1.4; older schemas remain unchanged. Governance conditions support only
the appropriate governance/diagnostic claims, not unsafe diagnostic capture.
No inventory records, user counts, product description/intent, critical API IDs
or exact sampling enter the package. No broker tools or permissions are added.

Schema 1.1 requires six ascending configured usage thresholds beginning at
zero. Zero is `Zero`; absent usage is `Unknown`; a positive count uses the
greatest threshold not exceeding it, selecting `VeryLow`, `Low`, `Medium`,
`High`, `VeryHigh`, or `Extreme`. The final band is unbounded. Configurations
with other threshold counts are rejected by this builder, not reinterpreted.
The default thresholds make 1 call `Low` and 1,000 calls `Medium`; custom
thresholds can make positive counts `VeryLow`. Exact thresholds and metrics
are not included in the package. Priority uses the replay-checked saved score
relative to the supplied scoring maps' maximum possible score: High at two
thirds, Medium at one third, otherwise Low; NotEvaluated remains Unknown.

Aliases and fact/finding IDs are ordinal-stable for equivalent reordered saved
inputs. They are not pinned across changed inventories. The restricted alias
map stores only aliases and required scope identities, not source labels or
credential-like/encoded identifiers. Candidate construction is not admission.
Independent validation combines the schema/reference gate with a separately
maintained, field-specific vocabulary and recursive prohibited-value scan.
Closed ASCII tokens and bounded IDs/counts reject arbitrary source text,
Unicode/encoded alternatives, and high-entropy strings without entropy-based
exceptions. Unknown fields/types/values and scanner errors fail closed.

`validation-attestation.schema.json` closes the local digest, supported
package schema version, module-derived builder/validator compatibility
versions, and fixed passing check metadata. The digest binds exact bytes,
not reserialized JSON. This is a local integrity record, not a signature or
cryptographic proof of who constructed a candidate.

Publication requires an explicit complete host-supplied visible-root set.
Restricted, analysis, and private-staging roots must be pairwise disjoint;
restricted/staging roots must be outside every supplied visible root.
Absolute canonical paths, traversal, linked ancestors/artifacts, and existing
analysis-zone contents are checked. Only closed validated package/attestation
pairs in named version directories may already occupy the analysis zone.
New bytes are validated in fresh private staging outside the visible roots,
rehash-checked with the source, and published by a no-overwrite directory rename
on the destination filesystem. Cross-filesystem/non-atomic rename failures have
no copy fallback. Failures preserve existing versions; alias maps never move.
The host must enforce exclusive ownership/ACLs on all roots and their ancestors.
This guards accidental/stale writers with checks and immutable API semantics;
it does not claim immunity to a hostile concurrent filesystem administrator.
The implemented broker rechecks package/attestation and exact hashes at read time.
Host trust/ACL configuration and actual isolated agent acceptance remain owner
checks under T-321/T-324 and G3 (D-48/D-49).

### 10.7 Specialist Copilot analysis

Three repository agent profiles are used:

1. **Architecture and exposure analyst** — reviews topology, policy inheritance/control flags, reachability, reliability, and governance.
2. **Security analyst** — reviews authentication, subscription scope, secrets/control flags, TLS, diagnostics, identity, and confidence-qualified threats.
3. **Executive synthesizer** — reconciles validated findings and specialist observations into audience-appropriate priorities, themes, decisions, and next actions.

Specialist outputs are validated against closed schemas. Every observation includes an observation ID, category, confidence, model-safe finding/fact references, rationale, and bounded recommendation code/text selected from an approved vocabulary. Agents cannot introduce new evidence, replace rule severity, or mark deterministic findings resolved. Unsupported claims fail validation and are excluded from reporting.

Version 1.0 uses approved `rationaleCode` and `recommendationCode` enums, not
free-text narrative. Observation IDs identify the ArchitectureExposure or
Security analyst; all citations must resolve in the supplied package, and each
observation must cite at least one finding or fact. Executive summaries contain
approved-code priorities, themes, decisions, and roadmap items with resolving
finding/fact/observation citations, plus the package's assumptions and data gaps.
Assumption and data-gap sets must match the package exactly: neither missing
nor invented codes are accepted.
The structural contract gate validates supplied specialist sets before accepting
executive references and rejects duplicate analyst roles. The separate
`Test-ApimAgentClaim` semantic gate additionally requires every direct citation
to support the selected rationale, compatible recommendations/categories, and
confidence no higher than supporting evidence. Executive codes reconcile to
supported specialist rationales/direct facts, retain exact assumption/gap sets,
and preserve posture from authoritative findings. High findings require at least
one highest-severity priority citation. NotEvaluated supports only low-confidence
MissingEvidence, never a confirmed risk. A schema-approved code is not itself
evidence; unsupported diagnostic-coverage claims reject, including attempts to
treat sensitive capture as insufficient diagnostics. Four explicit broker-only
profiles are implemented, but schema/profile declarations do not certify actual
host permissions or enable customer analysis (D-47/D-52/D-54).

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
| APIM-SEC-001 | Legacy TLS/ciphers enabled (gateway or backend side) | Medium | DP-3 | Service | recognized gateway/backend TLS10/TLS11 or gateway TripleDes168 explicitly true |
| APIM-SEC-002 | Minimum management API version not enforced | Low | AM-1 | Service | `apiVersionConstraint.minApiVersion` null |
| APIM-SEC-003 | Reachable API has no caller auth beyond subscription key | High | IM-1 | Api | Applies reachable; `callerAuth ∈ {SubscriptionKeyOnly}` |
| APIM-SEC-004 | Reachable API requires no subscription and no auth | High | IM-1 | Api | reachable; `subscriptionRequired=false` and no JWT/mTLS |
| APIM-SEC-005 | Subscriptions scoped to All APIs (incl. built-in master) active | High | PA-7 | Subscription | `scopeType=AllApis` and `state=active` |
| APIM-SEC-006 | Stale or non-expiring active subscriptions | Low | PA-7 | Subscription | active, `lastUsed` > `SubscriptionStaleDays` or null, or no `expirationDate` on partner products |
| APIM-SEC-007 | Hard-coded credentials in policy | High | DP-7 | Operation | `hardcodedSecret` |
| APIM-SEC-008 | Secret-like named values stored as plain text | Medium | DP-7 | NamedValue | `secret=false` and name/value matches secret pattern |
| APIM-SEC-009 | Secrets/certificates not Key Vault–backed or Key Vault sync failing | Medium | DP-7 | NamedValue/Certificate | `keyVault` null for secret values / `lastStatus.code != Success` |
| APIM-SEC-010 | Backend TLS certificate validation disabled | Medium | DP-3 | Backend | `validateCertificateChain=false` or `validateCertificateName=false` |
| APIM-SEC-011 | Backend over plain HTTP | Medium | DP-3 | Backend/Operation | backend `scheme=http` or structural `set-backend-service` HTTP override, excluding only exact configured targets |
| APIM-SEC-012 | Unsafe CORS (wildcard origin with credentials) | Medium | DP-3 | Api | `corsUnsafe` |
| APIM-SEC-013 | No backend authentication (managed identity/cert) | Low | IM-3 | Api | `backendAuth=false` and backend not anonymous by design (configurable allowlist) |
| APIM-SEC-014 | Bodies or sensitive headers logged | Medium | LT-3 | Api/Service | diagnostics `body.bytes > 0` or headers include `Authorization`, `Ocp-Apim-Subscription-Key`, `Cookie` |
| APIM-SEC-015 | Tracing allowed on subscriptions | Medium | LT-3 | Subscription | `allowTracing=true` |
| APIM-SEC-016 | Clients still using TLS < 1.2 | Low | DP-3 | Api | `logs/tls.json` |
| APIM-SEC-017 | Defender for APIs not enabled / open Defender recommendations | Medium | LT-1 | Service | defender.json |
| APIM-SEC-018 | Excess write-capable principals on APIM resource group | Medium | PA-1 | Service | count(Owner/Contributor/API Management Service Contributor) > `MaxWriteRolePrincipals` |
| APIM-SEC-019 | No managed identity on APIM | Low | IM-3 | Service | `identity` null |
| APIM-SEC-020 | Mock or trace policies in production | Medium | n/a | Operation | `mockOrTrace` (env = Prod) |

T-304 currently implements
SEC-001/002/003/004/005/007/008/009/010/011/012/014/015/019/020 against the
closed service-security, API, operation, subscription, named-value, backend,
and certificate models. Known
positive evidence remains
evaluated when another record has an unavailable fact; if all otherwise
applicable evidence is unknown, the rule emits one Info/NotEvaluated finding.
SEC-008 uses only the derived secret flag and structural pattern locations;
values are never evidence. SEC-009 uses one rule ID across NamedValue and
Certificate scopes. It flags secret named values without Key Vault, unsuccessful
named-value Key Vault synchronization, and certificates without Key Vault; a
known positive remains evaluated when another Key Vault fact is unavailable.
If no positive is known, missing Key Vault backing/status produces one
NotEvaluated finding for the rule (D-37). SEC-010 applies only to HTTPS backends
with an explicitly false chain or hostname-validation flag. HTTP TLS flags are
non-applicable, and missing HTTPS validation facts produce NotEvaluated when no
positive finding is known. SEC-014 consumes the collected diagnostic contract
through the API model and evaluates known body/sensitive-request-header logging
in saved runs. Incomplete diagnostic evidence remains null and produces
NotEvaluated when no positive fact is known (D-35/D-36). SEC-011 evaluates
backend entities from the closed URL scheme and operation-level policy
overrides from the structural `backendOverrideHttp` flag. Its optional exception
map suppresses only exact backend IDs or `apiId/operationId` keys and does not
infer internal status; Partial operation policy evidence produces NotEvaluated
when no unapproved HTTP target is known (D-38). SEC-001 preserves explicit
legacy TLS enablement when another control is unknown; otherwise incomplete
negative evidence remains NotEvaluated. SEC-002 and SEC-019 use definitive
absence of a minimum management API version or managed identity, respectively
(D-39). SEC-013 remains pending backend-to-API mapping plus
anonymous-by-design owner intent. Other deferred rules still require Defender,
RBAC, product-classification, telemetry, or authorization evidence (D-32).

### 11.3 Governance / Operational Excellence (GOV)
| ID | Title | Sev | Logic |
|---|---|---|---|
| APIM-GOV-001 | APIs not in any product | Medium | `products` empty |
| APIM-GOV-002 | APIs missing owner/team tag | Low | `ownerTag` null |
| APIM-GOV-003 | Products without description/owner or with approval disabled for external products | Low | product fields |
| APIM-GOV-004 | Unused APIs (no calls in window) | Medium | `calls90d == 0` (window capped by retention; evidence states effective window) |
| APIM-GOV-005 | Non-current revisions still online | Low | `nonCurrentOnlineRevisions > 0` |
| APIM-GOV-006 | Single-version version sets / unversioned APIs | Low | version set analysis |
| APIM-GOV-007 | Production policies differ from source control | Medium | Known policy presence/hash differences within mapped Git scope coverage; API definition/catalog absence is not inferred from XML |
| APIM-GOV-008 | Inconsistent path/versioning conventions | Low | path pattern clustering (`/v1/`, `/api/v1`, none) — service-level finding with distribution |
| APIM-GOV-009 | Diagnostics/logging not configured or sampling < 100% on critical APIs | Medium | diagnostics |
| APIM-GOV-010 | Policy missing `<base/>` drops inherited controls | Medium | `baseMissing` |
| APIM-GOV-011 | Environment drift (Dev/Test/Prod) | Low | drift across envs |

T-305 implements GOV-001/002/003/005/006/008/009/010; GOV-007/011 are provided
by the separate drift slice. Product membership, owner tags, and revision counts are
definitive catalog facts. GOV-006 flags APIs without a version set and complete
version sets with at most one distinct version; a set with an unknown member
version remains NotEvaluated unless another known positive exists. GOV-008
classifies API paths as `ApiVersionPrefix`, `VersionPrefix`,
`OtherVersionSegment`, or `NoVersionSegment` and emits one service-level
distribution finding when conventions differ. GOV-010 retains known
missing-`<base/>` findings when another operation has Partial policy evidence;
otherwise the incomplete fact is NotEvaluated (D-40).
GOV-003 flags a proven missing description, explicitly absent owner, or disabled
approval for an explicitly external product, using the optional product model.
GOV-009 flags known absent effective diagnostics, an unresolved logger reference,
or a known sample below 100 percent on an explicitly critical API. A sample of
100 passes that sampling check; noncritical APIs do not require full sampling.
Absent/unresolved intent, collection, logger or sampling evidence retains one
Info/NotEvaluated result per rule when no known positive exists, while a proven
positive survives unrelated incomplete evidence. This assessment of configured
diagnostics does not prove ingestion, retention or runtime logging delivery.
GOV-004 remains deferred to usage collection; GOV-009 is owned by T-305 rather
than implemented again under T-409 (D-59).

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

T-306 implements all six REL rules against closed service, backend, certificate,
and network models. REL-001/002 apply only when the manifest environment is
`Prod`; missing SKU facts remain NotEvaluated. REL-003 evaluates only exact
backend IDs in the optional validated `RuleTargets.CriticalBackendIds` array.
REL-004 derives probe paths only from App Gateway routes whose pool and effective
backend host target APIM; the platform default `/` is misaligned, no APIM route
is not applicable, and unresolved probe evidence is NotEvaluated. REL-005 uses
both service hostname-certificate dates and APIM certificate entities, uses
`manifest.startedUtc` as its stable clock, and treats expiry exactly at the
configured boundary as not within the threshold. Known expiring certificates
remain evaluated when another expiry is unavailable. REL-006 accepts `stv2`
and `stv2.1`; missing platform version remains NotEvaluated (D-41).

### 11.5 Developer portal (POR)
| ID | Title | Sev | Logic |
|---|---|---|---|
| APIM-POR-001 | Developer portal not enabled/published | Medium | `developerPortalStatus != Enabled` or no published revision |
| APIM-POR-002 | Username/password sign-in or open sign-up enabled | Medium | direct `portalconfigs/default.properties.enableBasicAuth`, sign-up enabled, or non-Entra identity paths (D-57) |
| APIM-POR-003 | Products not visible to intended groups / guests can see products | Low | productGroups includes `guests` for non-public products |
| APIM-POR-004 | Weak API documentation | Low | operation description coverage < 80% or `openApiScore < 70` |
| APIM-POR-005 | Legacy portal still enabled | Low | `legacyPortalStatus == Enabled` |

POR-001/002/003/005 use the Portal singleton target. Missing required facts yield
one Info/NotEvaluated per rule, but known positive evidence survives unrelated
Partial gaps. Basic auth uses a returned Boolean, never the service default or
an inference from an Entra-only provider list. Conflicting registration-delegation
evidence remains Unknown. POR-003 checks explicit nonpublic guests and missing
intended memberships only; absent/unresolved intent cannot pass. POR-004 targets
each API using existing `hasDescription` operation facts at the exact 80-percent
boundary and any legitimate non-null OpenAPI score at 70. Zero/incomplete
operations do not become 100-percent coverage. Optional T-105/T-504 evidence
adds source-bound offline Spectral scores under section 8.6; absent or failed
linting retains the specified documentation fallback. Finding evidence identifies
the method and unavailable-quality reasons without claiming a linter ran.

### 11.6 Cost (COST)
| ID | Title | Sev | Logic |
|---|---|---|---|
| APIM-COST-001 | Premium capacity utilization (informational right-sizing) | Info | capacity P95 and max vs units; recommendation respects zone/HA requirement |
| APIM-COST-002 | Cost per million calls trend | Info | month-over-month |
| APIM-COST-003 | Log Analytics ingestion growth from APIM/App GW | Medium | ingestion ×2 over window or body logging + top data types |
| APIM-COST-004 | Logic Apps cost increase (cost-only) | Medium | month cost > 1.5× first month; evidence: change start date, plan SKU/instance changes; states "workflow review out of scope" |
| APIM-COST-005 | Non-prod on Premium / over-provisioned non-prod | Low | env != Prod and sku Premium |

Implemented D-62 semantics: COST-001 is informational for Premium with complete
capacity; it preserves zone/HA caveats rather than asserting excess capacity.
COST-002 flags positive normalization change across complete adjacent UTC months.
COST-003 requires at least doubled comparable ingestion, or proven body logging
with billable APIM-table ingestion, not unrelated App Gateway access logs;
missing coverage yields NotEvaluated unless
another positive is established. COST-004 uses strictly greater than 1.5 times
the first complete month in the same currency for a workflow/linked shared plan.
It records the first qualifying month and current SKU/instances only, explicitly
leaving historical changes unknown and workflow review out of scope. COST-005
uses the configured environment, never resource-name heuristics. Missing required
models/facts emit one Info/NotEvaluated result per rule.

Evaluated COST findings select closed model-safe package 1.5 with only
`PremiumCapacityReview`, `NormalizedCostIncreasing`, `DiagnosticIngestionGrowth`,
`LogicAppCostIncreasing` and `NonProductionPremium`, all bound to Service aliases
and matching rule/condition citations. Exact costs, usage, capacity, dates and
resource/workspace/plan identifiers have no export field. Earlier schemas stay
unchanged; independent scanning, attestation and semantic claims admit 1.5
explicitly without new broker permissions.

> Maintainers add Microsoft Learn references to `References` manually. The tool must never generate URLs.

---

## 12. Stage 3 — Report

### 12.1 Template-driven
`template/ApimActionPlan.xlsx` holds all workbook formatting: title rows, navy header band (`#1F3864`, white bold), banding, frozen panes, column widths, conditional formats (severity, Pass/Fail, exposure), **empty Excel tables** with fixed names, a formatted network-summary block, and Summary formulas/charts bound to those tables. The private report writer copies the trusted template, writes typed values beginning at row 4, and updates the existing table ranges without rebuilding workbook styling, so charts and formulas grow automatically.

The customer-neutral template is generated by
`scripts/New-ApimActionPlanTemplate.ps1` using the pinned ImportExcel
development dependency and is committed with the repository. Fixed formatting,
validations, and conditional-format ranges cover rows 4–10,000; report writing
must reject larger output rather than silently dropping formatting or
validation. Structural tests open the committed workbook and a regenerated copy,
verify every sheet/table/header, and require empty placeholder rows (D-43).

`Export-ApimActionPlan` loads and validates the saved manifest, every registered
model contract, `findings.json`, and the installed rule catalog before selecting
an output filename or copying the template. It populates the currently
implemented Actions, Finding Details, API Inventory, Effective Policy Matrix,
Subscriptions, Exposure Map, network summary, Summary assumptions, Run Info,
implemented rules, and the manifest's exact scoring snapshot. Telemetry runs
populate Usage/Cost; requested comparison evidence populates Environment Drift. Output is
written under the run's restricted `report` folder, uses `manifest.startedUtc`
for the filename date, never overwrites an existing file, and fails before final
output on unsafe names, template drift, invalid inputs, or more than 9,997 rows
in any table (D-44/D-45).

`tblWeights` contains editable positive Severity, Exposure, and Usage values.
Each Finding Details Priority cell is a formula over its Severity, Exposure,
and Usage values; blank usage applies the neutral 1.0 multiplier. Each Action
Plan Priority cell uses the maximum recalculated Finding Details priority for
the same rule ID. The workbook requests automatic full recalculation when
opened. Editing weights changes only workbook formulas and cached presentation;
it never mutates `findings.json`, and action rows remain in their original
deterministic saved order rather than automatically resorting (D-45).

`template/ApimExecutiveSummary.html` holds the self-contained local HTML/CSS/SVG
template (D-54). The renderer, not an AI model, combines revalidated synthesis
with restricted local facts. It builds a fresh package from current replay-checked
models, checks exact digest and identity-map agreement, resolves all aliases
locally, and HTML-encodes local labels. The non-AI path requires no promotion,
agent output, broker, or Azure access. Excel/HTML share one basename; restricted
local registries retain relative artifact paths without returning them to a model.

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

Usage/Cost population under T-411 retains the fixed template table headers.
Unavailable route/latency columns remain blank. Additional local Excel tables
bind monthly line and separate-currency stacked cost charts; chart amounts use
resource rows only. Combined normalization rows repeat APIM/App Gateway costs
and are explicitly labeled not additional cost. Partial months and capacity
sample/current-sizing qualifications remain visible in Excel and local HTML.

### 12.3 Carry-forward (`Merge-PriorTracking`)
With `-PreviousReport <path>`: read `Action Plan` and `Finding Details` tracking columns, join on `ruleId` (actions) / `findingKey` (details), copy `Owner/Status/Target Date/Notes`. Unmatched prior rows are listed in a `Resolved Since Last Run` section with their tracking values.

D-55 qualifies unmatched rows: only a comparison bound to the prior workbook
snapshot can place comparable evaluated absences in Resolved Since Last Run.
Otherwise retain them in Not Reassessed. Older toolkit workbooks without that
binding still support matching tracking. These template-owned history tables
are separate from current findings/actions and their KPIs. Imported formulas,
invalid fields, duplicate keys, unsafe paths, and incompatible scope reject;
operator tracking never mutates deterministic findings.

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

D-55 bounds the implemented command to distinct saved runs for the same APIM,
environment, tenant and customer using supported current-version contracts.
Preserve historical severity rather than rewriting the baseline through today's
catalog. Current reporting still requires full deterministic replay. Changed
settings, historical replay mismatch, Partial required evidence and unavailable
reassessment qualify absences as NotReassessed; they are not confirmed fixes.
Missing usage/cost KPIs and deltas remain null with fixed reasons until those
model contracts exist. Six additional template sheets provide comparison,
assessment gaps, pillar/KPI summaries, and resolved/not-reassessed tracking.
Restricted comparison bindings reject modified or stale results at report time.
The baseline is unchanged; Compare writes a new current Excel/HTML pair.
HTML lifecycle narrative remains outside this lifecycle slice. Cross-environment
drift uses Analyze's separate optional model, not historical Compare.

---

## 14. CLI

The implemented operational slice (D-50/D-60) exposes Collect, Analyze, Excel/HTML Report,
and Assessment plus offline Compare over sixteen collectors, optional
committed Git policies, ten required models, optional portal/bound drift and
telemetry models, and the installed catalog. Analyze/Report are offline.
Configured cost and Log Analytics default on; SkipCost excludes cost/auxiliary
evidence, while SkipLogs excludes all LA queries including ingestion but not
metrics or diagnostic configuration. Explicit `:$false` enables configured
evidence; exclusions persist across resume. Custom/filtered catalogs remain
unavailable and unsupported requests fail explicitly. Git is configured/optional with explicit
SkipGit behavior in section 7.9. Cross-environment `Analyze -CompareRuns` is
available under the section 8 drift contract; same-environment Compare remains
a separate command.
Report and full Assessment accept PreviousReport; collection-only Assessment
rejects it rather than silently ignoring tracking.
`-SkipLogs` does not exclude diagnostic-configuration collection. Only
Cloudflare/AssumedReachable edge configuration and six usage bands are supported.
`-Stage Collect` on Assessment selects collection only; `-Resume` reuses a run
only after compatible identity/configuration/settings and per-collector
inventory/count/policy-hash validation. Changed prerequisites force dependent
recollection and invalidate downstream stage states. Collector-owned old files
are cleared before replacement; failed evidence is never read as a complete set.

The restricted closed `run-settings.json` snapshot persists only allowlisted
non-secret settings needed for reproducible analysis/package replay; scoring,
edge settings, and date anchors come from the manifest. Missing models produce
Info/NotEvaluated findings where possible and block Report/promotion. Report
requires Completed analysis, all ten valid baseline models, valid requested
drift bindings, any present closed portal model, and exact finding replay.
Old runs without portal evidence remain usable after ordinary offline Analyze
refreshes the expanded catalog. Portal absence is NotEvaluated, not a failed
baseline model or an inferred disabled portal.
Collection-only failures return 3; attempted downstream failure returns 4 while
preserving collector status. Console output is bounded status/exit-code text.
The examples involving future capabilities below describe the eventual v1
contract, not currently executable commands.

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
- `validate_agent_output(runId, packageSha256, kind, json)` → digest-bound validated output ID only.
- `read_validated_agent_outputs(runId)` → revalidated model-safe proposals only.

The broker allowlists operations and arguments, resolves local paths internally, captures/sanitizes stdout and stderr, never returns Azure exceptions verbatim, and has no generic command-execution method.

The implemented stdio server handshakes MCP 2025-11-25 and supports only
initialize/initialized, ping and tools/list/call. It is not a generic MCP
resource/file server. Exact tool schemas reject unknown fields/operations,
caller paths and unsupported options. Each tool runs in a fixed local worker
process whose OS stdout/stderr are drained, never forwarded; result-file content
must pass a separate closed result gate before reaching the wire. Errors use
fixed codes, without exception text. The module manifest supplies server version.
Operator startup is closed JSON with approved config aliases/environments,
registered saved runs, complete visible roots, disjoint canonical physical
restricted/analysis/private-staging roots and explicit approval/exclusive ownership.
Declarations are required inputs, not automatic proof of actual permissions.
Startup/configuration remains outside model control. IDs are session-scoped.

Promotion directories remain immutable two-file versions. Validated specialist
and executive proposals live in separate restricted storage with both output
and package hashes in closed persistent sidecars. Every output read/render rechecks those bindings and
semantics. Missing/rejected proposals use an explicitly labeled deterministic
report path; unvalidated output is never used. Specialist/synthesis profiles
allow only exact read-only namespaced tools; the orchestrator alone submits
proposals and requests reports. No generic shell/filesystem/delegation tools
are allowed. The operator must verify actual profile tool admission and filesystem
isolation in a clean session before assisted use (D-51/D-53).

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

The T-312 local saved-run check scans supported text artifacts and XML parts
inside Excel workbooks without extracting them. It detects recognizable JWTs,
authorization credentials, private-key PEM blocks, credential-bearing URLs,
and labeled key/password/secret or connection-string values, including decoded
JSON strings and XML attributes/text. Exact redaction markers, named-value
references, and policy expressions are not literal credentials. JWT header-name
selectors and scheme-only Authorization/Proxy-Authorization values are metadata,
not literal credentials. Bare "Bearer token"/"Bearer JWT" wording is ignored only
in recognized descriptive JSON fields, XML descriptions/error-message attributes,
and XML comments/processing instructions; credential-value contexts are not
exempt. Literal JWT-policy `token-value` attributes, signing/decryption keys,
and actual authorization credentials remain candidates. Known policy XML strings
inside JSON/log records are parsed as XML, including comments, instructions, and
mixed text; malformed serialized policies fail closed. Malformed,
unreadable, linked, unsupported, or oversized artifacts fail the check rather
than being skipped. Limits are 64 MiB per file and per expanded workbook, and
16 MiB per workbook entry. A clean result means no supported secret pattern was
found, not proof that arbitrary unlabeled/encoded secrets or identifying data
are absent. This check neither redacts files nor replaces the model-data airlock.
Operator entry points write restricted `secret-scan-locations.json` containing
relative files, fixed match kinds, text/log line numbers, JSON pointers,
positional XML paths (appended to the JSON pointer for embedded policy XML),
and workbook part locations without captured values or
excerpts. Report schema 1.1 includes a deterministic `artifactId` per file.
On candidate failure, scripts show an end-of-script table before the final
exit-code line: ordinal report row, artifact alias, fixed match kind, and nullable
line/column. The core emits newly shaped allowlist-only rows; the shared formatter
rejects unknown fields, kinds, aliases, or positions before printing. Actual
filenames, structured paths, workbook parts, values, and excerpts never enter
table rows. Console failure output explains how to open the report locally, never echoes
its locations or source content, and distinguishes a candidate from a confirmed
secret. Rescans initialize this scanner-owned report as `Incomplete` before
scanning, then replace it on completion. Report-write failures also fail closed;
error output warns that an existing report may be absent or stale.
The report is excluded from rescans and capped at
10,000 detections, with overflow failing closed.

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
Private-configuration preflight may emit only fixed missing-file, invalid-config,
unsafe-location, or unmatched-environment categories; it must never render
config values, identifiers, paths, or underlying exception messages.
The same smoke entry point validates its newly saved manifest against the
registered check outcomes and verifies required completed-collector files, JSON
collection shapes/counts, and policy index/XML hashes locally before exit 0.
Only bounded validation status is printed; a mismatched or missing output
returns exit 4. A Partial run can validate completed files but remains exit 3.
This does not perform Analyze, Render, or a model-data airlock validation.
The cumulative smoke includes all sixteen implemented configuration/telemetry
collectors and fresh observed-route settings 1.2 (D-64). Validate Partial/Skipped
telemetry with the same saved-evidence gates as collection. Only validated
unconfigured LogAnalytics/Cost/LogicApps exclusions may accompany exit 0;
baseline prerequisite skips and incomplete required evidence remain Partial.
Print fixed aggregate statuses for the four observed-route queries without
workspace identities, row counts or metrics. Skipped coverage never establishes
query execution, full live acceptance or a successful assessment.
Every handled smoke outcome prints a fixed final PASS/FAIL/PARTIAL result and
its numeric exit code before exiting; the displayed code must match the actual
process exit code. Operators do not need a second command to inspect it.
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

### 16.1 Synthetic live-validation lab

D-65/D-66 and T-701-T-712 define an opt-in, customer-neutral Bicep lab to fulfill
T-114 and support maintainer live testing. The detailed design is in
`.azure\deployment-plan.md`. Owner approval permits offline implementation;
actual bootstrap/provisioning needs separate permission, context,
quota, cost, DNS and live-execution approval.

Baseline scope: internal classic Developer APIM, five representative business
OpenAPI APIs (Supply Chain, E-commerce, PLM, Manufacturing and Service
Management), global/product/API/operation/fragment policies, HTTPS Application
Gateway path routing, Key Vault certificates, managed identities, workspace-based
Application Insights and Log Analytics with independent gateway diagnostics,
bounded synthetic traffic and GitHub environment-scoped OIDC delivery.
Default/unmatched gateway routes must not forward to APIM. Private-only negative
scenarios cannot bypass independent network/caller restrictions.
PLM is private-only; Manufacturing is initially excluded from generated
data-plane traffic. Product-context, routed and bounded-failure scenarios
are distributed across the remaining APIs, not separate extra APIs.
Fault behavior is controlled only through private worker jobs, never a public
fault-toggle operation. T-712's standalone contracts use synthetic examples,
local references and placeholder backend URLs; they do not implement policy
enforcement, API imports or a running backend.

T-703 provisions the VNet and all four subnets rather than requiring an existing
network. The parameterized synthetic layout uses a /22 VNet, dedicated /24
App Gateway subnet, /26 classic APIM subnet and separate /27 worker and
private-endpoint subnets. Require containment, non-overlap, capacity and private
collision checks before deployment; preserve documented platform traffic and
explicit worker egress. These sizes are lab defaults, not service minimum claims.

T-703's source-checkout foundation implements this topology with exact AVM
versions and a direct Log Analytics workspace: reviewed AVM workspace 0.16.1
unconditionally evaluates shared-key outputs and is unsuitable for this boundary.
The closed version 1.0 foundation input is validated locally before a new private
ARM parameter file is written. Require canonical RFC1918 /16-/22 VNet addressing,
the stated minimum subnet capacities, non-overlap/containment, and non-empty,
bounded public caller/worker-HTTPS CIDR lists. These checks cannot discover
collisions with existing private infrastructure or enforce destination FQDNs.
Standard App Gateway platform/outbound rules and classic APIM service dependencies
remain available; only the worker subnet uses the explicit NAT gateway.

The empty vault uses RBAC, soft delete, purge protection, a linked private endpoint
for worker/gateway access, and public-network firewall default Deny with
AzureServices bypass plus the APIM subnet's Key Vault service endpoint. This is
the documented APIM system-identity certificate control-plane path, not a
public-to-all fallback or obsolete gateway trusted-service assumption. Actual
certificate access must pass owner validation before later hostname binding.
The foundation declares independent resource-specific APIM gateway logs and
workspace-based Entra-only App Insights with system-identity logger credentials,
all-API bounded sampling/error controls and zero body/header/client-IP capture.
No foundation role assignment is made: T-702 Runtime still needs the future
worker principal, and neither log declaration nor offline snapshots prove ingestion.
Certificate issuance/binding, Application Gateway/listeners,
exact application-name private DNS, API imports/policies and protected delivery/
lifecycle remain separate tasks. No broad `azure-api.net` private zone is created.

T-704 adds a pinned AVM 0.22.3 small Linux worker on that existing subnet/NSG/NAT.
Its single NIC has a validated, unreserved static private IPv4 address; no public
IP, forwarding, inbound SSH or password authentication is enabled. Trusted Launch,
secure boot/vTPM and system-assigned identity are required. Cloud-init masks SSH,
creates protected directories/an unprivileged service user and does not fetch
binaries, generate certificates or start an unconfigured service. The root-owned
private job directory inherits its `apimlab` group so atomic fault files created
by privileged jobs remain readable, but not writable, by the backend.

The separate Linux-x64 .NET worker pins SDK 10.0.402, ASP.NET Core/JWT bearer
10.0.13 and locked public dependencies; it is not imported into the assessment
module. Its closed application configuration 1.0 requires canonical tenant/
resource/caller IDs and three distinct HTTPS DNS origins without paths, ports,
credentials, queries or fragments. Backend startup requires a matching, currently
valid RSA-2048+/EC-256+ certificate/private key and supplied chain. Serve TLS
1.2/1.3 only; callers must trust that chain without disabled validation.
Standard JWT validation requires RS256, exact tenant v2 issuer/resource audience,
lifetime, `ver=2.0`, fixed `Lab.Backend.Invoke` application role and an allowlisted
`azp`; delegated `scp` tokens reject. Frontend/backend resource audiences are
distinct and application-role assignments remain explicit owner directory work.

The backend follows the five committed contracts with bounded request/response
handling, never echoing arbitrary inputs. `/healthz` returns a fixed readiness
body without authentication; `/deny` and unmatched paths return fixed 403s and
never forward. No public HTTP fault toggle exists. Closed version 1.0 jobs accept
only readiness, clearFault, fault or six fixed traffic profiles: Supply Chain,
E-commerce, Service Management, private PLM, unmatched-denied and public-PLM-denied.
Traffic is serialized and sequential, limited to 1-20 requests, 250-2000 ms
spacing, three-second HTTP/metadata timeouts and a 60-second whole-job budget.
Manufacturing has no initial traffic profile. Redirects/proxies are disabled;
managed-identity tokens stay in memory. Faults affect Service Management only,
expire within 120 seconds and cap delay at 1000 ms and failures at ten. Persistent
counters preserve the remaining failure budget across restarts; monotonic deadlines
bound expiry within each backend process alongside the persisted UTC expiry.
Unknown/malformed inputs refuse; missing
TLS, identity, permission or readiness evidence never yields Ready.
Private jobs print only fixed codes with exit 0/3/1 for Ready/NotReady/Failed;
no identifiers, URLs, tokens, response bodies, metrics or exception details.

The VM agent/control-plane channel and root jobs are privileged, not isolation
between jobs/identities. T-704's binary publishing and offline acceptance do not
implement private delivery/protected orchestration (T-708), public ACME (T-705),
API imports/backend CA trust binding (T-706), or any live deployment/role grant.

T-705 adds separate source-checkout owner certificate tooling, not assessment
exports or broker operations. Its isolated PowerShell child pins Posh-ACME
4.35.0, Az.Accounts 5.5.3, Az.Dns 2.2.0 and Az.KeyVault 6.6.1 through an explicit
owner-only installer; ordinary offline tests neither load Azure contexts nor
install runtime dependencies. Closed configuration 1.0 supplies exact tagged
lab/tenant/subscription/VM/vault/zone/certificate names, three distinct canonical
DNS names, protected state directory and the complete declared model-visible
root list. Reject unknown/duplicate members, wildcards, IP hostnames, linked
paths, checkout/visible-root overlap and non-private ownership/permissions.
Owner storage uses Windows owner/SYSTEM/Administrators-only access or Unix
0700 directories/0600 files, separate staging/production profiles and an
exclusive local lock. This is not a distributed lock or automatic discovery of
all trusted roots; the owner must declare them completely and serialize issuers.

Authenticate only using the worker system-assigned managed identity with
process-local context/no autosave; reject App Service identity endpoint fallback,
wrong account/cloud/tenant/subscription and mismatching fresh owned resources.
The unchanged six T-702 Runtime grants do not supply all VM/vault ARM ownership
metadata reads required here. D-71 records this unresolved prerequisite; no
additional grant or weaker ownership check is authorized. T-705 execution
remains blocked pending an explicit owner-approved metadata-read design.
An IMDS resource-ID check binds execution to the expected worker VM without
retrieving an access token. Before certificate activity, verify the dedicated
public zone's NS set and all three direct per-hostname CNAME aliases through
credential-free, normal-TLS Google Public DNS HTTPS requests. Require explicit
public-query disclosure acknowledgement and separately approved HTTPS egress.
No proxy/redirect/custom resolver, recursive zone discovery or broad role
expansion is allowed; each query has a three-second/16-KiB bound and suppresses
client subnet disclosure using `edns_client_subnet=0.0.0.0/0`.

Check reads certificate metadata only and distinguishes missing, renewal due
within thirty days and critical expiry within seven days. Preview creates a new
private thirty-minute plan bound to configuration, local state, public resource/
certificate metadata, stage, action and explicit rotation. Apply requires the
exact plan digest, fresh matching snapshot and unexpired matching context before
writes. Production requires successful configuration-bound staging within seven
days, explicit ACME terms and certificate-transparency disclosure approval.
Request exactly the gateway/APIM/backend SANs with a fresh key for new issuance;
staging is never imported or bound. Validate SANs, dates, key strength/match,
matching PEM/PFX chains and production server-auth trust against system roots,
without fetching intermediates or bypassing TLS. Revocation/consumer refresh is
not certified by this offline validation.

The narrow DNS plugin changes only gateway/APIM/backend TXT aliases inside the
dedicated owned zone. Preserve unrelated TXT values; journal only newly owned
values before changes; never claim/remove identical preexisting values, delete
zones/record sets or bypass ETag conditions. Known service/conflict retries have
three attempts and one-/two-second backoff. A private journal/issuance intent
permits approved recovery of partial DNS operations, a completed client order
or an import whose response was lost; never silently roll back to an older
certificate. Retain necessary account/order state and pending failure material.
Import only the dedicated owned full-chain Key Vault certificate, never retrieve
vault secret values, and read back public metadata before storing a private
versionless reference with `PendingConsumerValidation`. Actual consumer binding/
trust/refresh, protected private delivery and scheduling remain T-706-T-708.

The public parent drains/discards all child stdout/stderr, including Console
and PowerShell streams; enforce a 1-MiB total-output limit and fifteen-minute
whole-process deadline. A closed worker exit protocol yields one fixed public
status and exit 0/3/1 for success/action-needed/incomplete. Unknown exits, excess
output, timeout or validation failures cannot become success. Failed/terminated
operations may leave protected recovery material and owned DNS challenges;
operator-reviewed recovery is required, not automatic deletion. Owner-controlled
backup/retention and later teardown remain T-711. No real Azure/DNS/ACME
operations or certificate issuance occur in the development/CI acceptance gate.

Provisioning, identity/RBAC bootstrap, certificate import/renewal and DNS writes
belong only to separately invoked lab tooling. They never extend the assessment
module, guarded ARM wrapper, collectors, broker operations or assessment-agent
permissions. Ordinary CI remains offline; only explicitly approved owner lab
workflows may change test infrastructure. Live assessment collection remains
maintainer-operated outside Copilot/CI, with raw evidence and reports restricted.

T-702's separate source-checkout owner bootstrap uses closed configuration 1.0,
two pre-existing resource groups tagged `apimAssessmentLab=<private labId>`, and
a deployment UAMI in the identity group, outside its own Contributor scope.
Only the lab group receives deployment Contributor. Owner preview writes a new
private plan with exact intended actions, configuration/state digests and a
30-minute lifetime. Apply requires the owner's exact plan SHA-256, fresh matching
state, and unexpired approval/matching interactive Azure context before writes.
Conflicting existing ownership, roles, federation, variables or protection
settings fail closed rather than being automatically changed. GitHub's required
reviewers, prevention of self-review/admin bypass and the exact `main` branch
policy must be read back before new federation is activated; unsupported or
missing control evidence blocks completion.

Identity and post-foundation Runtime are separately previewed/approved stages.
Runtime verifies all six named, tagged lab resources and distinct APIM,
gateway-UAMI and worker-VM principals before granting fixed roles only on the
dedicated vault, public challenge zone and App Insights component. Missing
foundation/worker metadata is NotReady, never a successful grant or invented
identity. Resource-audience applications and application-role assignments remain
separate directory approvals. Owner execution must be serialized; these state
digests are not signatures, distributed locks or a global effective-permission
audit. Role inventory is limited to assignments visible at/above/below the
approved subscription for each selected principal.

Private configuration/approval plans stay outside all agent-visible roots on
owner-controlled storage. The tool additionally rejects paths in/overlapping
the checkout and linked path ancestors. It never retrieves tokens or secret
values, changes assessment ARM exceptions, imports lab helpers into the module,
or grants broker/agent access. All external streams/exception text are suppressed;
the console receives only fixed outcomes. A failed apply may leave a partial
owned setup; it never deletes resources or silently rolls back protection.

The selected design uses DNS-only Cloudflare records with ACME challenge delegation
to Azure DNS for managed-identity renewal. A direct Cloudflare token is an
alternative requiring a new owner decision, not Azure identity authentication.
Use an isolated Azure DNS challenge subzone and explicit per-hostname CNAME
challenge aliases/client configuration; verify public delegation and staging
issuance before production issuance. No tokens,
certificate private material, real infrastructure identifiers or raw live output
enter tracked files/model context/CI artifacts. No Cloudflare assessment collector
is added. Product-policy exercise keys are isolated lab credentials and never
retrieved by assessment collectors. Initial lab results cannot establish
historical usage/cost, proxy/origin posture or approval of G3/G4/customer runs.

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
| 1 | Exact ARM property/mechanism to detect username/password identity on the developer portal | Resolved by T-502/D-57: use `portalconfigs/default.properties.enableBasicAuth` as direct evidence; absent values stay Unknown, never inferred disabled from providers. |
| 2 | Cloudflare origin-auth evidence (Authenticated Origin Pulls / secret header) not visible in Azure if done only via listener mTLS | Check listener SSL profile client-auth + WAF custom rules + APIM `check-header`; else finding with "Confirm with customer" note |
| 3 | Git repo layout | Support APIOps extractor layout; configurable regex |
| 4 | Whether App GW has any private listeners to APIM | Auto-detect; confidence downgrade if present |
| 5 | Log Analytics retention < 90 days | Cap window and state effective window in evidence |
| 6 | PowerPoint/readout deck automation | Out of v1; v1 produces a self-contained HTML executive presentation and keeps PowerPoint manual |
| 7 | AI gateway instance assessment | Same toolkit should run unchanged against it later; add AI rules (token limits, semantic cache, content safety) in v1.1 |
| 8 | Customer/organization approval for model-safe derived assessment facts | Copilot analysis remains disabled; deterministic collection, findings, Excel, and HTML still run locally |
| 9 | Local Copilot broker implementation | Prefer a local stdio MCP tool surface with exact tool/argument allowlists; manual path remains mandatory |
