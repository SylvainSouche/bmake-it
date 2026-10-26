---
schema_version: 2
id: 0f87-6abf-aeb9-ad9d
alias: requires-header-prefix-probe-req
type: req
status: confirmed
origin: implementation, 2026-10-02, lasviewer-fifth-round-issues-obs item 1
created: 2026-10-02
rel_informed_by: [0f87-6abf-aeb1-4d57]
rel_refines: [0f87-6abe-49ca-e589]
generator: model.py/2.4.0
checksum: 4bbbafdd3f1f
---

# A REQUIRES=header:<path> entry is also satisfied when <path> exists under <prefix>/include for any prefix the IMPORT_LIB=none step-4 probe uses (_TOOL_PREFIXES with the trailing bin/ stripped); the error names the prefixes tried. The check therefore runs after the 'pre' hook phase (new mk.requires.mk), so a pre hook that overrides _TOOL_PREFIXES or adds -I is seen

<!-- rationale, detail, alternatives considered -->
