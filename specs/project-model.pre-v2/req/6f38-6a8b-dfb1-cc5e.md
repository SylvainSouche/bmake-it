---
id: 6f38-6a8b-dfb1-cc5e
alias: destdir-prefix-confirmed-req
type: req
status: superseded
origin: user statement (clarifying question, 2026-08-22)
created: 2026-08-24
facets: [architecture]
relationships: {superseded_by: [REQ-6f38-6a8e-048e-f811], decided_by: [DEC-6f38-6a8b-dfb1-18e7], refines: [REQ-6f38-6a8b-df45-59b4]}
---

# make install DESTDIR=<staging-root> PREFIX=<final-path> installs build/<KEY>/{bin,lib,share} into $(DESTDIR)$(PREFIX)/{bin,lib,share}, using bsd makes own native DESTDIR/PREFIX variables unchanged

Confirms and closes the open variable-naming follow-up on REQ-install-target-exists-req: DESTDIR and PREFIX are used exactly as in real bsd make, no project-specific renaming. The relationship between make install and the per-format packaging targets (REQ-packaging-per-format-targets-req) -- e.g. whether make port/pkg internally invoke make install into a temporary DESTDIR -- remains an open follow-up.
