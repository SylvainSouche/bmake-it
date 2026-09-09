---
schema_version: 2
id: 0f87-6a95-afab-2ced
alias: mod-order-sysroot-hardcoded-macports-fallback
type: obs
status: recorded
origin: cross-platform test matrix run, 2026-08-31: found while automating linux-glibc/linux-musl/macOS/NetBSD test runs
created: 2026-08-31
generator: model.py/2.1.0
checksum: f284ab59f2e5
---

# gen-mod-order's nested -V LIBS/LIB queries silently see no dependencies on any non-macOS host

mk.framework.mk's module-order generation passed BMK_SYS_MK='${BMK_SYS_MK:U/opt/local/share/mk}' to gen-mod-order.sh -- hardcoding a MacPorts-only fallback whenever the caller hadn't already set BMK_SYS_MK (which nothing upstream ever does). gen-mod-order.sh's own _bmake_q swallows query failures via '|| true', so on Linux/other non-macOS hosts every nested -V LIBS/LIB/PROG query against the nonexistent sys.mk path failed silently, making every module look dependency-free. Modules then emit in plain glob (alphabetical) order instead of topological order. This was invisible in every test case whose alphabetical order happened to already satisfy the real dependency (e.g. 'libg' before 'prog'), and surfaced only in case 10-prog-link-lib (PROG name 'app' sorts before its LIB 'libg') -- specifically when run inside a Linux container, never on macOS/NetBSD where /opt/local/share/mk genuinely exists.
