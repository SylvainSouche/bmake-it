#!/bin/sh
# fetch-system-downloader-req: IMPORT=fetch: downloads with curl, else wget, else
# the system's own downloader (fetch on FreeBSD/DragonFly, ftp on NetBSD/OpenBSD).
# A guest that has curl -- our provisioned BSD guests do, as a dependency of
# cmake -- never reaches that last step, so this case REMOVES curl and wget from
# the build's PATH (a private directory of links to everything else on the real
# PATH). file:// URLs are copied by the product itself: NetBSD's ftp(1) cannot fetch
# one, so before this a NetBSD machine without curl could not use a local mirror.
set -eu
ROOT=$(pwd)

sha256() { (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1" 2>/dev/null || sha256 -q "$1" 2>/dev/null) | awk '{print $1}'; }

# --- the fake upstream distfile -------------------------------------------
mkdir -p "$ROOT/fake/upstream/fakelib-1.0" "$ROOT/fake/dist"
printf '#ifndef FAKELIB_GREET_H\n#define FAKELIB_GREET_H\nconst char *fakelib_greet(void);\n#endif\n' > "$ROOT/fake/upstream/fakelib-1.0/greet.h"
printf '#include "greet.h"\nconst char *fakelib_greet(void) { return "hello from fakelib"; }\n' > "$ROOT/fake/upstream/fakelib-1.0/greet.c"
( cd "$ROOT/fake/upstream" && tar czf "$ROOT/fake/dist/fakelib-1.0.tar.gz" fakelib-1.0 )
HASH=$(sha256 "$ROOT/fake/dist/fakelib-1.0.tar.gz")
mkdir -p "$ROOT/ws/Fw/libfakelib.m"
echo "SHA256 (fakelib-1.0.tar.gz) = $HASH" > "$ROOT/ws/Fw/libfakelib.m/distinfo"
cat > "$ROOT/ws/Fw/libfakelib.m/makefile" <<MEOF
LIB=fakelib
IMPORT=fetch:fakelib
FETCH_URL=file://$ROOT/fake/dist/fakelib-1.0.tar.gz
SRCS=greet.c
IMPORT_HEADERS=greet.h
.include <mk.lib.mk>
MEOF

# --- a PATH without curl and wget -----------------------------------------
mkdir -p "$ROOT/nopath"
oldifs=$IFS; IFS=:
for d in $PATH; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
        n=${f##*/}
        case "$n" in curl|wget|'*') continue ;; esac
        [ -e "$ROOT/nopath/$n" ] || ln -s "$f" "$ROOT/nopath/$n" 2>/dev/null || true
    done
done
IFS=$oldifs
PATH="$ROOT/nopath"; export PATH
if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    echo "setup: curl or wget is still on PATH" >&2; exit 1
fi

cd ws
# 1. a file:// distfile needs no downloader on ANY host (NetBSD's ftp(1) cannot fetch
#    one at all -- "ftp_strdup: called with NULL argument" -- so it is copied)
bmake >build1.log 2>&1 || { cat build1.log >&2; echo "file:// fetch must not need curl, wget or a system downloader" >&2; exit 1; }
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
"$bin" | grep -q "hello from fakelib"

# 2. a file:// URL that does not exist fails cleanly, naming the failure
rm -rf Fw/libfakelib.m/distfiles Fw/libfakelib.m/work Fw/libfakelib.m/build
sed -i.bak "s|FETCH_URL=.*|FETCH_URL=file://$ROOT/fake/dist/missing-1.0.tar.gz|" Fw/libfakelib.m/makefile
echo "SHA256 (missing-1.0.tar.gz) = $HASH" >> Fw/libfakelib.m/distinfo
if bmake >build2.log 2>&1; then echo "a missing file:// distfile must fail" >&2; exit 1; fi
grep -q "could not fetch any FETCH_URL" build2.log \
    || { cat build2.log >&2; echo "the failure should say no FETCH_URL could be fetched" >&2; exit 1; }
echo "fetch-without-curl-or-wget OK"
