# Assessment rule catalogs

Planned catalogs: `SEC`, `NET`, `GOV`, `REL`, `PERF`, `POR`, and `COST.rules.ps1`.
Use the hashtable contract in specification section 10 and stable catalog IDs in
section 11. The private rule engine, closed `findings.json` schema, and restricted writer
are implemented; no production rule catalogs exist yet. Synthetic definitions
in unit tests exercise the contract without advertising real rules. The current
engine supports Service, Api, Operation, Subscription, Route, and Network
targets backed by the implemented models. A rule must list its target model
in `Requires` and every additional model it reads; rule callbacks receive the
target and a context with `Config`, `Models`, and `Manifest`.

Each rule needs positive, negative, and missing-input tests against synthetic
models. Missing/failed required files produce one Info/NotEvaluated finding
per rule; invalid available models or callback output fail closed. Unknown usage
stays null and uses a neutral multiplier rather than being treated as unused.
Rule authors must check any relevant per-record `missingInputs` before returning
a negative result. References are supplied by maintainers, not invented by
the tool.
Generate `docs/RULES.md` from the catalog when task T-607 is implemented.
