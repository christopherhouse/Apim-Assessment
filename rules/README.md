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
must list its target model
in `Requires` and every additional model it reads; rule callbacks receive the
target and a context with `Config`, `Models`, and `Manifest`.
NET-009's Route target is the allowlisted `network.auxiliaryRoutes` field,
not an API route in `exposure.json`.
`SEC.rules.ps1` contains
SEC-003/004/005/007/008/010/012/014/015/020. These rules use only the
implemented API, operation, subscription, named-value, and backend models.
Positive evidence
is retained when another record is incomplete; otherwise unknown applicable
facts produce one NotEvaluated finding. SEC-008 uses derived structural
locations without retaining values. SEC-010 applies only to HTTPS backends and
keeps missing validation facts unknown. The remaining SEC rules require future
service/security, multi-scope Key Vault, configurable plain-HTTP exception,
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
