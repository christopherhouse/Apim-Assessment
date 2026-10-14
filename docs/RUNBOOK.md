# Operator runbook

## Availability

The toolkit is **not ready for customer assessment runs**. It has an importable
module foundation, strict private configuration validation, structured logging,
a guarded ARM transport, schema-validated run-folder/manifest persistence, and
internal APIM service/API/product catalog collectors with bounded parallel child
requests, an allowlisted subscription collector, plus restricted policy
collection with normalized hashes and collection-time secret-candidate
redaction, allowlisted named-value/backend/certificate and logger/diagnostic
collectors, and an internal network collector for Application Gateway/WAF and
Resource Graph evidence. Private offline helpers now merge effective policies,
normalize/hash them, and extract deterministic policy flags. Private offline
builders create schema-validated API, operation, policy-matrix, subscription,
service, named-value, backend, certificate, network, and pre-telemetry
exposure records from saved synthetic-equivalent inputs. A private rule engine,
seven NET catalog entries, fifteen model-backed
SEC catalog entries, six model-backed GOV catalog entries, all six REL catalog
entries, a closed findings schema, and private closed action-item aggregation
plus a customer-neutral generated Excel action-plan template are available for
offline synthetic testing. A private report writer can populate the current
deterministic workbook sheets from a validated saved run. Full
collection/analyze orchestration, remaining collectors and models,
telemetry-based exposure refinement, rule catalogs, the model-data airlock, Copilot
operator workflow, reports/comparison, and Excel/HTML templates are not
implemented.

All ten implemented model contracts share a private schema gate for pending
writes and complete saved-run loading. Private findings are validated against
`schemas/findings.schema.json` before restricted persistence. This does not add
a public Analyze command or authorize model/findings access to an agent.

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

Rule-engine acceptance remains offline and synthetic:

```powershell
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\RuleEngine.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\NetRules.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\SecRules.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\GovRules.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\RelRules.Tests.ps1
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\ActionPlan.Tests.ps1
```

The private `Get-ApimRuleCatalog`, `Invoke-ApimRuleEngine`, and
`Write-ApimFindingSet` helpers are not operator commands. Rules require explicit
model inputs; missing/failed inputs produce one Info/NotEvaluated finding per
rule. An optional, allowlisted field-level `DataGaps` callback marks required
facts within a present model as NotEvaluated instead of a false pass; malformed
available models and invalid evidence fail closed. Unknown usage is not zero
usage. `rules/NET.rules.ps1` includes NET-001/002/004/006/007/008/009.
NET-001 and NET-009 need operator-corroborated facts in the closed network
model. With no attestation, both emit Info/NotEvaluated rather than asserting
absent authentication or unnecessary publication. No full saved-run
Analyze path, findings report, or model-safe promotion is available yet.
`rules/SEC.rules.ps1` includes
SEC-001/002/003/004/005/007/008/009/010/011/012/014/015/019/020. Rules with
unknown applicable facts emit one Info/NotEvaluated finding unless other
records already provide definitive positive evidence. SEC-014 consumes
model-derived diagnostic body and sensitive-request-header facts; incomplete
normalized settings remain null and can still produce NotEvaluated rather than a
false pass. SEC-008 uses only structural named-value locations and never secret
values. SEC-009 uses one rule ID across named-value and certificate targets,
requires both closed models, and emits one NotEvaluated result when required
Key Vault facts are unknown without a known positive finding. SEC-010 evaluates
only HTTPS backends, ignores non-applicable HTTP TLS
flags, and emits NotEvaluated when no positive finding exists but an HTTPS
validation fact is missing. SEC-011 evaluates the closed backend `scheme` and
operation `backendOverrideHttp` facts. Its optional configuration is exact and
case-insensitive:

```powershell
RuleExceptions = @{
    ApprovedPlainHttpBackendIds = @('approved-backend')
    ApprovedPlainHttpOperationKeys = @('api-id/operation-id')
}
```

Omitting `RuleExceptions`, or leaving both arrays empty, approves nothing.
Entries suppress only the named backend or operation; they do not classify an
API as internal. If no known unapproved HTTP target exists, Partial operation
policy evidence remains NotEvaluated. SEC-001 evaluates only five normalized
client/backend legacy TLS controls; an explicit enablement remains a finding
when another control is unknown, while no enablement plus incomplete control
evidence is NotEvaluated. SEC-002 treats an absent minimum management API
version as a finding. SEC-019 evaluates only normalized managed-identity type
and never retains user-assigned identity IDs. Never pass restricted models or
findings to Copilot.

`rules/GOV.rules.ps1` includes GOV-001/002/005/006/008/010. These rules use
closed API and operation facts only. GOV-006 flags unversioned APIs and complete
version sets with one known version; an incomplete set is NotEvaluated unless
another known positive exists. GOV-008 emits one service-level finding with
bounded convention counts rather than one row per API. GOV-010 preserves a
known missing-`<base/>` operation finding when another policy is Partial.
GOV-003 and GOV-009 remain unavailable until product ownership/approval and
diagnostic enablement/sampling are modeled.

`rules/REL.rules.ps1` includes REL-001 through REL-006. SKU, zone, and platform
facts come from the closed service model. Critical backend evaluation is opt-in
and exact:

```powershell
RuleTargets = @{
    CriticalBackendIds = @('critical-backend-id')
}
```

Omitting `RuleTargets`, or leaving the array empty, declares no critical backend
targets. REL-004 considers only APIM-targeted App Gateway routes; a linked HTTP
setting without a custom probe uses the default `/` path, while unresolved
probe evidence is NotEvaluated. REL-005 compares normalized service-hostname and
APIM certificate-entity expiry with the saved `manifest.startedUtc` plus
`CertExpiryDays`, so rerunning analysis does not move the threshold. Missing
service, probe, or expiry facts remain
NotEvaluated unless another record provides a known positive.

The private `Get-ApimActionPlan` helper is also not an operator command. It
accepts only schema-valid findings with valid unique keys, groups them by rule,
counts evaluated instance rows, retains NotEvaluated gaps with zero affected
resources, selects deterministic top scopes, and validates the result against
`schemas/actions.schema.json`. It does not itself write a workbook, carry
tracking values forward, or expose models/findings to Copilot. The private
writer below consumes its output; tracking carry-forward remains T-507.

The checked-in workbook template can be regenerated and structurally tested
offline after installing pinned development dependencies:

```powershell
.\scripts\New-ApimActionPlanTemplate.ps1 -Force
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\WorkbookTemplate.Tests.ps1
```

This uses ImportExcel without desktop Excel, fixed column widths, and no Azure
access. The template contains no customer values. Regeneration is a development
operation only; no public report command currently populates or distributes it.

Private report-writer acceptance also remains synthetic and offline:

```powershell
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\ReportWriter.Tests.ps1
```

`Export-ApimActionPlan` is not an operator command. It validates the manifest,
all registered model files, and findings before copying the trusted template.
Current output fills actions, finding details, APIs, policy controls,
subscriptions, exposure, network summary, and Summary assumptions under the
run's `report` folder. It never overwrites an existing workbook and leaves no
partial output on validation/template failure. It also expands the manifest
into Run Info, writes the implemented rule catalog, and copies the manifest's
exact scoring snapshot into editable positive-number weight cells. Finding
Details formulas recalculate Severity × Exposure × Usage, with blank usage
remaining the neutral 1.0 multiplier; Action Plan formulas select each rule's
maximum recalculated detail priority. Weight edits change workbook values on
recalculation but do not alter restricted `findings.json` or automatically
resort action rows. Usage, Cost, and Environment Drift are intentionally empty
pending their owning tasks. The generated workbook is restricted customer
output and must never be sent to Copilot or another model.

## Reusable collection smoke (Microsoft-owned test APIM only)

The preparatory `scripts/Invoke-ApimSmoke.ps1` entry point exercises the eight
implemented collectors in fixed dependency order: Service, Apis, Products,
Subscriptions, SecurityAssets, Diagnostics, Policies, Network. SecurityAssets
writes only allowlisted metadata: named-value values are dropped after in-memory
pattern detection, backend credential values are reduced to structural facts,
and certificate data/private material is never stored. Diagnostics writes only
allowlisted logger targets, header names, nullable body-byte counts, and bounded
settings; it drops credentials, descriptions, samples, data-masking details,
header values, and unknown fields. The same command will run newly registered
checks after their synthetic acceptance. A failure is recorded in the manifest,
independent checks continue, and dependent checks are Skipped; no false success
is reported. Exit status is 0 when all registered collection checks complete, 1
for configuration/preflight failure, 2 for Az module/context failure, 3 when
collection is Partial, and 4 for an unexpected run or output-validation failure.
Only these fixed statuses, check names, and bounded codes for failed checks
appear on the console.
The command shows preflight steps, one numbered result row per registered
check, and a final completed-check count. An interactive terminal uses a
colored emoji scorecard that replaces its active `WORKING` row in place; the
console output encoding is temporarily set to UTF-8 for each rich write and
then restored. Redirected output and `NO_COLOR` keep the two-line ASCII event
feed without terminal cursor controls. If glyphs still
show as boxes, use an emoji-capable terminal/font (such as Windows Terminal)
or set `NO_COLOR` for a clean ASCII fallback.
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
`POLICY_XML_REJECTED` means the XML-encoded policy response still failed strict
parsing or used a prohibited document type; inspect the policy locally on the
Microsoft-owned test instance. Earlier sanitized policy files can exist while
Policies is Partial, but no complete policy index is written. Neither the
parser location nor policy content appears in smoke output.
The collector now preserves missing optional subscription display/tracing/date
metadata as null and runs separate Resource Graph queries for other front doors;
an older version can fail subscription validation or reject a multi-statement
graph query. A Partial policy check after an XML parse rejection is **not**
repaired automatically: the authorized maintainer should inspect the affected
policy locally in the Microsoft-owned test instance. Do not paste `$Error`,
policy XML, or returned Resource Graph diagnostics into Copilot.
After collection, the same script validates the exact new run locally: its
schema-valid completed manifest must agree with all eight check statuses,
the collection stage and untouched Analyze/Report stages. Every completed
check must have its required files and matching item counts; API/product
child collections, per-API diagnostics, network JSON files, and the policy
index and XML hashes are checked. Empty valid collections pass; missing
or malformed JSON, missing children, count mismatches, and changed policy
XML fail with `SMOKE_OUTPUT_INVALID` and exit 4. Only completed checks are
validated on a Partial run, which remains exit 3 rather than becoming a
success. The terminal prints `SMOKE_OUTPUT_VALID` only after structural
validation; it never prints saved content, paths, identifiers, or private
validation exceptions. This is not independent content-safety certification,
rule evaluation, model creation, or workbook rendering.
Restricted raw output, manifest, and logs stay under `Output.Root`. This is
**not** the full T-604 acceptance or a
customer assessment: Analyze, rules, reports, and model-data promotion are not
run. Do not pass live output, identifiers, errors, or logs to Copilot.
The maintainer's previously reported live smoke covered the original six checks;
the newly registered SecurityAssets and Diagnostics checks still require a
maintainer-only live run on the Microsoft-owned test environment.

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
.\scripts\Invoke-ApimSmoke.ps1 -Environment Test -MicrosoftOwnedTestEnvironment
```

The script prints its final PASS/FAIL/PARTIAL result and exit code itself,
including on preflight failures. A successful run ends with
`[SMOKE] PASS - collection and saved-output validation completed (exit code 0)`.
No follow-up shell command is required; the actual process exit code remains
available to automation.
The single script defaults to
`$HOME\apim-smoke-private\smoke.psd1`; if you use another private directory,
pass `-Config (Join-Path $private 'smoke.psd1')`. `Test` must match the
environment name in that config. Exit 0 requires all eight checks **and**
saved-output validation to pass; `SMOKE_OUTPUT_VALID` with exit 3 means only
the completed checks' files validated and collection is still Partial.
The command refuses an unacknowledged target, repo-local config or output
roots, or a context whose subscription ID differs from the configured target.
If it stops while checking Private configuration, its bounded
`SMOKE_CONFIG_ERROR` category identifies the next local check:
`CONFIG_NOT_FOUND` means the `.psd1` file is absent at the default path
(or the explicit `-Config` path); `CONFIG_INVALID` means required fields,
types, linked output paths, or non-overlapping output roots failed validation;
`LOCATION_INVALID` means the config path is linked or the config/output roots
are inside the repository; `ENVIRONMENT_NOT_FOUND` means `-Environment` does
not match the private config. The sample config names its environment `Prod`; a renamed test
environment must be explicitly set to `Test` before using the sample command.
If the private folder also holds `Output.Root`, keep the separate
`Output.ModelSafeRoot` outside it, or put the two output roots in distinct
sibling folders under that private folder; the roots must not contain each
other. Resolve issues only in the maintainer's terminal; do not paste private
settings or exceptions into Copilot. Inspect the
restricted manifest and outputs locally in that terminal; do not print or share
them in Copilot. There is no public full assessment command yet.

The internal policy collector reads the previously collected API, operation, and
product catalogs, discovers policy fragments, and writes restricted XML under
`policies/`. Missing policy scopes are represented in `policies/index.json`
instead of treated as failures. Potential hard-coded policy secrets are detected
before persistence; the index records structural locations only and stored XML
contains `***REDACTED***`, never the detected value.

The internal diagnostics collector reads the previously collected API inventory,
then calls the service logger and service diagnostic endpoints before issuing
bounded per-API diagnostic GETs. It writes `raw/loggers.json`,
`raw/diagnostics.json`, and one `raw/apiDiagnostics/<api>.json` file per API.
Logger output is restricted to name, logger type, target resource ID, and
buffering state. Diagnostic output is restricted to logger reference,
always-log, sampling, verbosity, client-IP/correlation settings, sorted header
names, and nullable body-byte counts. Missing sections remain `null`, while a
known empty header list remains `[]`; neither is converted to a false or zero
claim. Credentials, descriptions, payload samples, data-masking configuration,
header values, and unknown ARM fields are never persisted. Root logger and
service-diagnostic files are written before API children so a child failure
retains useful sanitized evidence and records Diagnostics as Partial.

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

When diagnostic inputs are supplied, a non-empty per-API diagnostic collection
overrides the all-APIs collection for that API; an empty per-API collection
inherits the all-APIs settings. `bodyLogging` is true when any effective
frontend/backend request or response body-byte count is positive.
`sensitiveHeadersLogged` is true when effective frontend/backend request headers
include `Authorization`, `Ocp-Apim-Subscription-Key`, or `Cookie`,
case-insensitively. If no positive fact is present but a required normalized
section is missing, the field stays null and `diagnostics` remains in
`missingInputs`. Missing per-API child files likewise remain unknown even when
the service file exists, because an uncollected API override cannot be ruled
out.

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

The private saved-run loader requires `service.json`, `apis.json`, `operations.json`,
`policyMatrix.json`, `subscriptions.json`, `namedValues.json`, `backends.json`,
`certificates.json`, `network.json`, and `exposure.json` under `model`. It
returns no models until all ten validate. Missing/invalid files, unavailable
schemas, and linked paths fail closed; other run artifacts are not loaded.
Explicit null/Partial/missing-input metadata remains intact, as do empty and
singleton arrays. Future model contracts join the gate with their builders.

The shared gate can be checked offline with synthetic fixtures:

```powershell
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\ModelSchema.Tests.ps1
```

This runs repository lint plus focused gate acceptance tests, without Azure
access. The helpers remain private until public orchestration is implemented.

## Security asset models

The private security-asset model helper transforms the allowlisted collected
payloads into three sorted, closed arrays. `model/namedValues.json` contains
secret classification, Key Vault status, structural secret-pattern locations,
and a derived plain-text risk flag; named-value values are never present.
`model/backends.json` contains only scheme, nullable HTTPS certificate
validation facts, credential presence, and resilience flags. HTTP backend TLS
facts are normalized to null because certificate validation is not applicable.
`model/certificates.json` contains normalized expiry, Key Vault-backed status,
and completeness metadata without certificate bytes or private material.

The customer-neutral security model path can be checked offline:

```powershell
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\SecurityAssetModel.Tests.ps1
```

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
The builder also accepts optional, in-memory `-OperatorEvidence` with exactly
`edgeRangesOnly` (Boolean or null), `originAuthentication`
(`Present`/`Absent`/`Unknown`), and `auxiliaryRoutes` (null or a complete
array of `routeKey`, `endpointType`=`Portal`/`Management`,
`publicListener` Boolean, and `ownerNeed`=`Needed`/`NotNeeded`/`Unknown`).
Only an authorized operator can corroborate these facts, including all
effective listener, WAF, NSG, and APIM-policy authentication paths and the
endpoint owner's need. They are *not* inferred from absent Azure resources or
missing policy evidence. Each supplied fact is labeled `OperatorAttestation`
in the restricted model; unknowns stay null/Unknown. This is a private model
input, **not** a live collection or public operator command. Never paste
private evidence or restricted model output into Copilot.

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
