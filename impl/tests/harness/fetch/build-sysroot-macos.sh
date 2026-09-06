#!/bin/sh
# build-sysroot-macos.sh <dest.tar>
#
# Packages a macOS cross-compilation sysroot from the LOCAL Xcode install's
# SDK (xcrun --show-sdk-path) into a tarball, consumed the same way the
# Linux sysroot is -- extracted inside a container/VM, never onto the
# macOS host filesystem directly (that would just be copying it to itself
# uselessly, but keeping the tar format keeps every cross job uniform).
#
# Apple's SDK license covers building on/for Apple platforms; this is your
# own extracted copy for your own cross-compilation use -- don't
# redistribute it.
set -eu
DEST="${1:?usage: build-sysroot-macos.sh <dest.tar>}"

SDK_PATH=$(xcrun --show-sdk-path 2>/dev/null)
[ -n "$SDK_PATH" ] || { echo "build-sysroot-macos.sh: xcrun --show-sdk-path failed -- is Xcode installed?" >&2; exit 2; }

DEST_DIR=$(CDPATH= cd -- "$(dirname "$DEST")" && pwd)
DEST_NAME=$(basename "$DEST")
SDK_NAME=$(basename "$SDK_PATH")

# xcrun already resolves to Apple's canonical, version-independent name
# (MacOSX.sdk), not a version-suffixed one -- archive it under that exact
# name so every consumer of this tarball can extract to a predictable path.
tar -C "$(dirname "$SDK_PATH")" -cf "$DEST_DIR/$DEST_NAME" "$SDK_NAME"
echo "build-sysroot-macos.sh: wrote $DEST from $SDK_PATH ($(du -h "$DEST" | cut -f1))"
