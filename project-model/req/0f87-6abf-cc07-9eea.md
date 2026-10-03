---
schema_version: 2
id: 0f87-6abf-cc07-9eea
alias: tst-scripts-are-tests-req
type: req
status: confirmed
origin: user, 2026-10-02, design discussion after the lasviewer usage retrospective (bmake-it-feedback-from-lasviewer.md); modelled on Dassault Systemes mkmk's Framework.tst test frameworks
created: 2026-10-02
rel_decided_by: [0f87-6abf-cc07-d57e]
rel_refines: [0f87-6aa8-00f3-4ed1]
generator: model.py/2.4.0
checksum: 736221c2a033
---

# Every script in a .tst module's testcases/ is a test, auto-discovered like src/ (no TESTS_SH= list) and registered with Kyua as an atf-sh test program; the module's built program(s) and its scripts are placed in one test directory so a script reaches its helper through atf_get_srcdir

<!-- rationale, detail, alternatives considered -->
