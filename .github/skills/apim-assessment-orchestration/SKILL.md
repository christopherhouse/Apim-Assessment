---
name: apim-assessment-orchestration
description: Run the approved APIM assessment workflow using only the narrow local broker, with safe deterministic fallback.
---

Use only the `apim-assessment-orchestrator` profile with its seven exact broker
tools. If the host does not enforce that tool allowlist, stop. A skill does not
remove tools from a broad development session.

1. An operator owns isolation, approvals, complete visible roots and startup.
   Accept only a config alias/environment or opaque saved run ID, not paths.
2. Start `run_assessment` with the alias/environment and `options.stage` All or
   Collect, or use the approved saved run ID. Read fixed status enums.
3. Call `promote_analysis_package`. On failure stop assisted analysis; never
   inspect candidates or ask for access to the restricted root.
4. Read the package, record its exact digest, and use approved-code specialist
   proposals. Submit each through `validate_agent_output` with the run ID,
   digest, kind ExpertObservations and closed JSON.
5. Read revalidated proposals and synthesize ExecutiveSummary. Submit with the
   same digest. Do not claim a specialist ran when synthesizing locally.
6. Call `render_reports` with accepted output IDs. If proposals are unavailable
   or rejected, use an empty list for deterministic reports.
7. Return only coarse outcomes and opaque artifact IDs. The operator inspects
   local report files and the restricted artifact registry independently.

No Azure/shell/filesystem/delegation tools, raw/model data, aliases-to-identities,
paths, logs, credentials, exact metrics or arbitrary free-text output. Never
weaken approvals/trust/sandbox controls. IDs expire at broker restart.
