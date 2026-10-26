---
schema_version: 2
id: 0f87-6abe-3eee-a5f1
alias: shared-import-link-flags-fix-req
type: req
status: confirmed
origin: lasviewer-third-round-issues-obs
created: 2026-10-01
rel_informed_by: [0f87-6abe-3ed4-e933]
rel_refines: [0f87-6ab5-8e3d-a85e]
generator: model.py/2.4.0
checksum: ea7549072978
---

# A shared IMPORT=pkg: resolution (a .so/.dylib found at the resolved libdir) uses plain pkg-config --libs, not --libs --static's full transitive closure -- the full closure's Requires.private entries can validly omit their own -L, relying on the host's default linker search path, breaking this project's own build for an unrelated transitive dependency. Only a static-only import (no .so/.dylib found) uses the full --static closure

<!-- rationale, detail, alternatives considered -->
