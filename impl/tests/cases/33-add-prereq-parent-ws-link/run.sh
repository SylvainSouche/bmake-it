#!/bin/sh
# add-prereq must work when the framework it names only exists in a
# PARENT_WS workspace, not the current one -- same real build+link+run
# guarantee as REQ-headers-resolved-from-source-req, but established via
# `bmake add-prereq` instead of hand-writing PREREQS=.
set -eu

parent=$(CDPATH= cd parent && pwd)
sed "s|@@PARENT@@|$parent|" child/makefile.in > child/makefile

(cd parent/Lib && bmake)

cd child/App
bmake add-prereq FW=Lib
grep -q '^PREREQS= Lib$' makefile
cd ..

bmake

bin=$(find . -type f -name app | head -1)
[ -n "$bin" ] || { echo "app binary not found" >&2; exit 1; }

libdir=$(find "$parent/Lib/build" -type d -name lib | head -1)
[ -n "$libdir" ] || { echo "parent Lib lib dir not found" >&2; exit 1; }
out=$(DYLD_LIBRARY_PATH="$libdir" LD_LIBRARY_PATH="$libdir" "$bin")
[ "$out" = "parent-lib" ] || { echo "expected 'parent-lib', got '$out'" >&2; exit 1; }

echo "add-prereq-parent-ws-link OK ($out)"
