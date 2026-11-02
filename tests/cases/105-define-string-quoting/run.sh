#!/bin/sh
# msvc-wrapper-keeps-arguments-whole-req. A string -D means the same on every
# toolchain: quotes, a space, a backslash and a dollar sign reach the compiler,
# in C and in C++. The MSVC wrapper re-read its flags through eval, so cl.exe
# got -DNAME=text and read the text as code (OpenRider, 2026-11-02).
set -eu
. "$BMK_TESTLIB"

mkdir -p ws/Fw/show.m/src ws/Fw/showxx.m/src
printf 'PARENT_WS=\n.include "mk.workspace.mk"\n' > ws/makefile
printf 'PREREQS=\n.include <mk.framework.mk>\n' > ws/Fw/makefile

cat > ws/Fw/show.m/makefile <<'EOF'
PROG=show
CFLAGS += -DGREETING='"hello world"' -DWHERE='"C:/a b/c"' -DBACK='"a\\b"' -DCOST='"cost $$5"' -DNUM=3
.include <mk.prog.mk>
EOF
cat > ws/Fw/show.m/src/main.c <<'EOF'
#include <stdio.h>
int main(void) { printf("%s|%s|%s|%s|%d\n", GREETING, WHERE, BACK, COST, NUM); return 0; }
EOF

cat > ws/Fw/showxx.m/makefile <<'EOF'
PROG=showxx
CXXFLAGS += -DGREETING='"hello world"' -DWHERE='"C:/a b/c"' -DBACK='"a\\b"' -DNUM=3
.include <mk.prog.mk>
EOF
cat > ws/Fw/showxx.m/src/main.cpp <<'EOF'
#include <cstdio>
int main() { std::printf("%s|%s|%s|%d\n", GREETING, WHERE, BACK, NUM); return 0; }
EOF

cd ws
bmake >build.log 2>&1 || { cat build.log >&2; echo "string defines should build" >&2; exit 1; }

run_one() {
    b=$(find . -type f -name "$(prog_name "$1")" | head -1)
    [ -n "$b" ] || { echo "$1 was not built" >&2; exit 1; }
    "$b" | tr -d '\r'
}
got=$(run_one show)
want='hello world|C:/a b/c|a\b|cost $5|3'
[ "$got" = "$want" ] || { echo "C: expected [$want], got [$got]" >&2; exit 1; }
got=$(run_one showxx)
want='hello world|C:/a b/c|a\b|3'
[ "$got" = "$want" ] || { echo "C++: expected [$want], got [$got]" >&2; exit 1; }

echo "define-string-quoting OK"
