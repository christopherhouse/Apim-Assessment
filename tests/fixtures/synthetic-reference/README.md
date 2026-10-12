# Synthetic reference-topology fixtures

This scaffold mirrors the *shape* of the reference environment, never a customer
export. All identifiers, IPs, policies, telemetry, and costs must be generated.
Do not include customer or engagement names, real-person names, or copied
customer data, even with a promise to anonymize it afterward.

The `raw/service.json` fixture is implemented for T-103 and describes a wholly
synthetic Internal VNet APIM service. Other raw subdirectories remain empty until
T-201 and subsequent collector/model tasks. Record exact counts and expected
outcomes here as each fixture surface is added. The target topology is Internal
VNet APIM behind a public Basic/host-wide Application Gateway route, disabled
WAF, and an assumed-reachable edge.

Planned T-201 counts: 60 APIs, four all-API subscriptions, 11 unused APIs,
14 APIs without products, seven key-only external APIs, three missing `<base/>`
cases, and two **synthetic** secret-pattern cases. These counts are targets,
not claims about fixtures that already exist.

Secret-pattern tests must use explicitly artificial strings. No real keys, JWTs,
connection strings, tenant IDs, or user identities are allowed.
