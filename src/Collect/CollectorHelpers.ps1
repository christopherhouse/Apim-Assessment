#Requires -Version 7.4

Set-StrictMode -Version Latest

$script:ApimAssessmentManifestPath = Join-Path (
    Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
) 'ApimAssessment.psd1'

function ConvertTo-ApimResourceSegment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Value
    )

    $segment = [System.Uri]::EscapeDataString($Value)
    if ($segment -eq '.') {
        return '%2E'
    }
    if ($segment -eq '..') {
        return '%2E%2E'
    }
    return $segment
}

function Get-ApimServiceResourcePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Environment
    )

    return (
        '/subscriptions/{0}/resourceGroups/{1}/providers/' +
        'Microsoft.ApiManagement/service/{2}'
    ) -f
        $Environment.SubscriptionId,
        (ConvertTo-ApimResourceSegment -Value $Environment.ApimResourceGroup),
        (ConvertTo-ApimResourceSegment -Value $Environment.ApimName)
}

function Get-ApimCollectionResourceName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Payload,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $CollectionName
    )

    $valueProperty = $Payload.PSObject.Properties['value']
    if ($null -eq $valueProperty) {
        throw "$CollectionName response did not contain a value collection."
    }

    $names = [System.Collections.Generic.List[string]]::new()
    $uniqueNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($item in @($valueProperty.Value)) {
        if ($null -eq $item) {
            throw "$CollectionName response contained an invalid resource."
        }
        $nameProperty = $item.PSObject.Properties['name']
        if ($null -eq $nameProperty -or
            [string]::IsNullOrWhiteSpace([string] $nameProperty.Value)) {
            throw "$CollectionName response contained an invalid resource name."
        }
        $name = [string] $nameProperty.Value
        if (-not $uniqueNames.Add($name)) {
            throw "$CollectionName response contained duplicate resource names."
        }
        $names.Add($name)
    }

    return @($names | Sort-Object)
}

function Invoke-ApimParallelArmRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Requests,

        [ValidateRange(1, 64)]
        [int] $ThrottleLimit = 6,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LogPath,

        [string] $ModulePath = $script:ApimAssessmentManifestPath
    )

    if ($Requests.Count -eq 0) {
        return @()
    }
    if (-not (Test-Path -LiteralPath $ModulePath -PathType Leaf)) {
        throw 'Parallel ARM request module path was not found.'
    }

    $results = @(
        $Requests | ForEach-Object -Parallel {
            $request = $_
            try {
                $module = Import-Module -Name $using:ModulePath -Force `
                    -PassThru -ErrorAction Stop
                $payload = & $module {
                    param($RequestUri, $RunLogPath)
                    Invoke-ApimArm -Uri $RequestUri -LogPath $RunLogPath
                } $request.Uri $using:LogPath
                [pscustomobject]@{
                    index        = [int] $request.Index
                    relativePath = [string] $request.RelativePath
                    success      = $true
                    notFound     = $false
                    payload      = $payload
                }
            }
            catch {
                $allowNotFound = $false
                $allowProperty = $request.PSObject.Properties['AllowNotFound']
                if ($null -ne $allowProperty) {
                    $allowNotFound = [bool] $allowProperty.Value
                }
                $statusCode = 0
                $isNotFound = $allowNotFound -and
                    $_.Exception.Data.Contains('StatusCode') -and
                    [int]::TryParse(
                        [string] $_.Exception.Data['StatusCode'],
                        [ref] $statusCode
                    ) -and
                    $statusCode -eq 404
                [pscustomobject]@{
                    index        = [int] $request.Index
                    relativePath = [string] $request.RelativePath
                    success      = $isNotFound
                    notFound     = $isNotFound
                    payload      = $null
                }
            }
        } -ThrottleLimit $ThrottleLimit
    )

    $failures = @($results | Where-Object { -not $_.success })
    if ($failures.Count -gt 0) {
        $exception = [System.InvalidOperationException]::new(
            'One or more parallel ARM requests failed.'
        )
        $exception.Data['FailureCount'] = $failures.Count
        throw $exception
    }

    return @($results | Sort-Object index)
}

function Get-ApimCollectorFailureCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $failureCount = 1
    if ($ErrorRecord.Exception.Data.Contains('FailureCount')) {
        $candidate = 0
        if ([int]::TryParse(
                [string] $ErrorRecord.Exception.Data['FailureCount'],
                [ref] $candidate
            ) -and $candidate -gt 0) {
            $failureCount = $candidate
        }
    }
    return $failureCount
}
