---
schema_version: 2
id: 0f87-6aea-dde0-a9df
alias: graceful-error-on-missing-variable-req
type: req
status: confirmed
origin: user, 2026-11-04, review of GarminViewer's include-first proposal; decided: guard + diagnostic, and graceful human-readable errors project-wide
created: 2026-11-04
rel_decided_by: [0f87-6aea-dde0-3c4c]
generator: model.py/2.4.0
checksum: e812b0fd6476
---

# A missing, invalid or too-late prerequisite variable ends in a human-readable error, never a raw bmake message or a silent result

Project-wide. When a variable the build depends on is unset, has an invalid value, or is set too late to have effect, the build stops through a .error (or the script equivalent) that names the variable, says what is wrong and says how to fix it. Not acceptable: bmake's own 'Variable X is undefined' or 'Cannot open ...', a stack of follow-on errors, or carrying on with a wrong result. Existing examples: unknown TOOLCHAIN, REQUIRES=, ABI=/TOOLCHAIN= contradiction. Gaps are fixed as they are found; an audit is tracked by graceful-error-audit-cand.
