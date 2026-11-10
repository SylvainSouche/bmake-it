#!/bin/sh
# common-includable-first-req, late-setting-error-req,
# graceful-error-on-missing-variable-req: a module makefile may include
# mk.common.mk first and test ${TARGET} in its top section -- run directly, with
# no BMK_MKDIR set, as well as from its workspace (it used to stop with
# "Variable TARGET is undefined", and with "Cannot open /mk.paths.default.mk"
# once mk.common.mk was included first). A setting mk.common.mk reads at parse
# time (TOOLCHAIN, OPENMP, SANITIZE) made after it ran -- by the module, or by a
# mk/pre.mk hook -- is a plain-language error naming the variable, not silently
# ignored; the same value again, and a value given on the command line, are fine.
set -eu
cd ws/Fw/mod.m
# the real bmake, past the harness wrapper (first on PATH), so BMK_MKDIR can be unset
REAL=${BMK_REAL_MAKE:-$(PATH=${PATH#*:} command -v bmake)}
direct() { env -u BMK_MKDIR "$REAL" "$@"; }   # MAKESYSPATH still finds the mk files

# 1. run directly, BMK_MKDIR unset: TARGET readable, BMK_MKDIR is the mk directory
T=$(direct -f early.mk -V '${TARGET}' 2>&1) || { echo "direct run failed:" >&2; echo "$T" >&2; exit 1; }
[ "$T" = "$(bmake -V '${TARGET}')" ] || { echo "TARGET read in the top section was '$T'" >&2; exit 1; }
M=$(direct -f early.mk -V '${BMK_MKDIR}')
[ "$(cd "$M" && pwd -P)" = "$(cd "$BMK_MKDIR" && pwd -P)" ] || { echo "BMK_MKDIR is '$M', not $BMK_MKDIR" >&2; exit 1; }
# the conditional on TARGET took effect, with this host's own TARGET: another
# one can need a compiler this cell does not have (gcc for win needs mingw-w64)
direct -f early.mk -V '${LDFLAGS}' WANT_TARGET="$T" 2>&1 | grep -q -- '-learly' \
    || { echo "TARGET=$T: the top section's conditional did not take effect" >&2; exit 1; }
if direct -f early.mk -V '${LDFLAGS}' 2>&1 | grep -q -- '-learly'; then
    echo "the top section's conditional took effect on another TARGET" >&2; exit 1
fi
# 2. the same makefile through the harness wrapper (BMK_MKDIR given), as in a workspace
bmake -f early.mk -V '${TARGET}' >/dev/null || { echo "early include failed with BMK_MKDIR set" >&2; exit 1; }

# 3. a setting made after the early include is an error, naming the variable
DEFAULT_TC=$(bmake -V '${TOOLCHAIN}')
case $DEFAULT_TC in gcc) OTHER=llvm ;; *) OTHER=gcc ;; esac
late() { # late <VAR> <value>: VAR=value set after mk.common.mk ran
    printf '.include "mk.common.mk"\n%s=%s\nPROG=x\n.include "mk.prog.mk"\n' "$1" "$2" > late.mk
    if out=$(direct -f late.mk -V '${CC}' 2>&1); then
        echo "$1=$2 set after mk.common.mk was accepted silently" >&2; exit 1
    fi
    echo "$out" | grep -q "$1=$2 was set after mk.common.mk had already resolved" \
        || { echo "$1: the error does not say what happened:" >&2; echo "$out" >&2; exit 1; }
    echo "$out" | grep -q "Set $1 before the .include of mk.common.mk, or on the command line" \
        || { echo "$1: the error does not say how to fix it:" >&2; echo "$out" >&2; exit 1; }
}
late TOOLCHAIN "$OTHER"
late OPENMP yes
late SANITIZE address

# 4. the same value again, and the value on the command line, are fine
printf '.include "mk.common.mk"\nTOOLCHAIN=%s\nPROG=x\n.include "mk.prog.mk"\n' "$DEFAULT_TC" > same.mk
direct -f same.mk -V '${TOOLCHAIN}' >/dev/null 2>&1 || { echo "the same TOOLCHAIN again was refused" >&2; exit 1; }
[ "$(bmake -V '${TOOLCHAIN}' TOOLCHAIN=$OTHER)" = "$OTHER" ] || { echo "TOOLCHAIN=$OTHER on the command line not honoured" >&2; exit 1; }

# 5. a mk/pre.mk hook cannot set TOOLCHAIN either: error, not a silent no-op
mkdir -p mk
echo "TOOLCHAIN=$OTHER" > mk/pre.mk
if out=$(bmake -V '${CC}' 2>&1); then echo "TOOLCHAIN set in mk/pre.mk accepted silently" >&2; exit 1; fi
echo "$out" | grep -q "TOOLCHAIN=$OTHER was set after mk.common.mk had already resolved" \
    || { echo "pre.mk: the error does not say what happened:" >&2; echo "$out" >&2; exit 1; }
rm -rf mk

echo "include-first-and-late-settings OK"
