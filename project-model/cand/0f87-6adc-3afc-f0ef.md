---
schema_version: 2
id: 0f87-6adc-3afc-f0ef
alias: cross-sysroot-with-prerequisites-cand
type: cand
status: open
origin: maintainer statement 2026-10-24 ('real cross compile limitation: sysroot only contains os, not prerequisites'); checked against mk/mk.common.mk and a FreeBSD arm64 sysroot
created: 2026-10-24
rel_informed_by: [0f87-6adc-3af6-3b8e]
generator: model.py/2.4.0
checksum: c06fcaff5559
---

# Make a cross sysroot carry the prerequisites: (A) lookup -- for every cross target run pkg-config with PKG_CONFIG_SYSROOT_DIR=<sysroot> and PKG_CONFIG_LIBDIR limited to the sysroot's pkgconfig directories (generalising the mingw mechanism), never the host's, with a clear error naming the sysroot when nothing is found; (B) content -- install the prerequisites with the target's own package manager in the target's guest (pkg on FreeBSD, pkg_add on NetBSD, apt -dev packages in a matching-arch container for Linux, a MacPorts/Homebrew prefix for macOS) and tar the guest including /usr/local or /usr/pkg; (C) declaration -- which packages a sysroot carries is declared once (the configuration makefile of chapter 05), not hard-coded in the harness. Open: package names differ per OS; versions are whatever the target's repository serves; building a sysroot needs the network

Part A is small and testable with a fake sysroot like the existing fake-package cases. Part B uses the guests already built. Part C waits for the chapter 05 configuration design.
