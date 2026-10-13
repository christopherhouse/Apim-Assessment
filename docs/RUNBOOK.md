# Operator runbook

## Availability

The toolkit is **not ready for customer assessment runs**. It has an importable
module foundation, strict private configuration validation, structured logging,
a guarded ARM transport, schema-validated run-folder/manifest persistence, and
internal APIM service/API/product catalog collectors with bounded parallel child
requests, an allowlisted subscription collector, plus restricted policy
collection with normalized hashes and collection-time secret-candidate
redaction. Private offline helpers now merge effective policies, normalize/hash
them, and extract deterministic policy flags. Private offline builders create
schema-validated API, operation, policy-matrix, and subscription records from
saved synthetic-equivalent inputs. Collection/analyze orchestration, remaining
collectors and models, rules, the model-data airlock, Copilot operator workflow,
reports/comparison, and Excel/HTML templates are not implemented.

Do not run the planned commands in specification section 14 until their tasks
are implemented, tested, and marked available in the root README.

## Safe bootstrap check

In PowerShell 7.4+ at the repository root:

```powershell
.\scripts\Install-DevDependencies.ps1
Import-Module .\ApimAssessment.psd1 -Force
Get-Module ApimAssessment
.\scripts\Invoke-Checks.ps1
```

These commands do not connect to Azure. The module exports no public assessment
functions, so the internal run-persistence and collector helpers are not operator
commands. ARM and collector behavior, including parallel throttle enforcement, is
exercised through mocked or synthetic offline tests only. Missing development
modules are installed into the current user's module path; Pester results go to
ignored `artifacts`.

The internal policy collector reads the previously collected API, operation, and
product catalogs, discovers policy fragments, and writes restricted XML under
`policies/`. Missing policy scopes are represented in `policies/index.json`
instead of treated as failures. Potential hard-coded policy secrets are detected
before persistence; the index records structural locations only and stored XML
contains `***REDACTED***`, never the detected value.

The internal merge helper consumes only saved, redacted policy XML. It produces
one effective policy per product membership (or one no-product path), replaces
section-level `<base/>`, records missing-base scope and section, expands policy
fragments to depth five with cycle/missing guards, and retains structural
`data-scope` attribution. Unresolved fragment includes remain in the effective
XML with a `data-fragment-status` marker and a structured issue; they are not
silently treated as expanded.

The internal flag helper consumes effective policy XML and missing-base metadata.
It detects caller/backend authentication, throttling, IP/host restrictions,
unsafe CORS, hard-coded-secret markers, backend overrides, mock/trace behavior,
unconditional inbound responses, and missing inheritance. Evidence is structural
and deterministic; hard-coded-secret evidence contains locations only. Stored
`***REDACTED***` markers preserve the same flags produced before synthetic
redaction. Secret-bearing HTTP(S) URLs retain only their scheme plus the marker
so plain-HTTP risk remains visible without retaining host, path, query, fragment,
or credential data. Effective policies with unresolved fragments are marked
Partial so downstream models cannot treat absent detections as authoritative
negatives. There is still no public analyze command.

The internal API/operation model helper joins current API catalog records,
operations, revisions, tags, product memberships, and per-product policy flags.
It sorts records and memberships deterministically, invalidates a catalog backend
host when effective policy overrides the target, and represents unavailable
collector-derived values as `null` rather than false or zero. Every incomplete
record carries `modelStatus=Partial` and sorted `missingInputs`. The policy matrix
uses `Pass`, `Fail`, or `NA`: a detected risk remains `Fail`, while missing or
Partial evidence that prevents a decision becomes `NA`. All three model arrays
must pass their closed JSON schemas before the writer creates any files.

## Offline model fixture check

The private model path can be validated without Azure access:

```powershell
Invoke-Pester .\tests\unit\ApiPolicyModel.Tests.ps1 -Output Detailed
```

The tests use only the customer-neutral synthetic fixture, exercise persisted
`model/apis.json`, `model/operations.json`, and `model/policyMatrix.json` in a
temporary test drive, and verify fail-closed schema handling. This is a
development check, not an operator assessment command.

## Subscription metadata boundary

The internal subscription collector calls only the APIM subscription list
endpoint through the guarded GET transport. It never calls `listSecrets`.
Persisted `raw/subscriptions.json` contains only subscription ID, display name,
scope, state, derived `ownerType`, dates, and `allowTracing`. Subscription keys,
`ownerId`, user identifiers, and unknown response fields are dropped before
persistence. `ownerType` is limited to `BuiltIn`, `User`, `None`, or `Unknown`.

The private subscription model derives AllApis/Product/Api scope and target,
detects `master` at AllApis scope as the built-in master, and writes sorted
flags from `AllApis`, `AllowTracing`, `BuiltInMaster`, `NoExpiration`, and
`OwnerMissing`. Until subscription usage telemetry is implemented, `calls90d`
and `lastUsed` are `null` and each record explicitly reports
`modelStatus=Partial` with `missingInputs=["usage"]`.

The customer-neutral subscription path can be checked offline:

```powershell
Invoke-Pester .\tests\unit\SubscriptionCollector.Tests.ps1,`
  .\tests\unit\SubscriptionModel.Tests.ps1 -Output Detailed
```

## Future operator requirements

Authorized maintainers will use an existing Azure login, least-privilege Reader
access, validated local configuration, a customer-approved restricted output
location, and a separate non-overlapping model-safe analysis location. Agents/CI
use synthetic fixtures instead. Do not store secret values or tokens, do not
upload customer outputs, and delete run data after the agreed readout.

When the Copilot-assisted path is implemented, agents will receive only a locally
validated and promoted `analysis-package.json` through narrow tools. They must
not receive raw/model run data, alias maps, Azure command output, exact metrics,
customer/infrastructure identifiers, credentials, or arbitrary filesystem access.
The deterministic collection, analysis, Excel, and HTML paths will remain
available without Copilot.

As each pipeline stage becomes available, add its tested commands, resume/skip
options, manifest interpretation, troubleshooting, and implemented exit codes
here. The specification's 0-4 exit codes are planned contracts, not current
assessment behavior.
