# APIM Assessment Toolkit: repository development instructions

## Before making changes

- Read `README.md`, `docs/APIM-Assessment-Spec.md`, the relevant sections of
  `docs/APIM-Assessment-Project-Plan.md`, and
  `docs/APIM-Assessment-Task-Register.md`. The specification defines behavior; the
  register defines task dependencies, acceptance checks, decisions, and status.
- Inspect the current branch and worktree. **All development must happen on
  `feature/<slug>`, `chore/<slug>`, or `bugfix/<slug>` branches.** Create an
  appropriate branch before editing if necessary. Do not edit or commit on
  `main`, release tags, or detached HEAD. Do not discard other people's changes.
- Run `.\scripts\Test-DevelopmentBranch.ps1` before edits and commits. PR CI
  enforces source-branch prefixes. Merge through a reviewed PR to `main`.
- Use the `assessment-task` project skill for implementing register tasks. Use
  `add-assessment-rule` when creating or modifying a rule catalog entry.
- Implement only the requested slice. Raise a specification deviation in the
  register's Decisions log before implementing it.

## Architecture and contracts

- Runtime is PowerShell **7.4+**, cross-platform with Windows as the primary
  workstation. Keep metadata in `ApimAssessment.psd1` and load implementation
  files through `ApimAssessment.psm1` in deterministic order.
- Separate `src/Core`, `Collect`, `Model`, `Rules`, and `Report`. Rule definitions,
  KQL, JSON schemas, and workbook formatting belong in `rules`, `queries`,
  `schemas`, and `template`, respectively.
- Keep the pipeline **Collect -> Analyze -> Report**. Analysis/reporting must
  work offline from a saved run. Customer-specific values live only in ignored
  local config, never implementation code.
- Use camelCase JSON fields, explicit schema versions, stable keys, and stable
  sorting. `findingKey` is `ruleId|resourceName|scope`; never include timestamps.
  Sort findings by priority descending, then rule ID and scope.
- Isolate collector failures and record Failed/Partial/Skipped in the manifest.
  Missing required data emits one Info/NotEvaluated finding per dependent rule;
  it must not silently count as a pass or as zero usage.
- APIM does not partition APIs by gateway hostname: public Basic/host-wide
  forwarding publishes every API unless effective policy blocks the route.
  JWT/mTLS change caller-auth risk, not reachability. Unresolved rewrites or
  insufficient telemetry retain Unknown/confidence qualifications.
- Preserve `<base/>` inheritance, fragment limits/cycle detection, and
  conservative multi-product policy flags with source-scope attribution.

## Non-negotiable safety boundary

- This is an **assessment**, never a remediation tool. All ARM calls go through
  the future `Invoke-ApimArm` wrapper, GET-only except the explicit Cost Management
  query POST allowlist. Log Analytics and Resource Graph use only their query
  cmdlets. Do not add other non-GET exceptions.
- Refuse URLs containing `listSecrets`, `listValue`, `listKeys`, `/secrets`,
  `regenerate`, or `token`; test the guard. Do not retrieve secret values,
  subscription keys, certificate private material, or persist tokens.
- Detect/flag hard-coded policy secrets before redacting stored XML; evidence
  records location, never values. Drop named-value values after detection.
  User identities are not persisted by default.
- **Use synthetic fixtures only.** Do not request or access real customer data
  or run against customer Azure resources. Agents and CI must not need Azure
  credentials. Authorized maintainers own live validation.
- Keep `runs`, private configuration, generated customer workbooks, and secrets
  out of Git, CI artifacts, and release packages. Logic Apps scope is cost-only;
  never inspect workflow definitions. Cloudflare API collection and AI-gateway
  design are out of v1 scope.
- Rule `References` remain empty until maintainers provide verified references.
  Do not invent URLs or generate them into findings.

## Development and verification

- Reuse existing helpers and patterns; prefer the simplest implementation. Use
  approved PowerShell verbs, explicit types/validation where meaningful,
  `Join-Path`, structured errors, and `Set-StrictMode`. Avoid `Write-Host` except
  the eventual progress helper.
- Add public exports to the manifest and loader together when implemented.
  Do not create success-shaped stubs or advertise planned commands as available.
- Development tooling is pinned in `scripts/DevDependencies.psd1`. Install with
  `.\scripts\Install-DevDependencies.ps1` and validate with
  `.\scripts\Invoke-Checks.ps1`. CI runs on Windows and Linux.
- Add focused Pester tests for changed behavior and edge cases, mocking Azure
  and external calls. Prefer targeted development runs; run the full existing
  lint/test gate before handoff. Do not weaken tests or lint settings to hide
  defects. The eventual Model/Rules coverage target is at least 80%.
- Use synthetic `tests/fixtures/brother-like` for the reference topology; document
  fixture counts and expected outcomes rather than importing a customer run.

## Documentation and handoff: required for every task

- Review and maintain **`README.md` in the same change** whenever commands,
  prerequisites, configuration, behavior, safety constraints, layout, releases,
  or implementation status changes. Keep Available/Planned honest. If unchanged,
  explicitly record that it was reviewed and remains accurate in the PR.
- Update task status, percentage, and notes plus the register session log at the
  end of each work session. Mark Done only when the acceptance check passes and
  tests are committed. Record blockers/deviations rather than declaring success.
- Maintain `docs/RUNBOOK.md` with runnable operator commands as they become
  available. Generate `docs/RULES.md` from the implemented catalog when that task
  is built; do not manually create a competing catalog.
- Use the PR checklist. Report meaningful changes, evidence, and remaining
  limitations. Do not push, release, or modify repository settings unless asked.

## Versioning

- `ApimAssessment.psd1`'s `ModuleVersion` is the single version source, a stable
  three-part `MAJOR.MINOR.PATCH`. Preserve the module GUID.
- Prepare bumps on `chore/release-<version>` and merge a reviewed PR. The manual
  release workflow runs on `main`, validates the exact commit, checks increasing
  SemVer, and creates the tag/release without committing to `main`.
- Do not retag, overwrite releases, upload customer data, or publish v1.0 before
  the task register's acceptance gate is approved. See `docs/RELEASES.md`.
