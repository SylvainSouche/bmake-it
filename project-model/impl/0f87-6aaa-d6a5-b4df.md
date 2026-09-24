---
schema_version: 2
id: 0f87-6aaa-d6a5-b4df
alias: impl-install-env-script
type: impl
status: asserted
origin: implemented 2026-09-16
created: 2026-09-16
rel_implements: [0f87-6aaa-d65f-eeca]
generator: model.py/2.4.0
checksum: b63a28f8059f
---

# scripts/install-env.sh: computes MAKESYSPATH via bmake -f /dev/null -V .SYSPATH (guarded against a stray/broken makefile in the invocation directory), appends an idempotent marker-delimited block to the invoking user's own shell rc file (zsh/bash/fish/POSIX sh detected via $SHELL, not guessed) by default, or writes /etc/profile.d/bmake-it.sh under --system (Linux only, needs root); --uninstall removes exactly what was added; explicit y/N confirmation (or -y) before touching any file

<!-- rationale, detail, alternatives considered -->
