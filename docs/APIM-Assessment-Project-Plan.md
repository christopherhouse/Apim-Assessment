# APIM Assessment Toolkit — Project Plan

| | |
|---|---|
| **Version** | 1.0 (draft) |
| **Date** | 2026-10-12 |
| **Owners** | Chris House, JohnHenry Hain (product owners / reviewers) |
| **Builder** | Coding agent |
| **Spec** | `APIM-Assessment-Spec.md` |
| **Tracking** | `APIM-Assessment-Task-Register.md` |

---

## 1. Objective
Deliver a read-only, reusable PowerShell toolkit (Collect → Analyze → Report) that assesses Azure API Management and its front door, and use it to deliver Brother's integration APIM audit — Prod first, then Dev/Test — with a WARA-style Excel action plan feeding the readout.

## 2. Context and drivers
- Brother asked for (1) a full audit of the existing integration APIM (~60 APIs, growing external use), security of external calls, API organization, developer portal enablement, and cost visibility (including a reported Logic Apps cost increase), and (2) advisory input on a separate AI gateway APIM instance.
- Customer reports senior-management visibility and urgency.
- Access: Reader on integration resource groups is in place; Chris and/or JohnHenry run the tool.
- Known topology: APIM Internal VNet behind App Gateway, host-wide forwarding, Cloudflare in front (assumed reachable).

## 3. Scope
**In scope (v1):** everything in the spec §1–§17: collectors, model, exposure classification, ~60 rules, Excel template + report, carry-forward, run diff, tests, docs, Brother Prod/Dev/Test runs.

**Out of scope (v1):** remediation, Cloudflare API collection, Logic Apps workflow review, readout deck automation (v1.1), AI gateway–specific rules (v1.1).

## 4. Approach
Build in vertical slices so a usable report exists early:

1. **Slice 1 (MVP, priority):** core + APIM config/policy collection + model + exposure + Security/Network/Governance rules + Excel → first Brother Prod draft.
2. **Slice 2:** logs, metrics, cost, usage-driven rules (unused, ExternalUnintended, perf, cost).
3. **Slice 3:** portal, Git drift, multi-env, carry-forward, run diff, Spectral.
4. **Hardening:** tests to coverage target, docs, live smoke, acceptance.

The coding agent builds and tests against **synthetic fixtures** only; Chris/JohnHenry run live against Brother.

## 5. Phases, milestones and timeline

Target start Tue 2026-10-13. Durations assume a dedicated coding agent with daily review by Chris/JohnHenry.

| Phase | Dates (target) | Content | Exit criteria / milestone |
|---|---|---|---|
| **P0 Setup** | Oct 13 | Repo, module skeleton, config loader, CI lint/test, fixture scaffold | **M0** – repo builds, Pester + ScriptAnalyzer run in CI |
| **P1 Core + APIM collection** | Oct 13–15 | ARM wrapper (read-only guard, paging, retry), service/API/product/subscription/named value/backend/cert/diagnostic/policy collectors, manifest | **M1** – raw folder produced against test APIM; guard tests pass |
| **P2 Model + exposure** | Oct 15–17 | Policy merge + flags, API/operation/policy matrix/subscription models, network collection, exposure classifier | **M2** – fixture yields correct exposure labels incl. host-wide forwarding |
| **P3 Rules + report MVP** | Oct 19–21 | Rule engine, scoring, SEC/NET/GOV/REL rules, template workbook, report writer | **M3 – MVP** – first Brother **Prod** run + draft action plan reviewed by Chris/JH |
| **P4 Telemetry + cost** | Oct 21–23 | Log Analytics (schema detect, queries), metrics, cost + Logic Apps cost-only, LA ingestion; usage/cost rules; Usage/Cost sheets | **M4** – Prod run with usage-based exposure (ExternalInUse vs Unintended) and cost views |
| **P5 Portal, drift, lifecycle** | Oct 26–28 | Portal collection/rules, Git hashing + drift, multi-env compare, carry-forward, run diff, Spectral (optional) | **M5** – Dev/Test runs; drift sheet; carry-forward verified |
| **P6 Hardening + acceptance** | Oct 28–30 | Coverage ≥ 80%, docs (README, RUNBOOK, RULES), live smoke, secret-scan check, acceptance criteria §17 | **M6 – v1.0** tagged |
| **Delivery (engagement)** | Oct 22 → Nov 6 | Working sessions using M3/M4 outputs; readout with final run | Readout delivered |

Engagement alignment:
- **Working session 1 (security & exposure, with Kirit):** after M3/M4 — exposure map, NET/SEC findings, Cloudflare origin-auth questions.
- **Working session 2 (API organization & portal):** after M5 — products/tags/hostname split model, portal plan, drift.
- **Working session 3 (cost & monitoring):** after M4 — cost sheet, Logic Apps cost observation, dashboard approach.
- **Readout:** final v1.0 run on Prod + summary of Dev/Test drift.

## 6. Roles and responsibilities

| Role | Who | Responsibilities |
|---|---|---|
| Product owner / reviewer | Chris House | Spec decisions, rule severity/recommendations, report review, live runs, customer readout |
| Product owner / reviewer | JohnHenry Hain | Live runs, AI landing zone alignment, customer coordination, access follow-ups |
| Builder | Coding agent | Implementation, tests, fixtures, docs per spec; daily status in task register |
| Customer contacts | Kiran Asokan, Kirit Nayee (Brother) | Access (incl. GitHub), Cloudflare confirmation, working sessions |

**Review cadence:** daily async review of the task register; PR review per phase; go/no-go at M3 before first customer run.

## 7. Working agreements for the coding agent
- Follow the spec; raise deviations as entries in the register's **Decisions/Issues** log before implementing.
- Never use or request real customer data; use `tests/fixtures` only.
- Never add write operations to Azure; never call secret-listing endpoints.
- Never invent documentation URLs; leave `References` empty for maintainers.
- Each task is "Done" only when its acceptance check in the register passes and tests are committed.
- Update the register status, % complete and notes at the end of every work session.

## 8. Dependencies
| Dependency | Needed by | Status |
|---|---|---|
| Reader on Brother integration RGs (Dev/Test/Prod) | M3 | In place |
| Log Analytics Reader on APIM/App GW workspace(s) | M4 | Confirm |
| Cost data access | M4 | Customer stated cost access granted — confirm scope |
| GitHub repo access (APIM/IaC) | M5 | In progress (customer) |
| Microsoft-owned test APIM (Developer tier) + App GW for smoke tests | M1 | To provision |
| Workspace IDs, App GW names, subnet CIDRs for config | M3 | Discover on first run / fill config |

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

## 10. Quality gates
| Gate | When | Criteria |
|---|---|---|
| G1 Read-only | M1 | Guard tests pass; code review of all collectors |
| G2 Exposure correctness | M2 | All exposure fixture scenarios pass |
| G3 MVP go/no-go | M3 | Fixture end-to-end green; Chris/JH review sample workbook; no secrets in outputs |
| G4 v1.0 | M6 | Spec §17 acceptance criteria all met |

## 11. Communication
- Task register is the single source of status (owners review daily).
- Decisions and issues logged in the register; customer-facing questions batched for JohnHenry to send.
- Milestone demos: M3 (MVP workbook), M5 (multi-env + carry-forward), M6 (v1.0).

## 12. Deliverables
1. `ApimAssessment` toolkit (code, rules, queries, schemas, template, tests, docs).
2. Brother Prod action plan workbook (draft at M3/M4, final at readout).
3. Brother Dev/Test runs + drift view.
4. Readout inputs (top findings, KPIs, exposure map) for the readout deck.
