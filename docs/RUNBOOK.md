# Operator runbook

## Availability

The bootstrap is **not ready for customer assessment runs**. It has an importable
module skeleton, development checks, and release automation only. Collection,
analysis, reporting, comparison, authentication/error handling, and the template
workbook are not implemented.

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

These commands do not connect to Azure. The initial module exports no public
assessment functions. Missing development modules are installed into the
current user's module path; Pester results go to ignored `artifacts`.

## Future operator requirements

Authorized maintainers will use an existing Azure login, least-privilege Reader
access, validated local configuration, and a customer-approved output location.
Agents/CI use synthetic fixtures instead. Do not store secret values or tokens,
do not upload customer outputs, and delete run data after the agreed readout.

As each pipeline stage becomes available, add its tested commands, resume/skip
options, manifest interpretation, troubleshooting, and implemented exit codes
here. The specification's 0-4 exit codes are planned contracts, not current
assessment behavior.
