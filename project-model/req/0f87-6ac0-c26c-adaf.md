---
schema_version: 2
id: 0f87-6ac0-c26c-adaf
alias: staging-symlink-chain-real-file-req
type: req
status: confirmed
origin: implementation, 2026-10-03, lasviewer-sixth-round-issues-obs item 3
created: 2026-10-03
rel_informed_by: [0f87-6ac0-c26c-ee92]
rel_refines: [0f87-6ab5-8a9c-1d21]
generator: model.py/2.4.0
checksum: 533296f2e3ee
---

# Staging a library whose entries are symlinks to a real file in ANOTHER directory (a distro's libfoo.so -> libfoo.so.3 -> libfoo.so.3.3 -> /usr/lib/<triple>/libfoo.so.3.3) copies that real file into the staged lib directory exactly once and recreates every other name as a relative link to it, never linking a name to itself

<!-- rationale, detail, alternatives considered -->
