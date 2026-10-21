# Operator runbook

## Availability

The toolkit is **not ready for customer assessment runs**. It has an importable
module foundation, strict private configuration validation, structured logging,
a guarded ARM transport, schema-validated run-folder/manifest persistence, and
internal APIM service/API/product catalog collectors with bounded parallel child
requests, an allowlisted subscription collector, plus restricted policy
collection with normalized hashes and collection-time secret-candidate
redaction, allowlisted named-value/backend/certificate and logger/diagnostic
collectors, and an internal network collector for Application Gateway/WAF and
Resource Graph evidence. Private offline helpers now merge effective policies,
normalize/hash them, and extract deterministic policy flags. Private offline
builders create schema-validated API, operation, policy-matrix, subscription,
service, named-value, backend, certificate, network, and evidence-qualified
exposure records from saved synthetic-equivalent inputs. A private rule engine,
seven NET catalog entries, fifteen model-backed
SEC catalog entries, ten model-backed GOV catalog entries, all six REL catalog
entries, all five POR and five COST catalog entries, a closed findings schema, and private closed action-item aggregation
plus a customer-neutral generated Excel action-plan template are available for
offline synthetic testing. A private report writer can populate the current
deterministic workbook sheets from a validated saved run. Five bounded public
commands now connect collection, offline analysis, and paired Excel/HTML
reporting, including validated resume. A synthetic-tested narrow stdio broker,
four broker-only assessment profiles, semantic output validation and four
operator skills are implemented. Remaining collectors/models and the rest of
the telemetry/PERF rule catalogs are not implemented. Offline tracking
carry-forward and same-APIM/environment saved-run comparison are available.
Optional committed Git policy collection, offline cross-environment policy/API
presence comparison, and Environment Drift workbook rows are also available.
Actual clean Copilot-session/tool isolation, approved roots/ACLs, organization
approval and visual/live G3 acceptance remain owner gates.

Usage/cost collection and offline reports are connected with synthetic-tested LA
aggregates, APIM/App Gateway metrics, daily costs, and cost-only Logic Apps
inventory/metrics. New telemetry runs use manifest 1.2/settings 1.2, adding scoped
aggregate-only route evidence and observed exposure; saved settings 1.0/1.1
keep their original contracts. Optional usage/capacity/cost and observed exposure rebuild from
validated saved sources/settings on every load. Development KQL tests require the pinned Kusto.Language assembly
restored by `.\scripts\Install-DevDependencies.ps1`; this is not an Azure runtime
dependency and does not authorize live access.

Ten required model contracts and optional drift/portal/OpenAPI-quality/product-governance/
diagnostic-coverage contracts share a private
schema gate for pending writes and saved-run loading. Requested drift additionally
requires unchanged restricted inputs, current evidence, and model bindings.
Private findings are validated against
`schemas/findings.schema.json` before restricted persistence. This does not add
authorization for model/findings access to an agent.

Closed schema version 1.0 contracts and a private in-memory reference gate are
also available for synthetic tests. They validate opaque aliases, approved
fact/narrative codes, typed usage buckets/cost trends, unique IDs, citations,
and executive assumption/data-gap carry-forward. Private package construction,
independent privacy validation, local attestation, and immutable atomic promotion
are also implemented and synthetic-tested. Packages use version 1.1, or 1.2 for
evaluated drift findings, 1.3 for evaluated POR findings, or 1.4 for evaluated
GOV-003/GOV-009 findings, or 1.5 for evaluated COST findings, with only approved
additional condition codes, never Git/source/environment or portal/provider/domain/
product/group values or exact coverage. Existing Service/Product/Api aliases are reused.
Package 1.4 exports only `ProductGovernanceWeak`/`ApiDiagnosticsWeak`, never
organization inventories, user counts, intent or exact sampling. Earlier
package schemas remain unchanged. Version 1.5 adds only five Service-bound COST
conditions; exact telemetry, billing, workspace/resource/plan identities and
current sizing remain restricted. Broker permissions are unchanged.
The broker invokes these private helpers;
standalone root package/promotion facades remain planned.
No customer data is approved for model access by a schema/reference pass.

Do not run the planned commands in specification section 14 until their tasks
are implemented, tested, and marked available in the root README.

## Implemented deterministic workflow

Collection is authorized-maintainer-only in an ordinary local terminal, with
existing Reader access and matching Azure context. Never launch it through a
coding agent, `!`, or CI. Store private configuration and restricted runs in
approved external locations. I-05/I-06 and live G3 remain owner gates.

Prerequisites: PowerShell 7.4+, Az.Accounts and Az.ResourceGraph for collection,
plus Az.OperationalInsights for configured Log Analytics queries;
ImportExcel 7.8.10 for Excel rendering. Use the dependency installer for the
pinned local Excel dependency, not Azure authentication. The runtime does not
log in, switch subscriptions, retrieve credentials, or install Azure modules.

```powershell
# In an authorized ordinary PowerShell terminal; not Copilot CLI.
.\Invoke-ApimAssessment.ps1 -Config <private-config.psd1> -Environment Prod
.\Invoke-ApimAssessment.ps1 -Config <private-config.psd1> -Environment Prod -Stage Collect
.\Invoke-ApimCollect.ps1 -Config <private-config.psd1> -Environment Prod -ThrottleLimit 4
.\Invoke-ApimCollect.ps1 -Config <private-config.psd1> -Environment Prod -Resume <run-folder>
.\Invoke-ApimCollect.ps1 -Config <private-config.psd1> -Environment Prod -SkipLogs -SkipCost

# Offline stages still operate on restricted local data.
.\Invoke-ApimAnalyze.ps1 -RunFolder <run-folder>
.\Invoke-ApimReport.ps1 -RunFolder <run-folder>
```

All scripts print only the stage outcome and matching process exit code, not
run paths, model data, findings, or exception text. Locate the run under the
configured restricted output root locally. The module functions return bounded
status objects, with Collect/Assessment carrying the run ID. Reports remain
under that run's `report` directory and never overwrite previous workbooks.

The implemented slice collects Service, Apis, Products, Subscriptions,
SecurityAssets, Diagnostics, Identity, Portal, OpenApi, Organization, Policies, Network,
LogAnalytics, Metrics, Cost and LogicApps. It accepts only
Cloudflare/AssumedReachable edge settings and six increasing usage thresholds.
Configured logs and cost default on. `-SkipLogs` excludes all LA queries including
ingestion; it does not skip diagnostic settings or resource metrics. `-SkipCost`
excludes daily costs, ingestion and cost-only Logic Apps evidence. Explicit
`:$false` enables the configured evidence. Exclusions must match when resuming.
Git is optional as described below.
Analyze's `-RulesPath`/`-OnlyRules` remain unavailable; neither silently
falls back to a speculative capability.

Resume verifies exact configuration/settings compatibility and run identity,
then validates completed collector output before reuse. Failed, partial,
missing, or damaged checks rerun; changed prerequisites invalidate dependent
checks and Analyze/Report/package stage state. Only collector-owned stale files
are removed. A changed configuration requires a new run. Do not edit the
restricted settings snapshot to change thresholds; it must match collection.
Analyze uses only saved evidence and the restricted closed settings snapshot.
Unavailable required models generate Info/NotEvaluated findings where possible,
leave analysis Failed, and withhold reporting. Missing diagnostics remain unknown
facts even if the other models can be built. Reporting replays every deterministic
finding, including evidence, before writing a workbook. Optional telemetry
exclusions and unconfigured optional targets are Skipped without failing collection;
metric gaps and configured-target failures stay Partial. Legacy resumes do not
silently add telemetry or accept new telemetry exclusions.

Usage contains monthly APIM counts and labeled partial boundary months, not
observed-route attribution. Cost retains currencies separately and leaves
same-period normalized costs null when calls or cost coverage are unknown.
The combined normalization rows repeat resource costs and must not be added
to them; stacked charts use resource rows only. Calendar months close at UTC
midnight, independent of workstation timezone; MTD is not a complete month.
APIM body logging can qualify an ingestion-cost signal only with billable
APIM-table ingestion, not stable App Gateway access-log volume.
Logic Apps Standard costs belong to the linked shared plan, not each workflow.
No workflow definitions or historical SKU changes are collected. Premium capacity
P95 is nearest-rank over hourly averages; current units, zones and SKU do not prove
historical capacity, safe downsizing or savings. Review HA requirements separately.

### Observed routes and exposure

New ordinary Collect/Assessment runs automatically include the four scoped route
queries in LogAnalytics. No new public switch or Azure permission exception is
added. Configure gateway subnet CIDRs for route classification; trusted edge
IPv4 CIDRs enable non-edge aggregates. `Edge.TrustedEdgeRangesFile` can provide
one CIDR per line with blank lines and `#` comments. Ranges are validated and
snapshotted; offline Analyze/Report do not reopen the file. A changed range file
requires a new run rather than incompatible resume.

The restricted files are `logs/appgwByListener.json`, `logs/appgwNonEdge.json`,
`logs/directNonAppGw.json` and `logs/headersLogged.json`. Gateway access logs
have independent schema detection and AppGateway evidence windows; APIM direct/
header queries use APIM usage windows. Records retain per-workspace coverage,
failures and retention, never individual client IPs or header values. Empty
configured ranges explicitly skip the corresponding query. `-SkipLogs` excludes
all four; `-SkipCost` leaves them enabled.

Complete route usage can distinguish ExternalInUse and ExternalUnintended.
Missing/Partial/mixed evidence cannot prove zero. Identical overlapping workspace
copies count once; conflicting copies stay Unknown. Public/private listener
ambiguity and indistinguishable public routes withhold public counts instead of
estimating a per-API split. Same-window listener evidence can exclude active
private paths, but retains Medium confidence. Unresolved rewrites stay Unknown.
API Inventory and Exposure Map show local counts/labels and evidence gaps.
Saved-model loading rechecks these against restricted sources/settings before
reports or model-safe construction. Packages retain only existing allowlisted
labels and bands, not raw route evidence. NET-003/NET-005/SEC-016 and remaining
T-409 rules are not enabled by this collection capability.

| Exit | Meaning and local action |
|---|---|
| 0 | Implemented requested stages completed; this is not owner/live approval. |
| 1 | Invalid config or unavailable requested capability; check settings/options locally. |
| 2 | Az modules or matching existing context unavailable; maintainers resolve outside Copilot. |
| 3 | Required collection has Failed/Partial/Skipped checks or configured Git failed; inspect the restricted manifest/log and resume. Optional Git Skipped alone is not a failure. |
| 4 | Analysis/report/runtime-state failed; inspect saved input/schema/stage state locally. |

An Assessment run preserves exit 3 if downstream stages succeed, but returns 4
if a requested downstream stage fails. Collector failure records remain intact.
No broker or model-safe access is enabled by these commands.

### Portal readiness and explicit product visibility

Identity collection saves closed structural metadata for identity providers,
authorization servers, OIDC providers, and authorization providers. Portal
collection saves sign-in/sign-up/delegation/default config and revision metadata.
Both discard secrets, unneeded URLs/free text and unknown fields before writing.
They do not enumerate users, crawl the portal, or retrieve secret endpoints.
New collector checks have synthetic acceptance only; live validation remains
maintainer-owned.

In the private configuration, optionally add this closed root section:

```powershell
Portal = @{
    ProductVisibility = @(
        @{ ProductId = 'private-product'; IsPublic = $false; IntendedGroupIds = @('partners') }
        @{ ProductId = 'public-product'; IsPublic = $true; IntendedGroupIds = @('guests') }
    )
}
```

Use exact product/group resource names, not display names. Duplicate or malformed
IDs, non-Boolean intent, and unknown fields fail validation. All configured values
stay in the restricted run-setting snapshot. Missing intent, unmatched products,
missing group evidence, or products without explicit intent remain NotEvaluated
unless another known mismatch establishes a finding. Guests trigger POR-003 only
for explicitly nonpublic products; missing intended memberships also trigger it.

POR-001 requires an Enabled developer portal and a current completed publication.
POR-002 uses direct `enableBasicAuth`, sign-up, and non-Entra provider evidence;
an absent basic-auth setting is Unknown, never inferred disabled from Entra-only
providers. Conflicting delegation evidence remains Unknown. POR-004 uses the
80-percent operation-description boundary and any available score's 70-point
boundary. Zero/incomplete operations do not become synthetic 100-percent coverage.
Optional OpenAPI/Spectral evidence is described below. POR-005 detects enabled
legacy portal status. Known positives survive unrelated Partial evidence.

Older ten-model runs do not require recollection. Rerun ordinary offline Analyze
then Report to refresh the expanded catalog; absent portal evidence gives explicit
Info/NotEvaluated findings. A malformed present portal model is not ignored.
Portal checks appear in the existing rule, finding, action-plan and HTML views;
no new report sheet or public command is introduced.

Offline acceptance uses compact synthetic raw fixtures: two APIs, two
operations, two products, six subscriptions, three named values, two backends,
two certificates, eight indexed policies, and nine network files. The separate
60-API generator produces saved models, not a scaled raw collector run.

```powershell
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\CollectionResume.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\RuntimeEntryPoint.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\integration\OperationalRuntime.Tests.ps1
```

## Optional OpenAPI quality

The OpenApi collector attempts current HTTP APIs only. It records each export,
explicit unsupported-type skip, or safe failure in a closed restricted index.
Inline exports use guarded ARM GET; a recognized link fallback uses a separate
credential-free HTTPS Azure Blob download with bounded size/time and no
redirects. Downloads pin a validated public IPv4 address; IPv6-only resolution
is conservatively rejected. Documents are limited to 5 MiB and depth 64.
Signed URLs never enter saved output. Invalid JSON, secret candidates,
or incomplete scans prevent document persistence. Valid successful exports from
a Partial check remain usable; unlisted stale files do not become evidence.

Node and Spectral are optional, not collection prerequisites. Supported setup
requires Node 22.x or 24+ and npm on PATH. To install the pinned optional
development tool explicitly, run:

```powershell
.\scripts\Install-OptionalTools.ps1
```

This is separate from `Install-DevDependencies.ps1`. Assessment execution never
installs packages or invokes auto-downloading `npx`. Analyze automatically uses
supported installed Spectral 6.17.0 from toolkit-relative `.tools\spectral`
with the shipped `rulesets/apim-style.yaml`. Global/PATH Spectral commands and
environment overrides are not discovered. The installer pins the package with
lifecycle scripts disabled; it does not install Node.
Only same-document references are supported; external URL and local-file
references are rejected before linting, without network/file resolution.

Optionally add this closed root section to the private configuration before
collection; both values must be integers from 0 through 100:

```powershell
OpenApiQuality = @{ ErrorPenalty = 10; WarningPenalty = 2 }
```

The score is `max(0, 100 - errors * ErrorPenalty - warnings * WarningPenalty)`.
Exact penalties are saved in restricted run settings. No-tool, unsupported
reference/API/export and process-failure outcomes retain a null score with a
fixed status/reason, not zero or 100. Description coverage remains available
from a complete nonempty operation inventory. POR-004 preserves the exact
70-score and 80-percent description thresholds and identifies the actual method.

`model/openApiQuality.json` is an optional restricted model bound to exported
document hashes, trusted ruleset, tool version and scoring settings.
`restricted/openapi-binding.json` protects replay under operator-owned storage;
it is an integrity check, not a signature. Report validates saved quality and
replays findings without invoking Spectral. Run offline Analyze explicitly to
regenerate quality. Changed/missing listed sources, models, settings or bindings
fail closed. Legacy runs without OpenApi collection remain usable without
Node, Spectral or recollection.

Definitions, server URLs, samples, diagnostic paths/messages, digests and exact
quality metrics never enter the model-safe package. Package 1.3 reuses only the
approved `ApiDocumentationWeak` condition and existing Api aliases. Live export
compatibility still requires authorized maintainer validation outside Copilot.

## Optional Git and cross-environment drift

In private environment configuration, leave `GitRepoPath = ''` to skip Git.
Set it to an absolute local ordinary-clone path to collect committed policies.
`GitPolicyRoot` is a non-empty slash-separated relative Git path, such as
`apim/policies`; absolute paths, backslashes and dot/parent/empty segments fail.
Git must be installed only when this capability is used. Source repositories,
private configuration and generated run data remain outside the coding session.

The default layouts beneath that root are `policy.xml` (Global),
`products/<product>/policy.xml`, `apis/<api>/policy.xml`, and
`apis/<api>/operations/<operation>/policy.xml`. Optional `GitPolicyMappings`
replaces, rather than extends, all defaults. Each closed map has `ScopeType`
and a timeout-bounded `Pattern`; captures must be named `product`, `api`,
`operation`, or `fragment` as appropriate. The collector anchors each complete
pattern. For example, a fragment-only source can use:

```powershell
GitPolicyMappings = @(
    @{ ScopeType = 'Fragment'; Pattern = 'fragments/(?<fragment>[^/]+)\.xml' }
)
```

Scope identities are `global`, product/API IDs, `api|operation`, and fragment IDs.
Ambiguous/colliding mappings, unmapped XML, malformed policies, links, gitlinks,
escaping roots, missing roots and invalid repositories fail closed. Config
syntax validation never opens a repository. Bare/linked-worktree repositories
are unsupported. Collection reads only UTF-8 blobs at one pinned HEAD and ignores
dirty/untracked files; it never fetches, clones, checks out, runs source scripts,
or modifies Git configuration. Bounds are 15 seconds per Git process, 8 MiB tree
output, 1 MiB per blob, 16 MiB aggregate XML, and 4,096 policies.
Restricted `git/policyHashes.json` retains only commit ID, scope coverage and
unique scope/hash records, never policy bodies, author identities or remotes.

```powershell
# Authorized ordinary local terminal, never a coding agent.
.\Invoke-ApimCollect.ps1 -Config <private-config.psd1> -Environment Prod -SkipGit
.\Invoke-ApimAnalyze.ps1 -RunFolder <prod-run> -CompareRuns <dev-run>,<test-run>
.\Invoke-ApimReport.ps1 -RunFolder <prod-run>
# Reanalysis reuses the validated saved source snapshots without external folders.
.\Invoke-ApimAnalyze.ps1 -RunFolder <prod-run>
```

No configured repository records Git Skipped without blocking ordinary analysis
or reports. Explicit `-SkipGit:$false` without configuration fails before auth;
configured Git failure returns collection exit 3 and is not treated as Skipped.
Resume checks the current committed snapshot; changed Git invalidates downstream
stages/package state. `-SkipGit` is part of resume configuration compatibility.

`-CompareRuns` accepts at most 15 additional supported saved runs, explicitly
grouped by the operator. Customer/tenant must match; environment labels, run IDs
and APIM resource identities must be distinct. Subscription/resource names may
differ. No automatic environment relationship is inferred. Valid incomplete
source inventory creates Unknown evidence, not an empty matching environment;
invalid or explicitly empty requested inputs fail. Supplying valid CompareRuns
replaces previous environment sources; omitting it reuses saved snapshots.

Analysis copies only closed inventories to `restricted/drift-inputs.json` and
binds their digests and `model/drift.json` locally. Report/package replay also
rechecks current deployed and saved Git evidence; modified/missing bindings or
requested drift output fail. External run folders are not retained or reopened.
These hashes are local integrity checks, not signed provenance.

GOV-007 emits one Medium production policy/source difference finding; GOV-011
emits one Low environment policy/API-presence difference finding. Evidence retains
all differences and incomplete-comparison qualifications. Missing sources emit
Info/NotEvaluated, while known differences survive gaps elsewhere. Git coverage
is limited to mapped scopes: XML absence does not prove API catalog absence.
Equal hashes compare protected normalized XML, not secret literal equality.
Full API definitions are not compared. Environment Drift displays pairwise
presence/hashes, changes and Unknown coverage; Run Info explicitly labels no
comparison evidence. Exact values remain local. Model-safe package 1.2 exports
only `SourcePolicyDrift`/`EnvironmentPolicyDrift` condition codes and existing
service aliases; no new broker arguments or agent tool permissions are added.

## Offline tracking and saved-run comparison

Run these commands in an ordinary local terminal for restricted saved data,
never through a coding agent. Automated acceptance uses synthetic fixtures only.

```powershell
.\Invoke-ApimReport.ps1 -RunFolder <current-run> -PreviousReport <prior-workbook.xlsx>
.\Invoke-ApimAssessment.ps1 -Config <private-config.psd1> -Environment Prod -PreviousReport <prior-workbook.xlsx>
.\Compare-ApimRun.ps1 -Baseline <baseline-run> -Current <current-run>
# After comparison, regenerate with tracking; the still-valid diff is included.
.\Invoke-ApimReport.ps1 -RunFolder <current-run> -PreviousReport <prior-workbook.xlsx>
```

Carry-forward accepts `.xlsx` toolkit workbooks with scope-matched Run Info,
Action Plan and Finding Details tables. Only Owner, Status, Target Date, and
Notes are copied, joining actions by rule ID and details by finding key.
Intentional blanks remain blank. New rows retain defaults. Dates must be Excel
dates or invariant `yyyy-MM-dd`; allowed statuses are Open, In progress, Done,
Accepted risk, Not applicable, or blank. Formula-bearing imported key/tracking
cells, duplicate/missing keys/headers, invalid types/status/dates, linked paths,
external links, macros, malformed archives, or scope mismatch fail. Text is
written literally. The prior workbook is never saved or overwritten.
Supported workbook bounds are 64 MiB compressed/expanded, 16 MiB per ZIP entry,
and 9,997 rows per table. Collection-only Assessment rejects PreviousReport.

Compare requires disjoint run directories with completed analysis, supported
saved settings/models/findings, and matching customer, tenant, APIM resource,
and environment. It preserves historical findings; the current run must still
match deterministic replay. The supported settings loader currently requires
the installed tool version for both runs. Cross-environment drift uses Analyze,
not Compare. Arbitrary historical schema/version migration remains unavailable.

Results stay in current-run `diff.json` and a new non-overwriting report pair.
Run Comparison lists comparable New/Resolved/Persisting findings, including
previous/current severity. Comparison Gaps lists NotReassessed rows; Comparison
Pillars and Comparison KPIs retain counts and availability reasons. Unknown
reachability produces a null reachable-API KPI; active AllApis counts use
collected subscription state/scope. Comparison's unused-API and monthly-cost KPIs
remain null: this slice adds report models, not a cross-run KPI period-selection
contract.

Changed settings, historical replay disagreement, and Partial required evidence
prevent unqualified absence claims. Resolved means absent from comparable
evaluated snapshots, not independently verified remediation. NotEvaluated rows
are never resolved risks. Unmatched tracking is listed in Not Reassessed unless
a comparison bound to that prior workbook snapshot supports resolution; then it
appears in Resolved Since Last Run. Old toolkit workbooks without snapshot
bindings can carry matching tracking, but unmatched rows stay Not Reassessed.
These history tables do not affect current findings or Summary counts.

The restricted `comparison-binding.json` sidecar binds diff contents to the
current input digest. Missing, changed or stale bindings fail Report with exit 4.
Rerun Compare from the intended baseline/current runs to refresh, rather than
editing comparison artifacts. The baseline is read-only. These hashes detect
accidental changes under the operator-owned filesystem threat model; they are
not signatures or proof against a malicious local writer. All lifecycle errors
return bounded statuses, never workbook cells, identifiers, paths, or excerpts.
Neither tracking nor comparison enters the model-safe package/tool surface.
HTML retains its existing deterministic executive content and paired basename.

## Narrow model-safe broker (owner admission required)

Do not attach the broker to a broad coding session or read restricted setup/run
files through Copilot. The owner must first approve I-05/I-06, select canonical
physical roots, enforce exclusive filesystem/ancestor ownership, stop other
writers, and verify the **complete** actual Copilot-visible path set. Restricted
and private-staging roots must be outside every visible root. All three roots
must be pairwise disjoint; staging and analysis must support atomic rename on
one filesystem. Links, mapped/substituted drives, unknown isolation, incomplete
roots, missing approvals or concurrent writers are blockers. No command here
discovers, modifies or bypasses host trust/ACL/tool controls.

Create `broker.json` locally inside the restricted root, outside the model
session. It must pass `schemas/broker-operator.schema.json`. This illustrative
shape starts with false admission flags and therefore **must fail startup**
until the owner verifies and explicitly changes them:

```json
{
  "schemaVersion": "1.0",
  "restrictedRoot": "<absolute restricted root>",
  "analysisRoot": "<absolute dedicated analysis root>",
  "privateStagingRoot": "<absolute private staging root>",
  "visibleRoots": ["<every actual visible root, including checkout/session grants>"],
  "visibleRootsComplete": false,
  "exclusiveFilesystem": false,
  "approved": false,
  "aliases": [
    {
      "alias": "synthetic-test",
      "configPath": "<private PSD1 inside restricted root>",
      "environments": ["Test"]
    }
  ],
  "savedRuns": [
    {
      "runId": "run-00000000000000000000000000000001",
      "relativePath": "synthetic-operational"
    }
  ]
}
```

Aliases are optional for saved-run offline workflows. For new collection, each
private PSD1 must be valid and its `Output.Root` must exactly match the restricted
root. Alias/environment names are bounded identifiers, not customer names.
Saved runs are registered by an owner-chosen opaque ID and a single safe
directory name beneath the restricted root; each must already have a valid
manifest. These are operator declarations, not model-supplied tool arguments.
Set `$brokerStartup` locally to that file. The stdio server command is:

```powershell
# Owner-configured MCP child process, not a Copilot shell/tool invocation.
pwsh -NoProfile -NonInteractive -File .\scripts\Start-ApimBroker.ps1 -OperatorConfigPath $brokerStartup
```

Configure this exact command as local MCP server **`apim-assessment`** in the
owner-managed host (`/mcp` opens configuration in Copilot CLI). Keep private
configuration outside model-readable directories; do not paste its resolved
paths or logs into chat. The server pins MCP 2025-11-25 and accepts only its
initialize/initialized, ping, tools/list and tools/call lifecycle. Clients using
an incompatible handshake fail closed. Tool calls have a 20-minute hard worker
timeout; worker stdout/stderr, including native/direct-console output, are
drained without forwarding. Fixed startup/operation/request error codes are
safe to report; inspect the restricted manifest locally for operational failures.
Run/output IDs are scoped to the broker process and expire on restart.

Select the reviewed source profiles in a **clean model-safe-only context**.
Before supplying any package, the owner must verify actual available tools,
not just the YAML text:

| Profile | Exact tools under `apim-assessment/` |
|---|---|
| `apim-architecture-exposure` | `read_validated_analysis_package` |
| `apim-security-analyst` | `read_validated_analysis_package` |
| `apim-executive-synthesizer` | `read_validated_analysis_package`, `read_validated_agent_outputs` |
| `apim-assessment-orchestrator` | `run_assessment`, `get_assessment_status`, `promote_analysis_package`, `read_validated_analysis_package`, `validate_agent_output`, `read_validated_agent_outputs`, `render_reports` |

No generic shell, filesystem, search, Azure, delegation or wildcard tools may be
available. Unrecognized/missing profile tools are a blocker, not permission to
use a development agent. Skills are instructions, **not** permission controls.
The four `apim-*` operator skills describe orchestration, analysis, deliverables
and validation; they must only be used in the admitted broker-only profile.

The workflow is start/register run -> coarse status -> promote -> read package
and digest -> propose specialists -> validate proposals -> read revalidated
proposals -> propose executive -> validate -> render. `run_assessment` accepts
only approved configAlias/environment and `options: {"stage":"All"}` or Collect.
Public ordinary-terminal Resume remains available; the broker has no path-based
resume argument. Read-only specialists/synthesizer return proposal JSON; the
orchestrator alone submits it through `validate_agent_output` with exact digest
and kind. Every direct citation must support the approved rationale/code and
recommendation/category. Confidence cannot exceed evidence; NotEvaluated only
supports Low MissingEvidence. Unknown diagnostic coverage cannot be asserted
from sensitive diagnostic capture. Executive posture and priority citations
preserve authoritative High findings; assumption/data-gap sets are exact.

On missing/rejected proposals, request `render_reports` with an empty
`validatedAgentOutputs` list. This is explicit deterministic non-AI fallback,
not a success-shaped AI summary. Both reports remain under `report/`;
`restricted/latest-reports.json` pairs the current filenames and
`restricted/report-artifacts.json` maps opaque returned artifact IDs to relative
paths for the owner. No broker operation reads those registries to a model.
Immutable analysis versions contain only package/attestation; proposals and
identity maps remain restricted. Each proposal also has a closed
`restricted/agent-outputs/<outputId>.binding.json` sidecar preserving exact package
and output hashes for local audit; these files never authorize restored IDs or
model access after restart. Rendering replays findings, rebuilds package
binding, checks identity-map agreement, resolves aliases locally and escapes text.
No agent writes templates or reads a rendered report. Human visual review,
accessible browser/print review and live G3 acceptance remain owner tasks.

Synthetic automated acceptance, without Azure credentials or actual host
admission, is runnable in a development checkout:

```powershell
.\scripts\Invoke-Checks.ps1 -TestPath tests\unit\AgentClaim.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath tests\unit\BrokerBoundary.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath tests\unit\AssessmentProfile.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath tests\integration\BrokerWorkflow.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath tests\integration\ExecutiveHtml.Tests.ps1
```

The real subprocess tests check lifecycle/strict dispatch, all-stream canaries,
byte/digest/identity mutations, approved specialist/executive handoff and paired
reports. Profile tests guard exact declaration allowlists; contrast tests measure
the used normal-text foreground/background pairs. These tests **do not** certify
actual Copilot tool filtering, organization approval, host ACLs or clean-session
execution. T-324 remains blocked on the owner demonstrating that clean workflow
without generic tools or permission expansion.

## Safe bootstrap check

In PowerShell 7.4+ at the repository root:

```powershell
.\scripts\Install-DevDependencies.ps1
Import-Module .\ApimAssessment.psd1 -Force
Get-Module ApimAssessment
.\scripts\Invoke-Checks.ps1
```

These commands do not connect to Azure. The module exports five implemented
assessment functions; the internal persistence and collector helpers remain
private. ARM and collector behavior, including parallel throttle enforcement, is
exercised through mocked or synthetic offline tests only. Missing development
modules are installed into the current user's module path; Pester results go to
ignored `artifacts`.

Rule-engine acceptance remains offline and synthetic:

```powershell
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\RuleEngine.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\NetRules.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\SecRules.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\GovRules.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\RelRules.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\ActionPlan.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\AnalysisContract.Tests.ps1
```

The contract check above uses only the independent synthetic examples under
`tests/fixtures/synthetic-reference/analysis-contracts`. It neither reads a
saved customer run nor creates/promotes an analysis package. The private gate
consumes JSON strings, rejects malformed/duplicate-member inputs, and bounds
each input to 16 MiB of UTF-8 content and a JSON nesting depth of 32. Rejections
use fixed messages without echoing input values or validator exception details.
Independent privacy validation and physical promotion are tested separately
below; specialist claim reconciliation remains T-322/T-323.

The private `Get-ApimRuleCatalog`, `Invoke-ApimRuleEngine`, and
`Write-ApimFindingSet` helpers are not operator commands. Rules require explicit
model inputs; missing/failed inputs produce one Info/NotEvaluated finding per
rule. An optional, allowlisted field-level `DataGaps` callback marks required
facts within a present model as NotEvaluated instead of a false pass; malformed
available models and invalid evidence fail closed. Unknown usage is not zero
usage. `rules/NET.rules.ps1` includes NET-001/002/004/006/007/008/009.
NET-001 and NET-009 need operator-corroborated facts in the closed network
model. With no attestation, both emit Info/NotEvaluated rather than asserting
absent authentication or unnecessary publication. The saved-run Analyze and
Excel Report commands are available; package promotion remains private.
`rules/SEC.rules.ps1` includes
SEC-001/002/003/004/005/007/008/009/010/011/012/014/015/019/020. Rules with
unknown applicable facts emit one Info/NotEvaluated finding unless other
records already provide definitive positive evidence. SEC-014 consumes
model-derived diagnostic body and sensitive-request-header facts; incomplete
normalized settings remain null and can still produce NotEvaluated rather than a
false pass. SEC-008 uses only structural named-value locations and never secret
values. SEC-009 uses one rule ID across named-value and certificate targets,
requires both closed models, and emits one NotEvaluated result when required
Key Vault facts are unknown without a known positive finding. SEC-010 evaluates
only HTTPS backends, ignores non-applicable HTTP TLS
flags, and emits NotEvaluated when no positive finding exists but an HTTPS
validation fact is missing. SEC-011 evaluates the closed backend `scheme` and
operation `backendOverrideHttp` facts. Its optional configuration is exact and
case-insensitive:

```powershell
RuleExceptions = @{
    ApprovedPlainHttpBackendIds = @('approved-backend')
    ApprovedPlainHttpOperationKeys = @('api-id/operation-id')
}
```

Omitting `RuleExceptions`, or leaving both arrays empty, approves nothing.
Entries suppress only the named backend or operation; they do not classify an
API as internal. If no known unapproved HTTP target exists, Partial operation
policy evidence remains NotEvaluated. SEC-001 evaluates only five normalized
client/backend legacy TLS controls; an explicit enablement remains a finding
when another control is unknown, while no enablement plus incomplete control
evidence is NotEvaluated. SEC-002 treats an absent minimum management API
version as a finding. SEC-019 evaluates only normalized managed-identity type
and never retains user-assigned identity IDs. Never pass restricted models or
findings to Copilot.

`rules/GOV.rules.ps1` includes all GOV rules except usage-dependent GOV-004.
GOV-006 flags unversioned APIs and complete
version sets with one known version; an incomplete set is NotEvaluated unless
another known positive exists. GOV-008 emits one service-level finding with
bounded convention counts rather than one row per API. GOV-010 preserves a
known missing-`<base/>` operation finding when another policy is Partial.
GOV-003 and GOV-009 use optional closed product-governance and
diagnostic-coverage evidence. Add explicit intent to private configuration:

```powershell
Governance = @{
    Products = @(
        @{ ProductId = 'external-product'; HasOwner = $true; IsExternal = $true }
        @{ ProductId = 'internal-product'; HasOwner = $false; IsExternal = $false }
    )
    CriticalApiIds = @('critical-api')
}
```

These are exact resource-name IDs, not display names or owner identities.
Unknown fields, duplicate/malformed IDs and non-Booleans fail validation.
Absent product intent is Unknown; an explicit empty `CriticalApiIds = @()`
attests none, while omission does not. Unresolved targets retain qualified gaps.
Intent is snapshotted for offline replay. Change it through a new compatible
collection run, not by editing saved settings/models/findings.

GOV-003 flags missing description, explicitly missing owner, or disabled approval
for an explicitly external product. GOV-009 flags known absent effective
diagnostics, unresolved logger references, or a known sample below 100 percent
on an explicitly critical API. API settings override service settings; service
fallback requires a known empty API diagnostic list. Missing settings or fixed
sampling values are Unknown, not disabled or zero. These are configuration
checks, not proof of ingestion/retention/runtime delivery. A known positive
survives unrelated gaps; otherwise incomplete evidence is Info/NotEvaluated.
Ten-model legacy runs still load and report with qualified missing evidence.

Organization is a separate seven-endpoint collector. It writes restricted
groups, tags, version sets, gateways, workspaces and fragment metadata, dropping
free text/identities/fragment XML and unknown fields before persistence.
`raw/users.summary.json` contains only total plus fixed state/provider counts.
No user records, names, UPNs, emails or identities persist. Provider counts are
per user per category and may sum above total. `Privacy.StoreUserIdentities`
must be false; true is rejected before authentication, ARM calls or run creation.
An unsupported/denied endpoint is Failed/Partial, never an empty successful
inventory; other successful files remain usable. Resume repairs incomplete or
invalid output and smoke validates projections and count consistency.
Organization failures do not invalidate independently collected product or
diagnostic evidence. Live endpoint compatibility remains maintainer-only.

`rules/REL.rules.ps1` includes REL-001 through REL-006. SKU, zone, and platform
facts come from the closed service model. Critical backend evaluation is opt-in
and exact:

```powershell
RuleTargets = @{
    CriticalBackendIds = @('critical-backend-id')
}
```

Omitting `RuleTargets`, or leaving the array empty, declares no critical backend
targets. REL-004 considers only APIM-targeted App Gateway routes; a linked HTTP
setting without a custom probe uses the default `/` path, while unresolved
probe evidence is NotEvaluated. REL-005 compares normalized service-hostname and
APIM certificate-entity expiry with the saved `manifest.startedUtc` plus
`CertExpiryDays`, so rerunning analysis does not move the threshold. Missing
service, probe, or expiry facts remain
NotEvaluated unless another record provides a known positive.

The private `Get-ApimActionPlan` helper is also not an operator command. It
accepts only schema-valid findings with valid unique keys, groups them by rule,
counts evaluated instance rows, retains NotEvaluated gaps with zero affected
resources, selects deterministic top scopes, and validates the result against
`schemas/actions.schema.json`. It does not itself write a workbook, carry
tracking values forward, or expose models/findings to Copilot. The private
writer consumes its output through a separate report-only tracking projection.

The checked-in workbook template can be regenerated and structurally tested
offline after installing pinned development dependencies:

```powershell
.\scripts\New-ApimActionPlanTemplate.ps1 -Force
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\WorkbookTemplate.Tests.ps1
```

This uses ImportExcel without desktop Excel, fixed column widths, and no Azure
access. The template contains no customer values. Regeneration is a development
operation only; the public Report command populates a local restricted copy.

Private report-writer acceptance also remains synthetic and offline:

```powershell
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\ReportWriter.Tests.ps1
```

`Export-ApimActionPlan` is not an operator command. It validates the manifest,
all registered model files, and findings before copying the trusted template.
Current output fills actions, finding details, APIs, policy controls,
subscriptions, exposure, network summary, and Summary assumptions under the
run's `report` folder. It never overwrites an existing workbook and leaves no
partial output on validation/template failure. It also expands the manifest
into Run Info, writes the implemented rule catalog, and copies the manifest's
exact scoring snapshot into editable positive-number weight cells. Finding
Details formulas recalculate Severity × Exposure × Usage, with blank usage
remaining the neutral 1.0 multiplier; Action Plan formulas select each rule's
maximum recalculated detail priority. Weight edits change workbook values on
recalculation but do not alter restricted `findings.json` or automatically
resort action rows. Telemetry runs populate Usage/Cost; requested comparison
evidence populates Environment Drift. The generated workbook is restricted customer
output and must never be sent to Copilot or another model.

## Owner-only lab bootstrap

`scripts\lab\Invoke-LabBootstrap.ps1` is separate source-checkout lab tooling,
not an assessment command or part of the release package. Its tests are offline
and synthetic; **do not run it through Copilot, a coding agent or ordinary PR
CI**. Availability does not authorize live bootstrap. Owner permission,
subscription/region/policy/cost approval and the later lab lifecycle/readiness
gates remain prerequisites. The offline Bicep foundation is documented below;
worker, certificate/DNS automation, protected live workflows and teardown
remain planned.

Owner prerequisites, established privately outside the model session:

- PowerShell 7.4+, `Az.Accounts` with `Get-AzContext`/`Invoke-AzRestMethod`, and
  authenticated `gh` for `github.com`. No login, context selection, token
  retrieval, secret creation or dependency installation happens in this tool.
- An existing interactive **User** AzureCloud context matching the exact private
  tenant/subscription; owner authorization to create the UAMI/federation and
  explicitly scoped role assignments. Routine CI receives no role administration.
- Two existing, distinct resource groups in the configured location, each tagged
  `apimAssessmentLab=<labId>`: the lab group and deployment-identity group.
  The deployment UAMI must remain outside the group it can deploy into.
- Administration of the exact, non-fork GitHub repository with default branch
  `main`; support for environment reviewers, prevention of self-review and admin
  bypass, and selected deployment branches. Choose 1-6 approved reviewer
  User/Team numeric IDs privately. Unsupported or unreadable controls block
  bootstrap; do not downgrade them to make the tool succeed.
- A canonical, owner-controlled private directory outside **every** actual
  Copilot-visible/trusted root, with protected ancestors/ACLs and no concurrent
  writers. The tool rejects checkout overlap and links but cannot discover or
  enforce the host's complete trust/ACL boundary. Gitignore is not isolation.
  Serialize owner executions and other administrative changes.

Copy `infra\live-validation-lab\bootstrap.sample.json` to that private directory
and replace synthetic identifiers there, not in Git or chat. The closed schema
`bootstrap.config.schema.json` allows only the documented version 1.0 fields,
`lab` environment, `main` branch and `baseline` profile. Keep `runtime: null`
for the first Identity stage. Unknown fields, credentials, arbitrary roles,
wildcards and overlapping resource groups are refused.

Run these commands only in an ordinary **owner PowerShell 7.4+ terminal**.
Set `$privateRoot` to the already approved private directory first; its value
and all files/output below must never enter model context or CI artifacts.

```powershell
$configPath = Join-Path $privateRoot 'bootstrap.json'
$planPath = Join-Path $privateRoot 'identity-plan-01.json'
pwsh -NoProfile -File .\scripts\lab\Invoke-LabBootstrap.ps1 `
    -ConfigPath $configPath -PlanPath $planPath -Mode Preview -Stage Identity `
    -OwnerAuthorized -MicrosoftOwnedTestEnvironment

# Owner reads this private plan locally and approves its exact actions/scopes.
$approved = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant()
pwsh -NoProfile -File .\scripts\lab\Invoke-LabBootstrap.ps1 `
    -ConfigPath $configPath -PlanPath $planPath -Mode Apply -Stage Identity `
    -ApprovedPlanSha256 $approved -OwnerAuthorized -MicrosoftOwnedTestEnvironment
```

Preview makes GET requests only and writes a **new**, non-overwriting private
plan. The plan contains exact targets/grants, non-secret variable values and
config/state SHA-256 bindings; it is restricted infrastructure metadata, **not**
a model-safe package. `issuedAt`/`expiresAt` are Unix seconds with a 30-minute
lifetime. Apply verifies the owner-supplied plan hash, unchanged config text
(including formatting), requested stage and newly checked state before mutation;
approval lifetime/context are checked again before actions. A new identity's
unknown principal/client IDs are resolved only from its owned, typed readback,
not caller-supplied arbitrary IDs. Hashes are approval/integrity bindings under
the owner-controlled filesystem model, not signatures or distributed locks.

Identity creates missing exact resources only: deployment UAMI, protected `lab`
environment with approved reviewers/no self-review/no admin bypass, branch
policy admitting only branch `main`, one federated credential with issuer
`https://token.actions.githubusercontent.com`, audience `api://AzureADTokenExchange`
and subject `repo:<private owner/repo>:environment:lab`, six non-secret variables
(`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_LOCATION`,
`LAB_RESOURCE_GROUP`, `LAB_PROFILE`), and Contributor only at the lab group.
Protection/branch controls are read back before new federation is enabled.
Existing conflicting trust, protection, ownership, variables or visible roles
refuse; the tool does not repair/overwrite them. No app secret, PAT, Entra
application or application-role assignment is created.

After T-703/T-704 provide all required resources, privately replace `runtime: null`
with an object containing exactly `apim`, `gatewayIdentity`, `workerVm`,
`keyVault`, `dnsZone`, `appInsights` resource **names**. IDs/types/scopes are
derived within the configured lab group; custom scopes/role IDs are not inputs.
All resources must carry the same ownership tag and configured location
(DNS is global); APIM/worker use distinct system identities and the gateway a
third UAMI, all distinct from deployment. The vault must use the matching tenant
and Azure RBAC; the challenge zone must be public. This is not verification of
later network, DNS delegation, certificate or telemetry readiness.

| Principal | Fixed role | Exact scope |
|---|---|---|
| APIM system identity | Key Vault Secrets User | Dedicated lab vault |
| Gateway UAMI | Key Vault Secrets User | Dedicated lab vault |
| APIM system identity | Monitoring Metrics Publisher | Lab App Insights component |
| Worker VM system identity | Key Vault Certificates Officer and Key Vault Secrets Officer | Dedicated lab vault |
| Worker VM system identity | DNS Zone Contributor | Lab challenge zone |

Use a different new plan for this **separately approved** stage:

```powershell
$runtimePlan = Join-Path $privateRoot 'runtime-plan-01.json'
pwsh -NoProfile -File .\scripts\lab\Invoke-LabBootstrap.ps1 `
    -ConfigPath $configPath -PlanPath $runtimePlan -Mode Preview -Stage Runtime `
    -OwnerAuthorized -MicrosoftOwnedTestEnvironment

# Owner reviews the private runtime grants and scopes before approving this hash.
$approved = (Get-FileHash -LiteralPath $runtimePlan -Algorithm SHA256).Hash.ToLowerInvariant()
pwsh -NoProfile -File .\scripts\lab\Invoke-LabBootstrap.ps1 `
    -ConfigPath $configPath -PlanPath $runtimePlan -Mode Apply -Stage Runtime `
    -ApprovedPlanSha256 $approved -OwnerAuthorized -MicrosoftOwnedTestEnvironment
```

Repeated **fresh** preview/apply on complete matching state performs no writes
or duplicate grants. Missing groups/foundation/worker metadata yields
`LAB_NOT_READY` (exit 2), never a successful runtime grant. Successful preview
and apply emit only `LAB_PREVIEW_READY`/`LAB_APPLIED` (exit 0). Refusals emit
fixed `LAB_*` codes (exit 1); no external stream, raw exception, identifier,
metric or response is printed or logged. ARM and GitHub errors are not treated
as success, missing protection evidence is not fabricated, and gh processing
has bounded time/combined stdout-stderr size.

`LAB_STATE_CHANGED` requires a new private preview/approval. Config/approval/
preflight refusals require owner correction of the relevant private prerequisite.
`LAB_APPLY_INCOMPLETE` means owned resources or grants may already exist: inspect
them privately, retain evidence, and take a new preview after resolving conflicts.
Some partial states (such as a created environment without the exact branch
policy) deliberately refuse automatic repair; an authorized owner must correct
them outside this tool before retrying. No automatic deletion/rollback, purge,
policy exemption, broader grant or protection downgrade is performed.
Role inventory is limited to assignments visible at/above/below the approved
subscription for the selected principals, not a global effective-access audit.
Live availability/permissions, consistency/propagation and recovery remain owner
acceptance; mocked checks do not claim that live bootstrap has been exercised.

## Offline lab foundation

`infra\live-validation-lab\foundation.bicep` is a resource-group-scoped
source-checkout template, not an assessment export, release asset or deployment
command. It creates internal classic Developer APIM (one unit/system identity),
a new VNet/four subnets/four NSGs, worker NAT/static IP, gateway UAMI, empty
RBAC/soft-delete/purge-protected vault with private endpoint/DNS, a public ACME
challenge zone, Log Analytics and linked workspace-based App Insights.
It creates **no** worker VM, gateway/listener, certificate/secret, API, application
DNS record, federation or role assignment. Keep the separate deployment identity
in its existing identity group; do not redeploy it into its own Contributor scope.

Install public dependencies, then run the existing synthetic-only gate:

```powershell
.\scripts\Install-DevDependencies.ps1
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\LabFoundation.Tests.ps1 `
    -OutputDirectory .\artifacts\lab-foundation-checks
```

This installs checksum-pinned Bicep 0.48.1 and exact public AVMs, then performs
build/lint and offline snapshot evaluation against fixed synthetic tenant,
subscription, resource-group, name and documentation-IP inputs. It checks evaluated
subnets, NSGs, private endpoint/DNS and observability, not just source strings.
Snapshots and compiled files stay in temporary test storage; only synthetic Pester
results enter CI artifacts. Public dependency/module download requires network
access, but no Azure account, credentials, context, resources, quota or what-if
request is used. The template configuration has no credential sources.
Do not deploy `foundation.synthetic.bicepparam` or the sample configuration.

For a future owner handoff, first establish `$privateRoot` outside every
agent-visible/trusted root on owner-controlled, non-linked storage with protected
ancestors/ACLs and serialized access, as required by the bootstrap section.
Copy `foundation.sample.json` there as `foundation.json` and replace synthetic
values **privately**, in an ordinary owner terminal, never in a model session.
The exact names, ownership `labId`, region and intended lab group must agree
with the bootstrap contract. The writer does not inspect Azure or verify existing
ownership, subscription/context, collisions, permissions, provider or SKU readiness.
Those remain owner deployment preflight checks; no command here authorizes provision.

```powershell
$foundationConfig = Join-Path $privateRoot 'foundation.json'
$foundationParameters = Join-Path $privateRoot 'foundation-parameters-01.json'
pwsh -NoProfile -File .\scripts\lab\New-LabFoundationParameters.ps1 `
    -ConfigPath $foundationConfig -OutputPath $foundationParameters
```

The writer validates closed schema 1.0, duplicate/case-conflicting members,
canonical IPv4 network boundaries, RFC1918 /16-/22 VNet, subnet containment,
pairwise non-overlap and at least the agreed /24, /26, /27, /27 capacities.
Caller and worker HTTPS destination lists must each contain 1-16 unique canonical
public CIDRs; unrestricted, private, loopback, multicast and selected nonpublic
ranges reject. Documentation IPs are allowed for synthetic tests, not proof of
routable destinations. Retention is 30/60/90/120/180/270/365 days, workspace daily
quota 1-10 GB, sampling 1-100%. Quotas/alerts are not a guaranteed cost cutoff.
Missing/unknown fields, invalid inputs, relative/checkout/linked paths, missing
directories and existing outputs refuse. A new file uses exclusive CreateNew;
no output is overwritten. Success prints only `LAB_FOUNDATION_PARAMETERS_READY`
(exit 0); failure prints `LAB_FOUNDATION_PARAMETERS_FAILED` (exit 1). A write
failure can leave a partial private file; investigate locally and use a new path.
Do not paste parameters, errors, snapshots, deployment outputs or identifiers
into chat or CI. Checkout/link checks do not audit every host trust root or ACL.

Worker egress uses NAT and explicit approved HTTPS CIDRs plus Azure ARM/Entra/
Monitor/Storage and platform DNS/agent/identity paths; no internet-wide outbound
allow is added to that subnet. NSGs cannot filter by FQDN: the owner must approve
and maintain the actual package/ACME and later gateway public-IP destinations.
Missing destinations are a readiness failure, not permission to replace the list
with `Internet`. APIM retains required classic platform/CRL/PKI/update egress;
the standard App Gateway subnet retains its required outbound default and
GatewayManager/load-balancer/health ports. This is not blanket egress isolation.
APIM HTTPS ingress permits only gateway/worker subnets before deny-all.

Key Vault private DNS serves worker/gateway access. APIM's system-identity
certificate control-plane path separately uses the documented default-deny
public firewall/AzureServices bypass and APIM Key Vault service endpoint;
there is no all-networks fallback. Later owner validation must prove certificate
access before hostname binding. App Gateway does not rely on a trusted-service
bypass. APIM's `publicNetworkAccess: Enabled` preserves classic control-plane
requirements; `virtualNetworkType: Internal` and NSGs keep its API data plane private.

Dedicated `GatewayLogs` to Log Analytics and APIM's all-API App Insights diagnostic
are independent. App Insights disables local ingestion auth and masks IPs;
logger credentials use connection-string metadata and `SystemAssigned`.
Body bytes/header lists/client-IP capture are disabled. T-702 Runtime supplies
the fixed vault and Monitoring Metrics Publisher roles only after all future
worker/foundation resources exist, so it remains NotReady after foundation alone.
Initial telemetry may be unavailable until those grants propagate; an owner must
prove actual ingestion, never interpret absent logs as zero traffic or a pass.
API-specific overrides/traffic, certificate bindings, exact APIM/backend application
DNS, gateway routing, lifecycle and live deploy/validation are later tasks.
Module pins and the shared-key-free workspace exception are recorded in
`.azure\deployment-plan.md`; module exports/version and release boundaries are unchanged.

## Offline private lab worker

T-704's `infra\live-validation-lab\worker.bicep` adds only one private Linux VM/NIC
to the foundation worker subnet, not another VNet, public endpoint or runtime
grant. VM AVM 0.22.3, a 32-GB Standard SSD, Trusted Launch/secure boot/vTPM,
system-assigned identity and password-disabled provisioning are fixed.
The owner chooses `Standard_B2ls_v2` or `Standard_B2s`, an available zone 1-3
and the fixed Canonical Ubuntu 24.04 server image version (`latest` or a numeric
version). Regional SKU/image/zone availability, quota, cost and private address
collisions remain unverified owner gates, never an automatic fallback.
Cloud-init masks both SSH service/socket and prepares protected directories.
It does not download a binary, issue a certificate or start a service.
The privileged VM agent channel is not job/identity isolation or a public runner.

Run only synthetic acceptance in this development session:

```powershell
.\scripts\Install-DevDependencies.ps1
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\LabWorker.Tests.ps1 `
    -OutputDirectory .\artifacts\lab-worker-checks
```

This checks closed VM/app/job inputs, reserved addresses, no-overwrite/private-path/
every-stream handling, evaluated VM/NIC/guest settings, actual loopback TLS 1.2,
JWT issuer/audience/role/caller/signature negatives and all sixteen contract
operations. Generated test keys/certificates stay in temporary synthetic storage.
Fake metadata/network clients cover bounded jobs without accessing Azure.
Locked Linux-x64 publishing admits binaries and the five contract files only,
not private configuration or sample/job files. Public SDK/NuGet/AVM downloads are
dependency installation, not live deployment or credential access.

For a future owner handoff, use the protected external `$privateRoot` established
in the bootstrap section. Privately copy `worker.sample.json` there as
`worker.json`; replace only synthetic values in an ordinary owner terminal.
Names, `labId`, region, VNet and worker subnet must agree with the foundation and
bootstrap. `workerCidr` is validation-only and is not a deployment parameter.
The static address must be canonical RFC1918 within that subnet, after Azure's
first four reserved addresses and before its final address; a /27 or larger
subnet is required. Supply a valid RSA 2048-4096 public provisioning key, never
a private key; its presence does not open SSH.

```powershell
$workerConfig = Join-Path $privateRoot 'worker.json'
$workerParameters = Join-Path $privateRoot 'worker-parameters-01.json'
pwsh -NoProfile -File .\scripts\lab\New-LabWorkerParameters.ps1 `
    -ConfigPath $workerConfig -OutputPath $workerParameters
```

The closed version 1.0 writer refuses missing/unknown/case-duplicate fields,
unsupported versions, unbounded SKU/image/zone choices, invalid addresses/keys,
relative/checkout/linked paths and existing output. It does not inspect Azure,
existing ownership or the actual subnet. Exclusive creation never overwrites a
file. Success prints only `LAB_WORKER_PARAMETERS_READY` (exit 0); failure prints
`LAB_WORKER_PARAMETERS_FAILED` (exit 1). A failed write may leave a partial
private file: inspect locally and use a new output path, without pasting it into
chat or CI. Checkout/link guards are not an audit of all host-visible roots/ACLs.
Do not deploy the committed synthetic parameter file.

Build the delivery payload offline from source, without private files. The SDK
resolver must run from the worker directory to honor exact `global.json`.
The installer either reuses an exact installed SDK or places it under `.tools`:

```powershell
$sdk = (Import-PowerShellDataFile .\scripts\DevDependencies.psd1).DotNetSdk
$dotnet = Join-Path $PWD ".tools\dotnet\$sdk\dotnet.exe"
if (-not $IsWindows) { $dotnet = Join-Path $PWD ".tools\dotnet\$sdk\dotnet" }
if (-not (Test-Path -LiteralPath $dotnet -PathType Leaf)) {
    $dotnet = @(Get-Command dotnet -CommandType Application -ErrorAction Stop)[0].Source
}
$workerPayload = Join-Path $PWD 'artifacts\lab-worker-publish'
Push-Location .\infra\live-validation-lab\worker
try {
    & $dotnet publish .\LabWorker.csproj --configuration Release `
        --runtime linux-x64 --self-contained true --output $workerPayload `
        -p:RestoreLockedMode=true --verbosity quiet
    if ($LASTEXITCODE -ne 0) { throw 'Worker publishing failed.' }
}
finally { Pop-Location }
```

SDK 10.0.402, ASP.NET Core/JWT bearer 10.0.13 and Linux runtime packs are pinned;
the closed NuGet configuration uses Microsoft's public `dotnet-public` mirror,
with committed dependency locks. No TLS/audit check is disabled.
This produces an ignored, self-contained Linux-x64 payload, not a Windows worker
or a release asset. No customer, certificate, token or job input belongs there.

**Private installation is not yet automated.** T-708 must deliver that payload
and the reviewed service unit through an approved protected channel, never
public SSH or a long-lived GitHub runner. The owner supplies these private files
outside all model-visible roots before starting the service:

| Guest path | Required protection / purpose |
|---|---|
| `/opt/apim-lab-worker` | Root-owned `root:apimlab`, directories/executable 0750 and readable libraries/contracts; reviewed published payload only |
| `/etc/apim-lab-worker/config.json` | Root-owned `root:apimlab` 0640; closed `worker/config.schema.json` 1.0 |
| `/etc/apim-lab-worker/tls/cert.pem` and `key.pem` | Root-owned `root:apimlab` 0640; matching valid leaf/chain and private key, never public/tracked/output |
| `/var/lib/apim-lab-worker` | Root-owned `root:apimlab` 2750; setgid preserves service-readable group on privileged atomic fault files without granting backend write access |
| `/var/lib/apim-lab-worker/request.json` | Root-owned `root:apimlab` 0640; closed `worker/job.schema.json` 1.0, privately replaced by one serialized privileged owner |
| `/var/lib/apim-lab-worker/runtime` | `apimlab:apimlab` 0750; backend may update bounded persistent fault counters only |
| `/etc/systemd/system/apim-lab-worker.service` | Root-owned 0644; shipped hardened unit with only bind-service capability |

Configuration requires canonical tenant/resource/caller IDs and distinct HTTPS
backend/APIM/gateway origins without paths, ports or query strings.
`backendCallerClientIds` names the allowed calling applications (for example the
APIM managed identity's client ID), not their principal/object IDs.
Backend startup verifies certificate hostname, validity and key strength;
clients must trust the complete supplied chain. Use an owner-approved private
test CA and configure APIM backend trust separately, or wait for T-705 public
ACME. Never disable certificate/name validation. Leaf/certificate inputs missing
or invalid fail startup; a process/VM existing is not a readiness pass.
Public ACME, private DNS, actual trust binding and file delivery remain separate
owner/T-705/T-706/T-708 gates.

After protected delivery only, these Linux guest commands use the fixed service
and installed input paths; they are not Azure invocation commands:

```sh
systemctl daemon-reload
systemctl enable --now apim-lab-worker.service
/opt/apim-lab-worker/LabWorker job
```

The service starts as unprivileged `apimlab`; privileged private jobs run
separately and exclusively. The backend serves TLS 1.2/1.3, exact synthetic
contract responses, a fixed unauthenticated `/healthz` and 403 deny/fallback
routes that never forward. Business routes require a valid RS256 Entra v2 token
for the configured backend resource GUID, exact tenant/issuer,
`Lab.Backend.Invoke` application role and an allowlisted `azp`; delegated `scp`
tokens reject. The backend and frontend resource applications must be distinct.
Creating those applications, requesting v2 access tokens and assigning roles
to APIM/worker are explicit owner directory tasks, not automatic RBAC/bootstrap.

Jobs read only the installed request path and return `LAB_WORKER_JOB_READY`
(exit 0), `LAB_WORKER_JOB_NOT_READY` (exit 3), or `LAB_WORKER_JOB_FAILED`
(exit 1); command/config failures return `LAB_WORKER_FAILED` (exit 1).
No URLs, identities, tokens, response bodies, exact metrics or exception text
are printed. `readiness` requires trusted HTTPS and the exact safe health body;
it does not certify APIM/gateway routes or telemetry.
Traffic uses system-assigned identity tokens held only in memory, fixed origins/
paths, no redirects/proxies, 1-20 sequential requests, 250-2000 ms spacing,
three-second HTTP/metadata timeouts and a 60-second whole-job budget.
Allowed profiles are `supply-chain`, `e-commerce`, `service-management`,
`plm-private`, `unmatched-denied` and `public-plm-denied`. There is no initial
Manufacturing profile, arbitrary URL/script, subscription-key job or public
fault toggle. Product-context/key automation is still future work.

Only a private `fault` job can enable Service Management faults: duration 1-120
seconds, delay 0-1000 ms, failure count 0-10, with at least one effect nonzero.
Faults are off by default, retain a request counter across backend restarts,
expire by UTC plus an in-process monotonic deadline, and never affect other APIs.
Malformed/tampered fault state fails closed; `clearFault` removes the active
profile. Same-VM/root access is privileged: these limits are not isolation from
a malicious administrator or job. Ordinary CI remains synthetic-only;
no deployment, runtime grants, live backend access or full lab readiness is claimed.

## Owner-only lab ACME certificates

**Offline implementation only:** the separate
`scripts\lab\Invoke-LabAcme.ps1` tooling is for an authorized maintainer on the
approved private worker, after separate provisioning, runtime grants and egress
approval. These instructions do not authorize deployment, DNS changes, ACME
issuance or Azure authentication from Copilot/CI. Never run owner commands in
a model-visible terminal. Actual protected binary/private-input delivery and
scheduling remain T-708; actual APIM/gateway/backend binding remains T-706/T-707.
No assessment-module transport exception, export or broker permission changes.
**Do not execute yet:** D-71 records an unresolved permission prerequisite.
The existing six T-702 Runtime grants do not include all fresh VM/vault ARM
ownership-metadata reads used by this tool. Reader scoped only to the worker VM
and dedicated vault was proposed, but approval was unavailable. No grant was
added; missing reads produce `LAB_ACME_INCOMPLETE` before DNS/issuance. Resolve
that design through an explicit owner decision and separately reviewed bootstrap
change, not ad hoc permission expansion or skipped ownership checks. The
commands below document the subsequent owner workflow, not current readiness.

The explicit owner installer pins Posh-ACME 4.35.0, Az.Accounts 5.5.3,
Az.Dns 2.2.0 and Az.KeyVault 6.6.1 in
`infra\live-validation-lab\acme.dependencies.psd1`, separate from CI tooling.
It accepts the pinned packages' licenses but does not import them or authenticate:

```powershell
.\scripts\Install-LabAcmeDependencies.ps1
```

The owner must first arrange these prerequisites privately:

- Provisioned tagged worker VM, Key Vault and dedicated **public** challenge
  subzone, matching the closed `acme.config.schema.json` configuration. Existing
  T-702 Runtime grants provide worker Key Vault Certificates Officer on that
  vault and DNS Zone Contributor on that zone; no subscription-wide discovery,
  broader DNS grant or direct Cloudflare token is required. Additional ownership
  metadata reads remain the separate unresolved D-71 prerequisite above.
- Public delegation of the challenge subzone to its Azure DNS NS set and direct
  `_acme-challenge` CNAMEs for the gateway/APIM/backend hostnames to
  `gateway`, `apim` and `backend` in that zone. Public application records and
  actual consumer bindings are separate tasks. Private split DNS is not proof.
- Approved HTTPS egress for pinned package sources, the staging/production ACME
  endpoints and `dns.google`. The credential-free Google query discloses only
  the configured public zone/challenge names, sets
  `edns_client_subnet=0.0.0.0/0`, verifies normal TLS and disables redirects/proxy.
  Requests are limited to three seconds and 16 KiB. No network rule is changed
  by this tool; the owner must maintain approved IP-based HTTPS destinations.
- A precreated owner-only state directory and private configuration outside
  the checkout and **every** Copilot trusted/allowed/model-visible root.
  `modelVisibleRoots` must list the complete host scope; the tool cannot discover
  all host trust configuration. Windows state root requires a protected DACL
  allowing only the current owner, SYSTEM and Administrators; descendants retain
  that restricted access. Unix directories/files require exact 0700/0600 and
  current ownership. Config and all path ancestors must be free of links.
- Serialized execution of all issuers for these aliases. The exclusive local
  lock and DNS ETag checks are not distributed coordination with another host.
  Protected owner-controlled backup/retention of the whole state directory,
  including ACME accounts/orders, is required. Never copy state into CI artifacts,
  release packages, a repository, chat or another model-visible location.

`acme.sample.json` is synthetic, not runnable private configuration. Copy and
edit it only in the private owner environment, replacing all identifiers, names
and OS-specific absolute paths. Set permissions before executing the tool.
It rejects unknown/missing/duplicate fields, wildcard/IP/noncanonical names,
repeated SANs, relative/linked/visible paths and insufficient permissions.
One certificate covers exactly the three configured DNS names. The worker uses
system-assigned managed identity, process-local Azure context and fresh
resource ownership/IMDS checks; interactive credentials and App Service identity
endpoint fallback are not accepted. No Key Vault secret value is retrieved.

In a private ordinary PowerShell 7.4+ terminal **on that worker**, set
`$configPath`, `$stateDirectory` and the following arguments without printing any
private values. On the Linux worker use native absolute Linux paths in the
private JSON; path values in the synthetic sample demonstrate Windows syntax.
The parent starts a fixed isolated PowerShell child with a private Unix umask
and discards all child stdout/stderr, even Console writes and warnings/errors.

```powershell
$acme = @{
    ConfigPath = $configPath
    OwnerAuthorized = $true
    MicrosoftOwnedTestEnvironment = $true
    AcceptPublicDnsQueries = $true
}
.\scripts\lab\Invoke-LabAcme.ps1 @acme -Mode Check
```

Check reads Key Vault certificate metadata only; it does not issue, import,
create a client profile or query public DNS. Exit 0 is `LAB_ACME_HEALTHY`;
exit 3 is `LAB_ACME_CERTIFICATE_MISSING`, `LAB_ACME_RENEWAL_DUE` (at most thirty
days) or `LAB_ACME_EXPIRY_CRITICAL` (at most seven days, including expired).
Missing/malformed ownership, identity or inputs produce
`LAB_ACME_INCOMPLETE` with exit 1, never a healthy/zero-expiry fallback.

Every apply requires a **new** private preview and its exact approval digest.
Preview writes a new `approval-<lowercase-slug>.json` directly under the state
directory, with exact configuration/state/resource/certificate digests, stage,
action, rotation flag and a thirty-minute lifetime. An existing plan is never
overwritten. Inspect/approve its contents only in the private owner environment;
do not echo the digest or plan to Copilot. Start with staging:

```powershell
$stagingPlan = Join-Path $stateDirectory 'approval-staging-initial.json'
.\scripts\lab\Invoke-LabAcme.ps1 @acme -Mode Preview -Stage Staging -PlanPath $stagingPlan
# Privately inspect and approve this exact file before assigning its digest.
$stagingDigest = (Get-FileHash -LiteralPath $stagingPlan -Algorithm SHA256).Hash.ToLowerInvariant()
.\scripts\lab\Invoke-LabAcme.ps1 @acme -Mode Apply -Stage Staging `
    -PlanPath $stagingPlan -ApprovedPlanSha256 $stagingDigest -AcceptAcmeTerms
```

Staging success is `LAB_ACME_STAGING_VALIDATED` (exit 0); staging material is
never imported or bound. Production requires a still-valid, successful staging
proof bound to this exact configuration from the last seven days, plus explicit
ACME terms and certificate-transparency disclosure approval. Public production
names enter certificate-transparency records; do not use confidential names.
Staging and production accounts/orders live in separate protected profiles.

```powershell
$productionPlan = Join-Path $stateDirectory 'approval-production-initial.json'
.\scripts\lab\Invoke-LabAcme.ps1 @acme -Mode Preview -Stage Production -PlanPath $productionPlan
$productionDigest = (Get-FileHash -LiteralPath $productionPlan -Algorithm SHA256).Hash.ToLowerInvariant()
.\scripts\lab\Invoke-LabAcme.ps1 @acme -Mode Apply -Stage Production `
    -PlanPath $productionPlan -ApprovedPlanSha256 $productionDigest `
    -AcceptAcmeTerms -AcceptCertificateTransparency
```

Successful production import is
`LAB_ACME_IMPORTED_PENDING_CONSUMER_VALIDATION` (exit 0), **not** proof that the
gateway, APIM or backend consumes that version or trusts its chain. The private
`lifecycle.json` receipt retains `PendingConsumerValidation` and a versionless
Key Vault secret reference. The tool validates exact SANs, matching RSA-2048+/
EC-256+ keys/dates, actual PEM/full-PFX chains and production system-root
server-auth trust with intermediate downloads disabled. It does not establish
revocation status or consumer refresh/trust. It reads back certificate metadata,
not secret material, and refuses unowned existing names or older-certificate
rollback. After completion it discards fixed PFX exports but retains account/
order and key state required by the client. That retained state remains secret.

Repeat Check under separately approved scheduling. For due renewal, obtain
fresh staging proof if needed and use a fresh Production preview/apply.
Healthy non-due production certificates yield `LAB_ACME_NOT_DUE` (exit 0)
without issuance/import. Forced fresh-key rotation requires **both** Preview
and Apply to include `-Rotate`; a plan without that flag cannot authorize it.
No timer, deployment, consumer update, secret download or file delivery is added.

Preview success is `LAB_ACME_APPROVAL_READY` (exit 0). Other failures, timeouts,
unknown worker exits or more than 1 MiB of child output produce only
`LAB_ACME_INCOMPLETE` (exit 1). The entire child has a fifteen-minute budget.
Before every write the tool rechecks approval expiry/context. DNS updates
preserve other TXT values and ETag conditions; it never deletes zones/record sets,
uses overwrite or removes identical preexisting tokens. The private
`dns-journal.json` records only owned new challenge intent. Known transient/
conflict operations have at most three attempts with one-/two-second backoff.

An incomplete/terminated apply can leave owned DNS challenges and protected
issuance/import material; do not delete the state or rerun a stale plan.
Privately inspect the pending state, correct the cause, and create/approve a new
preview. Recovery uses the exact journaled challenges, a completed cached client
certificate and metadata readback before retrying import, avoiding needless
reissuance or duplicate versions after a lost response. No silent rollback,
automatic teardown or full-lab Ready result is produced.

Offline development/CI acceptance uses only synthetic certificate material,
mocked Azure/ACME/DNS calls and local stream/timeout subprocesses:

```powershell
pwsh -NoProfile -File .\scripts\Invoke-Checks.ps1 `
    -TestPath .\tests\unit\LabAcme.Tests.ps1 -OutputDirectory .\artifacts\lab-acme-checks
```

## Reusable collection smoke (Microsoft-owned test APIM only)

The repeatable Bicep target is documented in
`.azure\deployment-plan.md` and tasks T-701-T-712. It includes Log Analytics and
workspace-based Application Insights, not just APIM/App Gateway.
Owner-only Identity/Runtime bootstrap, offline Bicep foundation/private worker,
synthetic backend/bounded jobs and owner ACME tooling are
available as documented above; actual deployment/delivery/certificate execution
remain planned. Five OpenAPI 3.0.3
contracts and a stable inventory are
available under `infra\live-validation-lab\scenarios`: Supply Chain (3 operations),
E-commerce (4), PLM (3), Manufacturing (3) and Service Management (3).
Examples include shipment lines, order amounts, part revision/BOM, quality
inspection and service work orders. They contain no real data or credentials.
The `backend.invalid` servers are non-routable placeholders; T-706 will bind
the private backend, import APIs and enforce caller/product policies.

The inventory declares intended tests, not observed deployment results:
PLM has no public route, Manufacturing receives no initial traffic, and two
product contexts share Supply Chain/E-commerce. Service Management's
controlled-failure profile must be private-worker-only and disabled by default;
there is no public fault-toggle endpoint.
The offline-tested T-703 foundation defines a new VNet and four subnets; no existing
VNet is required. `.azure\deployment-plan.md` records parameterized sizing and
the selected Azure DNS ACME challenge delegation, with private overlap checks
and staging issuance required before actual use.

Validate the API contracts offline with the existing development gate:

```powershell
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\LabOpenApi.Tests.ps1
```

The optional pinned local Spectral toolchain performs OpenAPI/APIM-rule
validation when installed as documented under developer tooling; otherwise its
cases are explicitly skipped. JSON/reference/example/security assertions still
run without it. No command here deploys APIs, accesses Azure or obtains keys.
Owner-only T-114 provisioning and live
acceptance remain separate from the existing smoke command below.

The preparatory `scripts/Invoke-ApimSmoke.ps1` entry point exercises the sixteen
implemented collectors in fixed dependency order: Service, Apis, Products,
Subscriptions, SecurityAssets, Diagnostics, Policies, Network, Identity, Portal,
OpenApi, Organization, LogAnalytics, Metrics, Cost, and LogicApps. SecurityAssets
writes only allowlisted metadata: named-value values are dropped after in-memory
pattern detection, backend credential values are reduced to structural facts,
and certificate data/private material is never stored. Diagnostics writes only
allowlisted logger targets, header names, nullable body-byte counts, and bounded
settings; it drops credentials, descriptions, samples, data-masking details,
header values, and unknown fields. The same command will run newly registered
checks after their synthetic acceptance. A failure is recorded in the manifest,
independent checks continue, and dependent checks are Skipped; no false success
is reported. Exit status is 0 when all required collection checks complete and
optional skips validate against unconfigured targets, 1
for configuration/preflight failure, 2 for Az module/context failure, 3 when
collection is Partial, and 4 for an unexpected run, output-validation failure,
secret candidate, or incomplete secret scan.
Console output uses fixed statuses, check names, bounded failure codes, and
the safe coarse candidate table described below; it never echoes source
identifiers or matched values.
The command shows preflight steps, one numbered result row per registered
check, and a final completed-check count. An interactive terminal uses a
colored emoji scorecard that replaces its active `WORKING` row in place; the
console output encoding is temporarily set to UTF-8 for each rich write and
then restored. Redirected output and `NO_COLOR` keep the two-line ASCII event
feed without terminal cursor controls. If glyphs still
show as boxes, use an emoji-capable terminal/font (such as Windows Terminal)
or set `NO_COLOR` for a clean ASCII fallback.
To preview the rich banner without connecting to Azure, run this in the same
ordinary PowerShell terminal from the repository root:

```powershell
. .\scripts\Format-ApimSmokeConsoleLine.ps1
Write-ApimSmokeConsoleLine -Line (
    Format-ApimSmokeConsoleLine -State Header -Color
) -Color
```

The progress count covers checks, not individual APIs or operations; a check
may take time after its `collecting...` line. A failed/partial result includes
a fixed troubleshooting hint keyed to its bounded code, **not** an exception
message or stack trace. Future registered checks join the same progress count.
`ARM_HTTP_401`/`ARM_HTTP_403` indicate an ARM authorization response; check
the maintainer's local Reader access to the test service.
`ARM_HTTP_404` indicates the service request was not found; verify the APIM
name and resource group locally against the selected subscription.
Other `ARM_HTTP_<status>` codes report only the numeric status (429 and 5xx
are reported after retries). `ARM_NO_RESPONSE` means the guarded request
received no usable HTTP response **and** the underlying error did not match a
known category; it does not prove a network outage. `ARM_AUTH_ERROR` indicates
an Az authentication/permission error; check the local login and test-resource
access. `ARM_COMMAND_ERROR` indicates a missing cmdlet or invalid parameter;
check the locally installed Az module. `ARM_NETWORK_ERROR` indicates a network
exception; check local connectivity to Azure Resource Manager.
`ARM_TIMEOUT` indicates a timeout/cancellation; check connectivity and retry
policy locally. These codes never include exception text or raw responses.
Earlier smoke versions could show `ARM_COMMAND_ERROR` because a bodyless GET
passed an empty `-Payload` to `Invoke-AzRestMethod`. The current guarded
transport omits that parameter; rerun from the updated bugfix branch or its
merged successor before investigating a recurring command error.
`LOCAL_IO_ERROR` means a local write/read failed; check restricted storage
permissions and available space. `UNKNOWN_FAILURE` needs maintainer-only
investigation and does not imply that Azure returned success. Do not paste
private exception text, config, identifiers, logs, or raw output into Copilot.
`POLICY_XML_REJECTED` means the XML-encoded policy response still failed strict
parsing or used a prohibited document type; inspect the policy locally on the
Microsoft-owned test instance. Earlier sanitized policy files can exist while
Policies is Partial, but no complete policy index is written. Neither the
parser location nor policy content appears in smoke output.
The collector now preserves missing optional subscription display/tracing/date
metadata as null and runs separate Resource Graph queries for other front doors;
an older version can fail subscription validation or reject a multi-statement
graph query. A Partial policy check after an XML parse rejection is **not**
repaired automatically: the authorized maintainer should inspect the affected
policy locally in the Microsoft-owned test instance. Do not paste `$Error`,
policy XML, or returned Resource Graph diagnostics into Copilot.
After collection, the same script validates the exact new run locally: its
schema-valid completed manifest must agree with all registered check statuses,
the collection stage and untouched Analyze/Report stages. Every completed
check must have its required files and matching item counts; API/product
child collections, per-API diagnostics, network JSON files, and the policy
index and XML hashes are checked. Empty valid collections pass; missing
or malformed JSON, missing children, count mismatches, and changed policy
XML fail with `SMOKE_OUTPUT_INVALID` and exit 4. Completed checks, supported
Partial configuration checks, and Partial/Skipped telemetry are
validated on a Partial run, which remains exit 3 rather than becoming a
success. The terminal prints `SMOKE_OUTPUT_VALID` only after structural
validation; it never prints saved content, paths, identifiers, or private
validation exceptions. This is not independent content-safety certification,
rule evaluation, model creation, or workbook rendering.
Fresh smoke runs use manifest/settings 1.2 and the same implemented telemetry
collectors as public collection. Configured logs and costs run automatically;
metrics always run. Unconfigured LogAnalytics, Cost, and LogicApps are explicitly
Skipped without being relabeled as failures or successful execution. Baseline
prerequisite skips and incomplete/failed collectors still make the run Partial.
After saved-output validation, four `[QUERY]` lines show Completed, Partial,
Failed, or Skipped coverage for `appgwByListener`, `appgwNonEdge`,
`directNonAppGw`, and `headersLogged`. Differing workspace statuses aggregate to
Partial; no workspace IDs, counts, header values or raw diagnostics are printed.
A query may be Skipped even when LogAnalytics completes, for example when
trusted edge ranges or gateway targets are unconfigured. A skipped query has not
been live-validated. Legacy twelve-check saved smoke output remains valid.
The command then scans the whole newly saved run, including artifacts from
failed/Partial collectors. `SECRET_SCAN_PASS` is required before the final
PASS; `SECRET_SCAN_FAIL` (candidate found) or `SECRET_SCAN_ERROR` (scan incomplete)
returns exit 4 instead. A clean scan does not upgrade Partial collection to
success. No matched value, filename, private path, or exception detail is printed.
On `SECRET_SCAN_FAIL`, the next error line tells you to open the fixed
`secret-scan-locations.json` report in the newest run directory under the
private config's `Output.Root`. That report is restricted local output, not
model-safe data.
Restricted raw output, manifest, and logs stay under `Output.Root`. This is
**not** the full T-604 acceptance or a
customer assessment: Analyze, rules, reports, and model-data promotion are not
run. Do not pass live output, identifiers, errors, or logs to Copilot.
The maintainer's previously reported live smoke covered the original six checks;
the later configuration and telemetry checks still require a
maintainer-only live run on the Microsoft-owned test environment.

In Copilot CLI, these `!` commands are safe because they run only synthetic
offline tests and automatically include all current/future unit tests:

```text
! pwsh -NoProfile -File .\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\SmokeRunner.Tests.ps1
! pwsh -NoProfile -File .\scripts\Invoke-Checks.ps1
```

**Live smoke is maintainer-operated in an ordinary PowerShell terminal, never
in Copilot CLI or its `!` shell.** An authorized maintainer must choose a
Microsoft-owned test APIM (T-114), use Reader-level APIM/network permissions
and an existing Az login, and verify that the private configuration, restricted
`Output.Root`, and separate unused `Output.ModelSafeRoot` are external paths
outside the repository and **all** Copilot trusted/allowed directories. Install
`Az.Accounts`, `Az.ResourceGraph`, and (when workspaces are configured)
`Az.OperationalInsights` in the maintainer's PowerShell environment
using the organization's approved process; the smoke command never installs
modules or initiates a login.

In that separate terminal, from the repository root, prepare a private config:

```powershell
$private = Join-Path $HOME 'apim-smoke-private'
New-Item -ItemType Directory -Path $private -Force | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $private 'smoke.psd1'))) {
    Copy-Item .\config\sample.psd1 (Join-Path $private 'smoke.psd1')
}
```

Edit `smoke.psd1` **locally, outside Copilot**. Set the Microsoft-owned test
subscription ID, APIM name/resource group, an environment name such as `Test`,
only the relevant network groups/gateways (empty arrays if none), and absolute
non-overlapping external Output roots. Leave other required sample settings
valid. Never paste this file or its values into a prompt. Use a separately
approved storage location and retention policy for the restricted run.
To exercise the new query paths, configure the test workspace IDs, App Gateway
name/resource group, App Gateway subnet CIDRs, and trusted edge IPv4 ranges.
The workspace needs APIM and gateway diagnostic tables with usable retained
traffic. Configure test cost scopes and Logic Apps groups only when relevant.
The existing identity also needs authorized log-query and Cost Management read
access for configured targets; the script does not grant access or change Azure.

Sign in if needed (`Connect-AzAccount`) and select the intended subscription
using your normal Azure PowerShell workflow in that same terminal. Then run:

```powershell
.\scripts\Invoke-ApimSmoke.ps1 -Environment Test -MicrosoftOwnedTestEnvironment
```

The script prints its final PASS/FAIL/PARTIAL result and exit code itself,
including on preflight failures. A successful run ends with
`[SMOKE] PASS - collection and saved-output validation completed (exit code 0)`.
No follow-up shell command is required; the actual process exit code remains
available to automation.
The single script defaults to
`$HOME\apim-smoke-private\smoke.psd1`; if you use another private directory,
pass `-Config (Join-Path $private 'smoke.psd1')`. `Test` must match the
environment name in that config. Exit 0 requires all required checks and
validated unconfigured optional skips,
saved-output validation, and the secret scan to pass;
`SMOKE_OUTPUT_VALID` and `SECRET_SCAN_PASS` with exit 3 mean only
the completed checks' files validated and collection is still Partial.
The command refuses an unacknowledged target, repo-local config or output
roots, or a context whose subscription ID differs from the configured target.
If it stops while checking Private configuration, its bounded
`SMOKE_CONFIG_ERROR` category identifies the next local check:
`CONFIG_NOT_FOUND` means the `.psd1` file is absent at the default path
(or the explicit `-Config` path); `CONFIG_INVALID` means required fields,
types, linked output paths, or non-overlapping output roots failed validation;
`LOCATION_INVALID` means the config path is linked or the config/output roots
are inside the repository; `ENVIRONMENT_NOT_FOUND` means `-Environment` does
not match the private config. The sample config names its environment `Prod`; a renamed test
environment must be explicitly set to `Test` before using the sample command.
If the private folder also holds `Output.Root`, keep the separate
`Output.ModelSafeRoot` outside it, or put the two output roots in distinct
sibling folders under that private folder; the roots must not contain each
other. Resolve issues only in the maintainer's terminal; do not paste private
settings or exceptions into Copilot. Inspect the
restricted manifest and outputs locally in that terminal; do not print or share
them in Copilot. The bounded public assessment command does not change the smoke
command's maintainer-only contract or grant customer-run approval.

The internal policy collector reads the previously collected API, operation, and
product catalogs, discovers policy fragments, and writes restricted XML under
`policies/`. Missing policy scopes are represented in `policies/index.json`
instead of treated as failures. Potential hard-coded policy secrets are detected
before persistence; the index records structural locations only and stored XML
contains `***REDACTED***`, never the detected value.

The internal diagnostics collector reads the previously collected API inventory,
then calls the service logger and service diagnostic endpoints before issuing
bounded per-API diagnostic GETs. It writes `raw/loggers.json`,
`raw/diagnostics.json`, and one `raw/apiDiagnostics/<api>.json` file per API.
Logger output is restricted to name, logger type, target resource ID, and
buffering state. Diagnostic output is restricted to logger reference,
always-log, sampling, verbosity, client-IP/correlation settings, sorted header
names, and nullable body-byte counts. Missing sections remain `null`, while a
known empty header list remains `[]`; neither is converted to a false or zero
claim. Credentials, descriptions, payload samples, data-masking configuration,
header values, and unknown ARM fields are never persisted. Root logger and
service-diagnostic files are written before API children so a child failure
retains useful sanitized evidence and records Diagnostics as Partial.

The internal merge helper consumes only saved, redacted policy XML. It produces
one effective policy per product membership (or one no-product path), replaces
section-level `<base/>`, records missing-base scope and section, expands policy
fragments to depth five with cycle/missing guards, and retains structural
`data-scope` attribution. Unresolved fragment includes remain in the effective
XML with a `data-fragment-status` marker and a structured issue; they are not
silently treated as expanded.

The internal flag helper consumes effective policy XML and missing-base metadata.
It detects caller/backend authentication, throttling, IP/host restrictions,
unsafe CORS, hard-coded-secret markers, backend overrides, mock/trace behavior,
unconditional inbound responses, and missing inheritance. Evidence is structural
and deterministic; hard-coded-secret evidence contains locations only. Stored
`***REDACTED***` markers preserve the same flags produced before synthetic
redaction. Secret-bearing HTTP(S) URLs retain only their scheme plus the marker
so plain-HTTP risk remains visible without retaining host, path, query, fragment,
or credential data. Effective policies with unresolved fragments are marked
Partial so downstream models cannot treat absent detections as authoritative
negatives. Public Analyze connects these builders to validated saved raw evidence.

The internal API/operation model helper joins current API catalog records,
operations, revisions, tags, product memberships, and per-product policy flags.
It sorts records and memberships deterministically, invalidates a catalog backend
host when effective policy overrides the target, and represents unavailable
collector-derived values as `null` rather than false or zero. Every incomplete
record carries `modelStatus=Partial` and sorted `missingInputs`. The policy matrix
uses `Pass`, `Fail`, or `NA`: a detected risk remains `Fail`, while missing or
Partial evidence that prevents a decision becomes `NA`. All three model arrays
must pass their closed JSON schemas before the writer creates any files.

When diagnostic inputs are supplied, a non-empty per-API diagnostic collection
overrides the all-APIs collection for that API; an empty per-API collection
inherits the all-APIs settings. `bodyLogging` is true when any effective
frontend/backend request or response body-byte count is positive.
`sensitiveHeadersLogged` is true when effective frontend/backend request headers
include `Authorization`, `Ocp-Apim-Subscription-Key`, or `Cookie`,
case-insensitively. If no positive fact is present but a required normalized
section is missing, the field stays null and `diagnostics` remains in
`missingInputs`. Missing per-API child files likewise remain unknown even when
the service file exists, because an uncollected API override cannot be ruled
out.

## Local saved-run secret check

An authorized maintainer can check a previously saved run in an **ordinary
PowerShell 7.4+ terminal outside Copilot**. The run must be outside the repository;
never paste its files or the contents of a failed scan into a model.
Set `$runFolder` locally to the saved run directory, then run:

```powershell
.\scripts\Test-ApimRunSecrets.ps1 -RunFolder $runFolder
```

No Azure context, credentials, ImportExcel, or desktop Excel is needed. The
script prints a fixed `SECRET_SCAN_PASS`, `SECRET_SCAN_FAIL`, or
`SECRET_SCAN_ERROR` line and the exit code itself: 0 for no recognized pattern,
1 for a secret candidate, 2 when a complete scan could not be performed. It
requires a schema-valid run manifest and never modifies scanned source artifacts.
It creates or replaces only its own `secret-scan-locations.json` in the run root.
The report starts as `Incomplete`; only a completed scan changes it to `Clean`
or `CandidateDetected`. Its own generated report is excluded from rescans.

**Finding the candidate:** open the report locally when the console prints
`SECRET_SCAN_DETAILS`. Each entry has a relative `file`, a fixed `kind`, a
`location`, and optional `line`/`column`; Excel candidates also have a `part`.
Open the indicated file in a local editor. Plain text has one-based line/column,
logs have the one-based record line plus JSON pointer, JSON files have escaped
JSON pointers, and XML/workbook parts have positional XPath expressions (for
example, `/*[1]/*[2]/@*[1]`). Policies serialized in JSON/log strings combine
the JSON pointer with that XPath; log records retain their source line.
`decodedHtml` refers to entity-decoded text on the
specified source line. A secret-like property name is represented by a
zero-based `[member:N]` locator instead of copying that name. The report has no
captured values, excerpts, or exception messages, but paths can identify
infrastructure: **do not paste it, or the source file, into Copilot**.

`CandidateDetected` means a heuristic matched, not that a credential has been
confirmed. Verify that location locally before making any changes. The Basic
authorization heuristic requires a decodable username/password payload; prose
such as "Basic rule" is not a credential. Redacted values and full policy
references should remain clean. JWT `header-name="Authorization"` selects the
header to inspect; it does not supply a secret. Scheme-only authorization metadata
and descriptive "Bearer token" wording are also not candidates. These exceptions
do not exempt JWT policies: literal `token-value`, signing/decryption keys, and
real authorization values are still checked, including embedded JSON/log policies.
An `Incomplete` report is not a current list of
all candidates; resolve the scan error locally and rerun. It
may also be absent or stale if its initialization/write failed; the
`SECRET_SCAN_ERROR` message explicitly warns not to trust an old report.
The location report
is capped at 10,000 detections; reaching that limit fails the scan, not truncates
a success result. A clean rescan replaces the prior candidate list with an
empty list.

When candidates are found, both scripts also print a table immediately before
their final FAIL/exit-code line. Columns are `#`, `Artifact`, `Match`, `Line`,
and `Column`. These rows are newly shaped from an explicit allowlist and
validated before any table output; unknown fields, aliases, kinds, or positions
fail closed. An `artifact-0001` alias maps to the `artifactId` in report schema
1.1; `#` is the one-based position in its `locations` array. Multiple rows from
one file share an artifact alias. A dash means no physical source line/column
is available: use that report entry's JSON pointer/XML path/workbook part.
Full filenames, structured paths, excerpts, and values do not enter the
console table. Clean and incomplete scans do not print candidate tables.

Supported files are UTF-8 or BOM-marked UTF-16 `.json`, `.xml`, `.log`, `.jsonl`,
`.txt`, `.md`, `.html`, and `.xlsx`. Logs/JSONL must contain valid JSON records.
JSON strings/property names and XML attributes/text are decoded before checks.
Excel archives are read without extraction; every non-directory part must be
valid `.xml` or `.rels`, so embedded images/binaries/encrypted workbooks are
rejected, not silently ignored. Limits are 64 MiB per file and per expanded
workbook, and 16 MiB per workbook entry. Malformed, unreadable, linked,
unsupported, or oversized files fail closed. Stop other writers before scanning;
this check is not an atomic snapshot or promotion gate.

Checks cover recognizable JWTs, Bearer/Basic credentials, private-key PEM
blocks, credential-bearing URLs, and labeled key/password/secret values,
including connection-string credentials. Exact `***REDACTED***` markers, full
`{{named-value}}` references, and policy expressions are not literal credentials.
Plain metadata flags, IDs, and policy hashes are not treated as secrets solely
because of their length. A clean result is not proof that arbitrary unlabeled or
encoded credentials, customer identifiers, or other restricted data are absent.
This scanner is an accident-detection check, not redaction, remediation, or the
independent model-data airlock. It never authorizes sending a run to Copilot.

## Private offline model-data airlock

Only synthetic development commands are available; do not use the following
checks to admit customer data, inspect actual trust settings, or run collection:

```powershell
.\scripts\Invoke-Checks.ps1 -TestPath tests\unit\SyntheticReference.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath tests\unit\AnalysisPackage.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath tests\unit\AnalysisPackageValidation.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath tests\unit\AnalysisPackagePromotion.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath tests\integration\AnalysisAirlock.Tests.ps1
```

The private `New-ApimAnalysisPackage -RunPath -Config` helper loads the manifest,
all ten required baseline models, present portal/quality models, any requested
bound drift model, and saved findings,
then replays all implemented
rules. Missing/invalid artifacts, changed findings/scoring, unsupported mappings,
and tainted required identities reject with `ANALYSIS_BUILD_REJECTED`. It writes
new candidate/package and identifier-only alias-map files beneath
`restricted/candidates/<opaque-candidate-id>` in the run and returns only
`Built` plus the candidate ID. It does not update manifest orchestration state.
The candidate is restricted, not approved for an agent.

Version 1.1 supports six ascending usage thresholds starting at zero and
relative priority buckets; other threshold counts reject. `Zero` and `Unknown`
remain distinct. Cost trend is relative and stays `Unknown` without comparable
complete-month normalization; multiple currencies never produce a merged trend. Conditions
are approved codes for replay-verified deterministic rule outcomes; source
evidence text, labels, paths, policy XML, and exact usage/cost/priority are not
copied. Equivalent reordered inventories produce identical package/map bytes.
Changed inventories may renumber aliases. Version 1.0 contract input remains
supported by validation. Version 1.2 adds only the two approved drift condition
codes on existing service aliases; no exact Git/environment evidence is copied.

`Test-ApimAnalysisPackage -CandidatePath` independently reads at most 16 MiB,
checks strict UTF-8, closed contracts/references/depth, and a separate recursive
field-specific vocabulary/prohibited-value scan. Arbitrary or encoded text,
Unicode alternatives, exact metrics, unexpected fields/types, and scan errors
reject with `ANALYSIS_VALIDATION_REJECTED`, without echoing input or paths.
Passing returns a closed local attestation with the exact-byte SHA-256,
supported package schema, module-derived builder/validator compatibility
versions, and fixed check statuses. Attestations are bounded to 64 KiB/depth
eight with no duplicate members. They are not signatures or proof of origin.

`Publish-ApimAnalysisPackage` requires the restricted run root, candidate ID,
dedicated analysis root, private staging root, `version-NNNNNN`, and an explicit
complete host-supplied `CopilotVisiblePath` set with `VisibleRootsComplete`.
The host/operator must supply **all** visible roots; an empty/incomplete set
rejects. No host permissions are discovered, changed, or bypassed.
All three roots must be absolute, canonical, pairwise disjoint, and free of
linked ancestors. Restricted/staging roots must be outside every visible root.
Portable paths ending a segment in a dot/space are rejected; Windows UNC/device,
alternate-stream, reserved-device, and short-name forms are unsupported.
Existing analysis contents must be closed version directories containing only
validated package/attestation pairs; links, unrelated files, stale hashes, and
tampering reject. This requirement also prevents an existing link back to
restricted data from being ignored.

The helper copies only package bytes into a fresh uniquely owned private
snapshot, validates there, persists/rechecks attestation, rechecks isolation
and source/snapshot hashes, then performs a no-overwrite directory rename.
Staging must support rename on the destination filesystem; cross-filesystem or
non-atomic failures never fall back to partial copying. Only package and
attestation become visible together; alias maps, models, logs, and rejected
bytes never enter the analysis zone. Existing versions are never overwritten.
Failures return `ANALYSIS_PROMOTION_REJECTED`; failed owned-stage cleanup returns
`ANALYSIS_CLEANUP_REJECTED`, requiring host-side inspection, not model access.

The host must exclusively control roots and ancestors through permissions/ACLs,
stop other writers, and retain the private staging area outside model-visible
paths. Supply native canonical physical roots, including every visible alias;
mapped/substituted drives and network/virtualized filesystems are unsupported.
API-level immutability and hash/path rechecks do not protect against a
hostile concurrent administrator or replace filesystem isolation. Real approved
paths, actual host-enforced agent tool isolation and owner-led G3 acceptance
remain outstanding. The narrow broker now invokes these helpers and rechecks
attestation/hashes on every read; standalone package root-script facades remain
planned.

## Offline model fixture check

The private model path can be validated without Azure access:

```powershell
Invoke-Pester .\tests\unit\ApiPolicyModel.Tests.ps1 -Output Detailed
```

The tests use only the customer-neutral synthetic fixture, exercise persisted
`model/apis.json`, `model/operations.json`, and `model/policyMatrix.json` in a
temporary test drive, and verify fail-closed schema handling. This is a
development check, not an operator assessment command.

## Shared model schema gate

The private model writers serialize pending outputs once, validate every
snapshot against its registered closed schema, check destinations for links, and
only then persist those same snapshots. Schema failure leaves existing outputs
unchanged; individual writes remain atomic, but a later I/O failure is not a
multi-file transaction.

The private saved-run loader requires `service.json`, `apis.json`, `operations.json`,
`policyMatrix.json`, `subscriptions.json`, `namedValues.json`, `backends.json`,
`certificates.json`, `network.json`, and `exposure.json` under `model`. It
returns no models until all ten validate. Present optional portal and
source/settings-bound quality models and requested bound drift are validated too.
Missing/invalid files, unavailable schemas, and linked paths fail closed.
Explicit null/Partial/missing-input metadata remains intact, as do empty and
singleton arrays. Future model contracts join the gate with their builders.

The shared gate can be checked offline with synthetic fixtures:

```powershell
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\ModelSchema.Tests.ps1
```

This runs repository lint plus focused gate acceptance tests, without Azure
access. The helpers remain private and are used by the deterministic stages.

## Security asset models

The private security-asset model helper transforms the allowlisted collected
payloads into three sorted, closed arrays. `model/namedValues.json` contains
secret classification, Key Vault status, structural secret-pattern locations,
and a derived plain-text risk flag; named-value values are never present.
`model/backends.json` contains only scheme, nullable HTTPS certificate
validation facts, credential presence, and resilience flags. HTTP backend TLS
facts are normalized to null because certificate validation is not applicable.
`model/certificates.json` contains normalized expiry, Key Vault-backed status,
and completeness metadata without certificate bytes or private material.

The customer-neutral security model path can be checked offline:

```powershell
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\SecurityAssetModel.Tests.ps1
```

## Subscription metadata boundary

The internal subscription collector calls only the APIM subscription list
endpoint through the guarded GET transport. It never calls `listSecrets`.
Persisted `raw/subscriptions.json` contains only subscription ID, display name,
scope, state, derived `ownerType`, dates, and `allowTracing`. Subscription keys,
`ownerId`, user identifiers, and unknown response fields are dropped before
persistence. `ownerType` is limited to `BuiltIn`, `User`, `None`, or `Unknown`.

The private subscription model derives AllApis/Product/Api scope and target,
detects `master` at AllApis scope as the built-in master, and writes sorted
flags from `AllApis`, `AllowTracing`, `BuiltInMaster`, `NoExpiration`, and
`OwnerMissing`. Until subscription usage telemetry is implemented, `calls90d`
and `lastUsed` are `null` and each record explicitly reports
`modelStatus=Partial` with `missingInputs=["usage"]`.

The customer-neutral subscription path can be checked offline:

```powershell
Invoke-Pester .\tests\unit\SubscriptionCollector.Tests.ps1,`
  .\tests\unit\SubscriptionModel.Tests.ps1 -Output Detailed
```

## Network evidence and direct reachability

The internal network collector reads configured Application Gateways and their
linked WAF policies through `Invoke-ApimArm` GET requests. It uses fixed
`Search-AzGraph` queries for the APIM subnet, NSGs, public IPs, private
endpoints, private DNS zones, route tables, and other configured-scope front
doors whose properties target an APIM hostname or address. Every response is
staged before restricted `raw/network/*.json` files are written; a failed ARM or
Resource Graph call marks the collector Failed rather than emitting a complete
success shape.

The private network model writes one closed-schema `model/network.json` object.
It honors NSG rule priority when deciding whether a broad Internet/any-source
allow reaches TCP 443, records positive direct-public reasons, and aggregates
multiple App Gateway TLS/WAF configurations conservatively. Missing subnet, NSG,
public-IP, or front-door evidence leaves `directPublic=null` with
`modelStatus=Partial`; it is never treated as restricted or safe by default.
The builder also accepts optional, in-memory `-OperatorEvidence` with exactly
`edgeRangesOnly` (Boolean or null), `originAuthentication`
(`Present`/`Absent`/`Unknown`), and `auxiliaryRoutes` (null or a complete
array of `routeKey`, `endpointType`=`Portal`/`Management`,
`publicListener` Boolean, and `ownerNeed`=`Needed`/`NotNeeded`/`Unknown`).
Only an authorized operator can corroborate these facts, including all
effective listener, WAF, NSG, and APIM-policy authentication paths and the
endpoint owner's need. They are *not* inferred from absent Azure resources or
missing policy evidence. Each supplied fact is labeled `OperatorAttestation`
in the restricted model; unknowns stay null/Unknown. This is a private model
input, **not** a live collection or public operator command. Never paste
private evidence or restricted model output into Copilot.

The customer-neutral network path can be checked offline:

```powershell
Invoke-Pester .\tests\unit\NetworkCollector.Tests.ps1,`
  .\tests\unit\NetworkModel.Tests.ps1 -Output Detailed
```

## Exposure classification

The private exposure model reads saved APIs, operations, the network model,
ARM-shaped Application Gateway configuration, and effective policy-path
evidence. It emits one closed-schema route-by-API record, treats Basic routing as
host-wide `/*`, resolves path maps and one unconditional literal path rewrite,
and fails unresolved rewrites to `Unknown` with Low confidence. Backend pools
must target the APIM gateway host or address. Direct-public evidence overrides
normal route matching.

Restrictions are evaluated on each operation/product path. IP allow/forbid
ranges and structural 403/404 host checks can classify a reachable route as
Restricted; an unrestricted product path remains authoritative when missing
inbound `<base/>` bypasses a restriction. JWT and mTLS do not change
reachability. Until P4 supplies route usage, reachable unrestricted routes stay
`exposure=Unknown`, `confidence=Medium`, and `missingInputs=["usage"]`; the
optional usage hook accepts complete normalized `apiId`/`route`/`calls` rows
where route is `ViaAppGw` or `Internal`, and only then distinguishes
`ExternalInUse` from `ExternalUnintended`. Incomplete telemetry remains Unknown.
The writer validates both `model/exposure.json` and the back-filled
`model/apis.json` before writing either file.

The customer-neutral exposure path can be checked offline:

```powershell
Invoke-Pester .\tests\unit\ExposureModel.Tests.ps1,`
  .\tests\unit\PolicyFlags.Tests.ps1 -Output Detailed
```

## Future operator requirements

Authorized maintainers will use an existing Azure login, least-privilege Reader
access, validated local configuration, a customer-approved restricted output
location, and a separate non-overlapping model-safe analysis location. Agents/CI
use synthetic fixtures instead. Do not store secret values or tokens, do not
upload customer outputs, and delete run data after the agreed readout.

On the admitted Copilot-assisted path, agents receive only a locally
validated and promoted `analysis-package.json` through narrow tools. They must
not receive raw/model run data, alias maps, Azure command output, exact metrics,
customer/infrastructure identifiers, credentials, or arbitrary filesystem access.
The deterministic collection, analysis, Excel, and HTML paths remain
available without Copilot.

As each pipeline stage becomes available, add its tested commands, resume/skip
options, manifest interpretation, troubleshooting, and implemented exit codes
here. The bounded public commands implement exit codes 0-4 as documented above;
future capabilities must not be advertised as implemented.
