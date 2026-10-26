---
schema_version: 2
id: 0f87-6abf-aeb9-4cb9
alias: failed-prereq-framework-skip-req
type: req
status: confirmed
origin: implementation, 2026-10-02, lasviewer-fifth-round-issues-obs item 2
created: 2026-10-02
rel_informed_by: [0f87-6abf-aeb1-4d57]
rel_refines: [0f87-6aaa-6a5e-378f]
generator: model.py/2.4.0
checksum: 47743855b239
---

# A workspace build skips a framework whose PREREQS= names a framework that failed or was itself skipped, printing '===> framework X skipped: prerequisite Y failed' (plus the root cause for a transitive skip); independent frameworks are still built; the skipped framework counts as failed for the exit status, and the final summary lists root failures first, skipped frameworks after

<!-- rationale, detail, alternatives considered -->
