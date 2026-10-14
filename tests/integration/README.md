# Offline integration tests

`AnalysisAirlock.Tests.ps1` exercises the scaled synthetic model generator,
registered saved models and deterministic findings, allowlist construction,
independent validation, and immutable atomic publication. Both absent-usage
and explicit synthetic-usage scenarios are covered. Source canaries include
identifiers, URLs, IPs, UPNs, XML, metric text, credentials, encoded values,
Unicode, and high-entropy markers. Tests check package/map/attestation bytes,
all new pipeline streams, unchanged source files, deterministic reruns,
new-field rejection, and preservation of prior good publications.

Run repository lint plus the integration suite:

```powershell
.\scripts\Invoke-Checks.ps1 -TestPath tests\integration\AnalysisAirlock.Tests.ps1
```

No Azure authentication or customer data is permitted. Root visibility is an
explicit synthetic host contract, not discovery or modification of actual
Copilot permissions. Focused builder/validator/promotion suites cover malformed
contracts, links/traversal/overlap, incomplete visibility, hash mutations,
attestation errors, and publication collisions.

Full raw collection-to-workbook/HTML, broker access, tracking carry-forward, and
hostile concurrent-filesystem protection are not claimed by these tests.
