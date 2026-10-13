# Operator runbook

## Availability

The toolkit is **not ready for customer assessment runs**. It has an importable
module foundation, strict private configuration validation, structured logging,
a guarded ARM transport, schema-validated run-folder/manifest persistence, and
internal APIM service/API/product catalog collectors with bounded parallel child
requests, plus restricted policy collection with normalized hashes and
collection-time secret-candidate redaction. Private offline helpers now merge
effective policies and normalize/hash them. Collection/analyze orchestration,
remaining collectors, policy flags/models/rules, the model-data airlock,
Copilot operator workflow, reports/comparison, and Excel/HTML templates are not
implemented.

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
silently treated as expanded. There is still no public analyze command.

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
