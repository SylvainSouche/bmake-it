#!/bin/sh
# msvc-pkg-config-skips-host-packages-req. For MSVC-runtime output the build
# host's packages describe the wrong libraries: IMPORT=pkg:curl resolved to
# Cygwin's libcurl.pc and only failed at the link (OpenRider, 2026-11-02). It
# now stops before building, saying why; cases 47 and 55 show PKG_CONFIG_PATH
# still answers. Only for the MSVC runtime.
set -eu
. "$BMK_TESTLIB"
msvc_runtime || exit 77
ROOT=$(pwd)

# A pkg-config standing for the host's: it has "decoy" in its default
# directory, which an empty PKG_CONFIG_LIBDIR replaces.
mkdir -p fake
cat > fake/pkg-config <<'EOF'
#!/bin/sh
[ -z "${PKG_CONFIG_LIBDIR+x}" ] || exit 1
case "$1" in
    --exists) exit 0 ;;
    --modversion) echo 1.0 ;;
    --cflags) echo -I/usr/include/decoy ;;
    --libs) echo -ldecoy ;;
esac
EOF
chmod +x fake/pkg-config

mkdir -p ws/Fw/libdecoy.m/src ws/Fw/libreq.m/src ws/Fw/libprobe.m/src
printf 'PARENT_WS=\n.include "mk.workspace.mk"\n' > ws/makefile
printf 'PREREQS=\n.include <mk.framework.mk>\n' > ws/Fw/makefile
printf 'LIB=decoy\nIMPORT=pkg:decoy\nIMPORT_HEADERS=decoy\n.include <mk.lib.mk>\n' > ws/Fw/libdecoy.m/makefile
printf 'LIB=req\nREQUIRES=decoy\n.include <mk.lib.mk>\n' > ws/Fw/libreq.m/makefile
printf 'int req(void) { return 1; }\n' > ws/Fw/libreq.m/src/r.c

# --- IMPORT=pkg: stops, before building, saying why --------------------------------
rc=0; ( cd ws/Fw/libdecoy.m && PATH=$ROOT/fake:$PATH bmake >"$ROOT/import.log" 2>&1 ) || rc=$?
[ $rc != 0 ] || { cat import.log >&2; echo "the host's package must not resolve for MSVC output" >&2; exit 1; }
grep -q 'IMPORT=pkg:decoy: cannot resolve' import.log || { cat import.log >&2; exit 1; }
grep -q 'built for the MSVC runtime' import.log || { cat import.log >&2; exit 1; }
[ -z "$(find ws -name '*.obj' -o -name '*.o')" ]

# --- REQUIRES= likewise ---------------------------------------------------------------
rc=0; ( cd ws/Fw/libreq.m && PATH=$ROOT/fake:$PATH bmake >"$ROOT/requires.log" 2>&1 ) || rc=$?
[ $rc != 0 ] || { cat requires.log >&2; echo "REQUIRES= must not pass on the host's package" >&2; exit 1; }
grep -q 'REQUIRES=decoy' requires.log || { cat requires.log >&2; exit 1; }

# --- no probing of the host's prefixes --------------------------------------------------
if [ -f /usr/include/stdio.h ]; then
    printf 'LIB=probe\nIMPORT=pkg:no-such-import-xyz\nIMPORT_LIB=none\nIMPORT_HEADERS=stdio.h\n.include <mk.lib.mk>\n' > ws/Fw/libprobe.m/makefile
    rc=0; ( cd ws/Fw/libprobe.m && bmake >"$ROOT/probe.log" 2>&1 ) || rc=$?
    [ $rc != 0 ] || { cat probe.log >&2; echo "a Cygwin header must not satisfy an MSVC import" >&2; exit 1; }
    grep -q 'cannot resolve' probe.log || { cat probe.log >&2; exit 1; }
fi

# --- the real pkg-config: an empty PKG_CONFIG_LIBDIR removes the default directories
if command -v pkg-config >/dev/null 2>&1; then
    # (pkgconf always lists itself: two virtual packages)
    p=$(pkg-config --list-all 2>/dev/null | awk '$1 != "pkgconf" && $1 != "pkg-config" { print $1; exit }')
    if [ -n "$p" ]; then
        ! env PKG_CONFIG_LIBDIR= PKG_CONFIG_PATH= pkg-config --exists "$p" || {
            echo "PKG_CONFIG_LIBDIR= still found the host's $p" >&2; exit 1; }
    fi
fi

echo "msvc-skips-host-packages OK"
