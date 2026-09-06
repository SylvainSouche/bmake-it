#!/bin/sh
# fetch-image.sh <platform-id> <dest>
#
# Downloads (and decompresses, if needed) a VM disk image for one of the
# vm-kind platforms in platforms.mk. Idempotent by virtue of being called
# from a Makefile file-target -- re-running only happens if $dest is
# missing/stale.
set -eu
PLATFORM="${1:?usage: fetch-image.sh <platform-id> <dest>}"
DEST="${2:?usage: fetch-image.sh <platform-id> <dest>}"

case "$PLATFORM" in
    freebsd_amd64)
        URL="https://download.freebsd.org/releases/VM-IMAGES/14.3-RELEASE/amd64/Latest/FreeBSD-14.3-RELEASE-amd64.qcow2.xz"
        DECOMPRESS=xz
        ;;
    linux_amd64_vm)
        URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
        DECOMPRESS=none
        ;;
    netbsd_amd64)
        URL="https://cdn.netbsd.org/pub/NetBSD/images/10.1/NetBSD-10.1-amd64-live.img.gz"
        DECOMPRESS=gzip
        ;;
    netbsd_arm64)
        URL="https://cdn.netbsd.org/pub/NetBSD/NetBSD-10.1/evbarm-aarch64/binary/gzimg/arm64.img.gz"
        DECOMPRESS=gzip
        ;;
    *)
        echo "fetch-image.sh: unknown platform '$PLATFORM' (want freebsd_amd64, linux_amd64_vm, netbsd_amd64, or netbsd_arm64)" >&2
        exit 2
        ;;
esac

DEST_DIR=$(CDPATH= cd -- "$(dirname "$DEST")" && pwd)
tmp="$DEST_DIR/.$(basename "$DEST").download"

echo "fetch-image.sh: downloading $URL"
curl -fL -o "$tmp" "$URL"

case "$DECOMPRESS" in
    xz)   xz -dc "$tmp" > "$DEST"; rm -f "$tmp" ;;
    gzip) gzip -dc "$tmp" > "$DEST"; rm -f "$tmp" ;;
    none) mv "$tmp" "$DEST" ;;
esac

echo "fetch-image.sh: wrote $DEST ($(du -h "$DEST" | cut -f1))"
