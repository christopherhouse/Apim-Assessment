# Synthetic reference-topology fixtures

This scaffold mirrors the *shape* of the reference environment, never a customer
export. All identifiers, IPs, policies, telemetry, and costs must be generated.
Do not include customer or engagement names, real-person names, or copied
customer data, even with a promise to anonymize it afterward.

The implemented collector fixtures currently contain one APIM service, two APIs,
three API revisions, two operations, two API-tag assignments, two products,
three product/API memberships, two product/group memberships, and six
subscriptions. Four subscriptions are AllApis-scoped, including the built-in
master; one is product-scoped and one is API-scoped. Subscription fixtures store
only allowlisted metadata with derived owner types, never keys or owner IDs.
Security-asset fixtures add three named values, two backends, and two
certificates. Named-value values and backend credential values are absent;
fixtures retain only derived pattern locations and structural authentication
metadata. Certificate fixtures contain expiry and Key Vault references only,
never certificate bytes, passwords, or private material. Diagnostic fixtures add
two logger targets, one service diagnostic, and one diagnostic record for each
of the two APIs. `orders-v1` captures request/response bodies and sensitive
request-header names; `status-v1` records empty header arrays, zero-byte capture,
and a missing backend section. Logger credentials, descriptions, payload
samples, data-masking details, and header values are absent. The
policy fixture index covers eight scopes: five present policies, three absent
policies, and two structural hard-coded-secret locations whose committed XML
values are already redacted. API/product relationships contain three memberships so
`orders-v1` exercises both the `internal` and `partner` policy paths. The network
fixture contains one public Application Gateway, one linked disabled
Detection-mode WAF policy, one APIM subnet, one restricted NSG, one configured
Gateway public IP, and empty private-endpoint, private-DNS, route-table, and
other-front-door collections.
The current model fixtures contain three effective policies: two product paths
for `orders-v1|get-orders` and one inherited `status-v1|get-status` path. Both
orders paths expand `common-auth`; the operation backend records one missing
`<base/>`. `model/policyFlags.json` records expected flags for those three saved,
sanitized effective policies: both orders paths require JWT, retain two
hard-coded-secret locations, and report missing backend inheritance; only the
partner path is throttled. The status path has no policy risks or controls.
The API/operation model fixtures contain two current APIs and two operations.
`orders-v1|get-orders` has two product paths, requires JWT on both, and has
throttling on only one path; its matrix therefore passes caller authentication,
fails rate-limit coverage, hard-coded-secret absence, and base presence, and
reports backend authentication as `NA`. `status-v1|get-status` falls back to a
subscription-required product, so its API caller-auth classification is
`SubscriptionKeyOnly` while the matrix caller-auth control fails. The API model
uses the non-empty API diagnostic override for each API: `orders-v1` has known
body logging and sensitive request-header logging, while `status-v1` remains
unknown because its backend diagnostic section is missing. Unavailable backend,
exposure, findings, Git, OpenAPI-quality, and usage inputs remain explicit
`null`/Partial values. Record exact counts and expected outcomes here as each
fixture surface is added.
The network model fixture proves that Internal VNet APIM behind a public
Basic/host-wide Application Gateway route, with a restricted APIM-subnet NSG,
is not directly public even though its configured App Gateway listener is
public. WAF is disabled and the external edge remains assumed reachable.
The exposure fixture contains two route-by-API records from that one public
Basic listener: both APIs are Reachable with no effective route restriction, but
both remain `exposure=Unknown`, Medium confidence, and Partial because route
usage is not yet available. `model/apis.exposure.json` records the corresponding
post-exposure API backfill separately from the pre-exposure `model/apis.json`
fixture used by the API-model tests.

Planned T-201 counts: 60 APIs, four all-API subscriptions, 11 unused APIs,
14 APIs without products, seven key-only external APIs, three missing `<base/>`
cases, and two **synthetic** secret-pattern cases. These counts are targets,
not claims about fixtures that already exist.

Secret-pattern tests must use explicitly artificial strings. No real keys, JWTs,
connection strings, tenant IDs, or user identities are allowed.
