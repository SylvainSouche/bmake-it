---
schema_version: 2
id: 0f87-6abf-cc7e-e78c
alias: tst-test-environment-dec
type: dec
status: recorded
origin: user, 2026-10-02, design discussion (.tst test modules)
created: 2026-10-02
rel_informed_by: [0f87-6abf-cc07-d57e]
generator: model.py/2.4.0
checksum: 82ce9c8f5393
---

# A test script's environment is the resulting build output, not just its own module or framework: every executable present in the resulting bin is callable (PATH), regardless of which framework built it. Using an executable from a framework outside the test's PREREQS= is bad practice, documented as such, and deliberately NOT an error and NOT tracked (no build-order or visibility check, so such an executable may be absent or stale depending on build order -- the cost of the practice). A helper SCRIPT a test needs is not hidden in a test module: it is shipped the usual way (share/ overlay, or an executable in bin/)

<!-- rationale, detail, alternatives considered -->
