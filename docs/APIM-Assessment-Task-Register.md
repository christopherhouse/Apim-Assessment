# APIM Assessment Toolkit — Task Register (Progress Register)

| | |
|---|---|
| **Version** | 1.1 (draft) |
| **Last updated** | 2026-10-12 |
| **Spec** | `APIM-Assessment-Spec.md` (section refs in **Spec §** column) |
| **Plan** | `APIM-Assessment-Project-Plan.md` |

**How to use (coding agent):** update `Status`, `%`, and `Notes` at the end of every work session. A task is **Done** only when its **Acceptance check** passes and tests are committed. Log any spec deviation in §Decisions before implementing it.

**Status values:** `Not started` · `In progress` · `Blocked` · `In review` · `Done` · `Deferred`
**Owner codes:** `AGENT` = coding agent · `PO` = product owner/reviewer · `CUST` = designated customer stakeholder

---

## Summary dashboard

| Phase | Milestone | Target | Tasks | Done | Status |
|---|---|---|---|---|---|
| P0 Setup | M0 | Oct 13 | 7 | 7 | Done |
| P1 Core + APIM collection | M1 | Oct 15 | 14 | 6 | In progress |
| P2 Model + exposure | M2 | Oct 17 | 13 | 0 | Not started |
| P3 Rules + model-safe report MVP | M3 | Oct 23 | 25 | 0 | Not started |
| P4 Telemetry + cost | M4 | Oct 27 | 13 | 0 | Not started |
| P5 Portal, drift, lifecycle | M5 | Oct 30 | 11 | 0 | Not started |
| P6 Hardening + acceptance | M6 | Nov 3 | 10 | 0 | In progress |
| Engagement runs | — | Oct 24 → Nov 10 | 8 | 0 | Not started |

---

## P0 — Setup (M0)

| ID | Task | Spec § | Depends | Owner | Status | % | Acceptance check | Notes |
|---|---|---|---|---|---|---|---|---|
| T-001 | Create repo + layout per spec; `.gitignore` (`runs/`, `model-safe/`, `config/*.psd1` except `sample.psd1`) | §4 | — | AGENT | Done | 100 | Implemented scaffold matches §4/D-07; local assessment paths ignored | Added the rebaselined `src/Package` scaffold and tested defense-in-depth `/model-safe/` ignore; future entry scripts/artifacts remain deferred to their implementation tasks per D-07. |
| T-002 | Module manifest/loader (`ApimAssessment.psd1/.psm1`), dot-source `src/**` | §4 | T-001 | AGENT | Done | 100 | `Import-Module` succeeds on PS 7.4+ (Win + Linux) | Deterministic Core/Collect/Model/Rules/Package/Report loading and release-package import pass on PowerShell 7.4+ in PR #3 Ubuntu/Windows CI. |
| T-003 | `Get-Config` + `config/sample.psd1` with validation | §5 | T-002 | AGENT | Done | 100 | Missing/invalid keys fail with clear message (Pester) | Strict nested validation, finite numeric constraints, normalized absolute roots, overlap/link rejection, and fail-closed agent-assisted Copilot-visible path checks pass synthetic tests and PR #3 CI. |
| T-004 | Logging helper (`logs/run.log`, structured lines, progress) | §7.1, §15 | T-002 | AGENT | Done | 100 | Log lines JSON-parsable; no planted secret patterns in tests | JSON-lines logging, explicit levels, query/fragment removal, credential-pattern redaction, append behavior, and `Write-Progress` pass planted-secret tests and PR #3 CI. |
| T-005 | CI: PSScriptAnalyzer + Pester on PR | §15, §16 | T-002 | AGENT | Done | 100 | Pipeline green on skeleton | Bootstrap PR and post-merge `main` CI passed on Windows and Linux. |
| T-006 | Fixture scaffold `tests/fixtures/synthetic-reference/` (empty structure + README on synthetic-only rule) | §16 | T-001 | AGENT | Done | 100 | Folder + README committed | Customer-neutral synthetic README and raw policy/network/security/log/metric/cost/git folders included; fixture data remains T-201. |
| T-007 | Rebaseline specification, plan, register, and README for Copilot-orchestrated assessment with a fail-closed model-data airlock | §1, §3.2, §10.6–§10.7, §12, §14.1–§14.2 | T-001 | AGENT | Done | 100 | Governing documents agree on trust boundaries, artifacts, agent roles, deterministic rendering, dependencies, and acceptance gates | D-09/D-10 logged; spec/plan/register/README/instructions/runbook aligned; branch guard, PSScriptAnalyzer, and 25 Pester tests pass. |

## P1 — Core + APIM collection (M1)

| ID | Task | Spec § | Depends | Owner | Status | % | Acceptance check | Notes |
|---|---|---|---|---|---|---|---|---|
| T-101 | `Invoke-ApimArm`: GET-only + POST allowlist, URL denylist, paging, retry/backoff with `Retry-After` | §3.1, §7.1 | T-002 | AGENT | Done | 100 | Unit tests: non-GET rejected; denylist URLs rejected; nextLink followed; 429 retried | GET-only/path-exact Cost POST guard, decoded denylist, approved ARM hosts, page aggregation, 429/5xx retry, `Retry-After`/Cost headers, exponential fallback, and sanitized failures pass mocked tests and PR #3 CI; **Gate G1 passed**. |
| T-102 | `Write-RunFile` + run folder + `manifest.json` lifecycle (collector status, warnings) | §6 | T-101 | AGENT | Done | 100 | Manifest validates against `schemas/manifest.schema.json` | Schema-validated atomic writes, traversal/link guards, required run folders, stage/collector/warning updates, completion timestamps, stable collector ordering, and release packaging pass offline tests. |
| T-103 | Collector: service | §7.2 | T-101 | AGENT | Done | 100 | `raw/service.json` written; fixture parity | Guarded ARM service GET writes the synthetic fixture shape, records manifest/log success, and records Failed without success-shaped output on mocked errors. |
| T-104 | Collector: APIs, revisions, operations, API tags | §7.2 | T-101 | AGENT | Done | 100 | Per-API files written; parallel throttle honoured | Synthetic two-API fixture parity passes; API revisions, operations, and tags use guarded ARM calls in bounded parallel runspaces with deterministic output ordering and explicit Partial status on child failure. |
| T-105 | Collector: OpenAPI export per API (with link fallback) | §7.2 | T-104 | AGENT | Not started | 0 | `raw/openapi/*.json` for HTTP APIs; non-HTTP skipped with log | |
| T-106 | Collector: products, product APIs, product groups | §7.2 | T-101 | AGENT | Done | 100 | Files written | Synthetic two-product fixture parity passes for products, API memberships, and group memberships; root and child failures produce explicit Failed/Partial manifest state. |
| T-107 | Collector: subscriptions (no secrets) | §7.2 | T-101 | AGENT | Not started | 0 | No `primaryKey`/`secondaryKey` fields in output (test) | |
| T-108 | Collector: named values (drop values after secret-pattern detection), backends, certificates | §7.2, §15 | T-101 | AGENT | Not started | 0 | Output contains no named-value values (test) | |
| T-109 | Collector: identity providers, auth servers, OIDC, authorization providers | §7.2 | T-101 | AGENT | Not started | 0 | Files written | |
| T-110 | Collector: loggers, diagnostics (service + per API) | §7.2 | T-104 | AGENT | Not started | 0 | Files written | |
| T-111 | Collector: groups, tags, version sets, gateways, workspaces, policy fragments, users summary (counts only) | §7.2 | T-101 | AGENT | Not started | 0 | `users.summary.json` contains no UPNs/emails by default | |
| T-112 | Collector: policies at global/product/API/operation/fragment scope + `index.json` | §7.3 | T-104, T-106 | AGENT | Done | 100 | 404 treated as "none"; index hashes present | Synthetic eight-scope parity passes with five present and three absent policies. Bounded guarded ARM calls treat 404 as none; DTD-safe parsing records structural secret locations, redacts values before persistence, and hashes normalized redacted XML deterministically. |
| T-113 | `-Resume` support and collector isolation (failure ≠ abort) | §6, §7.1 | T-102 | AGENT | Not started | 0 | Simulated failure → status `Failed`, run continues, exit code 3 | |
| T-114 | Provision Microsoft-owned test APIM (Developer) + App GW for smoke tests | Plan §8 | — | PO | Not started | 0 | Resource IDs stored only in restricted local config; agent receives no identifiers | |

## P2 — Model + exposure (M2)

| ID | Task | Spec § | Depends | Owner | Status | % | Acceptance check | Notes |
|---|---|---|---|---|---|---|---|---|
| T-201 | Populate synthetic reference fixtures: 60 APIs, Internal VNet, Basic App GW rule, WAF disabled, edge allowlist, 4 all-API subs, 11 unused, 14 no product, 7 key-only external, 3 missing `<base/>`, 2 hard-coded secrets | §2, §16 | T-006 | AGENT | Not started | 0 | Fixtures load; counts documented in fixture README | Synthetic only; no customer, engagement, or real-person identifiers |
| T-202 | `Merge-ApimPolicy` (base handling, fragments, multi-product, scope attribution) | §8.3 | T-112 | AGENT | Not started | 0 | Unit tests: base present/missing, fragment cycle, multi-product AND/OR | |
| T-203 | Policy normalization + SHA-256 hashing | §8.4 | T-202 | AGENT | Not started | 0 | Whitespace/attr-order changes → same hash | |
| T-204 | `Get-PolicyFlags` (all flags in §8.4; secret detection records location only) | §8.4 | T-202 | AGENT | Not started | 0 | Positive + negative test per flag | |
| T-205 | Secret redaction of stored policy XML after flagging | §15 | T-204 | AGENT | Not started | 0 | Redacted XML contains `***REDACTED***`; flags unchanged | |
| T-206 | Model: `apis.json`, `operations.json` | §8.1, §8.2 | T-204 | AGENT | Not started | 0 | Schema-valid; fixture counts match | |
| T-207 | Model: `policyMatrix.json` | §8.5 | T-204 | AGENT | Not started | 0 | Pass/Fail/NA per control | |
| T-208 | Model: `subscriptions.json` (scopeType, built-in master detection) | §8.5 | T-107 | AGENT | Not started | 0 | 4 AllApis in fixture | |
| T-209 | Collector: network (App GW, WAF policy, NSGs, public IPs, PEs, DNS, route tables, other front doors) | §7.4 | T-101 | AGENT | Not started | 0 | Files written for fixture-equivalent test env | |
| T-210 | Model: `network.json` (VNet mode, NSG evaluation, DirectPublic inputs) | §8.5, §9.1 | T-209 | AGENT | Not started | 0 | Internal VNet + restricted NSG → DirectPublic false | |
| T-211 | Exposure classifier steps 1–4 (published hostnames, Basic → `/*`, path maps, rewrites → Unknown, restrictions) | §9.1–§9.4 | T-210, T-204 | AGENT | Not started | 0 | Scenario tests: host-wide, path-based, rewrite, DirectPublic, ip-filter, host-check, base-missing | **Gate G2** |
| T-212 | Exposure final labelling with usage hook (stub until P4) | §9.5, §9.6 | T-211 | AGENT | Not started | 0 | Labels emitted; usage-dependent labels `Unknown` until P4 | |
| T-213 | JSON schemas for all model files + `Test-Json` validation step | §8, §16 | T-206–T-212 | AGENT | Not started | 0 | Analyze fails fast on invalid model | |

## P3 — Rules + model-safe report MVP (M3)

| ID | Task | Spec § | Depends | Owner | Status | % | Acceptance check | Notes |
|---|---|---|---|---|---|---|---|---|
| T-301 | Rule engine (load, Requires, Applies/Test, Evidence, NotEvaluated, stable sort) | §10.1, §10.5 | T-213 | AGENT | Not started | 0 | Engine tests incl. missing input → one NotEvaluated per rule | |
| T-302 | Findings schema + `findingKey` + priority scoring from config | §10.2, §10.3 | T-301 | AGENT | Not started | 0 | Re-run → byte-identical findings (excl. timestamp) | |
| T-303 | NET rules 001–002, 004, 006–009 | §11.1 | T-301 | AGENT | Not started | 0 | Pass/fail fixture per rule; NET-004 fires on fixture | |
| T-304 | SEC rules 001–015, 017–020 (excl. log-based 016) | §11.2 | T-301 | AGENT | Not started | 0 | Pass/fail fixture per rule | |
| T-305 | GOV rules 001–003, 005, 006, 008–010 | §11.3 | T-301 | AGENT | Not started | 0 | Pass/fail fixture per rule | |
| T-306 | REL rules 001–006 | §11.4 | T-301 | AGENT | Not started | 0 | Pass/fail fixture per rule | |
| T-307 | Action-plan aggregation by rule | §10.4 | T-302 | AGENT | Not started | 0 | Affected counts match instance findings | |
| T-308 | Template workbook `ApimActionPlan.xlsx` (styles, named tables, conditional formats, Summary formulas, charts, assumptions banner) | §12.1, §12.2 | — | AGENT | Not started | 0 | Opens in Excel; empty tables named per §12.2 | Use the sample workbook as visual reference |
| T-309 | Report writer (`Export-ActionPlan`) — fill all MVP sheets | §12.2 | T-307, T-308 | AGENT | Not started | 0 | Fixture → workbook; Summary KPIs equal findings counts | |
| T-310 | Run Info + Method & Rules sheets (rule catalog, editable weights) | §12.2 | T-309 | AGENT | Not started | 0 | Changing a weight recalculates Priority | |
| T-311 | `Invoke-ApimAssessment` wrapper + CLI switches + exit codes | §14 | T-309 | AGENT | Not started | 0 | All switches documented; exit codes tested | |
| T-312 | Secret-scan check over a run folder (keys, JWTs, connection strings) | §15, §17 | T-309 | AGENT | Not started | 0 | Script returns non-zero on planted secret fixture | |
| T-317 | Closed schemas for `analysis-package.json`, specialist observations, and `executive-summary.json`; define strict aliases, enums, buckets, fact references, and `additionalProperties: false` | §3.2, §10.6, §10.7 | T-302 | AGENT | Not started | 0 | Valid synthetic package passes; unknown fields, unrestricted strings, exact usage/cost, and invalid references fail | Model-safe contracts only |
| T-318 | Allowlist-only `New-AnalysisPackage` + restricted deterministic alias map | §3.2, §10.6 | T-213, T-302, T-317 | AGENT | Not started | 0 | Package is built as a new object; no raw/model object cloning; aliases stable across reruns | Alias map never promoted |
| T-319 | Independent `Test-AnalysisPackage` scanner, hash attestation, and fail-closed atomic promotion into a non-overlapping analysis zone | §3.2, §10.6 | T-318 | AGENT | Not started | 0 | Forbidden keys/values, unknowns, ambiguity, path overlap/link/traversal, Copilot-visible restricted roots, hash mismatch, and validator failure prevent promotion | **Model-data gate** |
| T-320 | Airlock canary/mutation fixture suite (identifiers, URLs, IPs, UPNs, policy XML, exact metrics, secrets, encoded/Unicode/high-entropy variants, new source fields) | §16, §17 | T-201, T-319 | AGENT | Not started | 0 | No planted value or fragment reaches package, logs, errors, attestation, or analysis zone; new fields cannot flow through | Synthetic only |
| T-321 | Narrow local Copilot broker (prefer stdio MCP): allowlisted assessment/status/promote/read/render tools, internal path resolution, captured output, sanitized error codes, no generic execution | §3.2, §14.1 | T-102, T-311, T-319 | AGENT | Not started | 0 | Agent tool surface cannot access credentials, arbitrary paths, raw/model data, alias map, stdout/stderr, or shell | Manual path retained |
| T-322 | Architecture/exposure and security analyst agent profiles with read-only model-safe tools and validated cited observations | §10.7 | T-317, T-319 | AGENT | Not started | 0 | Agents see only promoted package; unsupported facts and severity overrides are rejected | Distinct from code review agents |
| T-323 | Executive synthesizer agent + reconciliation contract | §10.7 | T-322 | AGENT | Not started | 0 | Summary validates, cites findings/facts, retains assumptions/data gaps, and introduces no unsupported evidence | |
| T-324 | Copilot orchestration, analysis, deliverable, and validation skills | §14.1, §14.2 | T-321–T-323, T-309 | AGENT | Not started | 0 | A clean Copilot session completes the synthetic workflow through narrow tools only; deterministic fallback works without Copilot | |
| T-325 | Self-contained HTML executive presentation renderer and template with local alias resolution, inline diagrams/charts, accessibility and print support | §12.1, §12.5 | T-323 | AGENT | Not started | 0 | Fixture renders polished offline HTML; no network dependencies; all aliases resolve; required sections and accessibility checks pass | Model never mutates report |
| T-313 | Fill ignored `config/customer.psd1` (Prod) with discovered names/IDs | §5 | T-311 | PO | Not started | 0 | Config validates | Kept out of repo |
| T-314 | **Gate G3** review: fixture end-to-end, airlock/broker isolation, agent traceability, sample workbook and HTML presentation | Plan §10 | T-309–T-312, T-317–T-325 | PO | Not started | 0 | Canary/mutation and hash-attestation gates green; agent access boundary demonstrated; workbook/HTML visually reviewed; go/no-go recorded in Decisions | |
| T-315 | First authorized customer **Prod** run (config + policy + network) | §17 | T-313, T-314 | PO | Not started | 0 | Manifest collectors Completed/Skipped; secret scan clean; validated package promoted with no prohibited data | |
| T-316 | Triage MVP findings and cited agent observations; tune deterministic severities/recommendations; log false positives | §10.7, §11 | T-315 | PO + AGENT | Not started | 0 | Rule tweaks merged; agent claims remain traceable; FP list in Issues | **M3** |

## P4 — Telemetry + cost (M4)

| ID | Task | Spec § | Depends | Owner | Status | % | Acceptance check | Notes |
|---|---|---|---|---|---|---|---|---|
| T-401 | LA schema detection (resource-specific vs AzureDiagnostics) + retention capping | §7.6 | T-101 | AGENT | Not started | 0 | Manifest records schema + effective windows | |
| T-402 | KQL queries (both schema variants): usageByApi, usageByRoute, usageMonthly, tls, noSubscriptionCalls | §7.6 | T-401 | AGENT | Not started | 0 | Queries in `queries/`; parse-tested | |
| T-403 | KQL: appgwByListener, appgwNonEdge, directNonAppGw, headersLogged | §7.6 | T-401 | AGENT | Not started | 0 | Queries return expected shape on test env | |
| T-404 | Metrics collector (APIM + App GW) | §7.7 | T-101 | AGENT | Not started | 0 | `metrics/*.json` written | |
| T-405 | Cost collector (Query API, daily, grouping, throttling) | §7.8 | T-101 | AGENT | Not started | 0 | 429 handling tested; `-SkipCost` works | |
| T-406 | Logic Apps cost-only inventory + billable metrics; LA ingestion by table | §7.8 | T-405 | AGENT | Not started | 0 | No workflow definitions read (test) | |
| T-407 | Models: usage, capacity, cost (+ cost per million calls) | §8.5 | T-402, T-404, T-405 | AGENT | Not started | 0 | Schema-valid | |
| T-408 | Exposure step 5–6 with observed routes (ExternalInUse vs ExternalUnintended; private-listener ambiguity) | §9.5, §9.6 | T-212, T-402, T-403 | AGENT | Not started | 0 | Fixture scenarios pass | |
| T-409 | Rules: NET-003, NET-005, SEC-016, GOV-004, GOV-009, PERF-001–003 | §11 | T-407, T-408 | AGENT | Not started | 0 | Pass/fail fixture per rule | |
| T-410 | Rules: COST-001–005 | §11.6 | T-407 | AGENT | Not started | 0 | Pass/fail fixture per rule | |
| T-411 | Usage + Cost sheets (charts bound to tables) | §12.2 | T-407 | AGENT | Not started | 0 | Charts render with fixture data | |
| T-412 | Confirm Log Analytics Reader + cost scope on the target customer environment | Plan §8 | — | PO | Not started | 0 | Access confirmed | |
| T-413 | Customer Prod run #2 with telemetry + cost; prep working sessions 1 & 3 | §17 | T-409–T-412 | PO | Not started | 0 | Workbook and HTML executive presentation reviewed | **M4** |

## P5 — Portal, drift, lifecycle (M5)

| ID | Task | Spec § | Depends | Owner | Status | % | Acceptance check | Notes |
|---|---|---|---|---|---|---|---|---|
| T-501 | Portal collector + `portal.json` model | §7.2, §8.5 | T-101 | AGENT | Not started | 0 | Model populated | |
| T-502 | Resolve basic username/password detection mechanism (Open item #1) | §18 | T-501 | AGENT | Not started | 0 | Decision logged; heuristic flagged if unresolved | |
| T-503 | Rules POR-001–005 | §11.5 | T-501 | AGENT | Not started | 0 | Pass/fail fixture per rule | |
| T-504 | Spectral integration (optional) + `openApiQuality.json` + fallback metric | §8.6 | T-105 | AGENT | Not started | 0 | Works with and without Spectral installed | |
| T-505 | Git collector (APIOps layout + regex) + `policyHashes.json` | §7.9 | T-203 | AGENT | Not started | 0 | Hash parity with deployed fixture policies | |
| T-506 | Drift model (Git + multi-env `-CompareRuns`) + GOV-007, GOV-011 | §8.5, §11.3 | T-505 | AGENT | Not started | 0 | Fixture variants → Differs/ProdOnly detected | |
| T-507 | `Merge-PriorTracking` carry-forward (actions by ruleId, details by findingKey; resolved section) | §12.3 | T-309 | AGENT | Not started | 0 | Owner/Status/Target/Notes preserved across runs | |
| T-508 | `Compare-ApimRun` + Run Comparison sheet | §13 | T-302 | AGENT | Not started | 0 | New/Resolved/Persisting correct on fixtures | |
| T-509 | Environment Drift sheet | §12.2 | T-506 | AGENT | Not started | 0 | Populated from fixtures | |
| T-510 | GitHub access for authorized maintainers and customer stakeholders | Plan §8 | — | CUST/PO | Not started | 0 | Repo cloned locally | Requested on scoping call |
| T-511 | Customer Dev + Test runs; drift review; prep working session 2 | §17 | T-506, T-510 | PO | Not started | 0 | Drift sheet reviewed | **M5** |

## P6 — Hardening + acceptance (M6)

| ID | Task | Spec § | Depends | Owner | Status | % | Acceptance check | Notes |
|---|---|---|---|---|---|---|---|---|
| T-601 | Pester coverage ≥ 80% for `src/Model`, `src/Rules` | §15 | all | AGENT | Not started | 0 | Coverage report attached | |
| T-602 | Determinism test (analyze twice → identical findings) | §15, §17 | T-302 | AGENT | Not started | 0 | Test green | |
| T-603 | Performance check on fixture scaled to 60 APIs / 600 ops | §15 | all | AGENT | Not started | 0 | Analyze < 2 min; Excel and HTML rendering each < 1 min | |
| T-604 | Live smoke on Microsoft-owned test APIM | §16 | T-114 | AGENT/PO | Not started | 0 | Full run exit 0 | |
| T-605 | `README.md` (prereqs, permissions, data handling) | §15, §17 | all | AGENT | In progress | 20 | Second CSA can install from README | Bootstrap README covers current availability, developer setup, planned permissions, privacy, layout and releases; same-change maintenance required. Full operator acceptance remains pending. |
| T-606 | `RUNBOOK.md` (step-by-step run, troubleshooting, exit codes) | §14, §17 | all | AGENT | In progress | 10 | Dry-run by a product owner without help | Bootstrap runbook explicitly marks assessment stages unavailable; runnable stage instructions and operator dry-run remain pending. |
| T-607 | `RULES.md` generated from rule files (ID, title, pillar, MCSB, severity, logic) | §11 | all rules | AGENT | Not started | 0 | Generation script + output committed | |
| T-608 | Maintainers add Microsoft Learn references to rules | §10.1 | T-607 | PO | Not started | 0 | References populated for High/Medium rules | Tool must not invent URLs |
| T-609 | Acceptance review vs spec §17 (all 14 criteria) | §17 | all | PO | Not started | 0 | All criteria checked off below | **Gate G4** |
| T-610 | Tag v1.0 + release notes | — | T-609 | AGENT | Not started | 0 | Tag exists | **M6** |

## Engagement runs and delivery

| ID | Task | Depends | Owner | Status | Target | Notes |
|---|---|---|---|---|---|---|
| E-01 | Send engagement agenda/plan to designated customer stakeholders | — | PO | Not started | Oct 14 | Committed on scoping call |
| E-02 | Ask the designated customer contact to confirm edge-origin authentication approach (or accept "assumed") | — | PO | Not started | Oct 16 | Feeds NET-001 |
| E-03 | Working session 1 — security & exposure | T-413 | PO/CUST | Not started | ~Oct 27 | Workbook and HTML executive presentation |
| E-04 | Working session 3 — cost & monitoring (incl. Logic Apps cost observation) | T-413 | PO/CUST | Not started | ~Oct 29 | |
| E-05 | Working session 2 — API organization, hostname split, developer portal | T-511 | PO/CUST | Not started | ~Nov 2 | |
| E-06 | Final Prod run on v1.0 + carry-forward | T-610 | PO | Not started | ~Nov 5 | |
| E-07 | Finalize readout narrative from validated findings and executive summary | E-06 | PO | Not started | ~Nov 8 | HTML is the generated executive artifact; PowerPoint remains manual/out of scope |
| E-08 | Readout delivered; delete run data per data-handling agreement | E-07 | PO | Not started | ~Nov 10 | |

---

## Acceptance checklist (spec §17)

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Full Prod run with Reader only; collectors Completed/Skipped | ☐ | |
| 2 | Only allowlisted non-GET calls; denylist tests pass | ☐ | |
| 3 | No secret values in outputs (secret scan clean) | ☐ | |
| 4 | Raw/model/restricted data inaccessible to agents; broker has no generic execution, arbitrary path, stdout/stderr, credential, or raw-data surface | ☐ | |
| 5 | Canary/mutation suite blocks prohibited values and unknown fields; package attestation/hash and promotion gate pass | ☐ | |
| 6 | Exposure map reports host-wide forwarding (NET-004) and correct per-API labels | ☐ | |
| 7 | Findings have evidence, sourceFiles, stable keys; deterministic | ☐ | |
| 8 | Specialist/executive observations validate, cite model-safe IDs, and do not alter deterministic findings | ☐ | |
| 9 | Workbook from template; Summary matches findings; charts render | ☐ | |
| 10 | HTML executive presentation is offline/self-contained, visually approved, accessible/printable, and resolves all aliases locally | ☐ | |
| 11 | Carry-forward preserves tracking fields | ☐ | |
| 12 | Run diff New/Resolved/Persisting correct | ☐ | |
| 13 | Dev/Test runs complete; drift populated | ☐ | |
| 14 | README/RUNBOOK sufficient for a second CSA to use deterministic and Copilot-assisted paths | ☐ | |

---

## Decisions log

| ID | Date | Decision | By | Spec impact |
|---|---|---|---|---|
| D-01 | 2026-10-12 | Output format: JSON at every stage (raw → model → findings); report from template workbook | PO | §6–§12 |
| D-02 | 2026-10-12 | Authorized maintainers run the tool with existing Reader access | PO | §3 |
| D-03 | 2026-10-12 | Topology: APIM Internal VNet behind App GW; host-wide forwarding; external edge treated as assumed reachable | PO | §2, §9 |
| D-04 | 2026-10-12 | Logic Apps: cost data only; no workflow review | PO | §1.2, §7.8 |
| D-05 | 2026-10-12 | Scope order: Prod first, then Dev/Test | CUST | Plan §5 |
| D-06 | 2026-10-12 | Use module `ModuleVersion` as the single three-part SemVer source; reviewed chore release PR, then manual main-only workflow with validation, tag, ZIP/checksum and generated notes. No version-bump commits on main. | AGENT | Release mechanics for T-610; no assessment contract change |
| D-07 | 2026-10-12 | Bootstrap importable module and folders without success-shaped assessment stubs; add the five entry scripts, schemas, catalogs and workbook only with their implementation tasks. README distinguishes available and planned features. | AGENT | §4 scaffold sequencing; no CLI contract change |
| D-08 | 2026-10-12 | Development uses feature/chore/bugfix branches and PRs to main; Copilot instructions, local guard, and PR CI enforce branch naming. Host-side main protection remains a maintainer setting. | AGENT | Contributor workflow; requested repository bootstrap |
| D-09 | 2026-10-12 | Use a hybrid architecture: deterministic PowerShell remains authoritative for collection, normalization, rules, evidence, and local rendering; Copilot orchestrates only through narrow local tools and specialist agents analyze only independently validated, allowlisted, pseudonymized packages. Raw/model customer data and unrestricted collection output must never enter model context. | PO/AGENT | Adds the model-data airlock, specialist analysis, local Copilot broker, and HTML executive summary requirements throughout the spec and plan. |
| D-10 | 2026-10-12 | Generate Excel and self-contained HTML locally from fixed templates. AI narrative uses model-safe aliases; a restricted local alias map and exact metrics may be reintroduced only by deterministic renderers after model work completes. | PO/AGENT | §12 reporting contract; HTML replaces automated readout-deck generation in v1. |
| D-11 | 2026-10-12 | ARM transport accepts relative paths beginning `/` and absolute HTTPS URLs only on known Azure Resource Manager cloud hosts; every decoded `nextLink` is revalidated. | AGENT | Tightens §3.1/T-101 against off-host authenticated requests without changing the documented Azure scope. |
| D-12 | 2026-10-12 | `Get-Config -AgentAssisted` requires the broker to supply at least one complete Copilot-visible path and rejects any overlap with the restricted root; promotion-time traversal/TOCTOU checks remain T-319. | AGENT | Implements the §3.2/§5 config-time boundary without claiming the later promotion gate is complete. |
| D-13 | 2026-10-12 | Tracked repository content must remain customer-neutral: customer/engagement names and real-person names stay outside files, paths, examples, branches, commits, and pull-request text. | PO | Tightens repository data handling without changing runtime behavior. |

## Issues / risks log

| ID | Date | Issue | Severity | Owner | Status | Resolution |
|---|---|---|---|---|---|---|
| I-01 | 2026-10-12 | External edge origin-auth not visible from Azure | Med | PO | Open | E-02 |
| I-02 | 2026-10-12 | Portal basic-auth detection mechanism unconfirmed | Low | AGENT | Open | T-502 |
| I-03 | 2026-10-12 | GitHub access pending | Med | CUST | Open | T-510 |
| I-04 | 2026-10-12 | LA retention / diagnostics coverage unknown | Med | PO | Open | T-401 on first run |
| I-05 | 2026-10-12 | GitHub Copilot organization policy/customer approval for model-safe derived assessment facts must be confirmed | High | PO | Open | Keep specialist analysis disabled until confirmed; deterministic reports remain available |
| I-06 | 2026-10-12 | Approved non-overlapping local paths for restricted collection and model-safe analysis zones are not yet selected | High | PO | Open | Required by T-319/T-321 before agent-assisted live runs |
| I-07 | 2026-10-12 | Prior commits contain customer or real-person identifiers in Git history | High | PO | Open | Current tracked tree is purged; permanent historical removal requires an explicitly approved, coordinated history rewrite and remote cleanup |

## Session log (agent appends)

| Date | Session summary | Tasks moved | Blockers |
|---|---|---|---|
| 2026-10-12 | Bootstrapped on `feature/bootstrap-repository`: module/fixture scaffold, sample config, Copilot guidance with two agents/two skills, maintained README/runbook, PR CI, and guarded SemVer release/package automation. Local Windows PSScriptAnalyzer, 25 offline Pester tests, package import/checksum/private-data exclusion, manifest/ignore checks and actionlint pass. No Azure calls, remote push, tag or release. | T-001 in progress; T-002/T-005 in review; T-006 done in bootstrap commit; T-605/T-606 started. | GitHub CI and minimum PS 7.4 validation await later acceptance; assessment runtime stages remain unimplemented. |
| 2026-10-12 | Rebaselined the governing specification, project plan, task register, README, repository instructions, config guidance, and runbook on `feature/copilot-assessment-orchestration` for a hybrid deterministic PowerShell/Copilot architecture. Added a fail-closed model-data airlock, external restricted root, narrow local broker, specialist agent contracts, deterministic alias rehydration, Excel action plan, and self-contained HTML executive presentation. Documentation-only; no Azure/customer data accessed. PSScriptAnalyzer and 25 offline Pester tests pass after installing pinned development modules. | T-005 moved Done after successful bootstrap PR/main CI; T-007 moved Done at 100%; P3 and acceptance gate expanded with T-317–T-325. | Copilot organization/customer approval and approved non-overlapping external collection/analysis paths remain open (I-05/I-06). |
| 2026-10-12 | Implemented the core foundation on `feature/core-foundation`: completed Package-aware deterministic loading and release packaging, explicit PowerShell 7.4+ CI import evidence, strict private config validation, JSON-lines secret-safe logging/progress, and the GET-only/Cost-POST ARM wrapper with approved-host validation, decoded denylist, paging, retry headers, exponential fallback, and sanitized failures. Added and tested `/model-safe/` defense-in-depth ignore. All work used synthetic config and mocked ARM responses; no Azure/customer access. PSScriptAnalyzer and 72 offline Pester tests pass locally; PR #3 branch policy and Ubuntu/Windows validation passed. | T-001/T-002/T-003/T-004/T-101 moved Done; P0 completed and Gate G1 passed. | No current implementation blocker; future I-05/I-06 approvals remain required before agent-assisted live runs. |
| 2026-10-12 | Implemented run persistence and the first APIM collector on `feature/run-persistence-service`: added atomic path-contained run-file writes, schema-validated manifest lifecycle, required run directories, collector/stage/warning tracking, a synthetic APIM service fixture, and mocked service collection through the guarded ARM wrapper. Updated release packaging assertions and current-status documentation. No Azure/customer data accessed. PSScriptAnalyzer and 82 offline Pester tests pass locally. | T-102/T-103 moved Done at 100%; P1 now has three completed tasks. | Public collection orchestration, resume/isolation, and remaining collectors are still pending; T-114 remains an owner-side smoke-test dependency. |
| 2026-10-12 | Purged customer, engagement, and real-person names from the tracked tree; renamed the fixture root to `tests/fixtures/synthetic-reference`; neutralized examples and engagement documentation; and added an explicit customer-neutral repository rule plus a tracked-fixture naming test. PSScriptAnalyzer and 83 offline Pester tests pass locally. | No task status changes; D-13 and I-07 added. | Current tree is clean, but prior Git history still requires explicit coordinated rewrite approval for permanent historical removal. |
| 2026-10-12 | Implemented customer-neutral APIM API and product catalog collectors on `feature/apim-catalog-collectors`: collected APIs, revisions, operations, API tags, products, product/API memberships, and product/group memberships through the guarded ARM wrapper. Added bounded parallel runspace execution with configurable throttle, stable result ordering, path-safe resource segments, explicit Failed/Partial status, synthetic fixture parity, and sanitized parallel failures. PSScriptAnalyzer and 90 offline Pester tests pass locally. | T-104/T-106 moved Done at 100%; P1 now has five completed tasks. | Public orchestration/resume remains pending; T-112 policy collection is now unblocked. |
| 2026-10-12 | Implemented customer-neutral APIM policy collection on `feature/apim-policy-collector`: collected global, product, API, operation, and fragment policy scopes through guarded ARM calls; indexed 404 as absent; rejected DTDs and unsupported roots; redacted hard-coded secret candidates before persistence while recording structural locations only; and produced deterministic normalized SHA-256 hashes. PSScriptAnalyzer and 99 offline Pester tests pass locally. | T-112 moved Done at 100%; P1 now has six completed tasks. | T-202 policy inheritance/fragment expansion is unblocked; T-204/T-205 still own effective-policy flag propagation and downstream redaction invariants. |
