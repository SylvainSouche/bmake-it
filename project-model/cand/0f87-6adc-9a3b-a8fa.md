---
schema_version: 2
id: 0f87-6adc-9a3b-a8fa
alias: cross-test-runner-cand
type: cand
status: accepted
origin: maintainer statement 2026-10-24 ('we need a cross test runner'); mk/mk.test.mk and mk.tst.mk read; cross-test-universal-coverage
created: 2026-10-24
rel_informed_by: [0f87-6adc-9a3a-95de]
generator: model.py/2.4.0
checksum: fbdd169bc789
---

# A cross test runner: bmake test TARGET=<os> TARGET_ARCH=<arch> builds the tests for the target and runs them ON the target. Design: kyua cannot be wrapped per test (it hands each ATF program a results file on the local filesystem), so the unit of work is the whole tests directory -- ship build/<key>/tests plus the libraries it loads to the target, run kyua test there, bring test-results.xml back and report it as usual. The target is named by a runner spec per target key, ssh:<host>:<port> (the BSD guests), docker:<image>[:<platform>] (Linux, amd64 emulated), or local (default, today's behaviour); the transfer-and-run script is generalised from the harness's exec-cross-vm.sh and exec-cross-docker.sh into scripts/. Open: product feature or harness only; where the runner spec is declared (workspace makefile, the chapter 05 configuration makefile, or the command line); the target needs kyua and atf installed (the provisioned BSD guests have them); macOS and Windows targets

<!-- rationale, detail, alternatives considered -->
