---
schema_version: 2
id: 6f38-6a8a-06bf-eece
alias: build-output-mirrors-install-prefix
type: dec
status: recorded
origin: user statement (clarifying question, 2026-08-22)
created: 2026-08-22
facets: [architecture]
rel_informed_by: [6f38-6a89-ba51-340e]
generator: model.py/2.4.0
checksum: 313e479f9383
---

# Build output under build/<KEY>/ is structured to mirror a real installable prefix layout (plain Unix /usr/local-style, MacPorts /opt/local-style, or a macOS .app bundle), not an arbitrary bin/lib/share convenience layout

User confirmed: the bin/lib/share layout under build/<KEY>/ is not just a made-up convenience structure -- it should mirror the actual destination/install-prefix layout the target uses. For plain Unix-style prefixes (FreeBSD, Linux, MacPorts at /opt/local/) this already matches what has been decided: bin/, lib/, share/ are exactly the standard *NIX install-prefix subdirectories, so REQ-build-output-tree-structure needs no structural change for those targets -- it now has an explicit rationale (it mirrors a real install prefix, not an ad-hoc convention). For macOS, however, a proper .app bundle uses a fundamentally different layout (Contents/MacOS/ for executables, Contents/Frameworks/ for dylibs, Contents/Resources/ for resources, Info.plist, etc.), which bin/lib/share does not resemble at all. This means macOS targets may need TWO possible output shapes depending on what is being built: a plain Unix-style prefix layout (for command-line tools/libraries, e.g. via MacPorts-style install) or a .app bundle layout (for GUI applications). Which of these applies, and whether .app bundle support is needed now or deferred, is an open follow-up question -- not yet decided.
