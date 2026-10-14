# Scaled synthetic reference (T-201 bounded slice)

This additive, offline generator preserves the compact two-API fixtures in the
parent tree. It uses synthetic fixture cloning **only for test-data generation**,
not as a runtime/package-builder implementation. No Azure calls, credentials,
secret retrieval, customer data, or new package code are needed.

## Available interface

Dot-source `New-SyntheticReference.ps1` **inside ApimAssessment module scope**;
the generator uses existing private policy detection/redaction helpers. It
defines `New-SyntheticReferenceModelSet [-WithUsage]`, returning one ordered
`System.Collections.IDictionary` with exactly the ten registered model keys.
It does not persist anything. Integration callers can use the existing writer:

```powershell
Import-Module ./ApimAssessment.psd1 -Force
& (Get-Module ApimAssessment) {
    param($generator, $runPath)
    . $generator
    $models = New-SyntheticReferenceModelSet # default: no usage supplied
    # Or: $models = New-SyntheticReferenceModelSet -WithUsage
    $null = Write-ApimModelSet -RunPath $runPath -Models $models
} (Join-Path $PWD 'tests/fixtures/synthetic-reference/scaled/New-SyntheticReference.ps1') `
  (Join-Path $PWD 'artifacts/scaled-synthetic-run')
```

`New-SyntheticReferencePolicy -Index <1..60>` returns sanitized XML, structural
secret locations and policy flags for tests; it never returns the raw candidate.
Both secret cases are constructed in memory, detected by
`Get-ApimPolicySecretLocation` **before** `Protect-ApimPolicyXml`, then flags are
derived from sanitized XML. Only location evidence survives; no raw secret
fixtures or policies are saved. Any caller saving this helper's XML gets the
sanitized version.

## Exact counts and cohorts

| Surface | Count / expected behavior |
|---|---|
| service / network | One each, cloned synthetic topology |
| apis / operations / policyMatrix / exposure | 60 each; sorted `api-001`–`api-060`, one GET operation and one host-wide route per API |
| subscriptions | Six, including four AllApis (three active, one suspended); API-scoped target updated to `api-001` |
| namedValues / backends / certificates | Three / two / two, existing secret-safe metadata |
| Productless APIs | 14: `api-047`–`api-060`; others in `internal` |
| Key-only externally reachable APIs | Seven: `api-001`–`api-007`; others JWT-authenticated and throttled |
| Missing backend `<base/>` | Three: `api-001`–`api-003`, reflected in API/operation flags and matrix |
| Hard-coded-secret structural cases | Two: `api-001`–`api-002`, one redacted Authorization value location each |
| Explicit unused-API scenario | **Only with `-WithUsage`:** 11, `api-050`–`api-060` |

Topology remains Internal VNet, restricted APIM-subnet NSG, no direct public
APIM, public Basic `/*` Application Gateway route, disabled WAF, and
`Cloudflare-Assumed` edge. JWT and subscription requirements do not block route
reachability: all 60 routes remain Reachable, with no effective route restriction.
The inherited compact network represents the edge allowlist/restricted NSG
structurally; this slice does not add raw network or edge configuration collection.

Without the usage switch, API/operation/subscription/route usage is **null, never
zero**, dependent records retain `missingInputs: ["usage", ...]`, API/route
exposure stays Unknown, and routes remain Partial/Medium confidence. With the
switch, 49 APIs have deterministic artificial external calls and 11 have explicit
zero calls; API/operation/route `usage` gaps are removed and route exposure is
ExternalInUse or ExternalUnintended respectively. Edge confidence stays Medium.
Subscription usage is unavailable in **both** scenarios. Other inherited data
gaps (diagnostics, backend association, findings, Git, OpenAPI quality) are not
fabricated or marked complete. Latency/error metrics remain null.

## Acceptance and session notes

Focused check:

```powershell
./scripts/Invoke-Checks.ps1 -TestPath tests/unit/SyntheticReference.Tests.ps1 -OutputDirectory artifacts/airlock-fixtures
```

2026-10-14: T-201 scaled-model slice implemented on the existing feature branch.
No design/specification deviations. Root README reviewed: public commands remain
unavailable; this is a fixture helper only. Root README, shared task register,
specification, schemas and package code intentionally left unchanged for the
coordinating shared-worktree session. This is not full T-201 raw-fixture
population, Analyze/Report integration, or airlock acceptance; no completion or
commit claim is made here. Focused acceptance results are reported at handoff.

Acceptance evidence: the exact focused command above passed repository-wide
PSScriptAnalyzer (Error/Warning) and all **10 Pester tests**, with zero failures,
skips or inconclusive results. The saved NUnit result is
`artifacts/airlock-fixtures/TestResults.xml` (ignored). Both usage scenarios pass
all ten schema contracts, exact-count assertions, deterministic generation and
byte-identical persistence round trips. Tests also verify compact-file hashes,
pre-redaction detection ordering and absence of artificial literal values in
returned policy evidence and saved models. An initial shared-worktree lint run
was blocked by concurrent package diagnostics and constructor warnings; the
constructor warnings were resolved with narrowly justified pure-constructor
suppressions. An initial usage round-trip test exposed date parsing differences,
resolved by constructing the artificial last-call timestamp explicitly as UTC.
The complete repository Pester suite was not run for this bounded slice.
