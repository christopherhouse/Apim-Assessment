#Requires -Version 7.4

function Write-ApimSecretScanTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Rows
    )

    $allowedFields = @('row', 'artifactId', 'kind', 'line', 'column')
    $allowedKinds = @(
        'Jwt', 'PrivateKey', 'AuthorizationCredential', 'UrlUserInfo',
        'UrlQueryCredential', 'CredentialAssignment', 'JsonPropertyName',
        'JsonCredentialValue', 'XmlCredentialValue'
    )
    if ($Rows.Count -gt 10000) { throw 'Secret summary row limit exceeded.' }
    for ($index = 0; $index -lt $Rows.Count; $index++) {
        $row = $Rows[$index]
        if ($null -eq $row -or $row -isnot [pscustomobject]) {
            throw 'Secret summary row is invalid.'
        }
        $fields = @($row.PSObject.Properties.Name)
        if ($fields.Count -ne $allowedFields.Count -or
            @($fields | Where-Object { $_ -cnotin $allowedFields }).Count -gt 0) {
            throw 'Secret summary fields are invalid.'
        }
        if ($row.row -isnot [int] -or $row.row -ne ($index + 1) -or
            $row.artifactId -isnot [string] -or
            $row.artifactId -cnotmatch '^artifact-[0-9]{4,5}$' -or
            [int] $row.artifactId.Substring(9) -lt 1 -or
            [int] $row.artifactId.Substring(9) -gt 10000 -or
            $row.kind -isnot [string] -or $row.kind -cnotin $allowedKinds) {
            throw 'Secret summary values are invalid.'
        }
        foreach ($position in @($row.line, $row.column)) {
            if ($null -ne $position -and
                ($position -isnot [int] -or $position -lt 1 -or $position -gt 64MB)) {
                throw 'Secret summary position is invalid.'
            }
        }
    }
    if ($Rows.Count -eq 0) { return }
    $displayRows = @(
        foreach ($row in $Rows) {
            [pscustomobject][ordered]@{
                '#' = $row.row
                Artifact = $row.artifactId
                Match = $row.kind
                Line = if ($null -eq $row.line) { '-' } else { $row.line }
                Column = if ($null -eq $row.column) { '-' } else { $row.column }
            }
        }
    )
    [Console]::Out.WriteLine('SECRET_SCAN_FINDINGS: candidates, not confirmed credentials.')
    [Console]::Out.WriteLine('Row numbers and artifact aliases map to secret-scan-locations.json; full file/location details stay local.')
    [Console]::Out.Write(
        ($displayRows | Format-Table -AutoSize | Out-String -Width 100)
    )
}
