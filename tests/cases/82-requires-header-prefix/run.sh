#!/bin/sh
# requires-header-prefix-probe-req (lasviewer round 5, item 1): a
# REQUIRES=header:<path> entry is also satisfied by <prefix>/include/<path>
# for any prefix in _TOOL_PREFIXES (bin/ stripped) -- the same prefixes
# IMPORT_LIB=none's step-4 probe uses. Found in real use: MacPorts' clang
# does not search /opt/local/include by default, so glm (installed there)
# was found by the import but rejected by REQUIRES=header:glm/glm.hpp.
# Here the header exists ONLY under a fake tool prefix the compiler does
# not search: it must pass; a genuinely absent header must still fail,
# naming the prefixes tried.
set -eu
ROOT=$(pwd)
PFX="$ROOT/fake/pfx"
mkdir -p "$PFX/bin" "$PFX/include/vendor"
echo '#define VEND_H 1' > "$PFX/include/vendor/vend.h"

M=ws/Fw/app.m
# _TOOL_PREFIXES is overridden from a "pre" hook (as case 48 does); the
# REQUIRES= check runs after that phase, so it sees the override.
echo "_TOOL_PREFIXES = $PFX/bin" > $M/mk/pre.mk

printf 'PROG=app\nREQUIRES=header:vendor/vend.h\n.include <mk.prog.mk>\n' > $M/makefile
cd ws
bmake >build1.log 2>&1
[ -n "$(find . -type f -name app | head -1)" ]

# Genuinely absent: still an error, naming what was tried.
printf 'PROG=app\nREQUIRES=header:vendor/absent-3f8a2b.h\n.include <mk.prog.mk>\n' > Fw/app.m/makefile
( cd Fw/app.m && bmake clean >/dev/null 2>&1 )
if bmake >build2.log 2>&1; then
    echo "expected an absent header to fail REQUIRES=header:" >&2
    exit 1
fi
grep -q "REQUIRES=header:vendor/absent-3f8a2b.h" build2.log
grep -q "header vendor/absent-3f8a2b.h not found" build2.log
grep -q "<prefix>/include for: $PFX" build2.log

echo "requires-header-prefix OK"
