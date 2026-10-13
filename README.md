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
service/API/product/subscription/policy/network collectors, but exports no
assessment commands.
Effective policy inheritance, fragment expansion, scope attribution, and
normalized hashing plus deterministic policy-flag extraction are implemented as
private offline model helpers. Private schema-validated builders now produce the
API, operation, policy-matrix, subscription, network, and pre-telemetry exposure
model records from saved inputs. Remaining collectors and models, telemetry-based
exposure refinement, rules, the
model-data airlock, Copilot operator workflow, CLI entry points, and report
templates are not implemented.

All six implemented model contracts now share a fail-closed schema gate.
Writers validate every pending serialized snapshot before writing any file, and
the private saved-run loader requires all six files to validate before returning
models for downstream analysis. Future model contracts remain deferred with their
builders; this gate is not a public Analyze command or the model-data airlock.

| Available | Planned |
|---|---|
| Module manifest and deterministic source loader | Remaining run orchestration and collectors |
| Strict private configuration validation | Public assessment entry points |
| Structured JSON-lines logging and progress | Run resume and persisted progress orchestration |
| Guarded ARM transport with paging/retry | Excel report, carry-forward, and run comparison |
| Versioned run manifest lifecycle and APIM service/API/product/subscription/policy/network collectors | Remaining APIM, telemetry, and cost collectors |
| Effective policy merge/flags plus six implemented models with shared schema-gated persistence and saved-run loading | Remaining model builders, telemetry exposure refinement, and rule engine |
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

The dependency installer installs pinned Pester 5.x and PSScriptAnalyzer versions
from PowerShell Gallery into the current user's module directory; administrator
rights are not needed. Validation is offline and does not authenticate to Azure.
Results are written to the ignored `artifacts` directory.

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

Subscription collection uses one guarded list request and persists only an
explicit metadata allowlist. It never calls `listSecrets`, drops key fields and
unknown response fields, derives only a non-identifying `ownerType`, and does not
persist `ownerId` or user identifiers.

Network collection reads configured Application Gateways and linked WAF policies
through the guarded GET transport, then runs fixed `Search-AzGraph` queries for
the APIM subnet, NSGs, public IPs, private endpoints, private DNS zones, route
tables, and other APIM-targeting front doors. The collector stages all responses
before writing restricted raw files. It never invokes an Azure write operation,
and automated tests mock both ARM and Resource Graph.

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

The shared gate validates only explicitly registered model names and persists
the exact JSON snapshots that passed validation. Saved-run loading validates the
API, operation, policy-matrix, subscription, network, and exposure files as a
complete set without returning partial output on failure. Empty model arrays
remain arrays; missing files, invalid shapes/fields, unavailable schemas, and
linked paths are rejected. Writes are atomic per file, not transactional across
the set if an I/O failure occurs after validation.

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
rules/                      Rule catalogs (planned)
queries/                    Log Analytics and Resource Graph KQL (planned)
schemas/                    Versioned JSON contracts (manifest and six models implemented)
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
