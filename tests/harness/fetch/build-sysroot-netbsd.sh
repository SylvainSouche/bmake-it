#!/bin/sh
# build-sysroot-netbsd.sh <arch> <dest.tar> [version]
#
# Builds a NetBSD cross-compilation sysroot tarball from NetBSD's own
# release sets -- base.tar.xz (shared libs, /libexec/ld.elf_so) and
# comp.tar.xz (headers, static libs) -- the same "official, freely
# redistributable OS release artifacts" pattern as FreeBSD's base.txz,
# no NetBSD host or VM needed. Written as a tar and extracted inside a
# container/VM by consumers, never onto the macOS host filesystem directly
# (same reasoning as the Linux sysroot: avoids case-insensitive-filesystem
# corruption of headers that differ only by case).
set -eu
ARCH="${1:?usage: build-sysroot-netbsd.sh <arch> <dest.tar> [version]}"
DEST="${2:?usage: build-sysroot-netbsd.sh <arch> <dest.tar> [version]}"
VERSION="${3:-10.1}"

DEST_DIR=$(CDPATH= cd -- "$(dirname "$DEST")" && pwd)
DEST_NAME=$(basename "$DEST")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

BASE_URL="https://cdn.netbsd.org/pub/NetBSD/NetBSD-${VERSION}/${ARCH}/binary/sets"
echo "build-sysroot-netbsd.sh: downloading base.tar.xz + comp.tar.xz for $ARCH"
curl -fL -o "$tmp/base.tar.xz" "$BASE_URL/base.tar.xz"
curl -fL -o "$tmp/comp.tar.xz" "$BASE_URL/comp.tar.xz"

mkdir -p "$tmp/sysroot"
tar -xJf "$tmp/base.tar.xz" -C "$tmp/sysroot" ./usr/lib ./lib ./libexec
tar -xJf "$tmp/comp.tar.xz" -C "$tmp/sysroot" ./usr/include ./usr/lib

# usr/include/machine is normally created by the installer (sysinst),
# pointing at the arch-specific header subdir -- it's not shipped in the
# raw comp.tar.xz set itself. Found empirically: <sys/cdefs.h> includes
# <machine/cdefs.h>, which doesn't resolve without this.
if [ ! -e "$tmp/sysroot/usr/include/machine" ]; then
    MACHINE_DIR=""
    for _cand in aarch64 amd64 x86_64 arm; do
        [ -d "$tmp/sysroot/usr/include/$_cand" ] && { MACHINE_DIR="$_cand"; break; }
    done
    [ -n "$MACHINE_DIR" ] || { echo "build-sysroot-netbsd.sh: could not find an arch header dir to link usr/include/machine to" >&2; exit 1; }
    ln -s "$MACHINE_DIR" "$tmp/sysroot/usr/include/machine"
fi

cd "$tmp/sysroot" && tar --no-xattrs --no-acls --no-mac-metadata -cf "$DEST_DIR/$DEST_NAME" . 2>/dev/null \
    || tar -cf "$DEST_DIR/$DEST_NAME" .

echo "build-sysroot-netbsd.sh: wrote $DEST ($ARCH, $(du -h "$DEST_DIR/$DEST_NAME" | cut -f1))"
