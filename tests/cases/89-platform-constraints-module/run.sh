#!/bin/sh
# platform-list-grammar-req, platform-constraint-evaluation-req,
# platform-list-validity-req, constraint-reason-message-req: PLATFORMS= and
# TOOLCHAINS= on a module. The host's own OS/arch/toolchain are asked from
# bmake so the same matrix runs on every host.
set -eu
cd ws
OS=$(bmake -V '${TARGET}'); ARCH=$(bmake -V '${TARGET_ARCH}'); TC=$(bmake -V '${TOOLCHAIN}')
KEY="${OS}_${ARCH}"
if [ "$OS" = freebsd ]; then OTHER=netbsd; else OTHER=freebsd; fi
cd Fw/m.m

mkmod() { printf 'PROG=m\n%s\n.include <mk.prog.mk>\n' "$1" > makefile; }
go() { mkmod "$1"; bmake clean >/dev/null 2>&1 || true; rc=0; bmake all >out.log 2>&1 || rc=$?; }
fail() { echo "FAILED [$1]: $2" >&2; sed 's/^/    /' out.log | tail -6 >&2; exit 1; }
built()   { go "$1"; [ $rc = 0 ] && grep -q '===> built m' out.log || fail "$1" "expected a normal build"; }
skipped() { go "$1"; [ $rc = 0 ] && grep -q "===> module m.m skipped: $2" out.log && ! grep -q '===> built m' out.log || fail "$1" "expected a skip matching '$2'"; }
errored() { go "$1"; [ $rc != 0 ] && grep -q -e "$2" out.log || fail "$1" "expected an error matching '$2'"; }

# --- platforms: grammar and evaluation ------------------------------------
built   ""
built   "PLATFORMS=$OS"
skipped "PLATFORMS=$OTHER" "PLATFORMS=$OTHER does not include $KEY"
skipped "PLATFORMS=-$OS" "PLATFORMS excludes $KEY (-$OS)"
built   "PLATFORMS=-$OTHER"
built   "PLATFORMS=$KEY"
skipped "PLATFORMS=${OS}_nonarch" "PLATFORMS=${OS}_nonarch does not include $KEY"
skipped "PLATFORMS=$OS -$KEY" "PLATFORMS excludes $KEY (-$KEY)"
errored "PLATFORMS=!-$OS" "excludes $KEY (!-$OS)"
errored "PLATFORMS=!$OTHER" "does not include $KEY"
built   "PLATFORMS=!$OS"
built   "PLATFORMS=$OS macos linux -${OS}_nonarch"

# --- validity: positive and negative only mix when the negative narrows ----
errored "PLATFORMS=$OS -$OTHER" "is not a subset of any positive entry"
errored "PLATFORMS=$OS -$OS" "is not a subset of any positive entry"
errored "PLATFORMS=$KEY -$OS" "is not a subset of any positive entry"

# --- toolchains ------------------------------------------------------------
built   "TOOLCHAINS=$TC"
skipped "TOOLCHAINS=-$TC" "TOOLCHAINS excludes $TC (-$TC)"
errored "TOOLCHAINS=!-$TC" "excludes $TC (!-$TC)"
errored "TOOLCHAINS=$TC -zzz" "cannot be mixed"
skipped "TOOLCHAINS=zzz" "TOOLCHAINS=zzz does not include $TC"

# --- both axes: an error beats a skip ------------------------------------------
errored "PLATFORMS=-$OS
TOOLCHAINS=!-$TC" "TOOLCHAINS excludes $TC"

# --- REASON.<entry> ------------------------------------------------------------
skipped "PLATFORMS=-$OS
REASON.$OS=needs a thing" "PLATFORMS excludes $KEY (-$OS) -- needs a thing"
errored "TOOLCHAINS=!-$TC
REASON.$TC=miscompiles the kernels" "-- miscompiles the kernels"

# --- unknown names only warn -----------------------------------------------------
built   "PLATFORMS=-bogusos"
grep -q "unknown platform 'bogusos'" out.log || fail "-bogusos" "expected a warning"

# --- a -V query and clean must work even under an error list ----------------
mkmod "PLATFORMS=!-$OS"
bmake -V PROG >/dev/null 2>&1 || fail "!-$OS" "-V PROG must not fail"
bmake clean >/dev/null 2>&1 || fail "!-$OS" "clean must not fail"

# --- an excluded module never resolves imports or REQUIRES ------------------------
cd ../l.m
mklib() { printf 'LIB=l\nIMPORT=pkg:does-not-exist-zzz\nREQUIRES=no-such-tool-zzz\n%s\n.include <mk.lib.mk>\n' "$1" > makefile; }
mklib ""
rc=0; bmake all >out.log 2>&1 || rc=$?
[ $rc != 0 ] || fail "lib control" "without PLATFORMS= the unresolvable import must fail"
mklib "PLATFORMS=-$OS"
bmake clean >/dev/null 2>&1 || true
rc=0; bmake all >out.log 2>&1 || rc=$?
[ $rc = 0 ] && grep -q "module l.m skipped" out.log || fail "lib excluded" "an excluded module must not resolve its import"

echo "platform-constraints-module OK"
