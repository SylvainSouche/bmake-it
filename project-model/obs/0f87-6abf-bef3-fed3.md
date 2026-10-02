---
schema_version: 2
id: 0f87-6abf-bef3-fed3
alias: lasviewer-usage-feedback-obs
type: obs
status: recorded
origin: user, 2026-10-02, pasted /Users/Shared/programming/pdalviewer/lasviewer-work/bmake-it-feedback-from-lasviewer.md
created: 2026-10-02
generator: model.py/2.4.0
checksum: 0c05044e25ec
---

# lasviewer usage retrospective (main c4d7295): five rounds done, no workarounds left (clean build 33s, no-op 5s, 44 tests); open items: one-time CMake reconfigure of a dependency FETCH_BUILD module, a prereqs-listing target, per-project pointer to bmake-it, display-needing tests, a permanent harness fixture shaped like a real project

Open item 1 reproduced with the 69-fetch-build-forwarding fixture: after a clean build the first rebuild re-ran the dependency module's configure+install once. Cause: its CMAKE_PREFIX_PATH listed every sibling's work/_install including a LATER sibling's, which exists only after that sibling is built. Items 2-5 are suggestions, not defects.
