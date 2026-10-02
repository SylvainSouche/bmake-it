---
schema_version: 2
id: 0f87-6abf-aeb9-0fd8
alias: repeated-messages-fix-req
type: req
status: confirmed
origin: implementation, 2026-10-02, lasviewer-fifth-round-issues-obs item 4
created: 2026-10-02
rel_informed_by: [0f87-6abf-aeb1-4d57]
rel_refines: [0f87-6abe-8e5b-5d79]
generator: model.py/2.4.0
checksum: 70ec4839e999
---

# Progress messages appear only when the work they describe happened: 'built static/shared/<prog>' is printed by the archive/link recipe rather than by all:, and _stage_fetch_headers: (fetch: + SRCS= path) is fingerprint-guarded like _stage_import:

<!-- rationale, detail, alternatives considered -->
