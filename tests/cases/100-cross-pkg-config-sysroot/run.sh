#!/bin/sh
# cross-import-from-sysroot-req, cross-requires-from-sysroot-req,
# cross-test-local-emulated-req: a cross build (another OS, or another
# architecture of the same OS) resolves IMPORT=pkg: and REQUIRES= in the
# target's .pc directories of BMK_<OS>_SYSROOT -- Linux's multiarch one,
# FreeBSD's usr/local/libdata, NetBSD's usr/pkg/lib -- never the host's (a
# decoy zed.pc on PKG_CONFIG_PATH must not leak in), with the resolved
# libdir and includedir in the sysroot; a native build still reads the
# host's; a package missing from the sysroot names it; TEST_RUNNER=local
# exports QEMU_LD_PREFIX for a foreign Linux target only. A fake sysroot of
# .pc files: nothing is compiled (bmake -n and -V), so any host runs it.
set -eu
command -v pkg-config >/dev/null 2>&1 || exit 77
# Every build here names its own target (and TOOLCHAIN=llvm): an ABI= the
# suite forces (ABI=mingw on a Windows host) does not exist for them.
bmake() { command bmake ABI= "$@"; }
ROOT=$(pwd)
SYS=$ROOT/sysroot

# The host's architecture, as Bmake It names it, and another one: every
# target below is foreign by its architecture, whatever the host's OS.
case $(uname -m) in
x86_64 | amd64) FOREIGN=arm64 MULTIARCH=aarch64-linux-gnu ;;
*) FOREIGN=amd64 MULTIARCH=x86_64-linux-gnu ;;
esac

pc() { # pc <dir> <version>
    mkdir -p "$1"
    cat > "$1/zed.pc" <<PC
prefix=/usr
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: zed
Description: fake package (no system package used)
Version: $2
Cflags: -I\${includedir}/zed
Libs: -L\${libdir} -lzed
PC
}
pc "$SYS/linux/usr/lib/$MULTIARCH/pkgconfig" 1.1
pc "$SYS/linux/usr/lib/riscv64-linux-gnu/pkgconfig" 1.4
pc "$SYS/freebsd/usr/local/libdata/pkgconfig" 2.2
pc "$SYS/netbsd/usr/pkg/lib/pkgconfig" 3.3
mkdir -p "$SYS/empty/usr/lib"
# The host's own OS on the other architecture: cross too (comparing the OS
# alone took it for native and read the host's .pc files).
case $(uname -s) in
Darwin) HOSTOS=macos ;;
Linux) HOSTOS=linux ;;
FreeBSD) HOSTOS=freebsd ;;
NetBSD) HOSTOS=netbsd ;;
*) HOSTOS= ;;
esac
for d in usr/lib/$MULTIARCH/pkgconfig usr/local/libdata/pkgconfig usr/pkg/lib/pkgconfig usr/lib/pkgconfig; do
    pc "$SYS/same-os/$d" 5.5
done
echo '{"Version":"14.0"}' > "$SYS/same-os/SDKSettings.json"
pc "$ROOT/host/pkgconfig" 9.9
export PKG_CONFIG_PATH="$ROOT/host/pkgconfig"

# resolve <args>: the version libzed.m resolves to, and its cache file.
resolve() {
    (cd "$ROOT/ws/Fw/libzed.m" && rm -rf build && bmake -n TOOLCHAIN=llvm "$@" all >"$ROOT/resolve.log" 2>&1) || return 1
    sed -n 's/^_IC_VERSION = //p' "$ROOT"/ws/Fw/libzed.m/build/*/.import-resolve-cache.mk
}
expect() { # expect <version> <sysroot or -> <args>
    want=$1 sys=$2; shift 2
    got=$(resolve "$@") || { cat "$ROOT/resolve.log" >&2; echo "FAIL: $* did not resolve" >&2; exit 1; }
    [ "$got" = "$want" ] || { echo "FAIL: $* resolved zed $got, expected $want" >&2; exit 1; }
    [ "$sys" = - ] && return 0
    cache=$(ls "$ROOT"/ws/Fw/libzed.m/build/*/.import-resolve-cache.mk)
    grep -q "^_IC_LIBDIR = $sys/usr/lib\$" "$cache" || { cat "$cache" >&2; echo "FAIL: libdir outside $sys" >&2; exit 1; }
    grep -q "^_IC_INCDIR = $sys/usr/include\$" "$cache" || { cat "$cache" >&2; echo "FAIL: includedir outside $sys" >&2; exit 1; }
    grep -q "^_IC_PCFILE = $sys/" "$cache" || { cat "$cache" >&2; echo "FAIL: .pc file outside $sys" >&2; exit 1; }
}

expect 9.9 - # native: the host's .pc files, unchanged
expect 1.1 "$SYS/linux" TARGET=linux TARGET_ARCH=$FOREIGN BMK_LINUX_SYSROOT="$SYS/linux"
expect 1.4 "$SYS/linux" TARGET=linux TARGET_ARCH=riscv64 BMK_LINUX_SYSROOT="$SYS/linux"
expect 2.2 "$SYS/freebsd" TARGET=freebsd TARGET_ARCH=$FOREIGN BMK_FREEBSD_SYSROOT="$SYS/freebsd"
expect 3.3 "$SYS/netbsd" TARGET=netbsd TARGET_ARCH=$FOREIGN BMK_NETBSD_SYSROOT="$SYS/netbsd"
if [ -n "$HOSTOS" ]; then
    HOSTOS_VAR=BMK_$(echo $HOSTOS | tr a-z A-Z)_SYSROOT
    expect 5.5 "$SYS/same-os" TARGET=$HOSTOS TARGET_ARCH=$FOREIGN $HOSTOS_VAR="$SYS/same-os"
fi

# The decoy never leaks: a sysroot without zed does not resolve at all.
if got=$(resolve TARGET=linux TARGET_ARCH=$FOREIGN BMK_LINUX_SYSROOT="$SYS/empty"); then
    echo "FAIL: zed resolved from a sysroot without it (got '$got', the host decoy is 9.9)" >&2; exit 1
fi

# REQUIRES=: zed and a host tool (sh, on PATH) are found in a cross build;
# a missing package names the sysroot.
cd "$ROOT/ws/Fw/needs.m"
bmake -n TOOLCHAIN=llvm TARGET=linux TARGET_ARCH=$FOREIGN BMK_LINUX_SYSROOT="$SYS/linux" all >req.log 2>&1 || { cat req.log >&2; echo "FAIL: REQUIRES=zed sh in a cross build" >&2; exit 1; }
if bmake -n TOOLCHAIN=llvm TARGET=linux TARGET_ARCH=$FOREIGN BMK_LINUX_SYSROOT="$SYS/empty" all >req.log 2>&1; then
    echo "FAIL: REQUIRES=zed passed with zed only on the host" >&2; exit 1
fi
grep -q "REQUIRES=zed: .*the target's sysroot $SYS/empty" req.log || { cat req.log >&2; echo "FAIL: the error does not name the sysroot" >&2; exit 1; }

# TEST_RUNNER=local: QEMU_LD_PREFIX for a foreign Linux target, the caller's
# own kept; nothing for a native build or another OS.
cd "$ROOT/ws/Fw/tool.m"
env_of() { bmake -V '${_XTEST_LOCAL_ENV}' TOOLCHAIN=llvm TEST_RUNNER=local "$@"; }
[ "$(env_of TARGET=linux TARGET_ARCH=$FOREIGN BMK_LINUX_SYSROOT=/sr)" = 'export QEMU_LD_PREFIX="/sr";' ] || { echo "FAIL: no QEMU_LD_PREFIX for linux-$FOREIGN" >&2; exit 1; }
[ "$(env_of TARGET=linux TARGET_ARCH=$FOREIGN BMK_LINUX_SYSROOT=/sr QEMU_LD_PREFIX=/mine)" = 'export QEMU_LD_PREFIX="/mine";' ] || { echo "FAIL: the caller's QEMU_LD_PREFIX was replaced" >&2; exit 1; }
[ -z "$(env_of)" ] || { echo "FAIL: QEMU_LD_PREFIX for a native build" >&2; exit 1; }
[ -z "$(env_of TARGET=freebsd TARGET_ARCH=$FOREIGN BMK_FREEBSD_SYSROOT=/sr)" ] || { echo "FAIL: QEMU_LD_PREFIX for freebsd" >&2; exit 1; }

echo "cross-pkg-config-sysroot OK"
