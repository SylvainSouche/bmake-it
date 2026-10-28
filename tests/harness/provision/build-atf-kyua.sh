#!/bin/sh
# build-atf-kyua.sh [prefix] -- build ATF, Lutok and Kyua from their release
# tarballs and install them under <prefix> (default /usr/local), for a host
# whose package manager has none: Cygwin (the Windows cells). Bmake It's
# `bmake test` runs atf-c/atf-c++/atf-sh test programs through Kyua.
#   needs: a C/C++ compiler, make, pkg-config, Lua 5.4 and SQLite 3
#   development files -- on Cygwin the packages lua and liblua-devel at
#   5.4.4 (test versions), libsqlite3-devel, sqlite3 (tests/README.md).
# The tarballs are kept in $BMK_CACHE/src (checked against the SHA-256s
# below, recorded when they were first fetched, 2026-10-28) and fetched only
# when missing.
set -eu
PREFIX=${1:-/usr/local}
SRC=${BMK_CACHE:-$HOME/.bmk-cache}/src
mkdir -p "$SRC"

sha256() { (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1") | awk '{print $1}'; }
fetch() {  # fetch <file> <url> <sha256>
    [ -f "$SRC/$1" ] || { echo "fetching $2"; curl -fsSL --retry 3 -o "$SRC/$1.part" "$2" && mv "$SRC/$1.part" "$SRC/$1"; }
    [ "$(sha256 "$SRC/$1")" = "$3" ] || { echo "build-atf-kyua.sh: $SRC/$1 does not match its SHA-256 ($3) -- delete it to fetch it again" >&2; exit 1; }
}
fetch atf-0.23.tar.gz    https://github.com/freebsd/atf/releases/download/atf-0.23/atf-0.23.tar.gz \
      a64e2427d021297f25b3f2e1798f8ec4dc3061ffb01a1cd3f66cc4cee486b10f
# Lutok 0.6.1 needs Lua 5.4 -- on Cygwin, the lua/liblua-devel 5.4.4 test
# packages (stable is 5.3). Kyua 0.14.1 needs Lutok >= 0.5; 0.5's release
# file builds badly (no build-aux files).
fetch lutok-0.6.1.tar.gz https://github.com/freebsd/lutok/releases/download/lutok-0.6.1/lutok-0.6.1.tar.gz \
      509c43c240ba47b8c452b45f3423a416fa91bdfc0341bfb806e0b78f65ce452d
fetch kyua-0.14.1.tar.gz https://github.com/freebsd/kyua/releases/download/kyua-0.14.1/kyua-0.14.1.tar.gz \
      3caf30a7e316f4f21c32e1c419ec80371fe113e3eed10ba1db9e6efc7ee15ecb

W=$(mktemp -d "${TMPDIR:-/tmp}/bmk-atfkyua.XXXXXX")
trap 'rm -rf "$W"' EXIT
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"; export PKG_CONFIG_PATH
PATH="$PREFIX/bin:$PATH"; export PATH
# Cygwin: configure compiles with a strict -std=c++14, under which newlib
# hides POSIX (mkstemp, usleep -- atf-check.cpp did not compile): ask for it.
case "$(uname -s)" in CYGWIN*) CPPFLAGS="-D_GNU_SOURCE ${CPPFLAGS:-}"; export CPPFLAGS ;; esac
for p in atf-0.23 lutok-0.6.1 kyua-0.14.1; do
    echo "=== $p"
    # each into its own directory: with a top directory or without one
    mkdir -p "$W/$p.d"; tar -xf "$SRC/$p.tar.gz" -C "$W/$p.d"
    if [ -d "$W/$p.d/$p" ]; then mv "$W/$p.d/$p" "$W/$p"; rmdir "$W/$p.d"; else mv "$W/$p.d" "$W/$p"; fi
    ( cd "$W/$p" \
      && ./configure --prefix="$PREFIX" --disable-dependency-tracking >"$W/$p.configure.log" 2>&1 \
      && make -j"$(nproc 2>/dev/null || echo 2)" >"$W/$p.make.log" 2>&1 \
      && make install >"$W/$p.install.log" 2>&1 ) || {
        echo "build-atf-kyua.sh: $p failed; the end of its last log:" >&2
        tail -30 "$(ls -t "$W"/$p.*.log | head -1)" >&2
        trap - EXIT; echo "(work tree kept: $W)" >&2; exit 1
    }
done
echo "installed under $PREFIX: $(command -v kyua) ($(kyua about version 2>&1 | head -1)), atf-c $(pkg-config --modversion atf-c)"
