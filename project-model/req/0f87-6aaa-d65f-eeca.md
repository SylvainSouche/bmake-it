---
schema_version: 2
id: 0f87-6aaa-d65f-eeca
alias: install-env-script-req
type: req
status: confirmed
origin: correcting a copy-paste alias typo ('qt', leftover from an unrelated earlier command) on an object created moments earlier -- content unchanged, alias only
created: 2026-09-16
rel_decided_by: [0f87-6aaa-d63e-839a]
rel_supersedes: [0f87-6aaa-d646-cf1d]
generator: model.py/2.4.0
checksum: aa7ee808b808
---

# scripts/install-env.sh sets up MAKESYSPATH so any out-of-tree project can find Bmake It's mk/ files without per-invocation flags: user-level by default (appends an idempotent, clearly-delimited block to the right shell rc file for the invoking user's shell -- bash/zsh/POSIX sh, detected not guessed), --system on Linux (/etc/profile.d/bmake-it.sh, one file, no per-user dotfile edits, needs elevated privileges), --uninstall removes exactly what was added and nothing else. Prints what it is about to modify and requires explicit confirmation (or -y) before touching any file -- this is persistent-configuration-modifying, not a silent side effect of anything else. macOS and Windows system-level equivalents are not designed here -- user-level (which works everywhere, including those hosts) covers the gap for now

Supersedes 0f87-6aaa-d646-cf1d (scripts/install-env.sh sets up MAKESYSPATH so any out-of-tree project can find Bmake It's mk/ files without per-invocation flags: user-level by default (appends an idempotent, clearly-delimited block to the right shell rc file for the invoking user's shell -- bash/zsh/POSIX sh, detected not guessed), --system on Linux (/etc/profile.d/bmake-it.sh, one file, no per-user dotfile edits, needs elevated privileges), --uninstall removes exactly what was added and nothing else. Prints what it is about to modify and requires explicit confirmation (or -y) before touching any file -- this is persistent-configuration-modifying, not a silent side effect of anything else. macOS and Windows system-level equivalents are not designed here -- user-level (which works everywhere, including those hosts) covers the gap for now).

Carries forward what remained valid and states what changed.
