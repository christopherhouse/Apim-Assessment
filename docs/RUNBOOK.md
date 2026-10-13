# Operator runbook

## Availability

The toolkit is **not ready for customer assessment runs**. It has an importable
module foundation, strict private configuration validation, structured logging,
a guarded ARM transport, schema-validated run-folder/manifest persistence, and
internal APIM service/API/product catalog collectors with bounded parallel child
requests, an allowlisted subscription collector, plus restricted policy
collection with normalized hashes and collection-time secret-candidate
redaction, and an internal network collector for Application Gateway/WAF and
Resource Graph evidence. Private offline helpers now merge effective policies,
normalize/hash them, and extract deterministic policy flags. Private offline
builders create schema-validated API, operation, policy-matrix, subscription,
network, and pre-telemetry exposure records from saved synthetic-equivalent
inputs. Full collection/analyze orchestration, remaining collectors and models,
telemetry-based exposure refinement, rules, the model-data airlock, Copilot
operator workflow, reports/comparison, and Excel/HTML templates are not
implemented.

All six implemented model contracts share a private schema gate for pending
writes and complete saved-run loading. This does not add a public Analyze
command or authorize model access to restricted run data.

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

## Reusable collection smoke (Microsoft-owned test APIM only)

The preparatory `scripts/Invoke-ApimSmoke.ps1` entry point exercises the six
implemented collectors in fixed dependency order: Service, Apis, Products,
Subscriptions, Policies, Network. The same command will run newly registered
checks after their synthetic acceptance. A failure is recorded in the manifest,
independent checks continue, and dependent checks are Skipped; no false success
is reported. Exit status is 0 when all registered collection checks complete, 1
for configuration/preflight failure, 2 for Az module/context failure, 3 when
collection is Partial, and 4 for an unexpected run failure. Only these fixed
statuses, check names, and bounded codes for failed checks appear on the console.
The command shows preflight steps, a numbered start/result line for each
registered check, and a final collection status. An interactive terminal
uses colored emoji and a block progress bar; the console output encoding is
temporarily set to UTF-8 for each rich line and then restored. If glyphs still
show as boxes, use an emoji-capable terminal/font (such as Windows Terminal)
or set `NO_COLOR` for a clean ASCII fallback. Redirected output also uses ASCII.
To preview the rich banner without connecting to Azure, run this in the same
ordinary PowerShell terminal from the repository root:

```powershell
. .\scripts\Format-ApimSmokeConsoleLine.ps1
Write-ApimSmokeConsoleLine -Line (
    Format-ApimSmokeConsoleLine -State Header -Color
) -Color
```

The progress count covers checks, not individual APIs or operations; a check
may take time after its `collecting...` line. A failed/partial result includes
a fixed troubleshooting hint keyed to its bounded code, **not** an exception
message or stack trace. Future registered checks join the same progress count.
`ARM_HTTP_401`/`ARM_HTTP_403` indicate an ARM authorization response; check
the maintainer's local Reader access to the test service.
`ARM_HTTP_404` indicates the service request was not found; verify the APIM
name and resource group locally against the selected subscription.
Other `ARM_HTTP_<status>` codes report only the numeric status (429 and 5xx
are reported after retries). `ARM_NO_RESPONSE` means the guarded request
received no usable HTTP response **and** the underlying error did not match a
known category; it does not prove a network outage. `ARM_AUTH_ERROR` indicates
an Az authentication/permission error; check the local login and test-resource
access. `ARM_COMMAND_ERROR` indicates a missing cmdlet or invalid parameter;
check the locally installed Az module. `ARM_NETWORK_ERROR` indicates a network
exception; check local connectivity to Azure Resource Manager.
`ARM_TIMEOUT` indicates a timeout/cancellation; check connectivity and retry
policy locally. These codes never include exception text or raw responses.
Earlier smoke versions could show `ARM_COMMAND_ERROR` because a bodyless GET
passed an empty `-Payload` to `Invoke-AzRestMethod`. The current guarded
transport omits that parameter; rerun from the updated bugfix branch or its
merged successor before investigating a recurring command error.
`LOCAL_IO_ERROR` means a local write/read failed; check restricted storage
permissions and available space. `UNKNOWN_FAILURE` needs maintainer-only
investigation and does not imply that Azure returned success. Do not paste
private exception text, config, identifiers, logs, or raw output into Copilot.
The collector now preserves missing optional subscription display/tracing/date
metadata as null and runs separate Resource Graph queries for other front doors;
an older version can fail subscription validation or reject a multi-statement
graph query. A Partial policy check after an XML parse rejection is **not**
repaired automatically: the authorized maintainer should inspect the affected
policy locally in the Microsoft-owned test instance. Do not paste `$Error`,
policy XML, or returned Resource Graph diagnostics into Copilot.
Restricted raw output, manifest, and logs stay under `Output.Root`. This is
**not** the full T-604 acceptance or a
customer assessment: Analyze, rules, reports, and model-data promotion are not
run. Do not pass live output, identifiers, errors, or logs to Copilot.

In Copilot CLI, these `!` commands are safe because they run only synthetic
offline tests and automatically include all current/future unit tests:

```text
! pwsh -NoProfile -File .\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\SmokeRunner.Tests.ps1
! pwsh -NoProfile -File .\scripts\Invoke-Checks.ps1
```

**Live smoke is maintainer-operated in an ordinary PowerShell terminal, never
in Copilot CLI or its `!` shell.** An authorized maintainer must choose a
Microsoft-owned test APIM (T-114), use Reader-level APIM/network permissions
and an existing Az login, and verify that the private configuration, restricted
`Output.Root`, and separate unused `Output.ModelSafeRoot` are external paths
outside the repository and **all** Copilot trusted/allowed directories. Install
`Az.Accounts` and `Az.ResourceGraph` in the maintainer's PowerShell environment
using the organization's approved process; the smoke command never installs
modules or initiates a login.

In that separate terminal, from the repository root, prepare a private config:

```powershell
$private = Join-Path $HOME 'apim-smoke-private'
New-Item -ItemType Directory -Path $private -Force | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $private 'smoke.psd1'))) {
    Copy-Item .\config\sample.psd1 (Join-Path $private 'smoke.psd1')
}
```

Edit `smoke.psd1` **locally, outside Copilot**. Set the Microsoft-owned test
subscription ID, APIM name/resource group, an environment name such as `Test`,
only the relevant network groups/gateways (empty arrays if none), and absolute
non-overlapping external Output roots. Leave other required sample settings
valid. Never paste this file or its values into a prompt. Use a separately
approved storage location and retention policy for the restricted run.

Sign in if needed (`Connect-AzAccount`) and select the intended subscription
using your normal Azure PowerShell workflow in that same terminal. Then run:

```powershell
.\scripts\Invoke-ApimSmoke.ps1 -Config (Join-Path $private 'smoke.psd1') `
    -Environment Test -MicrosoftOwnedTestEnvironment
$LASTEXITCODE
```

The command refuses an unacknowledged target, repo-local config or output roots, or a
context whose subscription ID differs from the configured target. Inspect the
restricted manifest and outputs locally in that terminal; do not print or share
them in Copilot. There is no public full assessment command yet.

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

## Shared model schema gate

The private model writers serialize pending outputs once, validate every
snapshot against its registered closed schema, check destinations for links, and
only then persist those same snapshots. Schema failure leaves existing outputs
unchanged; individual writes remain atomic, but a later I/O failure is not a
multi-file transaction.

The private saved-run loader requires `apis.json`, `operations.json`,
`policyMatrix.json`, `subscriptions.json`, `network.json`, and `exposure.json`
under `model`. It returns no models until all six validate. Missing/invalid
files, unavailable schemas, and linked paths fail closed; other run artifacts
are not loaded. Explicit null/Partial/missing-input metadata remains intact, as
do empty and singleton arrays. Future model contracts join the gate with their
builders.

The shared gate can be checked offline with synthetic fixtures:

```powershell
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\ModelSchema.Tests.ps1
```

This runs repository lint plus focused gate acceptance tests, without Azure
access. The helpers remain private until public orchestration is implemented.

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

## Network evidence and direct reachability

The internal network collector reads configured Application Gateways and their
linked WAF policies through `Invoke-ApimArm` GET requests. It uses fixed
`Search-AzGraph` queries for the APIM subnet, NSGs, public IPs, private
endpoints, private DNS zones, route tables, and other configured-scope front
doors whose properties target an APIM hostname or address. Every response is
staged before restricted `raw/network/*.json` files are written; a failed ARM or
Resource Graph call marks the collector Failed rather than emitting a complete
success shape.

The private network model writes one closed-schema `model/network.json` object.
It honors NSG rule priority when deciding whether a broad Internet/any-source
allow reaches TCP 443, records positive direct-public reasons, and aggregates
multiple App Gateway TLS/WAF configurations conservatively. Missing subnet, NSG,
public-IP, or front-door evidence leaves `directPublic=null` with
`modelStatus=Partial`; it is never treated as restricted or safe by default.

The customer-neutral network path can be checked offline:

```powershell
Invoke-Pester .\tests\unit\NetworkCollector.Tests.ps1,`
  .\tests\unit\NetworkModel.Tests.ps1 -Output Detailed
```

## Exposure classification

The private exposure model reads saved APIs, operations, the network model,
ARM-shaped Application Gateway configuration, and effective policy-path
evidence. It emits one closed-schema route-by-API record, treats Basic routing as
host-wide `/*`, resolves path maps and one unconditional literal path rewrite,
and fails unresolved rewrites to `Unknown` with Low confidence. Backend pools
must target the APIM gateway host or address. Direct-public evidence overrides
normal route matching.

Restrictions are evaluated on each operation/product path. IP allow/forbid
ranges and structural 403/404 host checks can classify a reachable route as
Restricted; an unrestricted product path remains authoritative when missing
inbound `<base/>` bypasses a restriction. JWT and mTLS do not change
reachability. Until P4 supplies route usage, reachable unrestricted routes stay
`exposure=Unknown`, `confidence=Medium`, and `missingInputs=["usage"]`; the
optional usage hook accepts complete normalized `apiId`/`route`/`calls` rows
where route is `ViaAppGw` or `Internal`, and only then distinguishes
`ExternalInUse` from `ExternalUnintended`. Incomplete telemetry remains Unknown.
The writer validates both `model/exposure.json` and the back-filled
`model/apis.json` before writing either file.

The customer-neutral exposure path can be checked offline:

```powershell
Invoke-Pester .\tests\unit\ExposureModel.Tests.ps1,`
  .\tests\unit\PolicyFlags.Tests.ps1 -Output Detailed
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
