---
schema_version: 2
id: 0f87-6aea-dde0-3c4c
alias: include-first-and-graceful-errors-dec
type: dec
status: recorded
origin: user, 2026-11-04, review of GarminViewer's include-first proposal; decided: guard + diagnostic, and graceful human-readable errors project-wide
created: 2026-11-04
generator: model.py/2.4.0
checksum: 9fcd93623382
---

# mk.common.mk may be included first; a setting made too late is an error; every missing prerequisite variable ends in a human-readable error

Decided with the user. (1) mk.common.mk defines BMK_MKDIR itself when unset, so a module makefile may .include it as its first line and then test TARGET before including mk.prog.mk/mk.lib.mk/mk.tst.mk. (2) What mk.common.mk reads at parse time (TOOLCHAIN, ABI, TARGET, TARGET_ARCH, OPENMP, SANITIZE) set to a different value after it has run -- by the module after an early include, or by a mk/pre*.mk hook -- stops the build with an error naming the variable, instead of being silently ignored; observed without the check: TOOLCHAIN=gcc, OPENMP=yes and SANITIZE=address after the early include were all ignored. (3) Project-wide principle: when a variable a build depends on is unset, invalid or set too late, the build exits gracefully through a .error that names the variable, says what is wrong and says how to fix it -- never a raw bmake message, never silent wrong behaviour. Other places that fall short are to be found and fixed as they are met.
