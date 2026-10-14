---
name: apim-model-safe-validation
description: Validate digest-bound APIM proposal handoffs through exact broker operations, never generic file access.
---

Use only the broker-only orchestrator profile. Validation is performed by local
code, not by a model pronouncing output safe.

Submit closed approved-code JSON using `validate_agent_output` with the exact
run ID, package digest and kind. The broker rejects unknown fields, duplicate
members/IDs, unsupported citations, evidence/code mismatches, confidence
escalation, posture/severity distortion, missing/invented gaps and stale digests.
Read back only `read_validated_agent_outputs`. Publication contains exactly the
package and attestation; proposals stay separately restricted.

On rejection, report the fixed code and omit that proposal or stop. Do not
relabel arbitrary prose as approved output, bypass a validator, seek raw
evidence, edit package/attestation files, widen permissions, or run generic
commands. Only an operator outside the model session may inspect restricted
diagnostics. Synthetic tests do not certify actual host/CLI isolation.
