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
Monthly usage remains descriptive; complete saved `usageByRoute` evidence now
feeds the source-bound exposure classifier under settings 1.2.

`appgwSchema.kql` independently detects scoped gateway access-log schemas.
`appgwByListener` and `appgwNonEdge` have resource-specific/legacy variants and
return gateway/listener/rule/host counts and approximate distinct-client counts,
never per-IP rows. Non-edge class is fixed NonEdge/Unknown; configured trusted
IPv4 ranges are required. `directNonAppGw` returns per-API counts only for
parseable callers outside gateway and internal CIDRs. `headersLogged` returns
observed-header-bag and two header-name presence counts, never values.
Both APIM queries have legacy variants. Independent AppGateway retention/window
coverage and closed saved evidence prevent partial queries from becoming zero.

Offline tests parse the bound queries using the pinned Kusto.Language parser.
These aggregates do not implement the deferred T-409 security/network/PERF rules.
Parser/mocked acceptance is not live Kusto execution; maintainers own that gate.
