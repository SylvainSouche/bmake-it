---
schema_version: 2
id: 0f87-6aea-ddec-454d
alias: impl-late-setting-error
type: impl
status: verified
origin: Claude, 2026-11-04, implementing include-first-and-graceful-errors-dec
created: 2026-11-04
rel_implements: [0f87-6aea-dde0-3d25]
generator: model.py/2.4.0
checksum: bb427ac2a542
---

# mk.common.mk records the resolved parse-time settings; mk.resolved.mk compares them

mk/mk.common.mk (end of guard) and mk/mk.resolved.mk, included by the role files after the pre-phase hooks
