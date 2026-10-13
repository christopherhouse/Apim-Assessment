# Synthetic reference-topology fixtures

This scaffold mirrors the *shape* of the reference environment, never a customer
export. All identifiers, IPs, policies, telemetry, and costs must be generated.
Do not include customer or engagement names, real-person names, or copied
customer data, even with a promise to anonymize it afterward.

The implemented collector fixtures currently contain one APIM service, two APIs,
three API revisions, two operations, two API-tag assignments, two products,
three product/API memberships, and two product/group memberships. The policy
fixture index covers eight scopes: five present policies, three absent policies,
and two structural hard-coded-secret locations whose committed XML values are
already redacted. API/product relationships contain three memberships so
`orders-v1` exercises both the `internal` and `partner` policy paths. Other raw
subdirectories remain empty until T-201 and subsequent collector/model tasks.
The current model fixtures contain three effective policies: two product paths
for `orders-v1|get-orders` and one inherited `status-v1|get-status` path. Both
orders paths expand `common-auth`; the operation backend records one missing
`<base/>`. Record exact counts and expected outcomes here as each fixture surface
is added. The target topology is Internal VNet APIM behind a public
Basic/host-wide Application Gateway route, disabled WAF, and an
assumed-reachable edge.

Planned T-201 counts: 60 APIs, four all-API subscriptions, 11 unused APIs,
14 APIs without products, seven key-only external APIs, three missing `<base/>`
cases, and two **synthetic** secret-pattern cases. These counts are targets,
not claims about fixtures that already exist.

Secret-pattern tests must use explicitly artificial strings. No real keys, JWTs,
connection strings, tenant IDs, or user identities are allowed.
