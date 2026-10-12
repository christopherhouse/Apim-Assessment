# APIM Assessment Toolkit

A customer-neutral, **read-only** Azure API Management assessment system:
deterministic PowerShell performs **Collect -> Analyze -> Render**, while a
constrained GitHub Copilot workflow performs **Review -> Synthesize** over an
independently validated, model-safe package. Planned outputs include versioned
JSON evidence, deterministic findings, an Excel action plan, a self-contained
HTML executive presentation, and run comparisons.

## Current status

**Core foundation only; not yet an operational assessment tool.** The module
imports and now contains private configuration validation, structured logging,
and a guarded ARM transport, but exports no assessment commands. Collectors,
models, rules, run persistence, the model-data airlock, Copilot operator workflow,
CLI entry points, and report templates are not implemented yet.

| Available | Planned |
|---|---|
| Module manifest and deterministic source loader | Run persistence and collectors |
| Strict private configuration validation | Public assessment entry points |
| Structured JSON-lines logging and progress | Policy merge, exposure model, and rule engine |
| Guarded ARM transport with paging/retry | Excel report, carry-forward, and run comparison |
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
This bootstrap does not change GitHub repository settings.

## Intended runtime and permissions

When collection is implemented, the runtime modules will be `Az.Accounts`,
`Az.ResourceGraph`, `Az.OperationalInsights`, `Az.Monitor`, and `ImportExcel`.
Optional OpenAPI linting will use Node.js and Spectral. They are not needed to
import or validate this initial skeleton.

The optional operator experience will use GitHub Copilot CLI repository agents
and skills through a narrow local broker. The deterministic collection, analysis,
Excel, and HTML paths will remain runnable without Copilot.

Operators will supply an existing `Connect-AzAccount` context. Intended access is
Reader on the APIM and network resource groups, Log Analytics Reader on the
workspaces, and Cost Management Reader on configured cost scopes. The toolkit
will neither retain authentication tokens nor perform Azure remediation.

Copy `config/sample.psd1` to an ignored customer-specific file only when the
configuration loader is implemented. Planned invocation and exit-code contracts
are in the specification's section 14; those entry points are **not available**
in this bootstrap.

## Data handling

Use **synthetic fixtures only** for development and automated tests. Never commit
customer configurations, tenant/subscription/workspace identifiers from real
environments, assessment outputs, credentials, subscription keys, or secret values.
Only `config/sample.psd1` and `config/README.md` are tracked under `config`.
The conventional local `runs` and `model-safe` directories are ignored; the
runtime will create configured output paths when persistence is implemented.

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
  Core/                     Config, ARM guard, persistence, logging, retries
  Collect/                  Isolated read-only collectors
  Model/                    Normalization, policy merge, exposure and drift
  Rules/                    Rule engine and priority scoring
  Package/                  Model-safe package construction, validation and promotion (planned)
  Report/                   Excel/HTML export and tracking carry-forward
rules/                      Rule catalogs (planned)
queries/                    Log Analytics and Resource Graph KQL (planned)
schemas/                    Versioned JSON contracts (planned)
template/                   Excel and HTML presentation templates (planned)
config/                     Tracked sample; ignored local configurations
tests/
  unit/                     Offline Pester tests
  integration/              Offline pipeline tests (planned)
  fixtures/brother-like/    Synthetic reference-topology fixture scaffold
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
