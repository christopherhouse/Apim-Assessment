# Synthetic reference-topology fixtures

This scaffold mirrors the *shape* of the reference environment, never a customer
export. All identifiers, IPs, policies, telemetry, and costs must be generated.
Do not copy customer data, even with a promise to anonymize it afterward.

The `raw` subdirectories are deliberately empty. Populate them in T-201 and
subsequent collector/model tasks, recording exact counts and expected outcomes
here. The target topology is Internal VNet APIM behind a public Basic/host-wide
Application Gateway route, disabled WAF, and an assumed-reachable edge.

Planned T-201 counts: 60 APIs, four all-API subscriptions, 11 unused APIs,
14 APIs without products, seven key-only external APIs, three missing `<base/>`
cases, and two **synthetic** secret-pattern cases. These counts are targets,
not claims about fixtures that already exist.

Secret-pattern tests must use explicitly artificial strings. No real keys, JWTs,
connection strings, tenant IDs, or user identities are allowed.
