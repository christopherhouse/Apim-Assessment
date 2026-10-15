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
The service model fixture records Premium capacity two, no zones, platform
version `stv2`, all five recognized legacy TLS controls as explicitly disabled,
a future service-hostname certificate expiry, a minimum management API version,
and a system-assigned identity. Its baseline
therefore produces REL-001 but not REL-002/REL-006, and no SEC-001, SEC-002, or
SEC-019 finding. Focused tests mutate each structural fact for positive,
non-finding, and missing-evidence cases; no resource or user-assigned identity
IDs enter the model.
The security-asset model fixtures contain three sorted named values, two
backends, and two certificates. `partner-api-key` has only structural
`displayName`/`value` secret-pattern locations and produces the expected
SEC-008 finding without storing its value. `orders-backend` is HTTPS with both
certificate-validation controls enabled; `status-backend` is HTTP and its
non-applicable TLS facts are null, so the baseline has no SEC-010 finding and
one SEC-011 Backend finding unless that exact backend ID is configured as an
approved plain-HTTP exception.
Focused rule tests mutate the HTTPS hostname-validation fact to false for the
positive case. The uploaded certificate is explicitly not Key Vault-backed and
produces the baseline SEC-009 certificate finding; the secret named-value
reference has a successful Key Vault status. Certificate model records retain
only normalized expiry and Key Vault-backed status.
The baseline App Gateway route uses the default `/` probe path, producing one
REL-004 finding. The uploaded certificate expires within the configured 60-day
threshold relative to the fixed focused-test run timestamp, producing one
REL-005 finding. No backend is critical by default; focused tests explicitly
target `status-backend` to exercise REL-003 without embedding fixture-specific
criticality in configuration.
The API/operation baseline produces six governance findings: both APIs lack an
owner/team tag, `status-v1` has one non-current online revision, both version
sets contain only one known version, and the orders operation has a missing
`<base/>` path. Both APIs belong to products and use the same no-version-segment
path convention, so GOV-001 and GOV-008 do not fire until focused tests mutate
those facts.

Git and drift acceptance creates disposable synthetic repositories/runs during
tests rather than tracking a source export. Git tests cover four default scope
mappings plus explicitly configured fragments, committed/dirty/untracked
semantics, protected-hash parity, mapping ambiguity/collisions, links, root
escapes and failed collectors. No fixture contains Git author/remotes or secrets
in its persisted policy inventory. The compact eight-policy/two-API snapshots
compare as eight policy rows plus two catalog rows per environment pair.
No Git/comparison sources leave the baseline at ten required models and emit
Info/NotEvaluated GOV-007/GOV-011 results; explicitly selected sources add one
optional drift model. Equal complete environments produce no GOV-011 finding.
Focused mutations produce one policy difference or production-only policy,
retain Unknown for partial inventories/unmapped Git scopes, and reject stale
input/model/Git bindings. Replay succeeds after the external source folder moves.
Integrated acceptance renders populated Environment Drift plus paired HTML,
and independently validates package 1.2 with only the approved drift code and
existing service alias, never source names, hashes, XML or paths.

`scaled/New-SyntheticReference.ps1` now generates the separate T-201 model
scenario: 60 APIs, four all-API subscriptions, 14 APIs without products, seven
key-only externally reachable APIs, three missing `<base/>` cases, and two
**synthetic** secret-pattern cases. `-WithUsage` supplies explicit synthetic
telemetry with 11 unused APIs; without it usage remains null and exposure
Unknown. Policies are detected before redaction and returned sanitized.
The scaled README documents overlapping cohorts and expected outcomes.
All ten generated model files validate and round-trip through the saved loader;
the existing compact raw/model fixtures above remain unchanged. This is not
an implementation of telemetry collection or a scaled ARM collector export.

Portal model/rule tests construct disposable synthetic evidence: one modern and
one legacy status, five portal-setting/revision payloads, one Entra provider,
one product, and one intended/actual partner-group membership. The passing
model has a current completed publication, direct basic-auth false, sign-up
false, matching product intent and a developer-portal domain under example.invalid.
Mutations exercise each of POR-001/002/003/005 independently, missing/conflicting
evidence, non-Entra identities, guests only for explicit nonpublic intent and
unresolved targets. POR-004 uses five synthetic operations to prove 4/5 is the
80-percent boundary and 3/5 fails, with score 70/69 and empty/incomplete cases.
The package/report case produces four evaluated portal conditions under existing
Service aliases, independently validates closed package 1.3, preserves Partial
confidence, and renders the existing paired Excel/HTML views without exporting
domains, provider/group/product identifiers or exact coverage. Baseline
ten-model fixtures still omit portal to exercise old-run compatibility.
The compact raw-to-report helper additionally stages one Identity item and five
Portal items, adding the optional portal model. Its
integration case preserves raw hashes across Analyze/Report. Saved-evidence tests
retain known Partial positives, reject malformed manifest-listed Identity/Portal
files, ignore unlisted stale files, and replay/report the old ten-model path.

OpenAPI acceptance generates disposable JSON definitions and export envelopes,
never imports a real definition. The compact collected-run helper adds two
current HTTP exports plus one closed index; Analyze adds the optional quality
model (twelve models with portal, thirteen when drift is also selected).
Collector tests exercise non-HTTP skips, inline/link transport, safe failure
metadata, malformed/duplicate JSON, size limits, secret-candidate rejection,
and Partial output/resume. Quality tests cover pinned real-tool and mocked
no-tool/failure paths, same-document references and refused external references,
score arithmetic/clamping and empty/incomplete operation coverage.
Saved-evidence tests bind source/settings/ruleset/model evidence, reject changed
and duplicate-member artifacts, ignore unlisted exports and replay reports
without a linter or Azure calls. A synthetic score of 58 produces POR-004 with
the Spectral method and package 1.3 `ApiDocumentationWeak` only; exact quality
counts/digests and definitions never enter the independently validated package.
Removing OpenApi collection and explicitly reanalyzing removes obsolete quality
and its binding; legacy ten-model inputs still work without recollection.

`analysis-contracts/` adds four independent T-317 JSON examples, not a package
generated or promoted from the raw/model fixture tree. Its package contains
four entity aliases, six typed facts, and three reduced findings (two Evaluated,
one Info/NotEvaluated). There is one observation for each specialist and an
executive summary with two priorities, one theme, one decision, and one roadmap
item. All references resolve and assumptions/data gaps are retained. Tests
mutate these examples to reject unknown fields, exact metrics/free text,
duplicate members/IDs, unsupported references, invalid analyst identity, and
lost or invented executive qualifications. The independent airlock integration
suite now exercises generated saved models through findings, construction,
validation, and promotion, plus source canaries and candidate mutations.
The 1.0 examples remain independent contract examples, not collected data.

Secret-pattern tests must use explicitly artificial strings. No real keys, JWTs,
connection strings, tenant IDs, or user identities are allowed.
