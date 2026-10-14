# Versioned JSON contracts

Versioned manifest, model, findings, action, and model-safe JSON schemas live here.
`manifest.schema.json` is validated before each manifest write with
`Test-Json -SchemaFile`. Closed schemas cover all ten registered model files,
instance findings, and aggregated action items. Future model contracts remain
deferred to their builders. Follow specification sections 6, 8, 9, and 10, use
camelCase fields and stable keys, and do not turn unavailable collector data
into an empty successful result.

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
