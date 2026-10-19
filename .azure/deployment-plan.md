# Azure Deployment Plan: Synthetic APIM Validation Lab

> **Status:** Offline implementation approved - API contracts in review
>
> Not deployment-ready. Five business API contracts are available for review.
> Infrastructure/bootstrap tooling and all live changes remain outstanding.
> Plan approval permits offline implementation, not deployment.

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
servers are placeholders, not deployed backends. T-706 binds private backend
URLs and imports the contracts; security declarations alone do not enforce
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

Implement an idempotent owner-run bootstrap, with preview before mutation:

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

## 6. Inventory and owner-only deployment preflight

These are planned quantities, not discovered resources or verified capacity.

| Resource type / component | Planned quantity | Usage / quota / readiness |
|---|---|---|
| Resource groups | 1 lab; optionally a separately approved retained identity boundary | Not queried; owner selects ownership/scope |
| APIM classic Developer | 1 | Not queried; confirm region, offer and service limit |
| Application Gateway WAF_v2 + WAF policy | 1 each | Not queried; confirm regional capacity and approved maximum |
| VNet / subnets / NSGs | 1 / 4 / at least 3 | Not queried; validate address space and platform rules |
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

## 7. Implementation tasks and order

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
| `infra/live-validation-lab/scenarios/` | Five OpenAPI contracts/inventory implemented in T-712; multi-scope policies and deployment bindings remain T-706 |
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
APIs, new lab-owned networking and Azure DNS ACME delegation. T-712 contracts
pass focused offline validation; the full gate/review is pending.
Bootstrap/infrastructure/policies/traffic implementation,
their offline checks, actual quota/context/cost confirmation, live
bootstrap/deployment authorization and live validation are outstanding.

Next infrastructure slice: T-702. Do not advance this plan to Ready for
Validation, Validated or Deployed
until the corresponding implementation and evidence exist.
