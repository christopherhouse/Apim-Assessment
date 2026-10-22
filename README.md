# APIM Assessment Toolkit

A customer-neutral, **read-only** Azure API Management assessment system:
deterministic PowerShell performs **Collect -> Analyze -> Render**, while a
constrained GitHub Copilot workflow performs **Review -> Synthesize** over an
independently validated, model-safe package. Implemented outputs include versioned
JSON evidence, deterministic findings, an Excel action plan, and a self-contained
HTML executive presentation, tracking carry-forward, and saved-run comparison.

## Current status

**Bounded deterministic entry points, local model-safe broker, and offline reports;
not approved for customer runs.** The
module imports and contains private configuration validation, structured logging,
a guarded ARM transport, schema-validated run persistence, and internal APIM
service/API/product/subscription/policy/network collectors plus allowlisted
named-value/backend/certificate and logger/diagnostic collectors, and exports
five implemented assessment commands: `Invoke-ApimCollect`,
`Invoke-ApimAnalyze`, `Invoke-ApimReport`, `Invoke-ApimAssessment`, and
`Compare-ApimRun`.
Effective policy inheritance, fragment expansion, scope attribution, and
normalized hashing plus deterministic policy-flag extraction are implemented as
private offline model helpers. Private schema-validated builders now produce the
service, API, operation, policy-matrix, subscription, named-value,
backend, certificate, network, and evidence-qualified exposure model records from
saved inputs. A private
offline rule engine now loads rule
definitions, evaluates available model-backed scopes, and validates deterministic
findings against a closed schema before restricted persistence. A private
report helper groups schema-valid findings into closed, deterministic action
items without removing the instance rows needed by future Finding Details.
Seven NET rules,
fifteen currently model-backed SEC rules, ten currently model-backed GOV rules,
all six REL rules, all five POR rules, and COST-001 through COST-005 are implemented. Secret-safe
identity/authentication and portal configuration collectors feed an optional
closed portal model. POR-002 reads `portalconfigs/default.properties.enableBasicAuth`
directly; absent evidence stays Unknown. POR-003 requires explicit product/group
intent. A guarded OpenAPI collector exports current HTTP APIs, rejects
secret-bearing documents before persistence, and records non-HTTP skips.
POR-004 combines operation-description coverage with optional offline Spectral
quality scores; unavailable tooling or unsupported references leave the score
null, never a synthetic pass. The organization collector saves six closed
structural inventories and a counts-only user summary; user identity storage
is rejected before authentication or run creation. Optional product-governance
and diagnostic-coverage models use explicit local ownership, external-product
and critical-API intent for GOV-003/GOV-009. Missing intent remains Unknown;
no owner or criticality is inferred from names. NET-001
and NET-009 require explicit operator attestation of effective origin
authentication and endpoint-owner need; without it, they produce
Info/NotEvaluated rather than guessing. The SEC catalog covers reachable weak
legacy TLS/cipher enablement, missing management API version constraints,
or absent caller authentication, active all-API subscriptions, hard-coded
policy credentials, secret-like plain-text named values, disabled HTTPS backend
certificate validation, Key Vault-backed secret/certificate health, unapproved
plain-HTTP backend targets, unsafe CORS, diagnostic body/sensitive-header
logging, subscription tracing, missing managed identity, and production
mock/trace policy. Remaining collectors
and models, the rest of the SEC catalog,
the remaining GOV and other rule catalogs
are not implemented. The offline Excel writer now
populates the implemented deterministic report sheets, Run Info, the implemented
rule catalog, and editable scoring weights from a validated saved run.
Optional local committed Git policy collection, offline cross-environment
policy/API-presence comparison, and the Environment Drift sheet are implemented.
The public Report command replays findings before rendering paired Excel/HTML
reports. HTML includes deterministic local topology/exposure charts, risks,
actions, assumptions/gaps, roadmap, keyboard navigation, print and reduced-motion
support. It has no remote dependencies and uses escaped local labels.

The approved usage/cost slice is connected end to end: versioned telemetry
settings, UTC evidence windows, aggregate-only LA queries with retention/schema
qualification, APIM/App Gateway metrics, cost-only Logic Apps inventory/metrics,
and reconciled daily costs feed source-bound offline usage/capacity/cost models,
five COST rules, populated Usage/Cost tables and table-bound Excel charts,
and local HTML summaries. Cost grouping uses two reconciled query stages
because the API permits only two grouping columns; blocked pagination stays
incomplete rather than weakening the ARM token guard.
Configured logs and cost default on; exclusions are saved and checked on resume.
Manifest 1.2/settings 1.1 add closed evidence coverage without upgrading legacy
runs. Unknown denominators stay null, overlapping copies are not added,
currencies stay separate, and complete months close at UTC midnight regardless
of workstation timezone; MTD is excluded from complete-month comparisons.
Body-logging cost signals require APIM-table ingestion, not unrelated App Gateway
access-log volume.
Capacity P95 uses nearest-rank hourly averages; current units/SKU are not
historical sizing or proof of achievable savings.

New collections use settings 1.2 for observed-route exposure: scoped App Gateway
listener/non-edge aggregates and APIM direct-call/header-presence counts remain
restricted. No client IPs or header values are persisted by these queries.
Complete saved route usage distinguishes ExternalInUse from ExternalUnintended;
absent/partial/mixed evidence is not zero. Ambiguous public/private traffic,
indistinguishable public routes and unresolved rewrites stay Unknown, with
confidence/data gaps retained. Listener totals are never proportionally assigned
to individual APIs. Trusted edge IPv4 CIDRs (including an optional local ranges
file) are snapshotted for offline replay; unsupported ranges reject.
Legacy settings 1.0/1.1 resume without silently enabling this capability.
Individual-subscription usage and remaining telemetry/PERF rules stay deferred.

An independent, **maintainer-only collection smoke command** now exercises all
sixteen implemented collector checks in dependency order against a Microsoft-owned test
APIM. It is not an assessment entry point or a customer-run command: it cannot
analyze or report, and its live execution is owned by authorized maintainers
outside Copilot CLI. The maintainer reports the prior six checks completed on a
test APIM; the later configuration and telemetry checks have
synthetic acceptance but still need maintainer-only live validation. No agent
used live Azure resources or inspected restricted output.
The same smoke script now validates the newly saved manifest, completed
collector file inventories, JSON collection shapes and item counts, and policy
index/XML hashes before reporting a completed smoke. Validation failures return
a fixed safe code and do not print restricted content. This is structural
collection validation, not a full analysis, privacy audit, or report check.
The same command now includes configured Log Analytics, metrics, cost, and
cost-only Logic Apps collection with fresh observed-route settings. It validates
telemetry Partial/Skipped evidence too and prints bounded coverage statuses for
`appgwByListener`, `appgwNonEdge`, `directNonAppGw`, and `headersLogged`.
Unconfigured optional collectors/queries stay explicitly Skipped, not tested;
configured failures or incomplete required evidence retain Partial status.
These statuses do not certify full live query acceptance or assessment results.
The smoke command also runs the local saved-run secret scanner before its final
PASS. A separate maintainer-only script can scan an existing run, including
compressed XML parts in its Excel reports. Both print safe statuses and, on
candidates, a final table with row numbers, artifact aliases, match kinds,
and available line/column positions;
secret candidates and incomplete scans fail without printing values or paths.
The commands write a restricted `secret-scan-locations.json` inside the run and
point to it when candidates are found. It lists relative files, match categories,
and source locations, never matched values or excerpts.
JWT policy header selectors such as `header-name="Authorization"` and scheme-only
authorization metadata are not credentials. Descriptive "Bearer token" wording
also remains clean; actual embedded token values and literal signing/decryption
keys are still checked, including policies serialized inside JSON or logs.

Ten required model contracts and optional drift/portal/OpenAPI-quality/product-governance/
diagnostic-coverage and usage/capacity/cost contracts share a fail-closed schema gate.
Writers validate every pending serialized snapshot before writing any file, and
the private saved-run loader requires all ten baseline files and validates any
present portal/quality/governance model and any requested drift model, including restricted
source/settings bindings, before returning models
for downstream analysis. Ordinary single-run analysis does not require Git or
comparison runs. Future model contracts remain deferred with their
builders. The Analyze command builds the implemented models from validated saved
collector evidence; this is not the model-data airlock.

Closed version 1.0 contracts now define model-safe packages, specialist
observations, and executive summaries. A private in-memory schema/reference
gate rejects unknown fields, unapproved text or exact usage/cost values,
duplicate members/IDs, and unsupported citations; executive summaries must
retain the package's assumptions and data gaps. These are synthetic-tested
contracts. Private offline helpers now construct version 1.1 packages from all
ten validated saved models and replay-checked findings, independently validate
them, and publish immutable package/attestation versions by atomic directory
rename. Construction uses new allowlisted objects and deterministic aliases;
identifier-only alias maps stay restricted. Six configured usage bands,
approved deterministic condition codes, and explicit unknowns replace raw
evidence, exact metrics, and free text. Evaluated drift findings select the closed
1.2 package with only two additional approved condition codes; Git paths, commits,
policy hashes/XML, and environment identities never enter it. Versions 1.0 and
1.1 remain supported unchanged. Evaluated POR findings select closed package 1.3
with five approved condition codes using existing Service/Api aliases and
portal-evidence-qualified confidence; provider, domain, product/group identifiers,
intent and exact coverage stay restricted. Package 1.2 remains supported unchanged.
Evaluated GOV-003/GOV-009 select closed package 1.4 with only
`ProductGovernanceWeak`/`ApiDiagnosticsWeak`, bound to existing Product/Api aliases.
Unreferenced collected products receive unique aliases too. No organization
inventory, user counts, product intent or exact sampling is exported; older
package versions remain unchanged. Evaluated COST findings select package 1.5:
five approved Service-bound condition codes and relative cost trends only;
exact costs/calls/capacity, resource/workspace/plan identifiers and billing
history remain restricted. Independent validation and claim entailment admit
this version without expanding broker operations.
Promotion requires explicit complete host-supplied visible roots, isolated
restricted/analysis/private-staging roots, and an exclusively controlled local
filesystem. Unknown isolation, linked paths, tampering, and failed validation
reject publication. A local stdio MCP broker now invokes the airlock through seven
closed operations; operator-owned config aliases and roots never come from tool
arguments. Per-tool worker processes drain every OS stdout/stderr stream and
expose only independently checked results. Package/attestation bytes are checked
on every read. Separate restricted proposal files bind to the package digest and
have persistent closed digest-binding sidecars, and are checked again for
citation entailment, recommendation/category compatibility,
confidence, executive posture, and complete assumption/data-gap carry-forward.
Four broker-only agent profiles and four operator skills are included in source.
Read-only specialist/synthesizer profiles cannot submit proposals or access files.
The orchestrator submits approved-code proposals and requests rendering with
opaque output IDs, or uses explicit deterministic non-AI fallback.
Synthetic stdio, privacy, semantic, rendering and profile tests are available;
actual clean Copilot-session/tool isolation, approved roots/ACLs, organization
approval, visual readout and live acceptance remain owner gates. Declarations
and static tool-list tests are not proof of host enforcement.
Neither a contract pass nor a private candidate authorizes model access to run
data. The coding-agent checks use synthetic data only.

| Available | Planned |
|---|---|
| Module manifest, deterministic source loader, and five bounded public commands | Remaining collectors and model capabilities |
| Strict private configuration validation and closed allowlisted saved-run analysis settings | Actual host isolation and approval acceptance |
| Structured JSON-lines logging; validated resume and prerequisite-aware collector isolation | Full live workflow acceptance |
| Guarded ARM transport with paging/retry; offline tracking, saved-run comparison, and cross-environment policy/API-presence drift | Full API-definition comparison |
| Versioned run manifest lifecycle, exact scoring snapshot, APIM configuration collectors, scoped LA/App Gateway route aggregates, resource metrics, daily costs, cost-only Logic Apps and optional committed Git policy hashes | Maintainer live query acceptance |
| Maintainer-only cumulative collection smoke script with local output validation (sixteen registered checks) and bounded observed-query coverage | Full live assessment acceptance |
| Owner-run lab bootstrap/staged RBAC, offline-tested Bicep foundation/private VM worker, synthetic TLS backend/bounded private jobs, owner-only ACME tooling, and five business API contracts (16 operations) | Gateway, API imports/policies, actual certificate consumer binding, protected delivery/scheduling/lifecycle and owner live acceptance |
| Local saved-run secret-scan script for supported text and Excel artifacts, also required by smoke | Host-enforced model-safe admission acceptance |
| Effective policy merge/flags, ten required models including source-bound observed exposure, and optional drift/portal/quality/governance/usage/capacity/cost with schema-gated loading | Remaining telemetry/PERF rules |
| Optional pinned offline Spectral, trusted APIM style rules and source/settings-bound quality scores with description fallback | Full API-definition drift and maintainer live export validation |
| Offline raw-to-model Analyze, seven NET, fifteen SEC, ten GOV, six REL, five POR and five COST checks; configurable scoring and closed findings/actions | Remaining telemetry-dependent SEC/GOV/NET and PERF entries |
| Public validated-run Excel/HTML rendering, Usage/Cost/Drift/Comparison views, tracking, table-bound charts and approved-code synthesis | Owner visual/live acceptance |
| Compact raw-to-Excel/HTML and actual stdio broker integration plus a deterministic 60-API synthetic model generator and offline airlock canary/mutation integration | Full scaled raw collection fixture and live acceptance |
| Closed model-safe contracts, allowlist package construction, independent privacy validation, hash attestation, immutable promotion, and digest-bound semantic proposal validation | Actual isolated Copilot/host admission acceptance |
| Windows/Linux lint and test CI | Owner visual/live go-no-go approval |
| Copilot development instructions plus narrowly allowlisted assessment profiles and operator skills | Clean isolated CLI acceptance of those declarations |
| Guarded SemVer tag/release workflow | v1.0 acceptance against the technical specification |

The authoritative scope and progress are in
[the specification](docs/APIM-Assessment-Spec.md),
[the project plan](docs/APIM-Assessment-Project-Plan.md), and
[the task register](docs/APIM-Assessment-Task-Register.md).

## Deterministic operator commands

**Approved offline lab pivot:** `.azure\deployment-plan.md` describes an internal
Developer APIM plus path-routed Application Gateway target, Key Vault/ACME,
managed identities, protected GitHub OIDC delivery, Log Analytics and
workspace-based Application Insights. Five self-contained OpenAPI 3.0.3 contracts
are available in `infra\live-validation-lab\scenarios`: Supply Chain,
E-commerce, PLM, Manufacturing and Service Management. Their sixteen operations
use small representative schemas and synthetic examples; the inventory maps
private-only, initially dormant, product-context and bounded-failure scenarios.
They are contracts, not deployed APIs or implemented authentication policies.
`infra\live-validation-lab\foundation.bicep` supplies the offline-tested foundation:
a new VNet/four sized NSG-protected subnets, explicit worker NAT egress, internal
classic Developer APIM, gateway identity, protected Key Vault/private DNS,
challenge zone, Log Analytics and workspace-based Entra-only App Insights.
Pinned AVMs are used where suitable; the direct workspace avoids an AVM's
unconditional shared-key retrieval. Independent gateway logs and a managed-identity
App Insights logger are configured without body/header capture. Runtime role
grants remain in the separate owner stage, so declared logging is not proof of
ingestion. ACME challenge delegation to Azure DNS remains the selected design.
`scripts\lab\Invoke-LabBootstrap.ps1` now provides owner-only Identity/Runtime
preview and digest-approved apply stages. It requires separately owned, tagged
lab/identity resource groups, private closed-schema configuration and a matching
interactive Azure context. It verifies protected GitHub `lab` environment
controls before enabling exact environment-scoped federation; routine deployment
receives Contributor only on the lab group. Runtime grants are fixed and
resource-scoped, and missing future foundation/worker resources yield NotReady.
See the [owner bootstrap runbook](docs/RUNBOOK.md#owner-only-lab-bootstrap)
for prerequisites, private approval commands and partial-failure handling.
The [foundation runbook](docs/RUNBOOK.md#offline-lab-foundation)
documents synthetic build/topology checks and a status-only private parameter
writer. It rejects invalid/overlapping/undersized IPv4 layouts and empty or
unrestricted internet lists before creating a new external parameter file.
Private network collisions, permissions, cost and actual readiness are owner gates.
`infra\live-validation-lab\worker.bicep` adds only a small private Linux VM/NIC,
system identity and static worker-subnet address, without public IP or inbound
SSH. Its separate, locked .NET application serves the sixteen synthetic business
operations over validated TLS, validates tenant/v2 audience/application role/
caller identity, and denies unmatched paths without forwarding. Private serialized
jobs accept fixed traffic profiles and short-lived Service Management faults;
they never accept arbitrary URLs/scripts, emit response bodies or deliberately
exercise Manufacturing initially. The [private worker runbook](docs/RUNBOOK.md#offline-private-lab-worker)
covers offline checks, closed parameters and Linux publishing. The guest does not
download/start an unconfigured service; private binary/config/certificate delivery
and protected invocation remain T-708. TLS trust, directory applications/roles,
APIM backend binding, actual public ACME issuance and live readiness remain separate owner gates.
`scripts\lab\Invoke-LabAcme.ps1` provides owner-only certificate health checks,
private digest-bound previews and explicit staging/production apply operations.
Its pinned client uses only three challenge aliases in the dedicated Azure DNS
zone, without broader DNS permissions or a Cloudflare token. Closed configuration,
ACME account/order state, challenge recovery journal and certificate material
must remain on protected owner storage outside every declared model-visible root.
The parent discards all child output and exposes only fixed status codes.
Production requires recent successful staging, public-query/terms/CT approval,
exact three-SAN/key/chain validation and metadata readback after Key Vault import.
Renewal is due within thirty days; seven-day expiry is critical; explicit rotation
is separately previewed. The private versionless reference remains
`PendingConsumerValidation`, not proof of gateway/APIM/backend refresh or trust.
See the [owner ACME runbook](docs/RUNBOOK.md#owner-only-lab-acme-certificates).
Under D-72, the owner approved the offline bootstrap prerequisite: its eight
fixed Runtime assignments include worker Reader on exactly its own VM and the
dedicated Key Vault, preserving all six existing grants and ownership checks.
Existing six-grant setups require a fresh owner-reviewed Runtime preview/apply;
old approvals do not authorize the added assignments. No grants were applied,
and missing metadata permissions still fail closed before DNS or issuance.
Protected delivery/scheduling and actual consumer binding remain T-706-T-708.
This source-checkout tooling is separate from the read-only assessment module
and release package. Mocked checks are not live authorization: no bootstrap,
deployment, DNS/certificate change or live inspection was performed.

Run collection only in an authorized ordinary PowerShell terminal with an
existing matching Azure context, never through Copilot or CI. Analyze and Report
work offline, but saved runs and customer reports are restricted and must not
be read by a coding agent.

The optional model-safe workflow is available only through
`scripts\Start-ApimBroker.ps1` in a separately approved, isolated operator host.
It must never be attached to this broad development session or given access to
restricted data through generic tools. See [the runbook](docs/RUNBOOK.md) for
startup/schema, exact tool allowlists, proposal handoff, and remaining owner gates.
Broker run/output IDs are session-scoped. Reports remain restricted; only opaque
artifact IDs reach a model, and operators resolve them locally.

```powershell
.\Invoke-ApimAssessment.ps1 -Config <private-config.psd1> -Environment Prod
.\Invoke-ApimCollect.ps1 -Config <private-config.psd1> -Environment Prod
.\Invoke-ApimCollect.ps1 -Config <private-config.psd1> -Environment Prod -Resume <run-folder>
.\Invoke-ApimAnalyze.ps1 -RunFolder <run-folder>
.\Invoke-ApimAnalyze.ps1 -RunFolder <prod-run-folder> -CompareRuns <dev-run-folder>,<test-run-folder>
.\Invoke-ApimReport.ps1 -RunFolder <run-folder>
.\Invoke-ApimReport.ps1 -RunFolder <run-folder> -PreviousReport <previous-workbook.xlsx>
.\Compare-ApimRun.ps1 -Baseline <baseline-run-folder> -Current <current-run-folder>
```

The public workflow runs sixteen implemented collectors and the installed rule
catalog, using `Cloudflare/AssumedReachable` edge settings. Collection requires
Az.Accounts and Az.ResourceGraph, plus Az.OperationalInsights for configured LA
queries; Excel requires pinned ImportExcel 7.8.10.
`-Stage Collect` limits Assessment to collection. `-ThrottleLimit` controls
implemented child-collection concurrency. Configured Log Analytics aggregates
and cost collection default on. `-SkipLogs` excludes LA queries, including
ingestion, but not diagnostic configuration or metrics; `-SkipCost` excludes
daily costs, ingestion and Logic Apps evidence. Explicit `:$false` includes
the configured evidence. Custom/filtered rules remain unavailable.
Configured `GitRepoPath` enables a local committed policy snapshot unless
`-SkipGit` is set. No repository means Git is explicitly Skipped, while
`-SkipGit:$false` without configuration fails before authentication.
Git reads a pinned HEAD, not dirty/untracked files; it never clones, fetches,
checks out, executes source scripts, or modifies the source repository.
`-SkipLogs` does not skip the existing diagnostic-configuration collector.
HTML is included in Report. Assisted access requires the separately admitted
broker and owner-approved isolated host; it is never enabled by these commands.

Resume requires matching configuration, run identity, tool version, and saved
settings. It validates collector files/counts and indexed policy hashes before
reuse; damaged or failed checks and their dependents rerun. Recollection clears
owned stale files and invalidates Analyze/Report/package stage state. Analysis
never reads stale files from failed collectors. Portal analysis can retain validated,
manifest-listed files from Partial Identity/Portal collection; missing facts remain
qualified, never false/safe defaults. Missing required model evidence
produces Info/NotEvaluated findings where possible and blocks downstream reports.
Reports also reject findings that disagree with complete deterministic replay.
Older ten-model saved runs remain usable: absent portal evidence yields
Info/NotEvaluated portal findings after ordinary offline Analyze replay, not a
recollection requirement. Present malformed portal models still fail closed.
Optional `Portal.ProductVisibility` supplies exact product IDs, Boolean `IsPublic`,
and `IntendedGroupIds`; it is validated and snapshotted for offline replay.
Missing/unresolved intent cannot pass POR-003. See the runbook for the configuration.
Analyze's optional `-CompareRuns` validates explicitly selected distinct
environments in the same customer/tenant scope and saves closed restricted
snapshots, not external run paths. Later Analyze/Report replay works without
those source folders. Policy hashes compare protected normalized XML, not secret
literal values or full API definitions. Incomplete evidence and unmapped Git
scope coverage remain Unknown; no comparison source produces explicit
Info/NotEvaluated drift findings rather than a match. The Environment Drift
sheet includes comparison rows and coverage qualifications.
`-PreviousReport` copies only operator tracking from a scope-matched toolkit
workbook into new report rows, never into `findings.json`. It is supported by
Report and full Assessment, not collection-only Assessment. Imported formulas,
duplicate keys, invalid tracking fields, unsafe paths, and incompatible scope
reject before workbook publication.

`Compare-ApimRun` operates offline on distinct saved runs for the same APIM and
environment. It saves restricted `diff.json` and renders a new Excel/HTML pair,
with Excel comparison, pillar, KPI, and data-gap views. Historical severity is
preserved. Changed settings, historical replay disagreement, and incomplete
reassessment qualify disappearing findings as NotReassessed, not remediation.
Resolved means absent from comparable evaluated snapshots, not independently
verified remediation. Unavailable usage/cost KPIs and deltas remain null with
explicit reasons. Unmatched tracking requires a matching bound comparison to
appear as resolved; older workbooks without a snapshot binding remain usable
for matching tracking but their unmatched rows stay Not Reassessed.
Stale/tampered comparison artifacts reject reporting; rerun Compare to refresh.
Tracking, exact comparison data, and report paths never enter model-safe
packages or new broker arguments. HTML retains its existing executive content.
CLI output is status-only, with matching process exit codes: 0 success, 1
config/capability error, 2 authentication error, 3 collector failures, and 4
analysis/report/runtime-state failure. See the runbook for operator setup and
the remaining owner-only acceptance gates.

## Development quick start

Use **PowerShell 7.4+** (`pwsh`), not Windows PowerShell 5.1, and Git.
Development commands require a Git checkout, not the module-only release ZIP.
Run these commands from the repository root:

```powershell
git switch -c feature/my-task
.\scripts\Test-DevelopmentBranch.ps1
.\scripts\Install-DevDependencies.ps1
Import-Module .\ApimAssessment.psd1 -Force
.\scripts\Invoke-Checks.ps1
```

The dependency installer installs pinned ImportExcel, Pester 5.x, and
PSScriptAnalyzer versions from PowerShell Gallery into the current user's module
directory; administrator rights are not needed. It also restores pinned
Kusto.Language 12.4.1 from NuGet into ignored `.tools/kusto` for real offline
KQL syntax checks, including an invalid-query control. It installs SHA-256-pinned
Bicep 0.48.1 into ignored `.tools\bicep` and restores exact public AVM versions
from MCR without Azure authentication. Build/lint and offline synthetic snapshots
run in the existing Pester gate on Windows/Linux; snapshot evaluation makes no
Azure requests. For the separate lab worker, it reuses an installed exact .NET SDK
10.0.402 or installs its SHA-512-pinned archive under ignored `.tools\dotnet`;
the worker's `global.json` disallows SDK roll-forward. JWT bearer/ASP.NET Core
10.0.13 and Linux runtime dependencies restore in locked mode from Microsoft's
public `dotnet-public` mirror. Synthetic runtime acceptance uses generated test
certificates/signing keys, real loopback HTTPS and fake identity/network clients;
no Azure credentials or private certificate inputs are required.
Network access is needed for dependency/module installation,
not live infrastructure inspection. No parser or compiler is downloaded
by collection or analysis. ImportExcel is used to generate
and structurally validate the workbook template without desktop Excel.
Validation is offline and does not authenticate to Azure. Results are written to
the ignored `artifacts` directory.

In Copilot CLI, `!` runs a shell command. The following commands run **only
synthetic and mocked offline checks** and automatically cover new Pester tests
as capabilities are implemented:

```text
! pwsh -NoProfile -File .\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\SmokeRunner.Tests.ps1
! pwsh -NoProfile -File .\scripts\Invoke-Checks.ps1
```

Do **not** run an Azure login, the live smoke command, or any command that reads
restricted output using `!` or an assessment agent. The live command and
maintainer-only setup are in [the runbook](docs/RUNBOOK.md).
For the standard private config at
`$HOME\apim-smoke-private\smoke.psd1`, the authorized maintainer can run
`.\scripts\Invoke-ApimSmoke.ps1 -Environment Test -MicrosoftOwnedTestEnvironment`
in a separate ordinary PowerShell terminal. The environment name must match
the private config; `-Config` overrides the default path when needed.
The collection smoke streams numbered preflight/check progress and prints its
final PASS/FAIL/PARTIAL result with the exit code automatically, including
preflight failures; no second shell command is needed. Interactive terminals
show a compact emoji scorecard that updates its
active row in place without changing the caller's console encoding; redirected
output or `NO_COLOR` uses plain ASCII. An emoji-capable terminal/font is
required for glyph rendering. Errors show fixed troubleshooting hints, not raw
Azure or policy exception messages. Rejected policy XML gets a bounded
`POLICY_XML_REJECTED` code. `SMOKE_OUTPUT_VALID` means the saved collector
output passed structural validation; `SMOKE_OUTPUT_INVALID` and exit 4 mean
the saved run needs local inspection.
`SECRET_SCAN_PASS` means no supported secret pattern was found.
`SECRET_SCAN_FAIL` or `SECRET_SCAN_ERROR` prevents smoke success and returns
exit 4. The separate `scripts/Test-ApimRunSecrets.ps1 -RunFolder <external-run>`
command prints its own PASS/FAIL/ERROR and exit code (0/1/2) automatically.
On a candidate, the error tells you to open `secret-scan-locations.json` locally
in that run folder. Text/log locations include line numbers; JSON has property
pointers, XML has positional paths, and Excel entries include their workbook
part. A candidate is not a confirmed credential; review that location locally.
The table appears before the final FAIL/exit-code line. Its row numbers match
the local report's location order, and its artifact aliases match `artifactId`
in report schema 1.1. Actual filenames, JSON/XML paths, and workbook parts stay
in that restricted report rather than the console.
Run it only in an ordinary local terminal, never through Copilot, for restricted
output. It does not redact files, certify privacy, or detect every arbitrary
unlabeled/encoded secret; the [runbook](docs/RUNBOOK.md) defines its limits.
Configuration preflight now reports only a bounded category:
`CONFIG_NOT_FOUND`, `CONFIG_INVALID`, `LOCATION_INVALID`, or
`ENVIRONMENT_NOT_FOUND`. These identify which private setting to check without
printing any config content or paths.

Develop only on `feature/<name>`, `chore/<name>`, or `bugfix/<name>` branches.
Open a pull request to `main`; CI rejects other source-branch prefixes.
For host-side enforcement, a maintainer must protect `main` and require the
`Branch policy`, `Validate (ubuntu-latest)`, and `Validate (windows-latest)` checks.
This repository setup does not change GitHub repository settings.

## Intended runtime and permissions

Collection uses `Az.Accounts` and `Az.ResourceGraph`, with
`Az.OperationalInsights` for configured LA queries. Metrics use guarded ARM GETs,
not an additional Az.Monitor dependency. Excel rendering uses pinned ImportExcel.
Optional OpenAPI linting uses Node 22.x or 24+ on PATH and toolkit-local pinned
Spectral 6.17.0 in `.tools\spectral`, installed explicitly by
`scripts\Install-OptionalTools.ps1`. Global/PATH Spectral commands and environment
overrides are not discovered. These optional tools are not needed to
import or validate the current core module. The implemented collectors call the
guarded ARM transport; API/product/policy child requests use bounded parallel
runspaces with a configurable `ThrottleLimit` (default 6). Policy 404 responses
are indexed as absent, while detected hard-coded secret candidates are recorded
by structural location and redacted before XML is persisted. Automated tests
never invoke live collectors; all Azure responses are mocked.
The guarded transport omits `-Payload` entirely for bodyless GET requests;
an explicitly empty payload fails before the Az cmdlet is called.
Policy collection requests XML-encoded policy content, parses it strictly,
redacts secret candidates before storage, and remains Partial if any policy
cannot be safely parsed. Previously sanitized policies may already be stored;
an incomplete run has no complete policy index.

OpenAPI collection uses guarded ARM export and a narrowly validated HTTPS Azure
Blob link fallback without ARM credential forwarding or redirects. Signed links
are transient and never persisted. Each document is capped at 5 MiB/depth 64 and
must pass JSON/shape validation and the in-memory secret scanner before writing.
Successful files remain usable
under Partial collection; stale unlisted files are ignored.
Analyze automatically uses a supported installed Spectral with the shipped local
ruleset, never `npx`, runtime installation, or remote/file-reference resolution.
Same-document references are supported. Defaults deduct 10 points per error and
2 per warning; optional closed `OpenApiQuality` configuration snapshots integer
`ErrorPenalty`/`WarningPenalty` values from 0 through 100. Missing/failed tools or
unsupported exports/references retain explicit statuses and description fallback.
Saved quality is bound to source/ruleset digests, tool version and scoring
settings; Report validates and replays it without executing Spectral.
See the [runbook](docs/RUNBOOK.md) for explicit optional-tool setup.

Diagnostics collection reads service loggers, service diagnostics, and bounded
per-API diagnostics through guarded GET requests. It persists only allowlisted
logger targets and diagnostic configuration: header names are sorted, body
capture is reduced to nullable byte counts, and logger credentials,
descriptions, samples, data-masking configuration, header values, and unknown
fields are dropped. Missing settings remain `null`; known empty header lists
remain arrays. Sanitized root files may remain when API child collection fails,
with the collector recorded as Partial.

Subscription collection uses one guarded list request and persists only an
explicit metadata allowlist. It never calls `listSecrets`, drops key fields and
unknown response fields, derives only a non-identifying `ownerType`, and does not
persist `ownerId` or user identifiers.
Missing optional display name, tracing setting, or creation date remains `null`
with model `missingInputs`; unavailable tracing never becomes a false control.
The subscription model also recognizes documented relative API/product scopes.

Network collection reads configured Application Gateways and linked WAF policies
through the guarded GET transport, then runs fixed `Search-AzGraph` queries for
the APIM subnet, NSGs, public IPs, private endpoints, private DNS zones, route
tables, and other APIM-targeting front doors. The collector stages all responses
before writing restricted raw files. It never invokes an Azure write operation,
and automated tests mock both ARM and Resource Graph. Front-door lookups use
three independent, single-resource-type Resource Graph queries instead of
unsupported multi-statement `let` queries.

The private model helpers can merge saved, redacted policy XML completely
offline. They produce one effective policy per product path, expand fragments
with depth and cycle guards, retain unresolved markers, record missing
`<base/>` scope/section metadata, preserve `data-scope` attribution, and compute
normalized SHA-256 hashes. Policy flags detect caller/backend authentication,
throttling, restrictions, unsafe CORS, backend overrides, hard-coded-secret
markers, mock/trace behavior, unconditional responses, and missing inheritance.
Unresolved fragments produce a Partial evaluation instead of silent negative
results. The API/operation builders preserve unavailable collector-derived
values as `null` with sorted `missingInputs` and `modelStatus=Partial`; the
policy matrix emits `NA` when incomplete evidence prevents a definitive result
while retaining detected failures. All three arrays are validated against closed
schemas before any model file is written. Public analyze orchestration remains
planned.

The named-value model retains only secret classification, Key Vault status, and
derived structural secret-pattern locations; it never retains a named-value
value. The backend model retains only URL scheme, nullable HTTPS certificate
validation facts, credential-presence and resilience flags; HTTP backends have
null TLS-validation fields because those controls are not applicable. The
certificate model retains only normalized expiry, Key Vault-backed status, and
completeness metadata. All three are sorted, closed-schema arrays.

The shared gate validates only explicitly registered model names and persists
the exact JSON snapshots that passed validation. Saved-run loading validates the
API, operation, policy-matrix, subscription, named-value, backend, certificate,
network, and exposure files as a complete set without returning partial output
on failure. Empty model arrays remain arrays; missing files, invalid
shapes/fields, unavailable schemas, and linked paths are rejected. Writes are
atomic per file, not transactional across the set if an I/O failure occurs after
validation.

The private rule engine accepts validated model inputs and a validated manifest,
loads only implemented `rules/*.rules.ps1` catalogs, applies each rule's target
filter/test/evidence callbacks, and emits stable findings sorted by descending
priority, then rule ID and scope. Missing or explicitly failed required model
inputs, or declared unavailable facts in an otherwise valid model, produce
exactly one `Info`/`NotEvaluated` finding per affected rule; malformed available
models or invalid callback output fail closed. A null
usage value stays unknown with a neutral scoring multiplier, never an inferred
zero-use result. `findings.json` has a closed top-level schema and is validated
before any restricted write. The seven private NET checks assess observed App
Gateway WAF/TLS posture, public host-wide forwarding, direct public APIM paths,
and broad APIM-subnet inbound NSG rules plus explicitly operator-attested
edge-origin authentication and auxiliary endpoint need. A known empty gateway
inventory is not a WAF/TLS failure; an unavailable inventory is NotEvaluated.
NET-001 and NET-009 remain NotEvaluated when the required attestation is absent.
The fifteen private SEC checks evaluate only facts represented by current closed
models; known positive evidence is retained when unrelated records are
incomplete, while wholly unknown applicable evidence produces one
Info/NotEvaluated finding. Collected service/API diagnostics now populate
`bodyLogging` and `sensitiveHeadersLogged` using API-over-all-APIs precedence, so
SEC-014 evaluates saved synthetic-equivalent runs while incomplete sections stay
unknown. SEC-008 uses only structural named-value locations, never values.
SEC-009 evaluates one stable rule ID across named-value and certificate scopes,
retains known Key Vault findings when another fact is unavailable, and emits one
NotEvaluated result when required evidence is unavailable without a known
positive.
SEC-010 applies only to HTTPS backends and treats missing validation facts as
NotEvaluated when no explicit disablement is known. SEC-011 evaluates backend
schemes and operation-level policy overrides, suppresses only exact targets in
the optional validated `RuleExceptions` allowlist, and keeps Partial policy
evidence NotEvaluated when no known unapproved target exists. SEC-001/002/019
use the closed service model for explicit legacy TLS settings, minimum
management API version enforcement, normalized managed-identity posture, SKU
capacity, zones, and platform version;
incomplete legacy TLS evidence remains NotEvaluated. Defender/RBAC posture,
backend intent/mapping, and product classification remain deferred.
Public Analyze/Excel Report commands now invoke the private engine and writer.
Model-safe promotion remains private; do not expose findings or models to an agent.

Six of the ten private GOV checks use only complete API catalog and effective-policy
facts for product membership, owner tags, online non-current revisions,
version-set maturity, path-version convention consistency, and missing
`<base/>` inheritance. Known missing-base findings remain evaluated when another
operation is Partial; otherwise incomplete version or policy evidence produces
one Info/NotEvaluated result. GOV-003 uses optional closed product evidence for
missing description/explicitly missing owner or disabled approval on explicitly
external products. GOV-009 uses effective diagnostic configuration/logger
resolution and known fixed sampling below 100 percent on explicitly critical
APIs; absent intent or evidence is Unknown, never zero or an inferred pass.
See the runbook for optional `Governance.Products`/`CriticalApiIds` configuration.
Two more aggregate production Git policy differences and explicit
cross-environment policy/API-presence drift, retaining Unknown coverage and
missing-source qualifications.

The six private REL checks cover production Premium zone redundancy, production
capacity below two units, operator-declared critical backends without a circuit
breaker or pool, APIM-targeted Application Gateway probe alignment, certificate
expiry from both APIM certificate entities and service hostname certificates
within `CertExpiryDays`, and non-stv2 platform versions. The optional
validated `RuleTargets.CriticalBackendIds` array declares exact critical backend
IDs; absent or empty configuration declares no applicable critical backend.
Probe alignment is derived only from routes whose backend pool and host target
APIM, and certificate thresholds use the saved run start time so repeat analysis
is deterministic. Unknown service, probe, or expiry facts produce one
Info/NotEvaluated result rather than a pass.

The private action-plan aggregator accepts only schema-valid findings with valid,
unique finding keys. It groups rows by `ruleId`, counts only evaluated instance
findings as affected, retains a sole NotEvaluated gap as an action with zero
affected resources, selects up to five evaluated scopes by priority and ordinal
scope, combines unique recommendations deterministically, and initializes
tracking defaults for the report-only carry-forward projection. Inconsistent same-rule metadata fails
closed. Action items are validated against `schemas/actions.schema.json` and
sorted by maximum priority then rule ID. This helper performs report shaping
only; the separate workbook writer consumes it through the public Report command.

The checked-in `template/ApimActionPlan.xlsx` is generated by
`scripts/New-ApimActionPlanTemplate.ps1` with pinned ImportExcel. It contains the
fixed Summary and report sheets, eighteen named empty tables, navy title bands,
frozen headers, fixed widths, finding/policy/exposure conditional formatting,
the action-status dropdown, positive-number validation and highlighting for
editable weights, Summary formulas, a pillar/severity chart, and an
assumptions/data-gap banner. The generator uses fixed widths and does not
require Excel or auto-size native dependencies. It contains no customer data
and does not make public report rendering available.

The private `Export-ApimActionPlan` helper loads the closed manifest, all ten
registered model files, and schema-valid findings from one saved run before
creating any output. It derives action rows through the same T-307 aggregator,
copies the trusted template, writes typed values directly into the existing
tables, fills the assumptions banner and network summary, and stores the result
under the run's restricted `report` folder. Unsafe filename components,
malformed inputs, incompatible templates, and tables above 9,997 data rows fail
closed without a partial workbook. Existing filenames are never overwritten;
`-2`, `-3`, and later suffixes are selected. Manifest schema 1.1 retains the
exact validated scoring snapshot used by the run. The writer expands an
explicit manifest allowlist into Run Info, emits the implemented rule catalog
in rule-ID order, and fills editable Severity/Exposure/Usage weights. Finding
Details priority formulas reference those weights, while Action Plan formulas
take the maximum recalculated detail priority for each rule. Editing a weight
therefore changes workbook priorities without mutating `findings.json`; rows
retain their original deterministic order. Usage and Cost are populated for
telemetry runs; Environment Drift is populated when comparison evidence exists.
Unimplemented route/latency columns remain blank, not inferred from monthly counts.
Generated reports can contain customer
and infrastructure identifiers and must never be provided to a model.

The subscription model classifies AllApis/Product/Api scope, extracts a stable
scope target, detects the built-in master subscription, and emits sorted
risk/context flags. Usage-dependent `calls90d` and `lastUsed` remain `null` with
`modelStatus=Partial` and `missingInputs=["usage"]`: aggregate telemetry does not
identify individual subscriptions. Its array is closed-schema validated before persistence.

The closed single-object network model evaluates the effective priority of broad
inbound NSG rules on port 443, identifies positive direct-public paths, and
aggregates App Gateway TLS and WAF posture conservatively. The synthetic Internal
VNet fixture with an App Gateway-subnet allow and deny-all fallback evaluates
`directPublic=false`. Missing reachability evidence produces
`directPublic=null`, `modelStatus=Partial`, and sorted `missingInputs` rather than
a success-shaped false result.

The optional operator experience uses broker-only profiles and skills in an
owner-approved isolated host. Collection, offline analysis, Excel, and HTML
remain runnable without Copilot.

For a pre-acceptance smoke only, `scripts/Invoke-ApimSmoke.ps1` runs the current
service, API catalog, product, subscription, security-asset, diagnostic, policy,
and network collectors with an existing matching `Az.Accounts` context and
`Az.ResourceGraph`. It requires
an explicit Microsoft-owned test-environment acknowledgement. Private config
and restricted output must be outside the repository and all Copilot
trusted/allowed directories. Only registered check/status names and, for failed
checks, a bounded ARM HTTP, transport-category, or local/unknown failure code
appear on the console,
never exception text, paths, or response content. The manifest and raw results
stay in restricted local storage. Check failures are recorded as Failed/Partial
and dependent checks as Skipped. Future implemented capabilities join this fixed
check list after synthetic acceptance
without changing the maintainer's invocation. A passing collection smoke
does **not** imply analysis, reports, full-run acceptance, or customer readiness.

Operators will supply an existing `Connect-AzAccount` context. Intended access is
Reader on the APIM and network resource groups, Log Analytics Reader on the
workspaces, and Cost Management Reader on configured cost scopes. The toolkit
will neither retain authentication tokens nor perform Azure remediation.

The public Collect/Assessment commands validate private configuration derived
from `config/sample.psd1`. Available invocation and exit-code contracts are
documented above and in the runbook; future capabilities in specification
section 14 remain unavailable until their implementation tasks land.

## Data handling

Use **synthetic fixtures only** for development and automated tests. Never commit
customer or engagement names, real-person names, customer configurations,
tenant/subscription/workspace identifiers from real environments, assessment
outputs, credentials, subscription keys, or secret values.
Only `config/sample.psd1` and `config/README.md` are tracked under `config`.
The conventional local `runs` and `model-safe` directories are ignored; public
orchestration creates run folders under the configured roots
through the implemented persistence helpers.

Real runs must remain local in a customer-approved storage location and be
deleted after the readout according to the agreed retention policy. Do not
upload run folders or generated customer workbooks to CI artifacts or releases.
Git ignores are an accident-prevention measure, not permission to store secrets.
For agent-assisted runs, the restricted collection root must be an explicitly
resolved external path outside every Copilot trusted/allowed directory; a
gitignored directory inside the repository is not a security boundary.

Raw responses, normalized models, findings, restricted alias maps, logs, exact
metrics, and customer-facing reports must never enter model context. Model-assisted
review is allowed only from a separately stored `analysis-package.json` that was
built from an explicit allowlist, validated against a closed schema and recursive
prohibited-value scanner, hash-attested, and promoted by a fail-closed local gate.
Copilot agents must not have shell/filesystem access to the restricted collection
zone, Azure credentials, collection output, or arbitrary paths.

## Repository layout

```text
ApimAssessment.psd1 / .psm1  Module metadata and source loader
src/
  Core/                     Config, ARM guard, manifest persistence, logging, retries
  Collect/                  Isolated read-only collectors (service/catalog/subscription/policy)
  Model/                    Policy merge/flags, required/optional models, offline analysis
  Rules/                    Rule engine and priority scoring
  Package/                  Airlock, narrow broker, digest-bound semantic output gates
  Report/                   Paired Excel/HTML export, tracking and saved-run comparison
rules/                      Implemented and planned rule catalogs
rulesets/                   Trusted local optional OpenAPI lint rules
queries/                    Log Analytics and Resource Graph KQL (planned)
schemas/                    Closed versioned run, model, report and broker contracts
template/                   Implemented Excel and self-contained HTML templates
config/                     Tracked sample; ignored local configurations
tests/
  unit/                     Offline Pester tests
  integration/              Synthetic raw-to-reports, airlock and stdio workflow tests
  fixtures/synthetic-reference/  Synthetic reference-topology fixture scaffold
scripts/                    Branch guard, checks, optional-tool setup, broker, packaging
docs/                       Specification, plan, register and operating guides
.github/
  agents/                   Development and broker-only assessment profiles
  skills/                   Task/rule authoring and broker-only operator workflows
  workflows/                CI, Copilot setup, and SemVer release
```

Four root assessment scripts are implemented. Compare/package root-script
facades in the specification remain future capabilities. Release archives
include deterministic runtime/templates, the trusted ruleset, optional-tool
setup and the two broker scripts; operator
agent/skill profiles are installed from the reviewed source checkout, not
automatically installed or configured by a release archive.

## Copilot-assisted development

[Repository instructions](.github/copilot-instructions.md) define the safety
boundary, branch policy, architecture, tests, and documentation requirements.
The `apim-implementer` agent handles bounded implementation tasks; the
`assessment-reviewer` agent provides read-only contract and correctness reviews.
Those profiles review repository changes; they are not the assessment analysts.
Separate broker-only profiles cover architecture/exposure, security, executive
synthesis and orchestration, with only promoted packages and validated proposals.
Operator skills cover orchestration, model-safe analysis, local deliverables and
proposal validation; invoking a skill alone does not remove tools from a broad
development session. See
[contribution guidance](CONTRIBUTING.md) for the exact workflow.

**Keep this README current in the same change as every task that changes
implementation status, commands, prerequisites, configuration, safety behavior,
repository layout, or releases.** If a task leaves it accurate, record that review
in the pull-request checklist. Keep the task register updated each work session.

## Versioning and releases

`ApimAssessment.psd1`'s `ModuleVersion` is the single version source, initially
`0.1.0`. Use three-part SemVer: patch for compatible fixes, minor for compatible
features, and major for breaking supported contracts. During `0.x` development,
minor versions may change experimental contracts; `1.0.0` requires the documented
acceptance gate.

To release, merge a version bump through a `chore/release-<version>` pull request,
then run **SemVer release** from the Actions tab on `main`. The workflow reruns
Windows/Linux checks, rejects existing or regressive versions, creates
`v<ModuleVersion>` at the validated commit, and publishes a ZIP, SHA-256 checksum,
and generated release notes. `0.x` releases are marked as GitHub prereleases.

There is no automatic version bump, direct development commit to `main`, or
release on every merge. See [release instructions](docs/RELEASES.md) for the local
dry run, permissions, and recovery procedure. No tag or remote release is created
by the bootstrap itself.
