#Requires -Version 7.4

Set-StrictMode -Version Latest

function Assert-ApimAnalysisIsolation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RestrictedRoot,
        [Parameter(Mandatory)][string] $AnalysisRoot,
        [Parameter(Mandatory)][string] $PrivateStagingRoot,
        [Parameter(Mandatory)][string[]] $VisibleRoots
    )

    $roots = @($RestrictedRoot, $AnalysisRoot, $PrivateStagingRoot)
    foreach ($root in $roots) { $null = Resolve-ApimAnalysisRoot -Path $root }
    for ($i = 0; $i -lt 3; $i++) {
        for ($j = $i + 1; $j -lt 3; $j++) {
            if (Test-ConfigPathOverlap -First $roots[$i] -Second $roots[$j]) {
                throw 'ANALYSIS_ISOLATION_REJECTED'
            }
        }
    }
    foreach ($visible in $VisibleRoots) {
        $path = Resolve-ApimAnalysisRoot -Path $visible
        foreach ($private in @($RestrictedRoot, $PrivateStagingRoot)) {
            if (Test-ConfigPathOverlap -First $private -Second $path) {
                throw 'ANALYSIS_ISOLATION_REJECTED'
            }
        }
    }
}

function Assert-ApimAnalysisZone {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    Test-ConfigPathLink -Path $Path -Context 'Analysis zone'
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw 'ANALYSIS_ZONE_REJECTED'
    }
    foreach ($version in Get-ChildItem -LiteralPath $Path -Force) {
        Test-ConfigPathLink -Path $version.FullName -Context 'Published version'
        if (-not $version.PSIsContainer -or $version.Name -cnotmatch '^version-[0-9]{6}\z') {
            throw 'ANALYSIS_ZONE_REJECTED'
        }
        $files = @(Get-ChildItem -LiteralPath $version.FullName -Force)
        if ($files.Count -ne 2) { throw 'ANALYSIS_ZONE_REJECTED' }
        foreach ($file in $files) {
            if ($file.PSIsContainer -or
                $file.Name -cnotin @('analysis-package.json', 'validation-attestation.json')) {
                throw 'ANALYSIS_ZONE_REJECTED'
            }
            Test-ConfigPathLink -Path $file.FullName -Context 'Published artifact'
        }
        $validated = Test-ApimAnalysisPackage -CandidatePath (
            Join-Path $version.FullName 'analysis-package.json'
        )
        $json = [Text.UTF8Encoding]::new($false, $true).GetString(
            (Read-ApimAnalysisSnapshot -Path (
                    Join-Path $version.FullName 'validation-attestation.json'
                ))
        )
        Test-ApimAnalysisAttestation -Json $json
        $attestation = ConvertFrom-Json -InputObject $json -AsHashtable -Depth 8
        if ($attestation.packageSha256 -cne $validated.packageSha256 -or
            $attestation.packageSchemaVersion -cne $validated.packageSchemaVersion) {
            throw 'ANALYSIS_ZONE_REJECTED'
        }
    }
}

function Publish-ApimAnalysisPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string] $RestrictedRoot,
        [Parameter(Mandatory)][string] $CandidateId,
        [Parameter(Mandatory)][string] $AnalysisRoot,
        [Parameter(Mandatory)][string] $PrivateStagingRoot,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $CopilotVisiblePath,
        [switch] $VisibleRootsComplete,
        [Parameter(Mandatory)][string] $Version
    )

    $ErrorActionPreference = 'Stop'
    $VerbosePreference = 'SilentlyContinue'
    $stage = $null
    try {
        if (-not $VisibleRootsComplete -or $CopilotVisiblePath.Count -eq 0 -or
            $CandidateId -cnotmatch '^candidate-[a-f0-9]{32}\z' -or
            $Version -cnotmatch '^version-[0-9]{6}\z') {
            throw 'ANALYSIS_PROMOTION_REJECTED'
        }
        $restricted = Resolve-ApimAnalysisRoot -Path $RestrictedRoot
        $analysis = Resolve-ApimAnalysisRoot -Path $AnalysisRoot
        $staging = Resolve-ApimAnalysisRoot -Path $PrivateStagingRoot
        $isolation = @{
            RestrictedRoot = $restricted; AnalysisRoot = $analysis
            PrivateStagingRoot = $staging; VisibleRoots = $CopilotVisiblePath
        }
        Assert-ApimAnalysisIsolation @isolation
        Assert-ApimAnalysisZone -Path $analysis
        $candidate = Resolve-RunFilePath -RunPath $restricted `
            -RelativePath "restricted/candidates/$CandidateId"
        Test-ConfigPathLink -Path $candidate -Context 'Candidate directory'
        $files = @(Get-ChildItem -LiteralPath $candidate -Force)
        if ($files.Count -ne 2) { throw 'ANALYSIS_PROMOTION_REJECTED' }
        foreach ($file in $files) {
            if ($file.Name -cnotin @('analysis-package.json', 'alias-map.json') -or
                $file.PSIsContainer -or ($file.Attributes -band
                    [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'ANALYSIS_PROMOTION_REJECTED'
            }
            Test-ConfigPathLink -Path $file.FullName -Context 'Candidate file'
        }
        $sourcePath = Join-Path $candidate 'analysis-package.json'
        $source = Read-ApimAnalysisSnapshot -Path $sourcePath
        $digest = Get-ApimAnalysisDigest -Bytes $source
        $destination = Join-Path $analysis $Version
        Test-ConfigPathLink -Path $destination -Context 'Publication destination'
        if (Test-Path -LiteralPath $destination) { throw 'ANALYSIS_PROMOTION_REJECTED' }
        if (-not $PSCmdlet.ShouldProcess('New analysis version', 'Publish validated snapshot')) {
            return
        }
        $null = [IO.Directory]::CreateDirectory($staging)
        $null = [IO.Directory]::CreateDirectory($analysis)
        Assert-ApimAnalysisIsolation @isolation
        $stage = Join-Path $staging ('.airlock-' + [guid]::NewGuid().ToString('N'))
        $null = [IO.Directory]::CreateDirectory($stage)
        Test-ConfigPathLink -Path $stage -Context 'Private snapshot'
        $snapshotPath = Join-Path $stage 'analysis-package.json'
        [IO.File]::WriteAllBytes($snapshotPath, $source)
        $attestation = Test-ApimAnalysisPackage -CandidatePath $snapshotPath
        if ($attestation.packageSha256 -cne $digest) { throw 'ANALYSIS_PROMOTION_REJECTED' }
        $attestationJson = ConvertTo-ApimAnalysisJson -Value $attestation
        Test-ApimAnalysisAttestation -Json $attestationJson
        $attestationPath = Join-Path $stage 'validation-attestation.json'
        [IO.File]::WriteAllText($attestationPath, $attestationJson, [Text.UTF8Encoding]::new($false))
        $savedAttestation = [Text.UTF8Encoding]::new($false, $true).GetString(
            (Read-ApimAnalysisSnapshot -Path $attestationPath)
        )
        Test-ApimAnalysisAttestation -Json $savedAttestation
        if ($savedAttestation -cne $attestationJson) { throw 'ANALYSIS_PROMOTION_REJECTED' }
        Assert-ApimAnalysisIsolation @isolation
        Test-ConfigPathLink -Path $candidate -Context 'Candidate directory'
        Test-ConfigPathLink -Path $stage -Context 'Private snapshot'
        Test-ConfigPathLink -Path $destination -Context 'Publication destination'
        foreach ($path in @($sourcePath, $snapshotPath)) {
            if ((Get-ApimAnalysisDigest -Bytes (Read-ApimAnalysisSnapshot -Path $path)) -cne $digest) {
                throw 'ANALYSIS_PROMOTION_REJECTED'
            }
        }
        if (@(Get-ChildItem -LiteralPath $stage -Force).Count -ne 2) {
            throw 'ANALYSIS_PROMOTION_REJECTED'
        }
        # Directory.Move is a no-overwrite rename, never a cross-filesystem copy fallback.
        [IO.Directory]::Move($stage, $destination)
        $stage = $null
        return [pscustomobject]@{
            status = 'Promoted'; version = $Version; packageSha256 = $digest
        }
    }
    catch {
        throw [InvalidOperationException]::new('ANALYSIS_PROMOTION_REJECTED')
    }
    finally {
        if ($null -ne $stage -and [IO.Directory]::Exists($stage)) {
            try {
                Test-ConfigPathLink -Path $stage -Context 'Owned staging cleanup'
                [IO.Directory]::Delete($stage, $true)
            }
            catch { throw [InvalidOperationException]::new('ANALYSIS_CLEANUP_REJECTED') }
        }
    }
}
