#!/bin/sh
# build-sysroot-freebsd.sh <dest-dir>
#
# Extracts a FreeBSD cross-compilation sysroot from the official base.txz
# (fully open, freely redistributable -- unlike the macOS SDK). Unlike the
# Linux sysroot builder, this is written directly to a host directory
# (not a tar extracted later) since FreeBSD headers/libs don't collide on
# a case-insensitive filesystem the way Linux kernel headers do.
set -eu
DEST="${1:?usage: build-sysroot-freebsd.sh <dest-dir>}"
ARCH="${2:-amd64}"
VERSION="${3:-14.3-RELEASE}"

mkdir -p "$DEST"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

URL="https://download.freebsd.org/ftp/releases/${ARCH}/${ARCH}/${VERSION}/base.txz"
echo "build-sysroot-freebsd.sh: downloading $URL"
curl -fL -o "$tmp/base.txz" "$URL"

tar -xJf "$tmp/base.txz" -C "$DEST" ./usr/include ./usr/lib ./lib
echo "build-sysroot-freebsd.sh: wrote $DEST ($(du -sh "$DEST" | cut -f1))"
