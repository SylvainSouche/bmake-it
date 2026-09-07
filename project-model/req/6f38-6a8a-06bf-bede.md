---
schema_version: 2
id: 6f38-6a8a-06bf-bede
alias: build-output-mirrors-prefix-layout
type: req
status: confirmed
origin: user statement (clarifying question, 2026-08-22)
created: 2026-08-22
facets: [architecture]
rel_decided_by: [6f38-6a8a-06bf-eece]
rel_refines: [6f38-6a89-ba51-340e]
generator: migrate.py/v2
checksum: 311b02eec4b7
---

# build/<KEY>/{bin,lib,share} mirrors a standard *NIX install-prefix layout for FreeBSD/Linux/MacPorts targets; macOS .app bundle output (a structurally different layout: Contents/MacOS, Contents/Frameworks, Contents/Resources) is a distinct, not-yet-designed alternative

Clarifies the rationale behind REQ-build-output-tree-structure: bin/, lib/, share/ under build/<KEY>/ are not an arbitrary convenience convention -- they mirror the real install-prefix layout used by plain *NIX systems (e.g. /usr/local/{bin,lib,share}) and by MacPorts (/opt/local/{bin,lib,share}). This layout is confirmed sufficient for FreeBSD, Linux, and MacPorts-style macOS targets. A macOS .app application bundle uses a structurally different layout (Contents/MacOS/ for the executable, Contents/Frameworks/ for shared libraries, Contents/Resources/ for resources, Info.plist metadata) that bin/lib/share cannot represent. Whether/when .app bundle output is needed, and how a module or framework would opt into it, is an open follow-up -- not yet decided, and not assumed to be in scope for phase 1.
