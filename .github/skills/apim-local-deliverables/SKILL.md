---
name: apim-local-deliverables
description: Request local deterministic Excel and HTML reports without exposing report contents or paths to a model.
---

Use only the broker-only orchestrator profile and `render_reports`. Supply a
known opaque run ID and accepted output IDs, or an empty list for deterministic
non-AI fallback. Package/output hashes and evidence compatibility are checked
locally. Rejected AI proposals are never silently used.

Report templates and restricted identity rehydration are deterministic local
operations. Never ask a model to open/edit a workbook, HTML report, alias map or
restricted model. Never send the rendered output to another tool or service.
Return only fixed status and opaque artifact IDs. Operator-owned
`restricted/report-artifacts.json` maps these IDs to local report files; no tool
reads that registry. Public ordinary-terminal Report also renders offline without
Copilot. Human visual/readout review remains required.
