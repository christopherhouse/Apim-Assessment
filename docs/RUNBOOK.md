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
service, named-value, backend, certificate, network, and pre-telemetry
exposure records from saved synthetic-equivalent inputs. A private rule engine,
seven NET catalog entries, fifteen model-backed
SEC catalog entries, six model-backed GOV catalog entries, all six REL catalog
entries, a closed findings schema, and private closed action-item aggregation
plus a customer-neutral generated Excel action-plan template are available for
offline synthetic testing. A private report writer can populate the current
deterministic workbook sheets from a validated saved run. Four bounded public
commands now connect collection, offline analysis, and paired Excel/HTML
reporting, including validated resume. A synthetic-tested narrow stdio broker,
four broker-only assessment profiles, semantic output validation and four
operator skills are implemented. Remaining collectors/models, telemetry-based
exposure refinement, rule catalogs and run comparison are not implemented.
Actual clean Copilot-session/tool isolation, approved roots/ACLs, organization
approval and visual/live G3 acceptance remain owner gates.

All ten implemented model contracts share a private schema gate for pending
writes and complete saved-run loading. Private findings are validated against
`schemas/findings.schema.json` before restricted persistence. This does not add
authorization for model/findings access to an agent.

Closed schema version 1.0 contracts and a private in-memory reference gate are
also available for synthetic tests. They validate opaque aliases, approved
fact/narrative codes, typed usage buckets/cost trends, unique IDs, citations,
and executive assumption/data-gap carry-forward. Private version 1.1 package
construction, independent privacy validation, local attestation, and immutable
atomic promotion are also implemented and synthetic-tested. The broker invokes
these private helpers; standalone root package/promotion facades remain planned.
No customer data is approved for model access by a schema/reference pass.

Do not run the planned commands in specification section 14 until their tasks
are implemented, tested, and marked available in the root README.

## Implemented deterministic workflow

Collection is authorized-maintainer-only in an ordinary local terminal, with
existing Reader access and matching Azure context. Never launch it through a
coding agent, `!`, or CI. Store private configuration and restricted runs in
approved external locations. I-05/I-06 and live G3 remain owner gates.

Prerequisites: PowerShell 7.4+, Az.Accounts and Az.ResourceGraph for collection;
ImportExcel 7.8.10 for Excel rendering. Use the dependency installer for the
pinned local Excel dependency, not Azure authentication. The runtime does not
log in, switch subscriptions, retrieve credentials, or install Azure modules.

```powershell
# In an authorized ordinary PowerShell terminal; not Copilot CLI.
.\Invoke-ApimAssessment.ps1 -Config <private-config.psd1> -Environment Prod
.\Invoke-ApimAssessment.ps1 -Config <private-config.psd1> -Environment Prod -Stage Collect
.\Invoke-ApimCollect.ps1 -Config <private-config.psd1> -Environment Prod -ThrottleLimit 4
.\Invoke-ApimCollect.ps1 -Config <private-config.psd1> -Environment Prod -Resume <run-folder>

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
SecurityAssets, Diagnostics, Policies, and Network. It accepts only
Cloudflare/AssumedReachable edge settings and six increasing usage thresholds.
`-SkipCost`, `-SkipLogs`, and `-SkipGit` confirm default exclusions of future
cost, Log Analytics queries, and Git collection. Diagnostic settings are still
collected. Explicit `:$false` on those switches is rejected. `-PreviousReport`,
Analyze's `-RulesPath`/`-OnlyRules`/`-CompareRuns`, and comparison commands
remain unavailable; none silently falls back to a speculative capability.

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
finding, including evidence, before writing a workbook.

| Exit | Meaning and local action |
|---|---|
| 0 | Implemented requested stages completed; this is not owner/live approval. |
| 1 | Invalid config or unavailable requested capability; check settings/options locally. |
| 2 | Az modules or matching existing context unavailable; maintainers resolve outside Copilot. |
| 3 | Collection has Failed/Partial/Skipped checks; inspect the restricted manifest/log and resume. |
| 4 | Analysis/report/runtime-state failed; inspect saved input/schema/stage state locally. |

An Assessment run preserves exit 3 if downstream stages succeed, but returns 4
if a requested downstream stage fails. Collector failure records remain intact.
No broker or model-safe access is enabled by these commands.

Offline acceptance uses compact synthetic raw fixtures: two APIs, two
operations, two products, six subscriptions, three named values, two backends,
two certificates, eight indexed policies, and nine network files. The separate
60-API generator produces saved models, not a scaled raw collector run.

```powershell
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\CollectionResume.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\RuntimeEntryPoint.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\integration\OperationalRuntime.Tests.ps1
```

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

These commands do not connect to Azure. The module exports four implemented
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

`rules/GOV.rules.ps1` includes GOV-001/002/005/006/008/010. These rules use
closed API and operation facts only. GOV-006 flags unversioned APIs and complete
version sets with one known version; an incomplete set is NotEvaluated unless
another known positive exists. GOV-008 emits one service-level finding with
bounded convention counts rather than one row per API. GOV-010 preserves a
known missing-`<base/>` operation finding when another policy is Partial.
GOV-003 and GOV-009 remain unavailable until product ownership/approval and
diagnostic enablement/sampling are modeled.

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
writer below consumes its output; tracking carry-forward remains T-507.

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
resort action rows. Usage, Cost, and Environment Drift are intentionally empty
pending their owning tasks. The generated workbook is restricted customer
output and must never be sent to Copilot or another model.

## Reusable collection smoke (Microsoft-owned test APIM only)

The preparatory `scripts/Invoke-ApimSmoke.ps1` entry point exercises the eight
implemented collectors in fixed dependency order: Service, Apis, Products,
Subscriptions, SecurityAssets, Diagnostics, Policies, Network. SecurityAssets
writes only allowlisted metadata: named-value values are dropped after in-memory
pattern detection, backend credential values are reduced to structural facts,
and certificate data/private material is never stored. Diagnostics writes only
allowlisted logger targets, header names, nullable body-byte counts, and bounded
settings; it drops credentials, descriptions, samples, data-masking details,
header values, and unknown fields. The same command will run newly registered
checks after their synthetic acceptance. A failure is recorded in the manifest,
independent checks continue, and dependent checks are Skipped; no false success
is reported. Exit status is 0 when all registered collection checks complete, 1
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
schema-valid completed manifest must agree with all eight check statuses,
the collection stage and untouched Analyze/Report stages. Every completed
check must have its required files and matching item counts; API/product
child collections, per-API diagnostics, network JSON files, and the policy
index and XML hashes are checked. Empty valid collections pass; missing
or malformed JSON, missing children, count mismatches, and changed policy
XML fail with `SMOKE_OUTPUT_INVALID` and exit 4. Only completed checks are
validated on a Partial run, which remains exit 3 rather than becoming a
success. The terminal prints `SMOKE_OUTPUT_VALID` only after structural
validation; it never prints saved content, paths, identifiers, or private
validation exceptions. This is not independent content-safety certification,
rule evaluation, model creation, or workbook rendering.
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
the newly registered SecurityAssets and Diagnostics checks still require a
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
`Az.Accounts` and `Az.ResourceGraph` in the maintainer's PowerShell environment
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
environment name in that config. Exit 0 requires all eight checks,
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
all ten registered models, and saved findings, then replays all implemented
rules. Missing/invalid artifacts, changed findings/scoring, unsupported mappings,
and tainted required identities reject with `ANALYSIS_BUILD_REJECTED`. It writes
new candidate/package and identifier-only alias-map files beneath
`restricted/candidates/<opaque-candidate-id>` in the run and returns only
`Built` plus the candidate ID. It does not update manifest orchestration state.
The candidate is restricted, not approved for an agent.

Version 1.1 supports six ascending usage thresholds starting at zero and
relative priority buckets; other threshold counts reject. `Zero` and `Unknown`
remain distinct. Cost is `Unknown` until a cost model is implemented. Conditions
are approved codes for replay-verified deterministic rule outcomes; source
evidence text, labels, paths, policy XML, and exact usage/cost/priority are not
copied. Equivalent reordered inventories produce identical package/map bytes.
Changed inventories may renumber aliases. Version 1.0 contract input remains
supported by validation.

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
returns no models until all ten validate. Missing/invalid files, unavailable
schemas, and linked paths fail closed; other run artifacts are not loaded.
Explicit null/Partial/missing-input metadata remains intact, as do empty and
singleton arrays. Future model contracts join the gate with their builders.

The shared gate can be checked offline with synthetic fixtures:

```powershell
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\ModelSchema.Tests.ps1
```

This runs repository lint plus focused gate acceptance tests, without Azure
access. The helpers remain private until public orchestration is implemented.

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
