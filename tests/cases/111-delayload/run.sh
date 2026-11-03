#!/bin/sh
# delay-load-default-by-library-req. A shared library declares DELAYLOAD; a
# module linking it overrides that. On output with delay loading, a delayed
# program starts without its DLL and fails only at the first call; on any other
# output a default does nothing and an explicit yes says so.
set -eu
. "$BMK_TESTLIB"
root=$(pwd)

mkdir -p ws/Fw/libdelay.m/src ws/Fw/libplain.m/src ws/Fw/libvar.m/src ws/Fw/app.m/src ws/Fw/over.m/src
printf 'PARENT_WS=\n.include "mk.workspace.mk"\n' > ws/makefile
printf 'PREREQS=\n.include <mk.framework.mk>\n' > ws/Fw/makefile

lib() { # lib <name> <extra makefile line> <source>
    printf 'LIB=%s\nLIB_SHARED=YES\nSHLIB_MAJOR=1\n%s\n.include <mk.lib.mk>\n' "$1" "$2" > "ws/Fw/lib$1.m/makefile"
    printf '%s\n' "$3" > "ws/Fw/lib$1.m/src/$1.c"
}
lib delay 'DELAYLOAD=yes' 'int delay_fn(void) { return 7; }'
lib plain '' 'int plain_fn(void) { return 7; }'
lib var   '' 'int var_fn(void) { return 7; }
int var_v = 7;'

prog() { # prog <dir> <PROG> <LIBS> <extra makefile line> <fn>
    printf 'PROG=%s\nLIBS=%s\n%s\n.include <mk.prog.mk>\n' "$2" "$3" "$4" > "$root/ws/Fw/$1.m/makefile"
    cat > "$root/ws/Fw/$1.m/src/main.c" <<EOF
#include <stdio.h>
int $5(void);
int main(int argc, char **argv) {
    puts("started");
    fflush(stdout);
    if (argc > 1) printf("got %d\n", $5());
    return 0;
}
EOF
}
prog app  app  'delay plain' '' delay_fn          # the library's default
prog over over 'delay plain' 'DELAYLOAD.delay=no
DELAYLOAD.plain=yes' plain_fn                     # both overridden
# over must import both libraries: a DLL it never refers to is not imported at all.
cat >> ws/Fw/over.m/src/main.c <<'EOF'
int delay_fn(void);
int (*over_keeps)(void) = delay_fn;
EOF

cd ws
bmake >build.log 2>&1 || { cat build.log >&2; exit 1; }
top=$(pwd)

bin() { find "$top/Fw" -type f -name "$(prog_name "$1")" | head -1; }

# The runtime stays reachable, the libraries do not: a mingw C program needs only
# system DLLs, and Cygwin output needs cygwin1.dll.
ALONE_PATH=/usr/bin:$(cygpath -u "${SYSTEMROOT:-C:/Windows}" 2>/dev/null || echo /bin)/System32

kind=$(bmake -C Fw/app.m -V _DELAYLOAD_KIND)

if [ "$kind" = none ]; then
    # --- no delay loading: the default has no effect and says nothing ------------
    # (Windows has no rpath: Cygwin output finds its DLLs on PATH)
    PATH="$(dirname "$(find "$top/Fw" -type f -name 'delay.dll' | head -1)"):$PATH"
    grep -q 'note: DELAYLOAD.plain=yes has no effect' build.log || { cat build.log >&2; echo "an explicit yes must be reported where delay loading does not exist" >&2; exit 1; }
    ! grep -q 'note: DELAYLOAD.delay' build.log || { cat build.log >&2; echo "a library's own default must not be reported" >&2; exit 1; }
    [ -z "$(find Fw -name '*.delayload')" ] || { echo "no .delayload expected on this output" >&2; exit 1; }
    "$(bin app)" 1 | tr -d '\r' | grep -q 'got 7'
    echo "delayload OK (no delay loading on this output)"
    exit 0
fi

# --- what the library recorded --------------------------------------------------------
f=$(find Fw -name 'libdelay.delayload' | head -1)
[ -n "$f" ] || { find Fw -name '*.delay*' >&2; echo "libdelay.delayload was not written" >&2; exit 1; }
set -- $(cat "$f")
[ "$1" = yes ] && [ "$2" = delay.dll ] || { cat "$f" >&2; echo "expected: yes delay.dll ..." >&2; exit 1; }

# --- the default: starts without the DLL, fails only at the first call -------------------
# app also links plain, which is not delayed: it needs plain.dll beside it, which is the point.
rm -rf "$top/one"; mkdir -p "$top/one"
cp "$(bin app)" "$top/one/"; cp "$(find Fw -name plain.dll | head -1)" "$top/one/"
out=$(cd "$top/one" && PATH=$ALONE_PATH "./$(prog_name app)" | tr -d '\r') || { echo "app must start without delay.dll, got [$out]" >&2; exit 1; }
[ "$out" = started ] || { echo "app without delay.dll: expected started, got [$out]" >&2; exit 1; }
rc=0; ( cd "$top/one" && PATH=$ALONE_PATH "./$(prog_name app)" 1 >/dev/null 2>&1 ) || rc=$?
[ $rc != 0 ] || { echo "the first call into a missing delay.dll must end the program" >&2; exit 1; }

# --- with the DLL there, the call works ------------------------------------------------------
cp "$(find Fw -name delay.dll | head -1)" "$top/one/"
out=$(cd "$top/one" && PATH=$ALONE_PATH "./$(prog_name app)" 1 | tr -d '\r')
printf '%s\n' "$out" | grep -q 'got 7' || { echo "app with delay.dll: got [$out]" >&2; exit 1; }

# --- the failure hook of docs/spec/29, defined by the program --------------------------------
mkdir -p Fw/hook.m/src
printf 'PROG=hook\nLIBS=delay\n.include <mk.prog.mk>\n' > Fw/hook.m/makefile
cat > Fw/hook.m/src/main.c <<'EOF'
#include <windows.h>
#include <delayimp.h>
#include <stdio.h>
#include <stdlib.h>
static FARPROC WINAPI on_failure(unsigned reason, PDelayLoadInfo info) {
    (void)reason;
    fprintf(stderr, "cannot load %s\n", info->szDll);
    exit(1);
}
#ifdef _MSC_VER
const
#endif
PfnDliHook __pfnDliFailureHook2 = on_failure;
int delay_fn(void);
int main(void) { return delay_fn() == 7 ? 0 : 2; }
EOF
bmake -C Fw/hook.m >hook.log 2>&1 || { cat hook.log >&2; echo "the failure hook of the spec does not build" >&2; exit 1; }
rm -rf "$top/hk"; mkdir -p "$top/hk"; cp "$(bin hook)" "$top/hk/"
rc=0; out=$(cd "$top/hk" && PATH=$ALONE_PATH "./$(prog_name hook)" 2>&1 | tr -d '\r') || rc=$?
printf '%s\n' "$out" | grep -q 'cannot load delay.dll' || { echo "the hook must name the DLL, got [$out]" >&2; exit 1; }
rm -rf Fw/hook.m

# --- the consumer overrides both ways --------------------------------------------------------
# over: delay is not delayed, plain is.
rm -rf "$top/two"; mkdir -p "$top/two"
cp "$(bin over)" "$top/two/"; cp "$(find Fw -name delay.dll | head -1)" "$top/two/"
out=$(cd "$top/two" && PATH=$ALONE_PATH "./$(prog_name over)" | tr -d '\r') || { echo "over must start without plain.dll (DELAYLOAD.plain=yes)" >&2; exit 1; }
[ "$out" = started ] || { echo "over without plain.dll: got [$out]" >&2; exit 1; }
rm -f "$top/two/delay.dll"; cp "$(find Fw -name plain.dll | head -1)" "$top/two/"
rc=0; ( cd "$top/two" && PATH=$ALONE_PATH "./$(prog_name over)" >/dev/null 2>&1 ) || rc=$?
[ $rc != 0 ] || { echo "over must not start without delay.dll (DELAYLOAD.delay=no)" >&2; exit 1; }

# --- a DLL exporting data is refused, by the library and by a consumer ----------------------
mkdir -p Fw/data.m/src
prog data data 'var' 'DELAYLOAD.var=yes' var_fn
rc=0; bmake -C Fw/data.m >data.log 2>&1 || rc=$?
[ $rc != 0 ] || { cat data.log >&2; echo "delay-loading a DLL that exports data must fail" >&2; exit 1; }
grep -Eqi 'exports data|due to import of data|LNK1194' data.log || { cat data.log >&2; echo "the failure must say why" >&2; exit 1; }
rm -rf Fw/data.m

# --- a misspelt library, a bad value, a static library ---------------------------------------
mkdir -p Fw/typo.m/src
prog typo typo 'plain' 'DELAYLOAD.plian=yes' plain_fn
rc=0; bmake -C Fw/typo.m >typo.log 2>&1 || rc=$?
[ $rc != 0 ] && grep -q 'DELAYLOAD.plian is set in typo.m, but plian is not in its LIBS=' typo.log || {
    cat typo.log >&2; echo "a DELAYLOAD.<lib> naming no library in LIBS= must be an error" >&2; exit 1; }
rc=0; bmake -C Fw/typo.m DELAYLOAD.plain=maybe >bad.log 2>&1 || rc=$?
[ $rc != 0 ] && grep -q 'DELAYLOAD.plain=maybe: expected yes or no' bad.log || { cat bad.log >&2; exit 1; }
rm -rf Fw/typo.m
rc=0; bmake -C Fw/libplain.m DELAYLOAD=maybe >bad.log 2>&1 || rc=$?
[ $rc != 0 ] && grep -q 'DELAYLOAD=maybe: expected yes or no' bad.log || { cat bad.log >&2; exit 1; }

mkdir -p Fw/libstat.m/src
printf 'LIB=stat\nLIB_SHARED=NO\nDELAYLOAD=yes\n.include <mk.lib.mk>\n' > Fw/libstat.m/makefile
echo 'int stat_fn(void) { return 1; }' > Fw/libstat.m/src/stat.c
rc=0; bmake -C Fw/libstat.m >stat.log 2>&1 || rc=$?
[ $rc != 0 ] && grep -q 'DELAYLOAD=yes on the static library stat' stat.log || { cat stat.log >&2; exit 1; }
printf 'LIB=stat\nLIB_SHARED=NO\nLIBS=plain\nDELAYLOAD.plain=yes\n.include <mk.lib.mk>\n' > Fw/libstat.m/makefile
rc=0; bmake -C Fw/libstat.m >stat.log 2>&1 || rc=$?
[ $rc != 0 ] && grep -q 'DELAYLOAD.plain=yes on the static library stat' stat.log || { cat stat.log >&2; exit 1; }
rm -rf Fw/libstat.m

# --- an imported DLL: its import library names it, the DLL itself is not staged ---------------
mkdir -p Fw/libext.m/src
printf 'LIB=ext\nLIB_SHARED=YES\nSHLIB_MAJOR=1\n.include <mk.lib.mk>\n' > Fw/libext.m/makefile
echo 'int ext_fn(void) { return 7; }' > Fw/libext.m/src/ext.c
bmake -C Fw/libext.m >ext.log 2>&1 || { cat ext.log >&2; exit 1; }
built=$(find Fw/libext.m -name ext.dll | head -1)
mkdir -p "$root/pkg/ext-1.0/lib" "$root/ws2/Fw/libext.m" "$root/ws2/Fw/use.m/src"
case "$kind" in
    msvc) cp "$(dirname "$built")/ext.lib" "$root/pkg/ext-1.0/lib/ext.lib" ;;
    *)    cp "$(dirname "$built")/ext.lib" "$root/pkg/ext-1.0/lib/libext.dll.a" ;;
esac
( cd "$root/pkg" && tar czf ext-1.0.tar.gz ext-1.0 )
hash=$( (sha256sum "$root/pkg/ext-1.0.tar.gz" 2>/dev/null || shasum -a 256 "$root/pkg/ext-1.0.tar.gz") | awk '{print $1}')
printf 'PARENT_WS=\n.include "mk.workspace.mk"\n' > "$root/ws2/makefile"
printf 'PREREQS=\n.include <mk.framework.mk>\n' > "$root/ws2/Fw/makefile"
printf 'SHA256 (ext-1.0.tar.gz) = %s\n' "$hash" > "$root/ws2/Fw/libext.m/distinfo"
cat > "$root/ws2/Fw/libext.m/makefile" <<EOF
LIB=ext
IMPORT=fetch-bin:ext
FETCH_URL=file://$root/pkg/ext-1.0.tar.gz
DELAYLOAD=yes
.include <mk.lib.mk>
EOF
printf 'PROG=use\nLIBS=ext\n.include <mk.prog.mk>\n' > "$root/ws2/Fw/use.m/makefile"
cat > "$root/ws2/Fw/use.m/src/main.c" <<'EOF'
#include <stdio.h>
int ext_fn(void);
int main(int argc, char **argv) {
    (void)argv;
    puts("started");
    fflush(stdout);
    if (argc > 1) printf("got %d\n", ext_fn());
    return 0;
}
EOF
rc=0; ( cd "$root/ws2" && bmake >"$root/ws2.log" 2>&1 ) || rc=$?
if [ "$kind" = gnu ]; then
    # GNU ld needs a delay-import library, and for an imported DLL there is no .def
    [ $rc != 0 ] && grep -q 'there is no libext.delay.a' "$root/ws2.log" || {
        cat "$root/ws2.log" >&2; echo "an imported DLL under GNU ld must be refused, saying why" >&2; exit 1; }
else
    [ $rc = 0 ] || { cat "$root/ws2.log" >&2; exit 1; }
    set -- $(cat "$(find "$root/ws2/Fw" -name libext.delayload | head -1)")
    [ "$1 $2 $3" = 'yes ext.dll ?' ] || { echo "imported: expected 'yes ext.dll ?', got '$*'" >&2; exit 1; }
    u=$(find "$root/ws2/Fw" -type f -name "$(prog_name use)" | head -1)
    rm -rf "$top/three"; mkdir -p "$top/three"; cp "$u" "$top/three/"
    out=$(cd "$top/three" && PATH=$ALONE_PATH "./$(prog_name use)" | tr -d '\r') || { echo "use must start without ext.dll" >&2; exit 1; }
    [ "$out" = started ] || { echo "use without ext.dll: got [$out]" >&2; exit 1; }
    cp "$built" "$top/three/"
    out=$(cd "$top/three" && PATH=$ALONE_PATH "./$(prog_name use)" 1 | tr -d '\r')
    printf '%s\n' "$out" | grep -q 'got 7' || { echo "use with ext.dll: got [$out]" >&2; exit 1; }
fi

echo "delayload OK ($kind)"
