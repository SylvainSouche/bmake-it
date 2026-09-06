#!/bin/sh
# pack-cases.sh — turn tests/cases/<name>/ into tests/archives/<name>.tar.gz
#
# COPYFILE_DISABLE=1 is required on macOS: without it, BSD tar embeds a
# "._name" AppleDouble sidecar entry for every file carrying an extended
# attribute (e.g. a Chrome-download com.apple.quarantine flag). macOS's own
# tar hides/merges those transparently on extraction, but GNU tar on
# Linux/*BSD does not understand the format and materializes them as literal
# files -- which a naive `find src -name '*.c'`-style scan then picks up as
# real source, breaking the build on exactly the platforms this project
# targets. This was found by actually running the suite on Linux.
set -eu
export COPYFILE_DISABLE=1
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
TESTS_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
CASES="$TESTS_ROOT/cases"
ARCHIVES="$TESTS_ROOT/archives"
mkdir -p "$ARCHIVES"
for d in "$CASES"/*; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    [ -f "$d/run.sh" ] || {
        echo "skip $name (no run.sh)" >&2
        continue
    }
    out="$ARCHIVES/$name.tar.gz"
    tar --no-xattrs --no-acls --no-mac-metadata -czf "$out" -C "$CASES" "$name" 2>/dev/null \
        || tar -czf "$out" -C "$CASES" "$name"
    echo "packed $name -> $out"
done
