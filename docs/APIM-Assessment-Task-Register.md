# APIM Assessment Toolkit — Task Register (Progress Register)

| | |
|---|---|
| **Version** | 1.0 (draft) |
| **Last updated** | 2026-10-12 |
| **Spec** | `APIM-Assessment-Spec.md` (section refs in **Spec §** column) |
| **Plan** | `APIM-Assessment-Project-Plan.md` |

**How to use (coding agent):** update `Status`, `%`, and `Notes` at the end of every work session. A task is **Done** only when its **Acceptance check** passes and tests are committed. Log any spec deviation in §Decisions before implementing it.

**Status values:** `Not started` · `In progress` · `Blocked` · `In review` · `Done` · `Deferred`
**Owner codes:** `AGENT` = coding agent · `CH` = Chris House · `JH` = JohnHenry Hain · `CUST` = Brother

---

## Summary dashboard

| Phase | Milestone | Target | Tasks | Done | Status |
|---|---|---|---|---|---|
| P0 Setup | M0 | Oct 13 | 6 | 0 | Not started |
| P1 Core + APIM collection | M1 | Oct 15 | 14 | 0 | Not started |
| P2 Model + exposure | M2 | Oct 17 | 13 | 0 | Not started |
| P3 Rules + report MVP | M3 | Oct 21 | 16 | 0 | Not started |
| P4 Telemetry + cost | M4 | Oct 23 | 13 | 0 | Not started |
| P5 Portal, drift, lifecycle | M5 | Oct 28 | 11 | 0 | Not started |
| P6 Hardening + acceptance | M6 | Oct 30 | 10 | 0 | Not started |
| Engagement runs | — | Oct 21 → Nov 6 | 8 | 0 | Not started |

---

## P0 — Setup (M0)

| ID | Task | Spec § | Depends | Owner | Status | % | Acceptance check | Notes |
|---|---|---|---|---|---|---|---|---|
| T-001 | Create repo + layout per spec; `.gitignore` (`runs/`, `config/*.psd1` except `sample.psd1`) | §4 | — | AGENT | Not started | 0 | Tree matches §4; `runs/` ignored | |
| T-002 | Module manifest/loader (`ApimAssessment.psd1/.psm1`), dot-source `src/**` | §4 | T-001 | AGENT | Not started | 0 | `Import-Module` succeeds on PS 7.4 (Win + Linux) | |
| T-003 | `Get-Config` + `config/sample.psd1` with validation | §5 | T-002 | AGENT | Not started | 0 | Missing/invalid keys fail with clear message (Pester) | |
| T-004 | Logging helper (`logs/run.log`, structured lines, progress) | §7.1, §15 | T-002 | AGENT | Not started | 0 | Log lines JSON-parsable; no secret patterns in tests | |
| T-005 | CI: PSScriptAnalyzer + Pester on PR | §15, §16 | T-002 | AGENT | Not started | 0 | Pipeline green on skeleton | |
| T-006 | Fixture scaffold `tests/fixtures/brother-like/` (empty structure + README on synthetic-only rule) | §16 | T-001 | AGENT | Not started | 0 | Folder + README committed | |

## P1 — Core + APIM collection (M1)

| ID | Task | Spec § | Depends | Owner | Status | % | Acceptance check | Notes |
|---|---|---|---|---|---|---|---|---|
| T-101 | `Invoke-ApimArm`: GET-only + POST allowlist, URL denylist, paging, retry/backoff with `Retry-After` | §3.1, §7.1 | T-002 | AGENT | Not started | 0 | Unit tests: non-GET rejected; denylist URLs rejected; nextLink followed; 429 retried | **Gate G1** |
| T-102 | `Write-RunFile` + run folder + `manifest.json` lifecycle (collector status, warnings) | §6 | T-101 | AGENT | Not started | 0 | Manifest validates against `schemas/manifest.schema.json` | |
| T-103 | Collector: service | §7.2 | T-101 | AGENT | Not started | 0 | `raw/service.json` written; fixture parity | |
| T-104 | Collector: APIs, revisions, operations, API tags | §7.2 | T-101 | AGENT | Not started | 0 | Per-API files written; parallel throttle honoured | |
| T-105 | Collector: OpenAPI export per API (with link fallback) | §7.2 | T-104 | AGENT | Not started | 0 | `raw/openapi/*.json` for HTTP APIs; non-HTTP skipped with log | |
| T-106 | Collector: products, product APIs, product groups | §7.2 | T-101 | AGENT | Not started | 0 | Files written | |
| T-107 | Collector: subscriptions (no secrets) | §7.2 | T-101 | AGENT | Not started | 0 | No `primaryKey`/`secondaryKey` fields in output (test) | |
| T-108 | Collector: named values (drop values after secret-pattern detection), backends, certificates | §7.2, §15 | T-101 | AGENT | Not started | 0 | Output contains no named-value values (test) | |
| T-109 | Collector: identity providers, auth servers, OIDC, authorization providers | §7.2 | T-101 | AGENT | Not started | 0 | Files written | |
| T-110 | Collector: loggers, diagnostics (service + per API) | §7.2 | T-104 | AGENT | Not started | 0 | Files written | |
| T-111 | Collector: groups, tags, version sets, gateways, workspaces, policy fragments, users summary (counts only) | §7.2 | T-101 | AGENT | Not started | 0 | `users.summary.json` contains no UPNs/emails by default | |
| T-112 | Collector: policies at global/product/API/operation/fragment scope + `index.json` | §7.3 | T-104, T-106 | AGENT | Not started | 0 | 404 treated as "none"; index hashes present | |
| T-113 | `-Resume` support and collector isolation (failure ≠ abort) | §6, §7.1 | T-102 | AGENT | Not started | 0 | Simulated failure → status `Failed`, run continues, exit code 3 | |
| T-114 | Provision Microsoft-owned test APIM (Developer) + App GW for smoke tests | Plan §8 | — | CH/JH | Not started | 0 | Resource IDs shared with agent (no customer data) | |

## P2 — Model + exposure (M2)

| ID | Task | Spec § | Depends | Owner | Status | % | Acceptance check | Notes |
|---|---|---|---|---|---|---|---|---|
| T-201 | Populate brother-like fixtures: 60 APIs, Internal VNet, Basic App GW rule, WAF disabled, edge allowlist, 4 all-API subs, 11 unused, 14 no product, 7 key-only external, 3 missing `<base/>`, 2 hard-coded secrets | §2, §16 | T-006 | AGENT | Not started | 0 | Fixtures load; counts documented in fixture README | Synthetic only |
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

## P3 — Rules + report MVP (M3)

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
| T-313 | Fill `config/brother.psd1` (Prod) with discovered names/IDs | §5 | T-311 | CH/JH | Not started | 0 | Config validates | Kept out of repo |
| T-314 | **Gate G3** review: fixture end-to-end + sample workbook review | Plan §10 | T-309–T-312 | CH/JH | Not started | 0 | Go/no-go recorded in Decisions | |
| T-315 | First live Brother **Prod** run (config + policy + network) | §17 | T-313, T-314 | CH/JH | Not started | 0 | Manifest collectors Completed/Skipped; secret scan clean | |
| T-316 | Triage MVP findings; tune severities/recommendations; log false positives | §11 | T-315 | CH/JH + AGENT | Not started | 0 | Rule tweaks merged; FP list in Issues | **M3** |

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
| T-412 | Confirm Log Analytics Reader + cost scope on Brother | Plan §8 | — | JH | Not started | 0 | Access confirmed | |
| T-413 | Brother Prod run #2 with telemetry + cost; prep working sessions 1 & 3 | §17 | T-409–T-412 | CH/JH | Not started | 0 | Workbook reviewed | **M4** |

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
| T-510 | GitHub access for JH/CH (customer) | Plan §8 | — | CUST/JH | Not started | 0 | Repo cloned locally | Requested on scoping call |
| T-511 | Brother Dev + Test runs; drift review; prep working session 2 | §17 | T-506, T-510 | CH/JH | Not started | 0 | Drift sheet reviewed | **M5** |

## P6 — Hardening + acceptance (M6)

| ID | Task | Spec § | Depends | Owner | Status | % | Acceptance check | Notes |
|---|---|---|---|---|---|---|---|---|
| T-601 | Pester coverage ≥ 80% for `src/Model`, `src/Rules` | §15 | all | AGENT | Not started | 0 | Coverage report attached | |
| T-602 | Determinism test (analyze twice → identical findings) | §15, §17 | T-302 | AGENT | Not started | 0 | Test green | |
| T-603 | Performance check on fixture scaled to 60 APIs / 600 ops | §15 | all | AGENT | Not started | 0 | Analyze < 2 min, report < 1 min | |
| T-604 | Live smoke on Microsoft-owned test APIM | §16 | T-114 | AGENT/CH | Not started | 0 | Full run exit 0 | |
| T-605 | `README.md` (prereqs, permissions, data handling) | §15, §17 | all | AGENT | Not started | 0 | Second CSA can install from README | |
| T-606 | `RUNBOOK.md` (step-by-step run, troubleshooting, exit codes) | §14, §17 | all | AGENT | Not started | 0 | Dry-run by JH without help | |
| T-607 | `RULES.md` generated from rule files (ID, title, pillar, MCSB, severity, logic) | §11 | all rules | AGENT | Not started | 0 | Generation script + output committed | |
| T-608 | Maintainers add Microsoft Learn references to rules | §10.1 | T-607 | CH | Not started | 0 | References populated for High/Medium rules | Tool must not invent URLs |
| T-609 | Acceptance review vs spec §17 (all 10 criteria) | §17 | all | CH/JH | Not started | 0 | All criteria checked off below | **Gate G4** |
| T-610 | Tag v1.0 + release notes | — | T-609 | AGENT | Not started | 0 | Tag exists | **M6** |

## Engagement runs and delivery

| ID | Task | Depends | Owner | Status | Target | Notes |
|---|---|---|---|---|---|---|
| E-01 | Send engagement agenda/plan to Brother | — | CH/JH | Not started | Oct 14 | Committed on scoping call |
| E-02 | Ask Kirit to confirm Cloudflare origin authentication approach (or accept "assumed") | — | JH | Not started | Oct 16 | Feeds NET-001 |
| E-03 | Working session 1 — security & exposure | T-413 | CH/JH/CUST | Not started | ~Oct 23 | |
| E-04 | Working session 3 — cost & monitoring (incl. Logic Apps cost observation) | T-413 | CH/JH/CUST | Not started | ~Oct 26 | |
| E-05 | Working session 2 — API organization, hostname split, developer portal | T-511 | CH/JH/CUST | Not started | ~Oct 29 | |
| E-06 | Final Prod run on v1.0 + carry-forward | T-610 | CH/JH | Not started | ~Nov 2 | |
| E-07 | Readout deck (from findings/model) | E-06 | CH | Not started | ~Nov 4 | Use prior readout format |
| E-08 | Readout delivered; delete run data per data-handling agreement | E-07 | CH/JH | Not started | ~Nov 6 | |

---

## Acceptance checklist (spec §17)

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Full Prod run with Reader only; collectors Completed/Skipped | ☐ | |
| 2 | Only allowlisted non-GET calls; denylist tests pass | ☐ | |
| 3 | No secret values in outputs (secret scan clean) | ☐ | |
| 4 | Exposure map reports host-wide forwarding (NET-004) and correct per-API labels | ☐ | |
| 5 | Findings have evidence, sourceFiles, stable keys; deterministic | ☐ | |
| 6 | Workbook from template; Summary matches findings; charts render | ☐ | |
| 7 | Carry-forward preserves tracking fields | ☐ | |
| 8 | Run diff New/Resolved/Persisting correct | ☐ | |
| 9 | Dev/Test runs complete; drift populated | ☐ | |
| 10 | README/RUNBOOK sufficient for a second CSA | ☐ | |

---

## Decisions log

| ID | Date | Decision | By | Spec impact |
|---|---|---|---|---|
| D-01 | 2026-10-12 | Output format: JSON at every stage (raw → model → findings); report from template workbook | CH | §6–§12 |
| D-02 | 2026-10-12 | Tool run by Chris and/or JohnHenry with existing Reader access | CH | §3 |
| D-03 | 2026-10-12 | Topology: APIM Internal VNet behind App GW; host-wide forwarding; Cloudflare treated as assumed reachable | CH | §2, §9 |
| D-04 | 2026-10-12 | Logic Apps: cost data only; no workflow review | CH | §1.2, §7.8 |
| D-05 | 2026-10-12 | Scope order: Prod first, then Dev/Test | CUST | Plan §5 |

## Issues / risks log

| ID | Date | Issue | Severity | Owner | Status | Resolution |
|---|---|---|---|---|---|---|
| I-01 | 2026-10-12 | Cloudflare origin-auth not visible from Azure | Med | JH | Open | E-02 |
| I-02 | 2026-10-12 | Portal basic-auth detection mechanism unconfirmed | Low | AGENT | Open | T-502 |
| I-03 | 2026-10-12 | GitHub access pending | Med | CUST | Open | T-510 |
| I-04 | 2026-10-12 | LA retention / diagnostics coverage unknown | Med | CH | Open | T-401 on first run |

## Session log (agent appends)

| Date | Session summary | Tasks moved | Blockers |
|---|---|---|---|
| | | | |
