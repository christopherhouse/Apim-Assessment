# APIM Assessment Toolkit — Project Plan

| | |
|---|---|
| **Version** | 1.1 (draft) |
| **Date** | 2026-10-12 |
| **Owners** | Product owners / reviewers |
| **Builder** | Coding agent |
| **Spec** | `APIM-Assessment-Spec.md` |
| **Tracking** | `APIM-Assessment-Task-Register.md` |

---

## 1. Objective
Deliver a read-only, reusable APIM assessment system in which deterministic PowerShell performs **Collect → Analyze → Render** and a constrained GitHub Copilot workflow performs **Review → Synthesize** over an independently validated, model-safe package. Support an initial customer integration APIM audit — Prod first, then Dev/Test — with a WARA-style Excel action plan and engaging self-contained HTML executive presentation.

## 2. Context and drivers
- The initial validation profile covers an integration APIM of roughly 60 APIs,
  growing external use, caller security, API organization, developer portal
  enablement, and cost visibility. Separate AI gateway advisory work is out of
  scope for the toolkit.
- The engagement has senior-management visibility and urgency.
- Authorized maintainers run the tool with Reader access on target resource groups.
- The synthetic reference topology is APIM Internal VNet behind App Gateway with
  host-wide forwarding and an assumed-reachable external edge.

## 3. Scope
**In scope (v1):** everything in the spec §1–§17: collectors, model, exposure classification, ~60 rules, fail-closed model-data airlock, local Copilot broker, architecture/security/executive agents, orchestration/deliverable skills, Excel template + report, HTML executive presentation, carry-forward, run diff, tests, docs, and authorized customer Prod/Dev/Test runs.

**Out of scope (v1):** remediation, Cloudflare API collection, Logic Apps workflow review, PowerPoint generation, AI gateway–specific rules, model access to raw/model/restricted customer data, and AI-generated rule results or direct report mutation.

## 4. Approach
Build in vertical slices so a trustworthy report exists early:

1. **Slice 1 (trusted engine):** config/logging + read-only ARM wrapper + APIM config/policy collection + manifest.
2. **Slice 2 (assessment authority):** normalized model + policy merge/flags + network/exposure + deterministic Security/Network/Governance rules.
3. **Slice 3 (model-safe review):** allowlist-only package builder + independent validator/scanner + physical promotion gate + local Copilot broker + architecture/security/executive agents.
4. **Slice 4 (MVP deliverables):** deterministic Excel action plan + self-contained HTML executive presentation with local alias resolution → first authorized Prod draft.
5. **Slice 5:** logs, metrics, cost, portal, Git drift, multi-env, carry-forward, run diff, Spectral.
6. **Hardening:** canary/mutation/airlock tests, coverage target, docs, live smoke, visual/accessibility review, acceptance.

The coding agent builds and tests against **synthetic fixtures** only; authorized
maintainers perform live runs in a customer-approved environment.

### 4.1 Trust model

- PowerShell remains authoritative for collection, normalization, findings, scoring, evidence, data safety validation, and report rendering.
- Copilot receives only a closed-schema, pseudonymized package promoted into a separate analysis zone after local validation succeeds; the restricted collection root is outside every Copilot-visible path.
- The model cannot access Azure credentials, raw/model folders, alias maps, arbitrary paths, collection stdout/stderr, or generic shell tools.
- Specialist agents may explain and correlate deterministic facts but cannot invent evidence, change severity, or resolve findings.
- Customer-facing names and exact metrics are reintroduced only by the local renderer after model work is complete.

## 5. Phases, milestones and timeline

Target start Tue 2026-10-13. Durations assume a dedicated coding agent with daily product-owner review.

| Phase | Dates (target) | Content | Exit criteria / milestone |
|---|---|---|---|
| **P0 Setup** | Oct 13 | Repo, module skeleton, config loader, CI lint/test, fixture scaffold | **M0** – repo builds, Pester + ScriptAnalyzer run in CI |
| **P1 Core + APIM collection** | Oct 13–15 | ARM wrapper (read-only guard, paging, retry), service/API/product/subscription/named value/backend/cert/diagnostic/policy collectors, manifest | **M1** – raw folder produced against test APIM; guard tests pass |
| **P2 Model + exposure** | Oct 15–17 | Policy merge + flags, API/operation/policy matrix/subscription models, network collection, exposure classifier | **M2** – fixture yields correct exposure labels incl. host-wide forwarding |
| **P3 Rules + model-safe report MVP** | Oct 19–23 | Rule engine/scoring, SEC/NET/GOV/REL rules, model-data airlock, broker, specialist agents/skills, Excel and HTML renderers | **M3 – MVP** – canary/mutation gate green; first authorized **Prod** run + draft action plan and executive presentation reviewed by product owners |
| **P4 Telemetry + cost** | Oct 23–27 | Log Analytics (schema detect, queries), metrics, cost + Logic Apps cost-only, LA ingestion; usage/cost rules; Usage/Cost sheets | **M4** – Prod run with usage-based exposure (ExternalInUse vs Unintended) and cost views |
| **P5 Portal, drift, lifecycle** | Oct 27–30 | Portal collection/rules, Git hashing + drift, multi-env compare, carry-forward, run diff, Spectral (optional) | **M5** – Dev/Test runs; drift sheet; carry-forward verified |
| **P6 Hardening + acceptance** | Oct 30–Nov 3 | Coverage ≥ 80%, docs (README, RUNBOOK, RULES), live smoke, secret/airlock scans, visual/accessibility review, acceptance criteria §17 | **M6 – v1.0** tagged |
| **Delivery (engagement)** | Oct 24 → Nov 10 | Working sessions using M3/M4 outputs; Excel action plan and HTML executive presentation support the final readout | Readout delivered |

Engagement alignment:
- **Working session 1 (security & exposure):** after M3/M4 — exposure map, NET/SEC findings, edge-origin authentication questions.
- **Working session 2 (API organization & portal):** after M5 — products/tags/hostname split model, portal plan, drift.
- **Working session 3 (cost & monitoring):** after M4 — cost sheet, Logic Apps cost observation, dashboard approach.
- **Readout:** final v1.0 run on Prod + summary of Dev/Test drift.

## 6. Roles and responsibilities

| Role | Who | Responsibilities |
|---|---|---|
| Product owner / reviewer | Designated maintainer | Spec decisions, rule severity/recommendations, report review, live runs, customer readout |
| Product owner / reviewer | Designated maintainer | Live runs, AI landing zone alignment, customer coordination, access follow-ups |
| Builder | Coding agent | Deterministic engine, local broker, validation, renderers, tests, fixtures, docs per spec; daily status in task register |
| Architecture/exposure analyst | Copilot custom agent | Review only the validated package; emit schema-valid, cited observations |
| Security analyst | Copilot custom agent | Review only the validated package; emit schema-valid, cited security observations |
| Executive synthesizer | Copilot custom agent | Reconcile validated findings/observations into a schema-valid executive narrative and priorities |
| Customer stakeholders | Designated contacts kept outside the repository | Access, edge confirmation, working sessions |

**Review cadence:** daily async review of the task register; PR review per phase; go/no-go at M3 before first customer run.

## 7. Working agreements for the coding agent
- Follow the spec; raise deviations as entries in the register's **Decisions/Issues** log before implementing.
- Never use or request real customer data; use `tests/fixtures` only.
- Never add write operations to Azure; never call secret-listing endpoints.
- Never expose raw/model/restricted data to a model. Build packages from an allowlist, validate locally, and promote only after a fail-closed gate passes.
- Never grant assessment agents generic shell/filesystem tools or access to collection stdout/stderr, credentials, alias maps, or restricted output roots.
- Keep AI observations traceable to model-safe fact/finding IDs and subordinate to deterministic findings.
- Never invent documentation URLs; leave `References` empty for maintainers.
- Each task is "Done" only when its acceptance check in the register passes and tests are committed.
- Update the register status, % complete and notes at the end of every work session.

## 8. Dependencies
| Dependency | Needed by | Status |
|---|---|---|
| Reader on target integration RGs (Dev/Test/Prod) | M3 | In place |
| Log Analytics Reader on APIM/App GW workspace(s) | M4 | Confirm |
| Cost data access | M4 | Customer stated cost access granted — confirm scope |
| GitHub repo access (APIM/IaC) | M5 | In progress (customer) |
| Microsoft-owned test APIM (Developer tier) + App GW for smoke tests | M1 | To provision |
| Workspace IDs, App GW names, subnet CIDRs for config | M3 | Discover on first run / fill config |
| GitHub Copilot CLI entitlement and organization policy approval for model-safe derived facts | M3 | Confirm before enabling specialist analysis; deterministic path remains available |
| Separate approved local collection and analysis-zone paths | M3 | Configure and validate non-overlap before agent-assisted runs |

## 9. Risks and mitigations

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Diagnostics not enabled or short LA retention → no usage data | Med | High (exposure intent, unused APIs) | Schema/retention detection; cap windows; `NotEvaluated` findings; recommend enabling diagnostics as a finding |
| R2 | Real client IP not logged (App GW subnet only) | High | Low | Route classification uses App GW subnet as designed; App GW access logs for listener split |
| R3 | Cost Management API throttling | Med | Low | Backoff + `-SkipCost`; resume |
| R4 | Cloudflare config unknown → origin-auth finding uncertain | High | Med | "Assumed reachable" banner; finding phrased "confirm with customer" |
| R5 | Hard-coded secrets exposure in our own outputs | Low | High | Redaction after flagging; secret-scan acceptance test; local storage guidance |
| R6 | Portal basic-auth detection ambiguity | Med | Low | Heuristic flagged in evidence; manual confirm |
| R7 | Policy merge edge cases (fragments, multi-product) | Med | Med | Dedicated unit tests; evidence carries scope attribution |
| R8 | Schedule pressure (customer urgency) | Med | Med | MVP slice first (M3) so working sessions start before v1.0 |
| R9 | Template/formula drift as columns change | Med | Low | Table-bound formulas; integration test validates Summary against findings |
| R10 | Customer or infrastructure data reaches model context | Low | Critical | Physical zone isolation; allowlist-only package construction; closed schema; independent prohibited-value scanner; canary/mutation tests; hash-attested promotion; narrow broker |
| R11 | Agent invents evidence or changes deterministic severity | Med | High | Closed observation schemas; required fact/finding citations; unsupported-reference rejection; deterministic findings remain authoritative |
| R12 | Collection errors leak identifiers through tool output | Med | High | Broker captures stdout/stderr and returns only opaque run IDs, fixed statuses and sanitized error codes |
| R13 | Visually engaging HTML obscures assumptions or is inaccessible | Med | Med | Fixed required sections, confidence/data-gap banner, accessible palette/semantics, reduced motion, print test and human visual review |

## 10. Quality gates
| Gate | When | Criteria |
|---|---|---|
| G1 Read-only | M1 | Guard tests pass; code review of all collectors |
| G2 Exposure correctness | M2 | All exposure fixture scenarios pass |
| G3 MVP go/no-go | M3 | Fixture end-to-end green; raw/model zone inaccessible to agents; canary/mutation and attestation gates green; agent outputs traceable; product owners review sample workbook and HTML presentation; no secrets or prohibited identifiers in model-safe outputs |
| G4 v1.0 | M6 | Spec §17 acceptance criteria all met |

## 11. Communication
- Task register is the single source of status (owners review daily).
- Decisions and issues logged in the register; customer-facing questions are batched for an authorized maintainer to send.
- Milestone demos: M3 (MVP workbook + HTML executive presentation), M5 (multi-env + carry-forward), M6 (v1.0).

## 12. Deliverables
1. `ApimAssessment` deterministic engine (code, rules, queries, schemas, templates, tests, docs).
2. Local Copilot broker, model-data airlock, specialist agent profiles, and orchestration/reporting skills.
3. Customer Prod action plan workbook and self-contained HTML executive presentation (draft at M3/M4, final at readout).
4. Customer Dev/Test runs + drift view.
5. Validated, cited readout inputs (top findings, KPIs, exposure map, priorities and next actions).
