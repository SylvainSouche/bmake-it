#!/bin/sh
# build-sysroot-linux.sh <amd64|arm64> <dest.tar>
#
# Builds a Linux cross-compilation sysroot tarball for the given arch, using
# a Docker container as the source of real glibc headers/libs/gcc-runtime.
# Written as a tar and never extracted onto the host filesystem -- macOS's
# default case-insensitive filesystem corrupts Linux kernel headers that
# differ only by case (e.g. xt_CONNMARK.h vs xt_connmark.h), found
# empirically. Consumers extract it inside a container/VM instead.
#
# Three things this needs beyond `apt-get install libc6-dev`, each found by
# a real link failure during this project's cross-compilation work:
#   1. usr/lib/gcc/<multiarch>/<ver>/ -- crtbeginS.o/crtendS.o/-lgcc live
#      here, not under usr/lib/<multiarch>.
#   2. The top-level ld-linux-*.so.* dynamic-linker symlink must be copied
#      DEREFERENCED (a real file, not a symlink) -- its target is an
#      absolute path that only resolves inside the container building this
#      sysroot, not under --sysroot as clang/lld see it.
#   3. Its location differs by arch: amd64 keeps it at /lib64/, arm64 keeps
#      it directly under /lib/ (merged-/usr distros still physically store
#      the target under /usr/lib).
set -eu

ARCH="${1:?usage: build-sysroot-linux.sh <amd64|arm64> <dest.tar>}"
DEST="${2:?usage: build-sysroot-linux.sh <amd64|arm64> <dest.tar>}"

case "$ARCH" in
    amd64) PLATFORM=linux/amd64 ;;
    arm64) PLATFORM=linux/arm64 ;;
    *) echo "build-sysroot-linux.sh: unknown arch '$ARCH' (want amd64 or arm64)" >&2; exit 2 ;;
esac

DEST_DIR=$(CDPATH= cd -- "$(dirname "$DEST")" && pwd)
DEST_NAME=$(basename "$DEST")

docker run --rm --platform "$PLATFORM" -v "$DEST_DIR:/out" debian:bookworm-slim sh -c '
set -e
apt-get update -qq >/dev/null && apt-get install -y -qq libc6-dev gcc >/dev/null 2>&1
mkdir -p /sysroot/usr/include /sysroot/usr/lib /sysroot/lib /sysroot/lib64 /sysroot/usr/lib/gcc
cp -a /usr/include/. /sysroot/usr/include/
MULTIARCH=$(gcc -dumpmachine)
mkdir -p "/sysroot/usr/lib/$MULTIARCH" "/sysroot/lib/$MULTIARCH"
cp -a "/usr/lib/$MULTIARCH/." "/sysroot/usr/lib/$MULTIARCH/" 2>/dev/null || true
cp -a "/lib/$MULTIARCH/." "/sysroot/lib/$MULTIARCH/" 2>/dev/null || true
cp -a /usr/lib/gcc/. /sysroot/usr/lib/gcc/
# Dynamic-linker interpreter symlink: dereferenced, arch-dependent location.
# Search /usr/lib (the real directory), not /lib -- on merged-/usr distros
# /lib is ITSELF a symlink to usr/lib, and find silently returns nothing
# when the search root is a symlink like that (empirically confirmed: same
# `find -mindepth 1 -maxdepth 1 -type l` query finds the file via /usr/lib
# but not via /lib, even though they are the same directory).
if [ -d /lib64 ]; then cp -aL /lib64/. /sysroot/lib64/ 2>/dev/null || true; fi
find /usr/lib -mindepth 1 -maxdepth 1 -name "ld-linux*" -type l 2>/dev/null | while read -r f; do
    cp -aL "$f" /sysroot/lib/
done
cd /sysroot && tar --no-xattrs --no-acls --no-mac-metadata -cf "/out/'"$DEST_NAME"'" . 2>/dev/null \
    || tar -cf "/out/'"$DEST_NAME"'" .
'

echo "build-sysroot-linux.sh: wrote $DEST ($ARCH, $(du -h "$DEST" | cut -f1))"
