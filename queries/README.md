# Assessment queries

Store Log Analytics queries as `*.kql`, AzureDiagnostics fallbacks as
`*.azdiag.kql`, and Resource Graph queries as `*.arg.kql`.

The five APIM aggregate queries have resource-specific and AzureDiagnostics
variants. `schema.kql` tests for APIM rows before selecting a schema.
`laIngestion.kql` returns billable workspace ingestion by data type and day;
workspace ingestion is not evidence of attribution to an individual resource.
The collector binds UTC run-anchored, retention-capped half-open intervals and
escapes configured resource/CIDR values before execution. No query returns
caller IPs, subscription identifiers, headers or payloads. Distinct subscription
counts are approximate; individual-subscription call counts remain unavailable.
Route aggregates are descriptive only and do not implement observed exposure.

Offline tests parse the bound queries using the pinned Kusto.Language parser.
App Gateway listener/direct-route/header queries remain planned (T-403).
The implemented TLS and no-subscription aggregates do not enable the deferred
observed-route exposure or security rules by themselves.
