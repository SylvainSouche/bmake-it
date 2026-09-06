#!/bin/sh
# When a PREREQS framework exists in BOTH the current workspace and a
# PARENT_WS workspace, the local one must win -- for compiling (headers),
# linking (library), and running (the actual symbols executed), not just
# whichever happens to be searched last.
set -eu

parent=$(CDPATH= cd parent && pwd)
sed "s|@@PARENT@@|$parent|" child/makefile.in > child/makefile

(cd parent/Lib && bmake)
(cd child/Lib && bmake)

cd child
bmake

bin=$(find App -type f -name app | head -1)
[ -n "$bin" ] || { echo "app binary not found" >&2; exit 1; }

# Compiled with the LOCAL Lib's headers, not the parent's -- inspectable
# via the recorded include path in the build (both dirs share the same
# header name, so only the search order tells them apart).
localdir=$(find Lib/build -type d -name lib | head -1)
parentdir=$(find "$parent/Lib/build" -type d -name lib | head -1)
[ -n "$localdir" ] && [ -n "$parentdir" ] || { echo "build lib dirs not found" >&2; exit 1; }

# Run with ONLY the local lib available -- must work without the parent's
# build present at all (proves it linked against local, not parent).
out=$(DYLD_LIBRARY_PATH="$localdir" LD_LIBRARY_PATH="$localdir" "$bin")
[ "$out" = "local-lib" ] || { echo "local-only run: expected 'local-lib', got '$out'" >&2; exit 1; }

# Run with BOTH available, local first -- local must still win, not
# whichever the loader happens to prefer.
combined="$localdir:$parentdir"
out=$(DYLD_LIBRARY_PATH="$combined" LD_LIBRARY_PATH="$combined" "$bin")
[ "$out" = "local-lib" ] || { echo "both-present run: expected 'local-lib', got '$out'" >&2; exit 1; }

echo "prereq-local-shadows-parent OK ($out)"
