# SemVer releases

## Version source and policy

`ApimAssessment.psd1`'s `ModuleVersion` is the only version source. Use exactly
`MAJOR.MINOR.PATCH`, without leading zeros, a fourth segment, or a prerelease
suffix. Tags are `v<ModuleVersion>`. The bootstrap starts at `0.1.0`.

Patch means compatible fixes; minor means compatible features; major means
breaking supported CLI, configuration, JSON, finding-key, or reporting contracts.
Experimental contracts may change at minor versions during `0.x`. GitHub marks
those releases as prereleases. Do not publish `1.0.0` until T-609 is approved.
The workflow enforces increasing versions, not an inferred compatibility impact.

## Prepare and validate

1. Create `chore/release-<version>` and run the branch guard.
2. Update `ModuleVersion` in the manifest; preserve its GUID. Update README and
   explain compatibility changes in the PR. Commit and merge after review/CI.
3. For the initial `0.1.0`, the bootstrap PR itself contains the version; a second
   bump PR is not required for the first release.
4. On GitHub, run **SemVer release** with **Branch: main**. The workflow does not
   bump versions or write commits to `main`.

Local preflight from the repository root:

```powershell
.\scripts\Invoke-Checks.ps1
git fetch origin --tags
$tags = @(git tag --list 'v*')
if ($LASTEXITCODE -ne 0) { throw 'Could not read tags.' }
.\scripts\Get-ReleaseVersion.ps1 -ExistingTags $tags
$package = .\scripts\New-ReleasePackage.ps1 -OutputDirectory artifacts\release-preview
Get-FileHash -LiteralPath $package.Archive -Algorithm SHA256
Get-Content -LiteralPath $package.Checksum
```

Use a fresh output directory for each packaging attempt. Existing files are not
overwritten. This dry run neither creates tags nor contacts the release API.

## Workflow behavior

- Refuses a non-main workflow dispatch, then reruns the shared Windows/Linux
  lint and offline-test workflow at the dispatch's exact commit.
- Fetches full history/tags and rejects the candidate if any existing stable
  `vMAJOR.MINOR.PATCH` tag has an equal or higher version. Non-version and
  prerelease-suffixed tags are not stable-release comparators.
- Creates `ApimAssessment-<version>.zip` and its SHA-256 checksum from an explicit
  source allowlist. Includes module files, implemented entry points, source,
  rules, KQL, schemas, workbook templates, documentation, and **only**
  `config/sample.psd1` from config.
- Preserves empty source folders so the initial package imports successfully.
  Excludes runs, customer config, tests/fixtures, local output, `.github`, and Git
  metadata. Files in allowlisted directories must still be reviewed for secrets.
  Developer scripts/tests are checkout-only; a release ZIP is for module/runtime
  use, not the development quick start.
- The source/schema allowlists include Organization collection, optional
  governance models and package 1.4 contracts automatically. User inventory is
  always counts-only; identity storage is not an available opt-in. Package
  contract 1.4 is separate from the module's SemVer and does not itself request
  a version bump or authorize customer/live/model access.
- Creates a draft release at the validated SHA with generated notes and assets,
  then publishes it. Serializes releases and never overwrites an existing tag.
- Uses `contents: read` by default and `contents: write` only for the publication
  job. No personal access token, Azure credentials, or branch-write permission
  bypass is required. Tag rulesets must permit the release job's `GITHUB_TOKEN`;
  if repository policy blocks it, a maintainer must resolve the policy.

Workflows become selectable in Actions after merge to the default branch.
Tag/release creation using `GITHUB_TOKEN` does not automatically trigger other
ordinary tag/release workflows; all current validation and packaging are in this
release workflow instead.

## Verify a downloaded package

Compare `Get-FileHash -Algorithm SHA256` with the published `.sha256` file. Extract
the ZIP to a clean directory and run `Import-Module` against its manifest in
PowerShell 7.4+. A `0.1.0` bootstrap package still has no assessment commands;
releasing it does not imply assessment readiness.

## Recovery

If creation/upload/publication fails, inspect the Actions error, tag target, and
draft release first. An existing tag intentionally blocks a blind retry.
For an intact draft with correct target and checksum, finish its missing upload
or publication manually. If the tag/release is already public, never change its
target or replace its assets: prepare a new version instead. Do not delete or
retag published versions to make the workflow pass.
