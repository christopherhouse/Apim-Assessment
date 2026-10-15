# Versioned JSON contracts

Versioned manifest, model, findings, action, and model-safe JSON schemas live here.
`manifest.schema.json` is validated before each manifest write with
`Test-Json -SchemaFile`. Closed schemas cover ten required baseline model files,
the optional bound drift, portal and OpenAPI-quality models,
instance findings, and aggregated action items. Future model contracts remain
deferred to their builders. Follow specification sections 6, 8, 9, and 10, use
camelCase fields and stable keys, and do not turn unavailable collector data
into an empty successful result.

## Restricted run settings

`run-settings.schema.json` closes the version 1.0 offline analysis settings
snapshot stored at `restricted/run-settings.json`. It contains only the
run/tool binding, configured gateway identities and subnet CIDRs, certificate
expiry threshold, exact backend/operation rule exceptions and critical targets,
six usage-band thresholds, optional explicit portal product visibility and
optional OpenAPI error/warning penalties. All fields use camelCase. It excludes private
configuration, paths, tokens, credentials, and user identities. Gateway
identities remain restricted; this schema does not authorize model access.
The loader validates the schema, identity/version binding, CIDR values, and
strictly increasing bands, and reconstructs scoring/edge settings from the
manifest. Collection separately stores a versioned configuration SHA-256 for
resume compatibility, never the full private configuration.

## Restricted report lifecycle

`comparison.schema.json` closes version 1.0 `diff.json`: source snapshot hashes,
historical/current severity, comparable changes, separate reassessment gaps,
pillar counts, and nullable KPI values/deltas with fixed availability reasons.
`comparison-binding.schema.json` binds the serialized comparison's canonical
digest in `restricted/comparison-binding.json`. Readers also recheck current
models/findings/settings provenance. Hashes are integrity checks under an
operator-owned filesystem, not signatures. Snapshot digests exclude changing
stage statuses and normalize findings/model inventory order.

`tracking.schema.json` closes imported report-only tracking records. Status is
an approved operator workflow value or null; deterministic `findings.json`
continues to require status Open. Workbook scope/key/date/formula/archive checks
are additional gates. None of these contracts is model-safe or eligible for
agent tools. Schema parsing also rejects duplicate JSON members.

## Optional restricted drift (T-505/T-506)

`git-policy-hashes.schema.json` closes version 1.0 committed Git output:
commit SHA, sorted scope coverage and unique ordered policy scope/hash records.
Runtime validation also enforces coverage, uniqueness and ordinal ordering.
No XML, source path, author, remote or credentials may be stored.

`drift-inputs.schema.json` closes version 1.0 restricted current/source policy
and API-presence inventories. It supports one optional Git source and up to 15
explicit environment runs without retaining external source paths. Identity
grouping, collector completeness, policy XML/hash checks and unique scope keys
are additional gates. `drift.schema.json` closes optional pairwise model rows:
presence and protected hashes are nullable; Unknown and fixed gap codes preserve
missing scope coverage/incomplete evidence. Full API definitions are not diffed.
The existing ten-model baseline remains required; absence of optional drift does
not break ordinary single-run loading.

`restricted/drift-binding.json` has a fixed runtime-validated version 1.0 shape:
`schemaVersion`, `inputsSha256`, and `modelSha256`. Readers rebuild drift from
saved inputs and compare current deployed/saved Git evidence too. Missing or
changed requested artifacts fail. Reanalysis never needs the external run paths.
These local integrity bindings are not signatures, and none of these artifacts
is model-safe or eligible for agent access.

## Optional restricted OpenAPI quality (T-105/T-504)

`openApiQuality.schema.json` closes an optional version 1.0 per-API array.
Only `Scored` rows have numerical error/warning counts and score. Other fixed
statuses preserve tool/export/reference/unsupported-type failures, nullable
scores and qualified description coverage. Runtime semantic validation rejects
duplicate/orphan APIs, incorrect score arithmetic, operation-count/coverage
conflicts and API backfill mismatches.

The runtime-validated `restricted/openapi-binding.json` has exactly
`schemaVersion`, `modelSha256`, `exportsSha256`, `settingsSha256` and
`rulesetSha256`. Readers compare the model, validated manifest-listed export
inventory, exact penalties and trusted local ruleset. Each row's source digest
must match its exported document. Binding retains tool version through the
closed quality model digest; replay never executes a linter or depends on an
installed tool. Local digests assume operator-owned storage, not digital signing.
Missing optional quality does not break legacy ten-model runs, while a present
model or orphaned binding fails closed if invalid.

Raw OpenAPI documents and closed export indexes remain restricted collector
output; neither those artifacts nor quality rows, exact metrics, source hashes,
diagnostic output, server URLs or samples are eligible for model access.
Existing package 1.3 `ApiDocumentationWeak` is the only quality condition.

## Model-safe contracts (T-317)

`analysis-package.schema.json`, `expert-observations.schema.json`, and
`executive-summary.schema.json` are self-contained draft-07 schemas with
`schemaVersion: "1.0"`. They resolve only local fragment references and close
every record with `additionalProperties: false`; no remote schema is loaded.

The package defines entities, typed facts, reduced deterministic findings,
assumptions, and data gaps. Alias prefixes identify Service, Api, Operation,
Product, Subscription, NamedValue, Backend, Certificate, Network, and Route
entities, followed by three to six ASCII digits with a nonzero ordinal.
Fact/finding IDs use six-digit ordinals. Fact codes constrain their value:
topology/authentication/exposure enums, nullable control booleans, usage buckets,
relative cost trends, or structural inventory counts from 0 to 10,000. Exact
usage, cost, priority scores, raw evidence, names, URLs, and free text have no
field in these contracts.

Specialist rationale/recommendations and executive priorities/themes/decisions/
roadmap entries use only the enums declared in their schemas. The private
`Test-ApimAnalysisContract` gate additionally checks decoded duplicate JSON
members, unique IDs, alias-kind agreement, resolving references, analyst/item
identity, missing-evidence qualifications, and exact package assumption/data-gap
carry-forward. Supplied specialist sets are revalidated before their references
can be used in an executive summary. A deterministic-only summary can cite
package facts/findings without specialist context.

Contract validation alone is not privacy certification, prohibited-value
scanning, source-evidence/claim verification, hash attestation, or promotion.
No agent receives a package here. Those boundaries remain separate tasks;
vocabulary changes require deliberate contract review rather than accepting
arbitrary strings or new fields.

## Private airlock contracts (T-318/T-319)

`analysis-package.v1.1.schema.json` adds approved `AssessmentCondition` values
and six configured positive usage bands to the existing closed package shape.
`analysis-package.v1.2.schema.json` preserves that shape and adds only the two
approved conditions `SourcePolicyDrift` and `EnvironmentPolicyDrift`, projected
onto existing service aliases. Older schemas are not broadened; the contract
gate selects exactly 1.0, 1.1 or 1.2 and rejects other versions. The independent
scanner and attestation accept 1.2 explicitly; semantic governance claims require
its cited condition evidence. Git paths, commits, policy hashes, XML and
environment identities have no field. Specialist/executive contracts remain
1.0 and may cite any supported package version.

The builder replays the implemented rules against validated saved models and
configuration, checks the saved findings, and constructs condition facts from
the fixed rule-to-condition mapping. It never copies finding evidence/text or
arbitrary model properties. Usage requires six strictly increasing thresholds
starting at zero; positive values select the greatest matching lower bound
(`VeryLow`, `Low`, `Medium`, `High`, `VeryHigh`, `Extreme`), with explicit
`Zero` and `Unknown`. Relative priority boundaries are one third/two thirds
of the configuration's maximum score. See specification section 10.6 and D-48.

`validation-attestation.schema.json` closes schema version 1.0 attestations:
package schema version, exact-byte SHA-256, module-derived tool compatibility
versions, status, and three fixed passing checks. No paths, times, identifiers,
rejected excerpts, or arbitrary diagnostics are allowed. Parsing rejects
duplicate members, excessive nesting, and attestations over 64 KiB.
The attestation is a local integrity record, not a digital signature or builder
provenance claim.

The independent privacy validator maintains its own field-specific vocabulary,
ASCII/encoding/prohibited-value checks, size/depth/work bounds, and fixed safe
failure code. It is distinct from the saved-run accident-detection secret scan.
Private promotion revalidates a fresh snapshot, verifies hashes and persisted
attestation, and atomically renames a two-file directory into a new immutable
version. Host-enforced root isolation and exclusive ownership remain required;
these schemas do not grant tools, trust, or model access.

## Broker startup and proposal binding (T-321-T-323)

`broker-operator.schema.json` is a closed local startup contract, not a model-safe
artifact. It contains paths/config aliases/registered saved runs and must remain
inside the operator-owned restricted root. Approval, exclusive filesystem and
complete-visible-root flags must all be true; canonical path/link/disjointness
checks are additional runtime requirements. These declarations do not prove
actual host permissions, and no tool accepts them.

The seven tool input/result contracts are generated locally by the broker.
Unknown fields/operations, caller paths, arbitrary text in returned statuses,
malformed/duplicate JSON, stale digest/output bytes and unsupported output IDs
fail closed. Results contain only approved statuses, hashes and opaque IDs, or
independently revalidated model-safe package/proposals.

The original observation/executive schemas remain version 1.0. A separate
`Test-ApimAgentClaim` evidence compatibility gate rejects unrelated or
contradictory cited facts/findings, incompatible recommendations/categories,
confidence escalation, unsupported executive codes/posture/priorities, and lost
or invented assumptions/data gaps. A vocabulary enum is not proof of evidence:
diagnostic capture does not entail insufficient diagnostic coverage.
Proposal handoff supplies the exact promoted digest outside the proposal JSON.
`agent-output-binding.schema.json` closes each restricted version 1.0 sidecar:
output ID, contract kind, exact package digest and output digest, with no paths
or narrative. Sidecars retain auditable bindings after process exit; IDs still
expire and are not automatically restored at restart. Every read/render
revalidates context. Immutable publication directories still contain exactly
package/attestation, never proposal output or alias maps.
