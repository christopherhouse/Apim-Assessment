---
name: assessment-task
description: Use when implementing or finishing a task from the APIM Assessment task register, including branch setup, offline acceptance tests, README maintenance, and progress updates.
---

# Implement a registered assessment task

1. Read the requested task and its dependencies in
   `docs/APIM-Assessment-Task-Register.md`, the linked specification sections, and
   README. Choose one complete, bounded slice; do not assume dependencies exist.
2. Inspect branch/worktree. Create `feature/<slug>`, `chore/<slug>`, or
   `bugfix/<slug>` before any edit if needed. Run
   `.\scripts\Test-DevelopmentBranch.ps1`. Preserve unrelated changes.
3. Set task status to In progress. Log proposed specification deviations in the
   Decisions log before implementing them.
4. Read existing helpers and tests. Implement portable PowerShell 7.4+ with no
   Azure writes, secret retrieval, or live customer access. Use synthetic fixtures
   and mocked calls exclusively.
5. Add focused acceptance tests, including failure/missing-input paths relevant
   to the task. Run targeted tests during development, then
   `.\scripts\Invoke-Checks.ps1` for the repository gate.
6. Update README's current status and all affected commands/prerequisites/data
   handling in the same change. Review it even when unchanged and note that in
   the PR. Update operator documentation when runnable behavior changes.
7. Update register status, percentage, notes, and session log. If tests are not
   committed or an acceptance check remains incomplete, use In review or
   In progress, not Done. Do not mark an entire milestone done for one task.
8. Run the branch guard before committing. Use the PR template for handoff.
   Do not push, release, or change repository settings without explicit approval.
