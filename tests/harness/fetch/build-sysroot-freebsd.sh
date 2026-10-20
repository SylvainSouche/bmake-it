#!/bin/sh
# build-sysroot-freebsd.sh <dest.tar> [arch] [version]
#
# A FreeBSD cross-compilation sysroot, from the official release's base.txz
# (fully open, freely redistributable -- unlike the macOS SDK), written as a
# tar like every other sysroot. For arm64 the sysroot of a RUNNING guest is
# better (vm.sh sysroot freebsd_arm64: it matches the OS the binary runs on);
# this is for targets with no guest here (amd64 on an arm64 host).
#   arch     amd64 (default) | arm64
#   version  15.1-RELEASE (default)
set -eu
DEST="${1:?usage: build-sysroot-freebsd.sh <dest.tar> [amd64|arm64] [version]}"
ARCH="${2:-amd64}"
VERSION="${3:-15.1-RELEASE}"
case "$ARCH" in
    amd64) DIR="amd64" ;;
    arm64) DIR="arm64/aarch64" ;;
    *) echo "build-sysroot-freebsd.sh: unknown arch '$ARCH'" >&2; exit 2 ;;
esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
URL="https://download.freebsd.org/releases/${DIR}/${VERSION}/base.txz"
echo "build-sysroot-freebsd.sh: downloading $URL"
curl -fL -o "$tmp/base.txz" "$URL"
mkdir -p "$tmp/sysroot"
tar -xJf "$tmp/base.txz" -C "$tmp/sysroot" ./usr/include ./usr/lib ./lib
rm -rf "$tmp/sysroot/usr/lib/debug" "$tmp/sysroot/usr/lib32"
mkdir -p "$(dirname "$DEST")"
(cd "$tmp/sysroot" && tar --no-xattrs --no-acls --no-mac-metadata -cf "$tmp/out.tar" . 2>/dev/null \
    || tar -cf "$tmp/out.tar" .)
mv "$tmp/out.tar" "$DEST"
echo "build-sysroot-freebsd.sh: wrote $DEST ($ARCH $VERSION, $(du -h "$DEST" | cut -f1))"
