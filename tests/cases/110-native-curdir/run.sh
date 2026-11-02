#!/bin/sh
# native-curdir-req. A path compiled into a program, opened by that program:
# ${.CURDIR} is /cygdrive/c/... for a native Windows program, which cannot open
# it (OpenRider, 2026-11-02). NATIVE_CURDIR works on every output, in C and
# C++, set before the role file is included.
set -eu
. "$BMK_TESTLIB"

mkdir -p ws/Fw/rd.m/src ws/Fw/rdxx.m/src
printf 'PARENT_WS=\n.include "mk.workspace.mk"\n' > ws/makefile
printf 'PREREQS=\n.include <mk.framework.mk>\n' > ws/Fw/makefile
echo 'found it' > ws/Fw/rd.m/data.txt
echo 'found it' > ws/Fw/rdxx.m/data.txt

cat > ws/Fw/rd.m/makefile <<'EOF'
PROG=rd
CFLAGS += -DDATA='"${NATIVE_CURDIR}/data.txt"'
.include <mk.prog.mk>
EOF
cat > ws/Fw/rdxx.m/makefile <<'EOF'
PROG=rdxx
CXXFLAGS += -DDATA='"${NATIVE_CURDIR}/data.txt"'
.include <mk.prog.mk>
EOF
cat > ws/Fw/rd.m/src/main.c <<'EOF'
#include <stdio.h>
int main(void) {
    char b[32];
    FILE *f = fopen(DATA, "r");
    if (!f || !fgets(b, sizeof b, f)) { fprintf(stderr, "cannot read %s\n", DATA); return 1; }
    fputs(b, stdout);
    return 0;
}
EOF
cat > ws/Fw/rdxx.m/src/main.cpp <<'EOF'
#include <cstdio>
int main() {
    char b[32];
    std::FILE *f = std::fopen(DATA, "r");
    if (!f || !std::fgets(b, sizeof b, f)) { std::fprintf(stderr, "cannot read %s\n", DATA); return 1; }
    std::fputs(b, stdout);
    return 0;
}
EOF

cd ws
bmake >build.log 2>&1 || { cat build.log >&2; exit 1; }
top=$(pwd)
for p in rd rdxx; do
    b=$(find "$top/Fw" -type f -name "$(prog_name "$p")" | head -1)
    [ -n "$b" ] || { echo "$p was not built" >&2; exit 1; }
    got=$(cd / && "$b" | tr -d '\r')
    [ "$got" = 'found it' ] || { echo "$p: expected the file's text, got [$got]" >&2; exit 1; }
done

v=$(cd Fw/rd.m && bmake -V NATIVE_CURDIR)
if native_win_runtime; then
    case "$v" in [A-Za-z]:/*) ;; *) echo "native Windows output: expected C:/..., got $v" >&2; exit 1 ;; esac
else
    [ "$v" = "$(cd Fw/rd.m && bmake -V .CURDIR)" ] || { echo "expected .CURDIR, got $v" >&2; exit 1; }
fi

echo "native-curdir OK"
