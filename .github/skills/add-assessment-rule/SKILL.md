---
name: add-assessment-rule
description: Use when adding or modifying an APIM assessment rule, its evidence, thresholds, fixtures, or missing-input behavior in rules/*.rules.ps1.
---

# Author a traceable assessment rule

Follow the repository instructions and `assessment-task` lifecycle first.
Read specification sections 9-11 and the existing engine/catalog implementation.
If the engine or required model is unimplemented, report that dependency instead
of creating a separate engine or hard-coded fixture-specific result.

## Rule contract

- Use the specified hashtable format and a stable `APIM-<PILLAR>-NNN` ID. Populate
  Id, Title, Pillar, Mcsb, Severity, Scope, Requires, Applies when needed, Test,
  Evidence, EvidenceText, Recommendation, Effort, References, SourceFiles, Enabled.
- `Test` returning true means a finding, not a passing control. Use configuration
  thresholds and existing model fields; do not embed customer names or resource
  IDs. Keep rules independent of ARM/authentication and workbook formatting.
- `Requires` lists the precise model inputs. Missing/failed data must produce one
  Info/NotEvaluated finding for the rule through the shared engine, not a false
  pass and not one row per target.
- Evidence is structured and traceable to raw files/scopes. Record detected
  secret locations only, never values. Recommendations are advisory text, never
  executable remediation. Leave References empty for maintainers.
- Preserve the engine's `ruleId|resourceName|scope` key and stable sort. Do not
  calculate separate priorities inside a rule.
- Authentication does not imply restricted reachability. Basic routing publishes
  all APIs; missing logs cannot establish ExternalUnintended or unused status.

## Acceptance

Add at least one finding case and one non-finding case, threshold boundaries where
relevant, and a missing-input/NotEvaluated case. Assert evidence and sourceFiles;
use synthetic fixtures. Add a deterministic-repeat test when output composition
changes. Validate affected model/findings schemas and run the repository gate.

Update README implementation status, task register, and session log. Once the
catalog generator exists, regenerate `docs/RULES.md` from rule files; do not
hand-maintain a duplicate catalog.
