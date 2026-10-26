---
schema_version: 2
id: 0f87-6adc-e6ab-ef14
alias: test-case-100-cross-pkg-config-sysroot
type: test
status: passing
origin: tests/cases/100-cross-pkg-config-sysroot, 2026-10-24; asked for in the review of PR #20; passes on macOS and Linux glibc arm64, fails against the OS-only cross check and without the sysroot prefix (mutation runs)
created: 2026-10-24
rel_verifies: [0f87-6adc-d562-5864, 0f87-6adc-d562-e6c5, 0f87-6adc-d727-47b4]
generator: model.py/2.4.0
checksum: 3ac4d5da8754
---

# Case 100, fake sysroots of .pc files and a decoy on PKG_CONFIG_PATH, nothing compiled: a native build reads the host's zed.pc; linux on the other architecture (multiarch dir), linux-riscv64, freebsd (usr/local/libdata), netbsd (usr/pkg/lib) and the host's own OS on the other architecture each resolve the sysroot's, with libdir, includedir and the .pc file in the sysroot; a sysroot without zed does not resolve (the decoy never leaks); REQUIRES= finds zed in the sysroot and sh on PATH, and a missing one names the sysroot; TEST_RUNNER=local gives QEMU_LD_PREFIX=<sysroot> for a foreign Linux target, keeps the caller's, and nothing for a native build or FreeBSD

<!-- rationale, detail, alternatives considered -->
