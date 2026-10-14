#Requires -Version 7.4

Set-StrictMode -Version Latest

function Read-ApimTrackingCell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Table,
        [Parameter(Mandatory)][int] $Row,
        [Parameter(Mandatory)][string] $Header
    )

    $columns = @($Table.Columns | Where-Object Name -CEQ $Header)
    if ($columns.Count -ne 1) { throw 'Prior workbook headers are invalid.' }
    $index = [array]::IndexOf(@($Table.Columns.Name), $Header)
    $cell = $Table.WorkSheet.Cells[$Row, ($Table.Address.Start.Column + $index)]
    if (-not [string]::IsNullOrEmpty($cell.Formula)) {
        throw 'Imported tracking formulas are not supported.'
    }
    return $cell.Value
}

function Read-ApimPriorTracking {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][object] $Manifest
    )

    Import-ApimReportDependency
    $fullPath = [IO.Path]::GetFullPath($Path)
    Test-ConfigPathLink -Path $fullPath -Context 'Prior workbook'
    if ([IO.Path]::GetExtension($fullPath) -ine '.xlsx' -or
        -not (Test-Path -LiteralPath $fullPath -PathType Leaf) -or
        (Get-Item -LiteralPath $fullPath).Length -gt 64MB) {
        throw 'Prior workbook is unsupported.'
    }
    $archive = [IO.Compression.ZipFile]::OpenRead($fullPath)
    try {
        [long] $expanded = 0
        foreach ($entry in $archive.Entries) {
            $expanded += $entry.Length
            if ($entry.Length -gt 16MB -or $expanded -gt 64MB -or
                $entry.FullName -match '(?i)(externalLinks/|vbaProject\.bin$)') {
                throw 'Prior workbook content is unsupported.'
            }
        }
    }
    finally { $archive.Dispose() }
    $package = Open-ExcelPackage -Path $fullPath
    try {
        $runSheet = $package.Workbook.Worksheets['Run Info']
        if ($null -eq $runSheet -or $null -eq $runSheet.Tables['tblRun']) {
            throw 'Prior workbook scope is unavailable.'
        }
        $runTable = $runSheet.Tables['tblRun']
        foreach ($scope in @(
                @{ Name = 'Customer'; Value = $Manifest.customer }
                @{ Name = 'Environment'; Value = $Manifest.environment }
                @{ Name = 'APIM Resource ID'; Value = $Manifest.apim.resourceId }
                @{ Name = 'Tenant ID'; Value = $Manifest.tenantId }
            )) {
            $values = @(
                for ($row = $runTable.Address.Start.Row + 1; $row -le $runTable.Address.End.Row; $row++) {
                    if ((Read-ApimTrackingCell -Table $runTable -Row $row -Header Name) -ceq $scope.Name -and
                        (Read-ApimTrackingCell -Table $runTable -Row $row -Header Section) -ceq 'Scope') {
                        Read-ApimTrackingCell -Table $runTable -Row $row -Header Value
                    }
                }
            )
            if ($values.Count -ne 1 -or [string] $values[0] -ine [string] $scope.Value) {
                throw 'Prior workbook scope is incompatible.'
            }
        }
        $rows = [Collections.Generic.List[object]]::new()
        foreach ($definition in @(
                @{ Sheet = 'Action Plan'; Table = 'tblActions'; Key = 'Rule ID'; Kind = 'Action' }
                @{ Sheet = 'Finding Details'; Table = 'tblFindings'; Key = 'Finding Key'; Kind = 'Finding' }
            )) {
            $sheet = $package.Workbook.Worksheets[$definition.Sheet]
            if ($null -eq $sheet -or $null -eq $sheet.Tables[$definition.Table]) {
                throw 'Prior tracking table is unavailable.'
            }
            $table = $sheet.Tables[$definition.Table]
            Assert-ApimReportRowCount -Count ($table.Address.Rows - 1) -TableName $definition.Table
            $keys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            for ($row = $table.Address.Start.Row + 1; $row -le $table.Address.End.Row; $row++) {
                $key = Read-ApimTrackingCell -Table $table -Row $row -Header $definition.Key
                if ($null -eq $key -or [string] $key -ceq '') {
                    $hasValues = $false
                    foreach ($header in @($table.Columns.Name)) {
                        if ($null -ne (Read-ApimTrackingCell -Table $table -Row $row -Header $header)) {
                            $hasValues = $true
                        }
                    }
                    if ($hasValues) { throw 'Prior tracking key is missing.' }
                    continue
                }
                $ruleId = Read-ApimTrackingCell -Table $table -Row $row -Header 'Rule ID'
                if ($key -isnot [string] -or $ruleId -isnot [string] -or
                    -not $keys.Add($key) -or
                    ($definition.Kind -ceq 'Action' -and $key -cne $ruleId) -or
                    ($definition.Kind -ceq 'Finding' -and $key -cnotmatch ('^' + [regex]::Escape($ruleId) + '\|[^|]+\|.+$'))) {
                    throw 'Prior tracking key is invalid or duplicated.'
                }
                $date = Read-ApimTrackingCell -Table $table -Row $row -Header 'Target Date'
                if ($null -ne $date -and [string] $date -cne '') {
                    if ($date -is [datetime]) { $date = $date.ToString('yyyy-MM-dd') }
                    elseif ($date -is [double] -or $date -is [int]) {
                        $date = [datetime]::FromOADate($date).ToString('yyyy-MM-dd')
                    }
                    elseif ($date -is [string]) {
                        $date = [datetime]::ParseExact($date, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture).ToString('yyyy-MM-dd')
                    }
                    else { throw 'Prior target date is invalid.' }
                }
                else { $date = $null }
                $rows.Add([ordered]@{
                        kind = $definition.Kind; key = $key; ruleId = $ruleId
                        evaluation = Read-ApimTrackingCell -Table $table -Row $row -Header Evaluation
                        owner = Read-ApimTrackingCell -Table $table -Row $row -Header Owner
                        status = Read-ApimTrackingCell -Table $table -Row $row -Header Status
                        targetDate = $date
                        notes = Read-ApimTrackingCell -Table $table -Row $row -Header Notes
                    })
            }
        }
        Test-ApimLifecycleJson -Json (ConvertTo-Json -InputObject $rows.ToArray() -Depth 100) -Contract tracking
        $snapshotValues = @(
            for ($row = $runTable.Address.Start.Row + 1; $row -le $runTable.Address.End.Row; $row++) {
                if ((Read-ApimTrackingCell -Table $runTable -Row $row -Header Section) -ceq 'Lifecycle' -and
                    (Read-ApimTrackingCell -Table $runTable -Row $row -Header Name) -ceq 'Snapshot SHA256') {
                    Read-ApimTrackingCell -Table $runTable -Row $row -Header Value
                }
            }
        )
        if ($snapshotValues.Count -gt 1 -or ($snapshotValues.Count -eq 1 -and
                $snapshotValues[0] -cnotmatch '^[a-f0-9]{64}$')) {
            throw 'Prior workbook snapshot binding is invalid.'
        }
        return @{
            records = $rows.ToArray()
            snapshotSha256 = if ($snapshotValues.Count -eq 1) { $snapshotValues[0] } else { $null }
        }
    }
    finally { $package.Dispose() }
}

function Merge-ApimPriorTracking {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][object] $Manifest,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Models,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Actions,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Findings,
        [string] $PreviousReport,
        [AllowNull()][object] $Comparison
    )

    $null = $RunPath
    $prior = @()
    $priorDigest = $null
    if ($PSBoundParameters.ContainsKey('PreviousReport')) {
        $imported = Read-ApimPriorTracking -Path $PreviousReport -Manifest $Manifest
        $prior = @($imported.records)
        $priorDigest = $imported.snapshotSha256
    }
    $history = [Collections.Generic.List[object]]::new()
    $projection = @{}
    foreach ($definition in @(
            @{ Kind = 'Action'; Key = 'ruleId'; Records = $Actions }
            @{ Kind = 'Finding'; Key = 'findingKey'; Records = $Findings }
        )) {
        $records = @(
            foreach ($record in $definition.Records) {
                $copy = ConvertFrom-Json -InputObject (ConvertTo-Json $record -Depth 100) -Depth 100 -AsHashtable
                if ($definition.Kind -ceq 'Finding') {
                    $copy.owner = $null; $copy.targetDate = $null; $copy.notes = $null
                }
                $priorRows = @($prior | Where-Object {
                        $_.kind -ceq $definition.Kind -and $_.key -ceq $record.($definition.Key)
                    })
                if ($priorRows.Count -eq 1) {
                    foreach ($field in @('owner', 'status', 'targetDate', 'notes')) {
                        $copy[$field] = $priorRows[0][$field]
                    }
                }
                $copy
            }
        )
        $projection[$definition.Kind] = $records
        foreach ($old in @($prior | Where-Object kind -CEQ $definition.Kind)) {
            if (@($records | Where-Object { $_[$definition.Key] -ceq $old.key }).Count -eq 0) {
                $resolvedRows = @()
                $gapRows = @()
                if ($null -ne $Comparison -and $priorDigest -ceq $Comparison.baseline.sha256) {
                    $resolvedRows = @($Comparison.changes | Where-Object {
                            $_.change -ceq 'Resolved' -and
                            (($old.kind -ceq 'Finding' -and $_.findingKey -ceq $old.key) -or
                                ($old.kind -ceq 'Action' -and $_.ruleId -ceq $old.ruleId))
                        })
                    $gapRows = @($Comparison.gaps | Where-Object ruleId -CEQ $old.ruleId)
                }
                $state = if ($old.evaluation -ceq 'Evaluated' -and $resolvedRows.Count -gt 0 -and
                    $gapRows.Count -eq 0 -and
                    (Test-ApimRuleReassessment -RuleId $old.ruleId -Models $Models -Findings $Findings)) {
                    'Resolved'
                }
                else { 'NotReassessed' }
                $history.Add([ordered]@{
                        kind = $old.kind; key = $old.key; ruleId = $old.ruleId
                        change = $state; owner = $old.owner; status = $old.status
                        targetDate = $old.targetDate; notes = $old.notes
                    })
            }
        }
    }
    return @{
        actions = $projection.Action; findings = $projection.Finding
        resolved = @($history | Where-Object change -CEQ Resolved | Sort-Object kind, key -CaseSensitive)
        notReassessed = @($history | Where-Object change -CEQ NotReassessed | Sort-Object kind, key -CaseSensitive)
    }
}
