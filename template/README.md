# Action-plan template

`ApimActionPlan.xlsx` is the customer-neutral workbook template defined by
specification section 12. It contains all fixed sheet/table names, title and
header styling, frozen panes, column widths, conditional formatting, action
tracking validation, Summary formulas/chart, and the assumptions/data-gap
banner. The Exposure Map also includes a formatted network-summary block.
The Method & Rules weight column is highlighted and validates positive numeric
entries. Tables contain only an empty placeholder row.

Regenerate it from the repository root after installing pinned development
dependencies:

```powershell
.\scripts\New-ApimActionPlanTemplate.ps1 -Force
.\scripts\Invoke-Checks.ps1 -TestPath .\tests\unit\WorkbookTemplate.Tests.ps1
```

The generator uses fixed widths, so desktop Excel and native auto-size
dependencies are not required. Never replace this file with a real customer
workbook or add customer values to the generator.

The private report writer copies this file and writes typed values into the
existing table ranges; it does not use a real customer workbook as a template.
It populates Run Info, the implemented rule catalog, and the exact scoring
snapshot saved in manifest schema 1.1. Finding and action priority formulas bind
to the editable weight table, and Excel is instructed to recalculate when the
workbook opens. Generated reports remain under an ignored restricted run folder
and are never model-safe artifacts.
