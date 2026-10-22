# Azure Deployment Plan: Synthetic APIM Validation Lab

> **Status:** T-706 offline acceptance complete; live gates remain
>
> Not deployment-ready. Five business API contracts, owner bootstrap tooling
> and the T-703 foundation pass offline acceptance;
> T-704's owner-approved private VM worker/backend/jobs pass offline acceptance,
> including complete Windows/Linux repository gates and an isolated local recheck.
> T-705's owner-only certificate lifecycle tooling passes its forty-three-case
> focused synthetic gate. The updated bootstrap passes sixty-eight focused cases;
> complete Windows/Linux repository gates pass on the approved prerequisite code.
> Linux required one unchanged-code retry of an existing output-order assertion.
> D-70 records the closed contracts and pinned client integration.
> Actual certificate issuance/binding, gateway, lifecycle and all live changes
> remain outstanding.
> D-72 resolves D-71's offline metadata-read design: retain six existing grants
> and add worker Reader only on its own VM and dedicated vault, behind a fresh
> owner-reviewed Runtime preview/apply. No live access or assignment is authorized.
> Plan approval permits offline implementation, not deployment.
> T-706 now supplies API/product/subscription/backend/policy templates and a
> private parameter writer. Thirty-nine focused cases and the twenty-two source
> contract cases pass; complete Windows/Linux repository gates pass on committed
> implementation/tests `fff902b` in #51. Required PR review and final
> documentation-head checks remain separate; no deployment readiness is claimed.

Generated: 2026-10-19

## 1. Goal and scope

Build a repeatable, customer-neutral Bicep lab with known positive, negative and
missing-evidence scenarios for the assessment toolkit. Temporarily prioritize
this work before T-409. D-66 records owner agreement and the five-API refinement.

Required: classic Developer APIM in internal VNet mode; generated OpenAPI APIs;
global, product, API, operation and fragment policies; HTTPS Application Gateway
path routes; managed identities; Let's Encrypt certificates in Key Vault;
workspace-based Application Insights and Log Analytics; and GitHub Actions
OIDC bootstrap, federated credentials and environment variables.

This is a separate provisioning/test harness, not an assessment capability.
No write exception, credential access or provisioning code enters the module,
collectors, guarded ARM wrapper, broker or model-safe tool surface. Live
assessment collection remains maintainer-operated outside Copilot and CI.

## 2. Requirements and design decisions

| Attribute | Design / gate |
|---|---|
| Mode | Add isolated lab assets to this repository; no changes to assessment behavior |
| Classification | Disposable development/test lab; synthetic data only |
| Recipe | Standalone Bicep; version-pinned Azure Verified Modules where suitable, with documented direct-resource gaps |
| APIM | One classic Developer instance, one unit, internal VNet mode; not Developer v2 or production HA |
| Gateway | One WAF_v2 instance with bounded capacity; proposed for WAF and routing coverage |
| Edge baseline | Cloudflare DNS-only records; proxied-edge scenarios deferred |
| ACME default | Delegate challenge records to a dedicated Azure DNS zone; managed-identity renewal |
| Private execution | One small Linux VM, no public IP/inbound SSH, for bounded jobs and a synthetic backend |
| Subscription / region | Owner-selected in private configuration; not requested or discovered by this planning session |
| Budget / lifetime | Owner-approved regional estimate and cap before creation; proposed initial lifetime 72 hours |
| Approval | Owner approved offline implementation on 2026-10-19, refining the API count to five, requiring lab-owned networking and selecting ACME delegation; live changes remain separately gated |

The zone stays with Cloudflare. Delegating only ACME challenge responses does
not require moving the zone or proxying application traffic. Direct
Cloudflare automation would require a new owner decision and an owner-created
zone-scoped DNS token in Key Vault; that is not managed-identity authentication
to Cloudflare. Never use a global API key or claim token scope is per-record.

## 3. Architecture

```text
Approved caller / private worker through explicit NAT egress
  -> Cloudflare DNS-only application record
  -> public HTTPS Application Gateway listener
       /supply-chain, /e-commerce, /service-management -> internal APIM gateway
       /manufacturing -> internal APIM gateway (no deliberate traffic initially)
       unmatched paths -> dedicated private deny backend, never APIM

Private worker -> internal APIM /plm directly for private-only scenario/probes
Internal APIM -> private synthetic backend with managed-identity authentication
APIM + App Gateway diagnostics -> Log Analytics
APIM managed-identity logger -> workspace-based Application Insights

Cloudflare ACME challenge CNAME/NS delegation -> dedicated Azure DNS zone
Private certificate worker managed identity -> DNS challenge records + Key Vault
Key Vault versionless certificate references -> APIM and Application Gateway

GitHub protected environment -> OIDC -> lab deployment managed identity
  -> ARM deployments / explicitly approved private worker job invocation
```

### Networking and routing

- T-703 provisions a new VNet and all APIM, App Gateway, worker and
  private-endpoint subnets; an existing VNet is not a prerequisite. Parameterize
  private addresses and reject overlaps, subnet addresses outside the VNet and
  insufficient capacity before deployment. The synthetic default layout is:

  | Component | Synthetic address range | Rationale |
  |---|---|---|
  | VNet | `10.240.0.0/22` | Covers the four subnets plus unallocated headroom; owner checks collisions before use |
  | App Gateway | `10.240.0.0/24` | Dedicated gateway subnet; recommended v2 sizing leaves maintenance/scaling room without enabling unbounded instance counts |
  | APIM | `10.240.1.0/26` | Separate classic internal-mode subnet with deliberate maintenance/growth headroom, not a claimed Developer minimum |
  | Worker | `10.240.1.64/27` | Separate worker/backend and explicit NAT egress boundary |
  | Private endpoints | `10.240.1.96/27` | Separate Key Vault/private-endpoint boundary with spare addresses |

  These are template defaults, not discovered infrastructure identifiers.
  No VPN gateway, peering, Bastion or on-premises connectivity is assumed.
  APIM has no subnet delegation. Preserve the gateway's documented management,
  load-balancer and outbound requirements rather than applying a blanket
  outbound-deny policy that would break a standard WAF_v2 deployment.
- Internal APIM has no public data-plane route. Preserve documented classic
  APIM management/platform dependencies rather than confusing them with public
  API access. Do not publish its portal or management endpoint through App Gateway.
- App Gateway exposes HTTPS only to approved source CIDRs, including the worker's
  explicit NAT egress for public-path tests. Empty caller allowlists reject;
  unrestricted internet ingress is not the default.
- Allow APIM traffic only from the gateway and worker subnets; preserve required
  platform/service-tag rules. Intentional policy defects cannot remove this
  independent network boundary.
- Specify backend Host/SNI, the APIM status health probe, certificate validation,
  and private DNS records for exact names. Do not create a broad private zone
  that shadows unrelated public API Management names.
- Match both API base paths and child paths, preserve their prefixes initially,
  and keep path ordering explicit. The default target is a private HTTPS service
  that always denies, not an all-API APIM backend. Test arbitrary, unmatched and
  internal-only paths as negative controls.
- Use explicit worker outbound connectivity; do not depend on implicit internet
  egress. Restrict destination access to required Azure, package, ACME and DNS
  services. Additional connectivity is an explicit reviewed change.
- Key Vault uses RBAC, soft delete, purge protection, private endpoint and linked
  private DNS for worker/App Gateway access. Use APIM's system-assigned identity
  and its documented certificate control-plane network path. Validate that path
  before binding; never open the vault to all networks as a fallback or rely on
  obsolete gateway trusted-service bypass behavior.

### Five representative business APIs

| API | Base path / representative operations | Validation intent |
|---|---|---|
| Supply Chain | `/supply-chain`: inventory availability; create/get shipments | Positive routing, product contexts, inheritance and backend managed identity |
| E-commerce | `/e-commerce`: list/get products; create/get orders | Positive caller baseline, product membership and operation-scope override |
| PLM | `/plm`: part revisions/BOM; create/review engineering changes | Private worker access only; no public path route, including unmatched fallback |
| Manufacturing | `/manufacturing`: create/get production orders; record quality inspection | Published but no initial calls; zero-use control only after complete supported observation |
| Service Management | `/service-management`: create/get tickets; create service work orders | Routed baseline and controlled backend latency/5xx through private worker configuration only |

T-712 supplies five standalone OpenAPI 3.0.3 JSON documents, sixteen operations,
and `inventory.json` in `infra/live-validation-lab/scenarios/`. Schemas include
bounded line arrays, enums, dates, quantities and currency-qualified integer
minor-unit amounts, without personal, payment, address or credential examples.
Local references keep each file self-contained. Non-routable `backend.invalid`
servers are placeholders, not deployed backends. T-706's separate template binds
private backend URLs and imports the contracts; security declarations alone do not enforce
APIM policies. The inventory records stable API paths, intended publication,
traffic controls, product membership and future assertions, not live results.

The previous six validation characteristics remain covered across five
business APIs rather than becoming six additional APIs. Do not add a public
fault-toggle operation/query/header: only separately approved private worker
jobs may enable bounded failures, and fault behavior is off by default.
Use API revisions/version-set metadata where it adds a specific
assertion. Do not deploy the 60-API fixture or artificial hard-coded secrets by
default. APIM mock policies may cover a subset, but a real private synthetic
backend is required for backend timing and authentication assertions.

Baseline policies preserve `<base/>`. Reusable fragments implement explicit
auth/validation patterns; global/product/API/operation markers make inheritance
observable without logging sensitive data. A separate opt-in, private-only
negative profile may omit inheritance or vary safe diagnostic/route settings.
Do not expose intentionally unauthenticated or weak-auth scenarios publicly.

Product policy tests need product-scoped APIM subscriptions: an all-APIs or
API-scoped subscription does not exercise product policies. Generate those test
keys inside owner-run lab automation, retain them only in Key Vault/private job
memory, and require the independent lab caller controls too. Managed identity
does not replace the product subscription mechanism. Assessment collectors
still never call `listSecrets`, obtain these keys or consume certificate values.

### Observability is baseline, not a follow-up

- One Log Analytics workspace and one linked workspace-based Application Insights
  component. APIM's logger uses connection-string metadata plus managed identity
  and narrowly scoped Monitoring Metrics Publisher; avoid key-only ingestion.
- Independently configure APIM Azure Monitor gateway diagnostics to
  `ApiManagementGatewayLogs` and App Gateway access/WAF diagnostics to
  `AGWAccessLogs`/the applicable WAF table. App Insights alone is not the source
  of the collector's gateway-log tables.
- Use resource-specific tables by default. A separately selected legacy profile
  can validate `AzureDiagnostics`; do not double-count overlapping copies.
- Apply explicit all-API/per-API sampling and error settings. Disable body,
  authorization, subscription-key and secret/header-value capture. Retention,
  ingestion budgets and traffic caps are explicit private parameters.
- Generate controlled successful, denied, internal-direct, routed, throttled and
  backend-failure calls, with non-secret synthetic test markers. Poll bounded
  readiness queries until required tables and aggregate shapes are available;
  lack of ingestion is NotReady, not zero traffic or a pass.
- DNS-only traffic does not prove Cloudflare proxy/origin controls or edge-client
  attribution. Keep related attestations unknown. The current public command's
  `Cloudflare/AssumedReachable` contract is an assumption, not proof of an active
  proxy. With owner-approved actual trusted-edge CIDRs configured, the DNS-only
  baseline can exercise non-edge query shape using its non-edge traffic, but
  cannot prove a positive Cloudflare-proxied path. That needs a later proxy profile.
- A new lab has no historical cost/usage window. Do not fabricate logs, complete
  months, retention coverage or 90-day inactivity. Initial tests cover transport,
  current evidence and qualified gaps; historical conclusions remain offline
  fixture tests until sufficient real time elapses.

## 4. Identity, certificate and secret boundaries

| Principal | Minimum intended access / restrictions |
|---|---|
| Owner bootstrap session | Approved lab-scoped resource/role creation and repository environment administration; separately consented directory access for test resource applications |
| GitHub deployment UAMI | Exact repository/environment OIDC trust; Contributor on lab RG only, no standing subscription Owner or role-assignment administration |
| App Gateway UAMI | Runtime certificate secret read in the isolated lab vault; no DNS writes or certificate issuance |
| APIM system identity | Required lab certificate read, App Insights publishing and explicit synthetic-backend application role |
| Private worker system identity | Restricted challenge-zone updates, lab certificate import/renewal/state and designated test-caller role |
| Assessment operator | Existing Reader/log-query/cost-query permissions; no certificate issuance, subscription-key or vault-secret access |

Create separate resource audiences/application roles for front-door test callers
and the synthetic backend; assign application roles to the relevant managed
identities without client secrets. The privileged bootstrap must explicitly
approve these Entra application/role changes; OIDC federation itself need not
introduce a password-bearing app registration.

Role assignments are a separate owner-authorized bootstrap/RBAC stage, including
APIM's identity after it exists. Ordinary deployment identity cannot grant itself
more roles. Treat deployment/policy editing and VM job execution as privileged:
they can exercise runtime identities indirectly. Multiple identities/jobs on one
VM are not a security isolation boundary.

### Certificate lifecycle

1. Owner establishes only approved lab DNS/delegation records in Cloudflare.
   Do not replace, enumerate into model context or delete unrelated records.
   Selected approach: delegate an isolated challenge subzone to Azure DNS,
   then use DNS-only `_acme-challenge` CNAME aliases for each approved hostname
   to unique records in that zone. The app records stay with Cloudflare.
   The ACME client must explicitly target the delegated alias records; do not
   assume that an arbitrary DNS plugin automatically follows CNAMEs for writes.
2. Deploy the dedicated public Azure DNS challenge zone and worker identity/RBAC.
   Verify delegation before attempting issuance.
3. Use a pinned ACME client supporting Azure managed identity and challenge
   aliases. Posh-ACME is a researched candidate; verify its exact pinned release,
   plugin and packaging during implementation.
4. Test with Let's Encrypt staging first. Obtain production-trusted, narrowly
   named certificates only after explicit issuance approval; no wildcard is
   required. Public issuance publishes certificate names in public transparency
   infrastructure; the owner must accept that disclosure.
5. Import certificates as Key Vault certificate objects with the required PFX
   backing secret. Consumers use versionless secret references and correct
   managed identities. Do not put PFX material in Bicep parameters/outputs.
6. Persist necessary ACME account/order state only in protected owner storage.
   Limit transient worker files, permissions and retention; never upload private
   keys, tokens, PFX/passwords, ACME state or vault values to GitHub artifacts/logs.
7. Schedule bounded renewal checks with retry/backoff and an expiry alert. Renew
   before expiry, verify certificate binding and client trust, and test rotation
   without assuming consumers refresh immediately. Never disable TLS validation.

If direct Cloudflare DNS automation is selected instead, owner enters the
zone-limited token locally into Key Vault. The issuer retrieves it via managed
identity, uses it only for approved lab challenge records, and suppresses it on
every output stream. Tokens are not requested in chat, stored as ordinary GitHub
variables or created with account-wide DNS authority.

## 5. CI/CD bootstrap and delivery

T-702 implements separate owner-run tooling under D-67, tested with synthetic
mocks only. `scripts\lab\Invoke-LabBootstrap.ps1` uses closed private
configuration and a separate identity resource group: the routine deployment
identity receives no write access to the resource containing its own federation.
A read-only preview writes a private, expiring approval plan; apply must bind
to that exact plan/configuration and freshly checked state. Existing conflicting
trust/scopes/environment settings refuse rather than being silently overwritten.
GitHub protections and branch policy must be read back successfully before
federation becomes active. Unsupported or missing controls block completion.
Runtime Azure RBAC is a separate owner-approved post-foundation stage; Entra
resource-application creation/application-role assignments remain separate
directory approvals, not inferred permission for this bootstrap.

Owner bootstrap requires two pre-existing resource groups in the selected
location, both tagged `apimAssessmentLab=<private labId>`: one lab group and a
separate retained deployment-identity group. It does not create/tag arbitrary
resource groups. The private config schema/sample are under
`infra\live-validation-lab`; they are not assessment configuration or release
assets. Follow `docs\RUNBOOK.md`'s owner-only lab bootstrap section, outside
Copilot, only after the remaining private/live/lifecycle gates are approved.
No command here has been executed against Azure or GitHub settings.

The implemented idempotent bootstrap uses preview before mutation:

- Confirm the private subscription/tenant/location, target resource groups,
  repository/environment and permissions; refuse mismatched existing resources.
- Create the deployment UAMI and exact federated credential:
  issuer `https://token.actions.githubusercontent.com`,
  audience `api://AzureADTokenExchange`,
  subject `repo:<owner>/<repo>:environment:lab`.
  No wildcard subject, pull-request trust, stored Azure client secret or PAT.
- Configure the protected GitHub `lab` environment, trusted deployment branches
  and available approval controls through `gh`. If repository plan/policy cannot
  enforce the intended gate, stop for an owner decision rather than silently
  weakening protection.
- Populate non-secret environment variables such as `AZURE_CLIENT_ID`,
  `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_LOCATION`,
  `LAB_RESOURCE_GROUP` and `LAB_PROFILE`. Real values remain outside tracked
  examples, PR text, model context and job output.
- Grant only lab resource-group deployment access. Create runtime RBAC in the
  separately authorized owner stage, not by giving routine CI unlimited role
  administration. GitHub bootstrap authorization is separate from Azure OIDC.
- Repeat bootstrap with the same inputs without duplicates; detect changed
  subjects/scopes/environment settings and require explicit update approval.

Runtime stage requires the future tagged APIM, gateway UAMI, worker VM, vault,
public challenge zone and App Insights component. It grants APIM/gateway
Key Vault Secrets User on the dedicated vault; APIM Monitoring Metrics Publisher
on App Insights; worker Key Vault Certificates Officer plus Secrets Officer on
the vault and DNS Zone Contributor on the challenge zone. D-72 adds worker
Reader only on its own VM and dedicated vault for ownership metadata, bringing
the fixed Runtime matrix to eight assignments. It never grants
Key Vault Administrator, subscription-wide roles or role administration to CI.
Missing metadata returns NotReady. Existing broader/unrelated assignments
visible in the approved subscription refuse; this is not a global permissions
audit. Plans expire after 30 minutes, bind exact config text and fresh state,
and are neither distributed locks nor live-readiness proof. Partial failure
requires private owner inspection and a fresh preview; conflicting settings are
not automatically repaired and no automatic deletion/rollback occurs.

Ordinary PR CI remains offline and unprivileged: Bicep build/lint, synthetic
OpenAPI/policy/topology assertions, script tests and existing checks. It has no
Azure login, secret access or live lab access.

Separate opt-in workflows use `workflow_dispatch`, protected environments,
`contents: read`, job-scoped `id-token: write`, SHA-pinned actions, serialized
per-lab concurrency and bounded timeouts. Stages: reviewable what-if, approved
deployment, certificate readiness, API/policy/routing deployment, and bounded
connectivity/traffic/telemetry checks.

Standard public GitHub-hosted runners do not directly reach internal APIM or
private Key Vault. The proposed worker uses Azure Run Command/control-plane
execution for pinned lab jobs; do not open SSH or install a long-lived GitHub
runner/PAT. Suppress raw Run Command responses and expose only fixed job states.
Owner-managed private runners are an alternative requiring an explicit design
choice, not an assumed existing capability.

No workflow uploads live assessment artifacts, normalized models, findings,
exact metrics, raw logs, cloud output, IDs or reports. Private job evidence stays
in the owner's restricted location; CI receives bounded pass/fail/not-ready
codes. Run the existing assessment smoke from an authorized ordinary terminal,
not from PR CI or this coding session.

### 5.1 T-703 offline foundation implementation

`foundation.bicep` and `network.bicep` under `infra/live-validation-lab/` target
the existing owner-tagged lab resource group. They never recreate the deployment
identity/federation or grant runtime roles. `New-LabFoundationParameters.ps1`
validates closed private configuration and canonical RFC1918 IPv4 containment,
overlap and agreed subnet capacity, then creates a new external private parameter
file with fixed console outcomes. It performs no cloud preflight or deployment.
Owner collision/context/ownership/cost approval remains mandatory.

Suitable resource AVMs are pinned to the exact versions below. The official
pattern index was reviewed on 2026-10-20; it has no matching bounded classic-APIM
lab foundation. No pattern with unrelated workloads is introduced.

| AVM registry path (`br/public:avm/res/`) | Exact version |
|---|---|
| `api-management/service` | `0.15.0` |
| `network/virtual-network` | `0.10.2` |
| `network/network-security-group` | `0.5.4` |
| `network/nat-gateway` | `2.1.1` |
| `network/public-ip-address` | `0.13.0` |
| `managed-identity/user-assigned-identity` | `0.6.0` |
| `key-vault/vault` | `0.14.2` |
| `network/dns-zone` | `0.6.2` |
| `network/private-dns-zone` | `0.8.1` |
| `insights/component` | `0.8.0` |

**Direct-resource gap:** `Microsoft.OperationalInsights/workspaces@2025-07-01`
replaces unsuitable workspace AVM `0.16.1`, whose unconditional secure outputs
evaluate `listKeys()` twice even when the caller never requests those keys.
The direct workspace sets only metadata, retention, bounded daily cap, local-auth
disablement and query/ingestion configuration; it has no key retrieval or output.
No other direct resource gap is needed. Registry tags and corresponding immutable
version-tagged upstream source contracts were checked before implementation.

The developer installer verifies official release SHA-256 values for Bicep
`0.48.1`, installs it under ignored `.tools/bicep`, and restores the pinned public
modules. Existing CI uses that toolchain without Azure authentication. Focused
Pester tests build/lint and evaluate an offline snapshot of the real module graph:
25 predicted resources, four NSGs/four subnets, internal Developer APIM, explicit
worker NAT, protected vault private endpoint/DNS and separate gateway/App Insights
diagnostics. Tests use explicit synthetic context, not a live account or what-if.
No compiled template/snapshot/private parameters are uploaded.

**Validation proof (offline slice only):** pinned `bicep build` and `bicep lint`
passed without diagnostics. The focused command
`pwsh -NoProfile -File .\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\LabFoundation.Tests.ps1 -OutputDirectory .\artifacts\lab-foundation-checks`
passed repository-wide PowerShell lint and all 39 foundation cases, with zero
failures or skips. The full command
`pwsh -NoProfile -File .\scripts\Invoke-Checks.ps1 -OutputDirectory .\artifacts\lab-foundation-full-checks`
passed lint and 1435 tests, with zero failures and two existing skips.
Code CI run 39459307855 on committed implementation/tests `0be6e73` passed both
full gates: Windows 1429 passed/eight existing skips; Linux 1431 passed/six
existing skips; zero failures and lint clean on both. All 39 new tests execute
without skips on both platforms. PR #48 remains subject to required review;
final commands/results are recorded in the task register.
Static role review confirms that this slice deliberately creates no grants;
the fixed resource-scoped grants, including D-72's two metadata Readers, remain
separately owner-approved T-702 Runtime operations and need the worker identity.
The `azure-validate` Bicep recipe's authenticated ARM validation, what-if and
policy/capacity checks were **not run**: they access live infrastructure and are
outside this offline authorization. Full deployment validation is blocked,
not marked Validated or Ready for Deployment; do not invoke deployment.

The worker has no blanket Internet egress; owner-approved package/ACME/later-gateway
HTTPS CIDRs supplement fixed Azure/platform dependencies. This is IP-based control,
not FQDN filtering. Standard App Gateway egress and classic APIM platform
dependencies are preserved. Key Vault's default-deny public firewall with
AzureServices bypass/APIM service endpoint is intentional for its system-identity
certificate control plane; worker/gateway use private endpoint/DNS. A successful
snapshot is not proof of that path, grants, certificate binding or ingestion.
No VM, gateway listener, application DNS record, certificate, API or role grant
is created by this slice. Keep T-704-T-711 and all owner live gates blocked as
their dependencies require.

### 5.2 T-704 private worker implementation

The owner explicitly confirmed the VM choice on 2026-10-20; D-69 records the
bounded implementation. Reuse the foundation worker subnet/NSG/NAT rather than
creating another network or public VM IP. Pin VM AVM `0.22.3` (version-tagged
source commit `2af429a8933beea9b7d0754535d33e47eff0d007`), use a system-assigned
identity, static private IPv4 address, Trusted Launch and password-disabled
Linux provisioning. No inbound SSH, standing runtime grant or public runner.

The separate backend/job application uses .NET SDK `10.0.402` and ASP.NET Core
JWT bearer `10.0.13`, verified against the official 2026-10-13 release metadata.
The public Microsoft `dotnet-public` package mirror avoids reliance on inaccessible
NuGet endpoints; lock restored dependencies. Serve only TLS 1.2/1.3 with an
owner-provided certificate/private key and a chain trusted by each caller.
Missing certificate/trust/identity inputs must not produce a readiness pass.
Linux-x64 is the fixed self-contained publish target. Default/static web asset
publication is disabled; only binaries/runtime metadata and the five explicitly
listed contract assets may ship. SDK roll-forward is disabled. Windows synthetic
TLS acceptance reimports PEM keys into Schannel-compatible certificate handles
without bypassing trust/name validation; the Linux service retains PEM loading.

Backend tokens require a configured tenant, exact v2 resource audience, fixed
application role and explicit caller-client allowlist. Synthetic business
responses follow the five committed contracts; the deny endpoint never forwards.
Fault state is private, time/request-bounded, off by default and restricted to
Service Management. Jobs accept only fixed profiles, cap calls/time/body sizes,
disable redirects, keep managed-identity tokens in memory and emit fixed outcomes,
not URLs, tokens, response bodies, metrics or exception details. Manufacturing
is not in initial traffic profiles.
Traffic bounds are 1-20 sequential requests, 250-2000 ms spacing, three-second
HTTP/metadata timeouts and a 60-second whole-job deadline. Service Management
faults expire within 120 seconds, cap delay at 1000 ms and failure count at ten,
with persistent failure counters and an in-process monotonic expiry bound.
Only the runtime counter directory is service-writable; the root-owned job/state
directory uses setgid so root-created atomic profiles inherit the readable
service group without granting backend write access.

Implement and test offline only. Actual private binary/config/certificate delivery
and protected Run Command orchestration remain T-708; public ACME stays T-705,
and resource-application grants/APIM backend trust and imports stay owner/T-706
gates. The VM agent channel is privileged, not a job/identity isolation boundary.
**Validation scope:** Offline acceptance applies only to this T-704
slice. Final pinned Bicep build/lint, the evaluated two-resource VM/NIC graph,
real synthetic TLS/JWT/operation/job acceptance and exact Linux-x64 publish
allowlist all pass through twenty focused Pester checks with zero failures/skips.
Complete Windows/Linux repository gates pass. The local full run had one
unchanged secret-scan regex timeout; its isolated suite passes without changes.
Section 7 records both the original failure and the successful recheck.

Authenticated ARM validation/what-if, policy/capacity/permission checks,
deployment, private delivery, role grants and actual TLS/ingestion readiness are
**not run and blocked** by the explicit offline-only authorization. There is no
Azure context or private input to inspect. Do not run those recipe steps,
call the full lab Validated/Ready for Deployment or invoke deployment.

### 5.3 T-705 certificate lifecycle implementation

The owner approved proceeding with T-705 on 2026-10-21 after #49 merged.
Implement only separate owner-operated ACME DNS-01 certificate tooling:
delegation checks, staging before explicitly approved production issuance,
protected local account/order state, Key Vault certificate import, bounded
renewal checks and rotation/expiry evidence. Ordinary CI uses synthetic/mocked
inputs exclusively. No actual DNS, ACME, Azure identity/resource or certificate
operation is authorized in this development session.

D-70's implementation contract:

- Pin Posh-ACME 4.35.0 (released 2026-10-12, source commit
  `392c2e76ef8d3fcc0f131617549af4e1068d85e4`) and owner-only Az.Accounts
  5.5.3, Az.Dns 2.2.0 and Az.KeyVault 6.6.1 in a separate lab runtime
  dependency manifest. Ordinary offline tests do not import Az contexts or
  issue certificates. Runtime installation is explicit, never automatic.
- Use a custom Posh-ACME DNS-01 plugin for exactly the dedicated zone and
  `gateway`, `apim` and `backend` TXT aliases. The built-in Azure plugin's
  subscription-wide zone discovery is unsuitable for the existing zone-scoped
  grant. Preserve T-702 roles: no extra permission, zone enumeration, Cloudflare
  token, DNS application record or role assignment.
- Check the public zone NS set and each direct per-hostname challenge CNAME via
  fixed, credential-free Google Public DNS HTTPS queries. Private split DNS is
  not public-delegation proof. Require explicit public-query acknowledgement,
  normal TLS validation, no redirects/proxy, bounded responses/timeouts and
  owner-approved `dns.google` HTTPS egress. Set `edns_client_subnet=0.0.0.0/0`;
  only the configured public zone/challenge names are queried.
- Closed private configuration supplies exact lab/tenant/subscription/resource
  names, the three distinct hostnames, protected state directory and complete
  host-visible roots. Reject unknown/duplicate fields, wildcards, noncanonical
  names/paths, links, visible-root overlap and insufficient private permissions.
  ACME account/order data never uses a default home directory.
- A dedicated child process uses system-managed-identity authentication only,
  process-local context/no autosave, matching tenant/subscription and fresh
  owner-tagged VM/vault/zone evidence. Drain every child stdout/stderr stream;
  a bounded exit-code protocol exposes fixed statuses only, even on failures.
- Read-only health checks distinguish absent, renewal-due and critically
  expiring certificates. Preview writes a new private configuration/state-bound
  approval plan with a thirty-minute lifetime; apply requires its exact digest
  and fresh matching evidence. Staging/production state is separate. Production
  needs successful staging bound to this configuration within seven days,
  explicit terms acceptance and certificate-transparency disclosure approval.
- Request one narrowly named three-SAN certificate for the configured gateway,
  APIM and backend names. Staging certificates are never imported or bound.
  Validate candidate keys, exact SANs/dates and production system-root chain
  before importing a full-chain PFX as the dedicated Key Vault certificate.
  Read only certificate metadata, never vault secret values.
- Preserve unrelated TXT values and use conditional DNS updates without
  overwrite. Keep a private journal of this invocation's challenge changes for
  bounded recovery; never delete a zone/record set. Serialize owner execution,
  limit retries/backoff and bound the complete child process to fifteen minutes.
  Approval/context checks apply before writes. A failed/terminated run can leave
  owned challenge/pending state; it is not silently rolled back or called Ready.
- Renew within thirty days of expiry; emit a fixed critical warning within seven
  days. Support separately approved forced rotation, fresh keys and idempotent
  recovery of a completed client certificate or successful import. Read back
  the imported certificate before recording its versionless secret reference.
  A receipt explicitly retains pending consumer refresh/trust validation; do
  not claim that importing a new version proves gateway/APIM/backend rotation.

Consumer binding/delivery/protected scheduling remain T-706-T-708. Persistent
private account/order state and retained pending material require owner-controlled
backup/retention; T-711 must preserve them during later lifecycle operations.
Full lab deployment and all private/live acceptance gates remain blocked.

**Scoped metadata prerequisite (D-72):** after clarification, the owner approved
the offline bootstrap change resolving D-71. Preserve the six existing Runtime
assignments and add Reader only for the worker identity on its own VM and
dedicated vault. No subscription/resource-group/DNS Reader or other-principal
Reader is allowed. These management-plane reads preserve fresh ownership checks
without broadening the DNS grant. Existing six-grant installations propose only
the two missing assignments; old six-action approvals refuse. Actual assignment
still needs a fresh owner-reviewed digest-bound Runtime plan and private live
permission validation. No Azure login or assignment is authorized by this code
approval. Forbidden-read coverage remains, proving refusal before DNS/issuance.

### 5.4 T-706 offline API and policy implementation

After merged #50, implement only the five existing T-712 APIs/sixteen operations.
`apis.bicep` targets children of the existing APIM, never the parent service.
Pin API 0.2.2, backend 0.2.2, product 0.2.3, subscription 0.1.3, global policy
0.1.2 and operation policy 0.1.0 AVM child modules with telemetry disabled.
Two direct 2024-05-01 policy-fragment resources fill the absent published AVM
fragment module. No network, hostname, diagnostic or runtime grant changes.

The evaluated topology contains 47 children: five APIs, five backends, two
products, seven product/API memberships, two active product-scoped subscriptions,
one global policy, two product policies, five API policies, sixteen operation
policies and two fragments. Preserve the original schemas/examples, replacing
only non-routable server placeholders; operation policy targets use APIM's
normalized lowercase operation IDs.

Frontend Entra validation requires the exact tenant, v2 frontend GUID audience,
worker application and `Lab.Frontend.Invoke`; delegated tokens reject. PLM
also requires the exact private worker source and `Lab.Plm.Invoke`. Real matching
product context plus an executed product-policy marker is mandatory; API/all-API
keys cannot bypass product policy. Preserve subordinate inheritance and fixed
non-sensitive scope markers. Backends require HTTPS/chain/name validation;
strip caller authorization/subscription credentials and use APIM's system identity
for the distinct backend `api://` resource. No redirects or public fault toggles.
Manufacturing remains initially dormant.

The closed version 1.0 API configuration validates canonical private source
ranges, their non-overlap and worker containment, distinct application IDs and
an HTTPS DNS origin. `New-LabApiParameters.ps1` writes only new external files
with fixed status output. It cannot confirm resource ownership, network collision,
live DNS, trust, application-role assignment or effective permissions.
Private certificate/DNS/hostname binding and protected product-key delivery/use
remain owner/T-707/T-708 gates. Current worker jobs do not send product keys;
their existence is not a product-context readiness pass.

**Focused evidence:** official `Invoke-Checks.ps1` with
`-TestPath .\tests\unit\LabApis.Tests.ps1 -OutputDirectory .\artifacts\lab-api-checks`
passes repository-wide lint and all 39 cases, zero failures/skips, in 17.42 seconds.
Tests compile/evaluate the real template, merge all 23 product-operation paths
through the real inheritance engine, and compile the actual guard expressions
against synthetic contexts, including denied/missing context. Official
`Invoke-Checks.ps1` with `-TestPath .\tests\unit\LabOpenApi.Tests.ps1 -OutputDirectory .\artifacts\lab-api-contract-checks`
passes lint and all 22 cases, zero failures/skips, in 37.89 seconds, including
the five installed pinned Spectral validations.

**Complete code evidence:** CI run 39790189051 on committed implementation/tests
`fff902b` passed its first attempt. Windows passed 1537 tests, zero failed and
eight existing skips, in 1945.42 seconds; Linux passed 1539 tests, zero failed and
six existing skips, in 487.16 seconds. Branch policy and repository-wide lint
pass; all 39 new API cases execute without skips on both platforms.
`gh run watch 39790189051 --repo christopherhouse/Apim-Assessment --exit-status --interval 60`
passed. T-706 is Done at 100%; required PR review and final documentation-head
checks remain separate. No actual APIM/Entra/Azure request, key retrieval,
private DNS/certificate access, deployment or release was performed.

## 6. Inventory and owner-only deployment preflight

These are planned quantities, not discovered resources or verified capacity.

| Resource type / component | Planned quantity | Usage / quota / readiness |
|---|---|---|
| Resource groups | 1 lab + 1 separately owned retained identity boundary | Owner-created/tagged bootstrap prerequisites; not queried |
| APIM classic Developer | 1 | Not queried; confirm region, offer and service limit |
| Application Gateway WAF_v2 + WAF policy | 1 each | Not queried; confirm regional capacity and approved maximum |
| VNet / subnets / NSGs | 1 / 4 / 4 | Offline foundation asserted; private address collisions/platform readiness not queried |
| Public IP / NAT gateway | 2 / 1 | Not queried; confirm public-IP/NAT limits and cost |
| Linux VM / NIC / OS disk | 1 each | Not queried; select small supported SKU and vCPU quota |
| Key Vault / private endpoint / vault private DNS zone | 1 each | Not queried; confirm policy, protection and routing |
| Application/backend private DNS | Exact records/zones as required by approved names | Owner-defined; no broad public namespace shadowing |
| Public Azure DNS challenge zone | 1 | Not queried; delegation/CAA/issuance permission required |
| Log Analytics / Application Insights | 1 each | Not queried; retention, ingestion, auth and cost approval required |
| User-assigned identities / federated credential | 2 / 1 baseline | Not queried; deployment and gateway identities; other runtime identities are system-assigned |
| Synthetic API resource applications | 2 | Not queried; explicit owner directory/application-role approval |
| APIM APIs / products / test subscriptions | 5 / 2 / 2 product-scoped | Five business contracts; actual keys remain private |

**Capacity status: unverified; deployment blocked.** This planning session does
not inspect Azure subscriptions or fetch quotas. Before any deployment, the
owner confirms actual subscription/region, provider availability, current usage,
limits, organizational policy, DNS ownership, explicit permissions and budget.
Record that proof privately and expose only an approved readiness result. No
quota increase, policy exemption or broader role is assumed.

Estimate APIM, WAF_v2 capacity, VM/disk, NAT/public IP, private endpoint, DNS,
Key Vault operations and log ingestion for the selected region/lifetime. Budget
alerts are notifications, not a spending cutoff. Labels/expiry reminders do not
stop billing; approved cleanup is still required.

## 7. Implementation tasks, order and validation proof

The authoritative acceptance/status records are T-701 through T-712 in
`docs/APIM-Assessment-Task-Register.md`. Existing T-114 owns actual provisioning;
T-403/T-604 live acceptance remains separate.

| Order | Task | Delivery |
|---|---|---|
| 1 | T-701 | Owner agreed offline design/redirect with D-66 refinements; live gates remain |
| 2a | T-712 | Independent requested five business API contracts/inventory, after T-701 only |
| 2 | T-702 | Offline-tested identity/federation/GitHub environment bootstrap and staged RBAC tooling |
| 3 | T-703 | Bicep network, internal APIM, observability, vault and identity foundation |
| 4 | T-704 | Private worker, TLS deny/synthetic backend and bounded job contracts |
| 5 | T-705 | Delegated ACME issuance, protected state, Key Vault import, renewal and rotation |
| 6 | T-706 | Import T-712 OpenAPI, products/subscriptions and multi-scope policies after worker readiness |
| 7 | T-707 | App Gateway TLS, explicit API path routes, fail-closed fallback and probes |
| 8 | T-708 | Protected deployment/what-if/job workflows, no live PR CI |
| 9 | T-711 then T-709 | Lifecycle/cleanup tooling, offline acceptance harness and maintainer runbook |
| 10 | T-114 then T-710 | Owner-approved provision, live assertions and restricted acceptance evidence |

Use small reviewed implementation PRs; do not land eleven tasks as one
unvalidated deployment. The requested independent API assets are T-712;
T-702 remains the first infrastructure/bootstrap slice, with mocked
Azure/GitHub calls and no actual bootstrap execution.

### Validation proof: T-704 offline slice

- [ ] All deployment validation checks pass (blocked; not deployment-ready).
  - [ ] Core validation: CLI/authentication, ARM validation and what-if.
    Not run: requires unauthorized live Azure access and private scope/parameters.
    The offline build portion passes through the pinned standalone compiler.
  - [x] Bicep lint: pinned compiler and evaluated synthetic VM/NIC graph pass.
  - [ ] Azure Policy validation. Not run: owner subscription/policy/capacity/
    permission inspection remains outside this offline authorization.
- [x] Build verification: locked .NET build and self-contained Linux-x64 publish
  pass; private JSON canary is excluded and the published JSON inventory is exact.
- [x] Static role review: the worker template creates only its VM/NIC/system
  identity, with no role assignments or broad grant. Separate T-702 Runtime
  grants and owner directory application roles are prerequisites for actual use;
  their absence is not an implied successful deployment.
- [x] `pwsh -NoProfile -File .\scripts\Test-DevelopmentBranch.ps1` passed on
  `feature/lab-private-worker`.
- [x] `pwsh -NoProfile -File .\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\LabWorker.Tests.ps1 -OutputDirectory .\artifacts\lab-worker-checks`
  passed: repository-wide PSScriptAnalyzer clean, twenty Pester tests passed,
  zero failed/skipped. Includes locked runtime build/publish, actual loopback
  TLS/JWT/contract acceptance, bounded private jobs and evaluated topology.
- Local full `pwsh -NoProfile -File .\scripts\Invoke-Checks.ps1 -OutputDirectory .\artifacts\lab-worker-full-checks`
  completed: repository lint clean, 1454 tests passed, one failed and two existing
  skips. The unchanged oversized-workbook total test hit a regex timeout;
  this initial local run is not recorded as a clean pass.
- [x] `pwsh -NoProfile -File .\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\RunSecretScan.Tests.ps1 -OutputDirectory .\artifacts\lab-worker-secret-scan-recheck`
  passed: repository lint clean, all 76 tests passed, zero failed/skipped,
  including the original timeout case. No code, tests or safety limits changed.
- [x] `gh run watch 39507608895 --repo christopherhouse/Apim-Assessment --exit-status --interval 60`
  passed on committed worker code `cdf1a80`: branch policy and complete
  Windows/Linux lint/Pester gates. Windows: 1449 passed, zero failed, eight
  existing skips; Linux: 1451 passed, zero failed, six existing skips. All twenty
  worker tests ran without skips; the oversized-workbook case passed on both.
  Six optional-tool skips and the two Windows platform/privilege skips are
  pre-existing. Offline proof and implementation are submitted in #49;
  required PR review and final-head checks remain separate.

Do not invoke `azure-deploy`: authenticated/owner/lifecycle checks have not passed.
Offline proof is not live permission, certificate trust, telemetry ingestion or
full lab readiness.

### Validation proof: T-705 offline slice

- [ ] All deployment validation checks pass (blocked; not deployment-ready).
  - [ ] Core validation: CLI/authentication, ARM validation and what-if.
    Not run: requires unauthorized live Azure access and private scope/parameters.
  - [ ] Azure Policy validation. Not run; no subscription/resource inspection.
  - [x] Focused build/lint: source-checkout PowerShell tooling and closed schemas
    pass repository-wide PSScriptAnalyzer and sixty-eight bootstrap plus
    forty-three ACME cases. No Bicep/network/module export or actual role
    assignment is changed.
- [x] Static role verification: D-72's approved fixed Runtime matrix includes
  worker Reader on exactly its own VM and dedicated vault for ownership GETs.
  Microsoft's built-in Reader definition supplies management-plane `*/read`
  with no data actions or writes. The six existing grants and all DNS/ownership
  guards are unchanged; actual effective permission validation remains owner-only.
- [x] `pwsh -NoProfile -File .\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\LabBootstrap.Tests.ps1 -OutputDirectory .\artifacts\lab-acme-bootstrap-checks`
  passed all sixty-eight cases with zero failures/skips in 16.9 seconds and
  repository-wide lint clean. Covers exact Reader scopes/principal, legacy
  six-grant upgrade, stale six-action approval refusal and broad-read rejection.
- [x] `pwsh -NoProfile -File .\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\LabAcme.Tests.ps1 -OutputDirectory .\artifacts\lab-acme-checks`
  passed all forty-three cases with zero failures/skips in 29.1 seconds and
  repository-wide lint clean. Includes strict private-state types, forbidden
  ownership reads, private lock ownership/reopening and real RSA/ECDSA keys.
- `pwsh -NoProfile -File .\scripts\Invoke-Checks.ps1 -OutputDirectory .\artifacts\lab-acme-full-checks`
  was stopped as superseded after initial CI exposed portability defects; it
  discovered before the final focused cases and is not claimed as a pass.
- `gh run watch 39649898253 --repo christopherhouse/Apim-Assessment --exit-status --interval 60`
  failed on initial committed code `07692ce`. Windows: 1485 passed, six failed,
  eight existing skips; Linux: 1492 passed, one failed, six existing skips.
  Failures identified default Windows lock ownership and PowerShell's OpenSSL
  key-size property access. The lock now uses an explicit owner/DACL at atomic
  creation, and certificate validation invokes the inherited getter directly;
  existing unsafe-file refusal, locking and key-strength thresholds are unchanged.
- [x] `gh run watch 39656977836 --repo christopherhouse/Apim-Assessment --exit-status --interval 60`
  passed on committed portability code `9efbbdb`: branch policy and complete
  Windows/Linux lint/Pester gates. Windows: 1492 passed, zero failed, eight
  existing skips; Linux: 1494 passed, zero failed, six existing skips.
  All forty-three ACME tests execute without skips. Six optional-tool skips
  and the two Windows platform/privilege skips are pre-existing.
  This full code proof predates D-72's approved bootstrap prerequisite.
- `gh run watch 39678315366 --repo christopherhouse/Apim-Assessment --exit-status --interval 60`
  initially failed on committed D-72 code `b2e7200`: Windows lint/Pester passed
  with 1498 passed, zero failed and eight existing skips in 1139 seconds; Linux
  had 1499 passed, one failed and six existing skips in 608.95 seconds. The sole
  failure was the unchanged secret-scan standalone process test's final merged
  stdout/stderr line assertion. Neither its test nor entrypoint changed.
- [x] `gh run rerun 39678315366 --repo christopherhouse/Apim-Assessment --failed`
  followed by `gh run watch 39678315366 --repo christopherhouse/Apim-Assessment --exit-status --interval 60`
  passed on the same `b2e7200` commit. Linux: 1500 passed, zero failed and six
  existing skips in 674.5 seconds; branch policy and Windows remain green.
  All sixty-eight bootstrap and forty-three ACME cases run without skips.
  No code, test, output contract or safety limit changed for this retry; the
  initial attempt is not claimed as a pass. T-705's offline acceptance is
  complete; required PR review and final documentation-head checks are separate.

The `azure-validate` Bicep recipe was reviewed for this separate tooling slice.
Its authenticated core/policy steps are intentionally unexecuted and blocked;
there is no private owner context to inspect. Do not set full `Validated` or
invoke `azure-deploy`. Synthetic certificate validation does not establish live
permission sufficiency, issuance, consumer trust/refresh, protected delivery or
full lab readiness.

## 8. Acceptance gates

**Offline gate before live authorization**

- Bicep compiles/lints; verified pinned modules/API versions are recorded.
  OpenAPI documents validate/import structurally and policies are well-formed.
- Assert internal Developer SKU, runtime identities, required LA/App Insights
  diagnostics, safe auth, Key Vault references and deny-default path topology.
- Test bootstrap idempotence, wrong scope/environment/subject refusal, failure
  isolation and every-stream secret handling using synthetic inputs only.
- Fail closed on absent private parameters, caller allowlists, certificate
  readiness, unsupported provider/SKU, permission or network preflight.
- Preserve the assessment guard tests, module exports, release package exclusions
  and model-data boundary. Lab assets must not become executable module content.
- Teardown preview and retained-resource behavior are ready before deployment.
  Existing lint/Pester gates and documented lab checks pass on supported hosts.

**Owner live gate**

- Reviewed what-if, capacity/cost/permission approval and private inputs precede
  any create/update, federated identity, GitHub environment or DNS mutation.
- Deploy twice without unintended replacement; verify healthy APIM-targeted
  probes, valid TLS/SNI and denial of unmatched/internal-only public paths.
- Verify positive and negative authentication, each product policy context,
  backend identity, inheritance markers, bounded faults and rate behavior.
- Prove APIM/App Gateway resource log ingestion and App Insights telemetry
  separately; execute all configured observed-route query shapes. Skipped or
  partial capabilities remain gaps, not successful executions.
- Validate staging issuance, approved trusted issuance, managed-identity vault
  retrieval and renewal/rotation without revealing private material.
- Run the existing sixteen-collector smoke and secret scan locally, then the
  implemented deterministic assessment workflow separately. Compare against
  declared supported expectations; no fabricated history or new-rule passes.
- Keep raw evidence/results/reports outside every Copilot-visible root and out
  of CI/release artifacts. Record only owner-approved bounded acceptance status
  in the register. G3/G4 and customer-run approval are not implied by this lab.

**Lifecycle**

Protect persistent identity/ACME state from accidental stack deletion. A
manual, separately approved teardown previews exact owned resources/DNS
records, cleans only the lab, and never purges Key Vault or touches unrelated
zone records/resources. Retained resources, access revocation, certificate
expiry, DNS cleanup and continued charges must be explicit.

## 9. Files and implementation boundary

| Location | Intended content |
|---|---|
| `infra/live-validation-lab/` | Bicep entry points, pinned modules and synthetic parameter examples |
| `infra/live-validation-lab/scenarios/` | Five original OpenAPI contracts/inventory implemented in T-712 |
| `infra/live-validation-lab/apis.bicep` and `policies/` | T-706 offline API/product/subscription/backend deployment and multi-scope policy bindings; actual execution remains gated |
| `scripts/lab/` | Separate owner bootstrap, bounded jobs, readiness/validation and cleanup tooling |
| `.github/workflows/lab-*.yml` | Offline lab validation and separately protected manual delivery |
| `tests/unit/` and `tests/integration/` | Offline lab contracts, mocks and synthetic assertion tests |
| `docs/RUNBOOK.md` | Runnable lab commands only when implemented |

Actual parameter files, provider outputs, role/principal IDs, zone/host names,
certificates/keys and live evidence belong in private owner storage, not these
tracked examples. Add explicit exclusions when implementation introduces those
artifacts; do not treat gitignore as an access boundary.

## 10. Research references

Official service and project-maintainer documentation checked on 2026-10-19;
these are planning references, not assessment rule `References`.

- Internal APIM with Application Gateway:
  `https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-integrate-internal-vnet-appgateway`
- Classic APIM subnet requirements and recommended gateway sizing:
  `https://learn.microsoft.com/en-us/azure/api-management/virtual-network-injection-resources`
  `https://learn.microsoft.com/en-us/azure/application-gateway/configuration-infrastructure`
- OpenAPI 3.0.3:
  `https://spec.openapis.org/oas/v3.0.3`
- URL routing and its default backend:
  `https://learn.microsoft.com/en-us/azure/application-gateway/url-route-overview`
- Gateway Key Vault identity/certificate integration:
  `https://learn.microsoft.com/en-us/azure/application-gateway/key-vault-certs`
- APIM identity, firewall and certificate requirements:
  `https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-use-managed-service-identity`
- Managed-identity Application Insights logger:
  `https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-app-insights`
- APIM diagnostic settings/resource-specific logs:
  `https://learn.microsoft.com/en-us/azure/api-management/monitor-api-management`
- GitHub Azure OIDC:
  `https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-azure`
- Hosted-runner private networking:
  `https://docs.github.com/en/actions/concepts/runners/private-networking`
- Azure VM Run Command:
  `https://learn.microsoft.com/en-us/azure/virtual-machines/run-command-overview`
- DNS-01 and challenge delegation:
  `https://letsencrypt.org/docs/challenge-types/`
- Cloudflare token scoping:
  `https://developers.cloudflare.com/fundamentals/api/get-started/create-token/`
- Managed-identity ACME DNS client and aliases:
  `https://poshac.me/docs/v4/Plugins/Azure/`
  `https://poshac.me/docs/v4/Guides/Using-DNS-Challenge-Aliases/`
- Product policy subscription context:
  `https://learn.microsoft.com/en-us/previous-versions/azure/api-management/api-management-howto-policies`
- Explicit outbound networking and budgets:
  `https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/default-outbound-access`
  `https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-acm-create-budgets`
- Public certificate-transparency disclosure:
  `https://letsencrypt.org/docs/ct-logs/`

## 11. Current readiness

Owner approved offline implementation with D-66 refinements: five business
APIs, new lab-owned networking and Azure DNS ACME delegation. T-701/T-712 design/
contracts, T-702 bootstrap and T-703 foundation have committed offline acceptance.
The owner-approved T-704 private VM, TLS backend/deny service and bounded jobs now
pass twenty focused checks including closed Linux publishing and the complete
Windows/Linux repository gates. The local full run's single unchanged regex
timeout passed on an isolated 76-test rerun without code or safety changes.
Implementation/tests are committed in `cdf1a80` and submitted in #49; required
PR review and final-head checks remain separate. No whole-lab acceptance is claimed.

T-705's separate certificate lifecycle and approved D-72 metadata-read
prerequisite have committed offline acceptance in merged #50, including complete
Windows/Linux gates. T-706's API/product/policy templates and tests are committed
in `fff902b` and #51, with focused acceptance and complete Windows/Linux code
gates passing. Required PR review and final documentation-head checks remain
separate. Actual issuance,
deployment/trust binding, gateway routes, protected delivery/invocation, lifecycle
and live acceptance remain owner gates or T-707-T-711. Actual quota/context/cost/permission/DNS confirmation and owner
bootstrap/deployment authorization remain blocked, not implicitly approved.
Completed offline acceptance applies only to the implemented T-701-T-706/T-712 slices;
do not mark the full lab Validated, Ready for Deployment or Deployed.
