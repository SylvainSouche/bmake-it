---
schema_version: 2
id: 6f38-6a8a-dba2-dcc2
alias: modules-and-frameworks-auto-discovered-req
type: req
status: confirmed
origin: user statement (clarifying question, 2026-08-22)
created: 2026-08-23
facets: [architecture]
rel_decided_by: [6f38-6a8a-dba2-7b93]
rel_informed_by: [6f38-6a88-1836-bfe8, 6f38-6a8a-f6ee-e69f]
rel_refines: [6f38-6a88-1836-74a5, 6f38-6a8a-9be8-14df]
generator: model.py/2.4.0
checksum: 290a8537e0b1
---

# A frameworks modules are discovered by scanning for *.m-suffixed immediate subdirectories; a workspaces frameworks are discovered by scanning immediate subdirectories -- neither is explicitly listed in the parent makefile

Extends the auto-discovery philosophy of REQ-module-src-auto-discovery up two levels. At framework level: mk.framework.mk scans the frameworks own directory for immediate subdirectories matching *.m (REQ-module-dir-naming-convention) and treats each as a module to build. At workspace level: mk.workspace.mk scans the workspace root for immediate subdirectories and treats each as a framework -- exact discrimination signal for what counts as a framework subdirectory (vs. e.g. build/) is a related open follow-up, see REQ-framework-discovery-signal-req.
