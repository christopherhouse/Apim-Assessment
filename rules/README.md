# Assessment rule catalogs

Planned catalogs: `SEC`, `GOV`, `REL`, `PERF`, `POR`, and `COST.rules.ps1`.
Use the hashtable contract in specification section 10 and stable catalog IDs in
section 11. The private rule engine, closed `findings.json` schema, and restricted writer
are implemented. `NET.rules.ps1` contains NET-002/004/006/007/008; NET-001 and
NET-009 remain unimplemented until their origin/portal evidence is modeled.
Synthetic definitions in unit tests exercise the contract. The current
engine supports Service, Api, Operation, Subscription, Route, and Network
targets backed by the implemented models. A rule must list its target model
in `Requires` and every additional model it reads; rule callbacks receive the
target and a context with `Config`, `Models`, and `Manifest`.

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
