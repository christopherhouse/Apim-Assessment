# Assessment rule catalogs

Planned catalogs: `GOV`, `REL`, `PERF`, `POR`, and `COST.rules.ps1`.
Use the hashtable contract in specification section 10 and stable catalog IDs in
section 11. The private rule engine, closed `findings.json` schema, and restricted writer
are implemented. `NET.rules.ps1` contains NET-001/002/004/006/007/008/009.
NET-001 and NET-009 evaluate only explicitly operator-attested evidence in
the closed network model; absent/unknown attestations remain NotEvaluated.
Synthetic definitions in unit tests exercise the contract. The current
engine supports Service, Api, Operation, Subscription, NamedValue, Backend,
Certificate, Route, and Network targets backed by the implemented models. A rule
may declare one scope or a non-empty unique array of scopes. It must list every
target model in `Requires` plus every additional model it reads; the same
callbacks evaluate each target independently, while a missing required model or
fact still produces one NotEvaluated finding for the rule. `TargetField` remains
limited to a single Route scope. Rule callbacks receive the target and a context
with `Config`, `Models`, and `Manifest`.
NET-009's Route target is the allowlisted `network.auxiliaryRoutes` field,
not an API route in `exposure.json`.
`SEC.rules.ps1` contains
SEC-003/004/005/007/008/009/010/011/012/014/015/020. These rules use only the
implemented API, operation, subscription, named-value, and backend models.
Positive evidence
is retained when another record is incomplete; otherwise unknown applicable
facts produce one NotEvaluated finding. SEC-008 uses derived structural
locations without retaining values. SEC-009 evaluates named-value and
certificate Key Vault posture under one stable rule ID and preserves known
positives when another fact is unavailable. SEC-010 applies only to HTTPS
backends and keeps missing validation facts unknown. SEC-011 evaluates backend
scheme and operation-level policy override facts. Its optional allowlist matches
only exact backend IDs or `apiId/operationId` keys and never infers that an API
is internal; Partial policy evidence remains unknown when no unapproved HTTP
target is known. The remaining SEC rules require future service/security,
backend intent/mapping, product-classification, telemetry, or authorization
evidence and must not be approximated from partial fields.
The current synthetic NET fixture has two API route records and one App
Gateway. Focused tests add one attested edge/origin assessment and one
attested public portal route: NET-001 and NET-009 each yield one evaluated
finding; the unchanged fixture yields one NotEvaluated finding per rule.

Each rule needs positive, negative, and missing-input tests against synthetic
models. Missing/failed required files produce one Info/NotEvaluated finding
per rule. The optional `DataGaps = { param($ctx) ... }` callback returns
`model/<name>.json#<field>` for required facts that remain unknown within a
valid declared model; the engine emits one Info/NotEvaluated finding and rejects
undeclared paths or invalid values. Invalid available models or callback output
fail closed. Unknown usage stays null and uses a neutral multiplier rather than
being treated as unused.
Rule authors must check any relevant per-record `missingInputs` before returning
a negative result. References are supplied by maintainers, not invented by
the tool.
Generate `docs/RULES.md` from the catalog when task T-607 is implemented.
