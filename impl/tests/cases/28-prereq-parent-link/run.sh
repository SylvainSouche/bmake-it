#!/bin/sh
# A framework's PREREQS can name a framework that only exists in a PARENT_WS
# workspace, not the current one (REQ-headers-resolved-from-source-req):
# header AND library must resolve there, and the built program must
# actually run using it.
set -eu

parent=$(CDPATH= cd parent && pwd)
sed "s|@@PARENT@@|$parent|" child/makefile.in > child/makefile

# Parent's Lib must be built first -- prereq access is dynamic search
# against real build output, not a copy step (DEC-prereq-access-dynamic-only).
(cd parent/Lib && bmake)

cd child
bmake

bin=$(find . -type f -name app | head -1)
[ -n "$bin" ] || { echo "app binary not found" >&2; exit 1; }

libdir=$(find "$parent/Lib/build" -type d -name lib | head -1)
[ -n "$libdir" ] || { echo "parent Lib lib dir not found" >&2; exit 1; }
out=$(DYLD_LIBRARY_PATH="$libdir" LD_LIBRARY_PATH="$libdir" "$bin")
[ "$out" = "parent-lib" ] || { echo "expected 'parent-lib', got '$out'" >&2; exit 1; }

echo "prereq-parent-link OK ($out)"
