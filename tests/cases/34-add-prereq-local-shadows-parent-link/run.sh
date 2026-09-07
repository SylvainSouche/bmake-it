#!/bin/sh
# add-prereq wires PREREQS=Lib in the CHILD workspace, where Lib exists both
# locally and in a PARENT_WS workspace -- the local one must win for
# compiling, linking, and running, exactly as in prereq-local-shadows-parent,
# but the PREREQS= line itself is established via `bmake add-prereq`.
set -eu

parent=$(CDPATH= cd parent && pwd)
sed "s|@@PARENT@@|$parent|" child/makefile.in > child/makefile

(cd parent/Lib && bmake)
(cd child/Lib && bmake)

cd child/App
bmake add-prereq FW=Lib
grep -q '^PREREQS= Lib$' makefile
cd ..

bmake

bin=$(find App -type f -name app | head -1)
[ -n "$bin" ] || { echo "app binary not found" >&2; exit 1; }

localdir=$(find Lib/build -type d -name lib | head -1)
parentdir=$(find "$parent/Lib/build" -type d -name lib | head -1)
[ -n "$localdir" ] && [ -n "$parentdir" ] || { echo "build lib dirs not found" >&2; exit 1; }

# Local only present -- must work without the parent's build at all.
out=$(DYLD_LIBRARY_PATH="$localdir" LD_LIBRARY_PATH="$localdir" "$bin")
[ "$out" = "local-lib" ] || { echo "local-only run: expected 'local-lib', got '$out'" >&2; exit 1; }

# Both present, local first in the search path -- local must still win.
combined="$localdir:$parentdir"
out=$(DYLD_LIBRARY_PATH="$combined" LD_LIBRARY_PATH="$combined" "$bin")
[ "$out" = "local-lib" ] || { echo "both-present run: expected 'local-lib', got '$out'" >&2; exit 1; }

echo "add-prereq-local-shadows-parent-link OK ($out)"
