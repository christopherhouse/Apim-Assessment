# APIM Assessment Toolkit

A customer-neutral, **read-only** Azure API Management assessment system:
deterministic PowerShell performs **Collect -> Analyze -> Render**, while a
constrained GitHub Copilot workflow performs **Review -> Synthesize** over an
independently validated, model-safe package. Planned outputs include versioned
JSON evidence, deterministic findings, an Excel action plan, a self-contained
HTML executive presentation, and run comparisons.

## Current status

**Collection and deterministic-model foundation only; not yet an operational assessment
tool.** The
module imports and contains private configuration validation, structured logging,
a guarded ARM transport, schema-validated run persistence, and internal APIM
service/API/product/subscription/policy/network collectors plus allowlisted
named-value/backend/certificate and logger/diagnostic collectors, but exports no
assessment commands.
Effective policy inheritance, fragment expansion, scope attribution, and
normalized hashing plus deterministic policy-flag extraction are implemented as
private offline model helpers. Private schema-validated builders now produce the
service, API, operation, policy-matrix, subscription, named-value,
backend, certificate, network, and pre-telemetry exposure model records from
saved inputs. A private
offline rule engine now loads rule
definitions, evaluates available model-backed scopes, and validates deterministic
findings against a closed schema before restricted persistence. A private
report helper groups schema-valid findings into closed, deterministic action
items without removing the instance rows needed by future Finding Details.
Seven NET rules,
fifteen currently model-backed SEC rules, six currently model-backed GOV rules,
and all six REL rules are implemented privately. NET-001
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
and models, telemetry-based exposure refinement, the rest of the SEC catalog,
the remaining GOV and other rule catalogs, the model-data airlock, Copilot
operator workflow, assessment CLI entry points, public report command, and
executive HTML template are not implemented. A private offline Excel writer now
populates the implemented deterministic report sheets, Run Info, the implemented
rule catalog, and editable scoring weights from a validated saved run, but no
public command invokes it.

An independent, **maintainer-only collection smoke command** now exercises all
eight implemented collector checks in dependency order against a Microsoft-owned test
APIM. It is not an assessment entry point or a customer-run command: it cannot
analyze or report, and its live execution is owned by authorized maintainers
outside Copilot CLI. The maintainer reports the prior six checks completed on a
test APIM; the newly registered SecurityAssets and Diagnostics checks have
synthetic acceptance but still need maintainer-only live validation. No agent
used live Azure resources or inspected restricted output.
The same smoke script now validates the newly saved manifest, completed
collector file inventories, JSON collection shapes and item counts, and policy
index/XML hashes before reporting a completed smoke. Validation failures return
a fixed safe code and do not print restricted content. This is structural
collection validation, not a full analysis, privacy audit, or report check.
The smoke command also runs the local saved-run secret scanner before its final
PASS. A separate maintainer-only script can scan an existing run, including
compressed XML parts in its Excel reports. Both print safe statuses and, on
candidates, a final table with row numbers, artifact aliases, match kinds,
and available line/column positions;
secret candidates and incomplete scans fail without printing values or paths.
The commands write a restricted `secret-scan-locations.json` inside the run and
point to it when candidates are found. It lists relative files, match categories,
and source locations, never matched values or excerpts.

All ten implemented model contracts now share a fail-closed schema gate.
Writers validate every pending serialized snapshot before writing any file, and
the private saved-run loader requires all ten files to validate before returning
models for downstream analysis. Future model contracts remain deferred with their
builders; this gate is not a public Analyze command or the model-data airlock.

| Available | Planned |
|---|---|
| Module manifest and deterministic source loader | Remaining run orchestration and collectors |
| Strict private configuration validation | Public assessment entry points |
| Structured JSON-lines logging and progress | Run resume and persisted progress orchestration |
| Guarded ARM transport with paging/retry | Public report command, carry-forward, and run comparison |
| Versioned run manifest lifecycle with an exact scoring snapshot, plus APIM service/API/product/subscription/policy/network and secret-safe named-value/backend/certificate and logger/diagnostic collectors | Remaining APIM, telemetry, and cost collectors |
| Maintainer-only cumulative collection smoke script with local output validation (eight registered checks) | Full assessment orchestration and live acceptance |
| Local saved-run secret-scan script for supported text and Excel artifacts, also required by smoke | Independent model-safe package validation and promotion |
| Effective policy merge/flags plus ten implemented models with shared schema-gated persistence and saved-run loading | Remaining model builders and telemetry exposure refinement |
| Private offline rule engine, seven NET checks, fifteen SEC checks, six GOV checks, all six REL checks, configurable priority scoring, schema-gated findings, and closed action-item aggregation | Remaining SEC/GOV catalog entries, PERF and other catalogs, public Analyze orchestration, and Excel rendering |
| Generated customer-neutral Excel template plus private validated-run population for actions, findings, APIs, policy, subscriptions, exposure, network summary, Summary assumptions, Run Info, rule catalog, and editable scoring weights | Public workbook rendering, tracking carry-forward, and future usage/cost/drift population |
| Synthetic-fixture scaffold | Populated fixtures and offline integration pipeline |
| Windows/Linux lint and test CI | Model-data airlock and local Copilot broker |
| Copilot development instructions, agents, and skills | Assessment analyst agents and operator skills |
| Guarded SemVer tag/release workflow | v1.0 acceptance against the technical specification |
|  | Architecture/exposure, security, and executive synthesis agents |
|  | Self-contained HTML executive presentation |

The authoritative scope and progress are in
[the specification](docs/APIM-Assessment-Spec.md),
[the project plan](docs/APIM-Assessment-Project-Plan.md), and
[the task register](docs/APIM-Assessment-Task-Register.md).

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
directory; administrator rights are not needed. ImportExcel is used to generate
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

The full collection runtime will use `Az.Accounts`,
`Az.ResourceGraph`, `Az.OperationalInsights`, `Az.Monitor`, and `ImportExcel`.
Optional OpenAPI linting will use Node.js and Spectral. They are not needed to
import or validate the current core module. The implemented collectors call the
guarded ARM transport; API/product/policy child requests use bounded parallel
runspaces with a configurable `ThrottleLimit` (default 6). Policy 404 responses
are indexed as absent, while detected hard-coded secret candidates are recorded
by structural location and redacted before XML is persisted. No public command
invokes the collectors yet and all automated tests mock Azure responses.
The guarded transport omits `-Payload` entirely for bodyless GET requests;
an explicitly empty payload fails before the Az cmdlet is called.
Policy collection requests XML-encoded policy content, parses it strictly,
redacts secret candidates before storage, and remains Partial if any policy
cannot be safely parsed. Previously sanitized policies may already be stored;
an incomplete run has no complete policy index.

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
There is no public
evaluation command, report, or model-safe promotion yet; do not expose these
private findings or models to an agent.

The six private GOV checks use only complete API catalog and effective-policy
facts for product membership, owner tags, online non-current revisions,
version-set maturity, path-version convention consistency, and missing
`<base/>` inheritance. Known missing-base findings remain evaluated when another
operation is Partial; otherwise incomplete version or policy evidence produces
one Info/NotEvaluated result. Product ownership/approval and diagnostic
enablement/sampling remain deferred to their own closed models.

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
tracking fields for future carry-forward. Inconsistent same-rule metadata fails
closed. Action items are validated against `schemas/actions.schema.json` and
sorted by maximum priority then rule ID. This helper performs report shaping
only; the separate private workbook writer consumes it, and no public report
command exists yet.

The checked-in `template/ApimActionPlan.xlsx` is generated by
`scripts/New-ApimActionPlanTemplate.ps1` with pinned ImportExcel. It contains the
fixed Summary and report sheets, twelve named empty tables, navy title bands,
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
retain their original deterministic order. Usage, Cost, and Environment Drift
remain empty until their owning tasks. Generated reports can contain customer
and infrastructure identifiers and must never be provided to a model.

The subscription model classifies AllApis/Product/Api scope, extracts a stable
scope target, detects the built-in master subscription, and emits sorted
risk/context flags. Usage-dependent `calls90d` and `lastUsed` remain `null` with
`modelStatus=Partial` and `missingInputs=["usage"]` until telemetry is
implemented. Its array is also closed-schema validated before persistence.

The closed single-object network model evaluates the effective priority of broad
inbound NSG rules on port 443, identifies positive direct-public paths, and
aggregates App Gateway TLS and WAF posture conservatively. The synthetic Internal
VNet fixture with an App Gateway-subnet allow and deny-all fallback evaluates
`directPublic=false`. Missing reachability evidence produces
`directPublic=null`, `modelStatus=Partial`, and sorted `missingInputs` rather than
a success-shaped false result.

The optional operator experience will use GitHub Copilot CLI repository agents
and skills through a narrow local broker. The deterministic collection, analysis,
Excel, and HTML paths will remain runnable without Copilot.

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

The private configuration loader can validate an ignored copy of
`config/sample.psd1`, but no public assessment command consumes it yet. Planned
invocation and exit-code contracts are in the specification's section 14; those
entry points are **not available**.

## Data handling

Use **synthetic fixtures only** for development and automated tests. Never commit
customer or engagement names, real-person names, customer configurations,
tenant/subscription/workspace identifiers from real environments, assessment
outputs, credentials, subscription keys, or secret values.
Only `config/sample.psd1` and `config/README.md` are tracked under `config`.
The conventional local `runs` and `model-safe` directories are ignored; future
public orchestration will create run folders under the configured external roots
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
  Model/                    Policy merge/flags, six model builders, shared schema gate
  Rules/                    Rule engine and priority scoring
  Package/                  Model-safe package construction, validation and promotion (planned)
  Report/                   Excel/HTML export and tracking carry-forward
rules/                      Implemented and planned rule catalogs
queries/                    Log Analytics and Resource Graph KQL (planned)
schemas/                    Versioned JSON contracts (manifest and nine models implemented)
template/                   Excel and HTML presentation templates (planned)
config/                     Tracked sample; ignored local configurations
tests/
  unit/                     Offline Pester tests
  integration/              Offline pipeline tests (planned)
  fixtures/synthetic-reference/  Synthetic reference-topology fixture scaffold
scripts/                    Branch guard, validation and release packaging
docs/                       Specification, plan, register and operating guides
.github/
  agents/                   Development plus planned assessment specialist profiles
  skills/                   Task/rule authoring plus planned operator workflows
  workflows/                CI, Copilot setup, and SemVer release
```

The five assessment entry scripts named in the specification will be added when
their stages are implemented, rather than exposing nonfunctional commands now.

## Copilot-assisted development

[Repository instructions](.github/copilot-instructions.md) define the safety
boundary, branch policy, architecture, tests, and documentation requirements.
The `apim-implementer` agent handles bounded implementation tasks; the
`assessment-reviewer` agent provides read-only contract and correctness reviews.
Those profiles review repository changes; they are not the planned customer
assessment analysts. Planned operator profiles separately cover APIM
architecture/exposure, security, and executive synthesis and will receive only a
validated model-safe package. Project skills currently cover task lifecycle and
rule authoring; planned skills will orchestrate assessment, package analysis,
deliverable generation, and validation. See
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
