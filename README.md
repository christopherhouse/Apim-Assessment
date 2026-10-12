# APIM Assessment Toolkit

A customer-neutral, **read-only** PowerShell toolkit for Azure API Management and
its network front door: **Collect -> Analyze -> Report**. The planned output is
versioned JSON evidence, deterministic findings, an Excel action plan, and run
comparisons.

## Current status

**Bootstrap only; not yet an operational assessment tool.** The module imports,
but exports no assessment commands. Collectors, configuration validation, models,
rules, CLI entry points, and the Excel template are not implemented yet.

| Available | Planned |
|---|---|
| Module manifest and deterministic source loader | Read-only ARM wrapper and collectors |
| Customer-neutral sample configuration | Validated configuration and structured logging |
| Synthetic-fixture scaffold | Policy merge, exposure model, and rule engine |
| Windows/Linux lint and test CI | Excel report, carry-forward, and run comparison |
| Copilot instructions, agents, and skills | Live validation by authorized maintainers |
| Guarded SemVer tag/release workflow | v1.0 acceptance against the technical specification |

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
The entire `runs` directory is ignored and will be created by the runtime.

Real runs must remain local in a customer-approved storage location and be
deleted after the readout according to the agreed retention policy. Do not
upload run folders or generated customer workbooks to CI artifacts or releases.
Git ignores are an accident-prevention measure, not permission to store secrets.

## Repository layout

```text
ApimAssessment.psd1 / .psm1  Module metadata and source loader
src/
  Core/                     Config, ARM guard, persistence, logging, retries
  Collect/                  Isolated read-only collectors
  Model/                    Normalization, policy merge, exposure and drift
  Rules/                    Rule engine and priority scoring
  Report/                   Workbook export and tracking carry-forward
rules/                      Rule catalogs (planned)
queries/                    Log Analytics and Resource Graph KQL (planned)
schemas/                    Versioned JSON contracts (planned)
template/                   Excel action-plan template (planned)
config/                     Tracked sample; ignored local configurations
tests/
  unit/                     Offline Pester tests
  integration/              Offline pipeline tests (planned)
  fixtures/brother-like/    Synthetic reference-topology fixture scaffold
scripts/                    Branch guard, validation and release packaging
docs/                       Specification, plan, register and operating guides
.github/
  agents/                   Implementation and read-only review profiles
  skills/                   Task lifecycle and assessment-rule authoring
  workflows/                CI, Copilot setup, and SemVer release
```

The five assessment entry scripts named in the specification will be added when
their stages are implemented, rather than exposing nonfunctional commands now.

## Copilot-assisted development

[Repository instructions](.github/copilot-instructions.md) define the safety
boundary, branch policy, architecture, tests, and documentation requirements.
The `apim-implementer` agent handles bounded implementation tasks; the
`assessment-reviewer` agent provides read-only contract and correctness reviews.
Project skills cover task lifecycle and rule authoring. See
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
