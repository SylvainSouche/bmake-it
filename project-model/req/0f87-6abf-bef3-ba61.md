---
schema_version: 2
id: 0f87-6abf-bef3-ba61
alias: fetch-build-prefix-stability-req
type: req
status: confirmed
origin: implementation, 2026-10-02, lasviewer-usage-feedback-obs open item 1
created: 2026-10-02
rel_informed_by: [0f87-6abf-bef3-fed3]
rel_refines: [0f87-6abf-aeb9-719c]
generator: model.py/2.4.0
checksum: 5f8b755f3d8e
---

# A module's FETCH_BUILD= CMAKE_PREFIX_PATH lists only install prefixes that exist when it is first parsed: modules before it in its framework's build order plus every PREREQS=-visible framework's modules -- never its own or a later sibling's work/_install -- so the build fingerprint is identical on its first and second build

<!-- rationale, detail, alternatives considered -->
