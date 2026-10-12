# Contributing

## Start a task

1. Read `docs/APIM-Assessment-Spec.md` and the relevant task-register acceptance
   check. Follow the current dependency order; log a specification deviation in
   the register's Decisions log before implementing it.
2. Check `git status --short --branch`. Preserve unrelated work. Start from the
   appropriate reviewed base and create `feature/<name>`, `chore/<name>`, or
   `bugfix/<name>`. Never develop on `main`, a tag, or detached HEAD.
3. Run `.\scripts\Test-DevelopmentBranch.ps1` before editing and before committing.
   Use lowercase branch names with a descriptive slug.
4. Set the affected task to In progress. Work in a bounded vertical slice.

## Implement and validate

Use PowerShell 7.4+, approved verbs, explicit parameters, and portable `Join-Path`
paths. All Azure ARM requests must eventually flow through `Invoke-ApimArm`; only
GET and the specification's narrowly allowlisted query operations are permitted.
Never call secret-listing APIs or introduce remediation.

Tests must be offline, use synthetic fixtures, and mock Azure/network calls. Add
focused Pester cases for changed behavior. Use `.\scripts\Invoke-Checks.ps1` for
the same lint/test gate as CI. Do not suppress diagnostics merely to pass a gate.
No live customer access is required or permitted for agent development.

## Finish a task

Update the README in the same change when behavior, commands, dependencies,
configuration, safety, layout, release behavior, or implementation status changes.
Review it even if unchanged; do not document unimplemented commands as runnable.
Update the task register's status, percentage, notes, and session log. A task is
Done only after its stated acceptance check passes and its tests are committed;
otherwise use In progress or In review and explain what remains.

Open a pull request to `main` using the checklist. Prefer concise conventional
commit subjects (`feat:`, `fix:`, `chore:`, `docs:`, `test:`); commit messages do
not calculate release versions. Maintainers review scope and safety before merge.
Enable branch protection and required CI checks on GitHub to enforce this policy
beyond instructions and PR validation.

## Releases

Prepare version changes on `chore/release-<version>`, update `ModuleVersion` in
`ApimAssessment.psd1`, and describe compatibility changes in the PR. Do not change
the module GUID, retag published versions, or write generated versions to `main`.
Follow `docs/RELEASES.md` after merge. Selecting a new version is an explicit
maintainer decision, not an inference from commit messages.
