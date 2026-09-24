---
schema_version: 2
id: 0f87-6aaa-665e-fded
alias: build-workspace-aggregation-req
type: req
status: superseded
origin: user statement, 2026-09-16, motivated by integration-manager-ci-cycle
created: 2026-09-16
rel_decided_by: [0f87-6aaa-661a-ada2]
rel_motivated_by: [0f87-6aaa-6432-66a7]
generator: model.py/2.4.0
checksum: 11823f894dee
---

# A framework/workspace-level bmake all always captures each module's build output to a log file (<module>/build/<KEY>/build.log, tee'd so console output is unchanged) -- REPORT unset keeps today's fail-fast-on-first-error abort; REPORT=yes instead continues past a failing module so every module gets a chance to build, and afterward generates a workspace-level build-report/index.html dashboard (build-report/index.html) listing every framework/module with PASS/FAIL and a link to its build.log, mirroring the test dashboard

<!-- rationale, detail, alternatives considered -->
