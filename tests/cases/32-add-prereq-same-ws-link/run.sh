#!/bin/sh
# add-prereq's effect must be real, not just a text edit: wiring App's
# PREREQS= to a sibling framework (Lib) in the SAME workspace must make
# Lib's headers visible at compile time and its library resolvable at
# link/run time.
set -eu

cd ws/App
bmake add-prereq FW=Lib
grep -q '^PREREQS= Lib$' makefile
cd ../..

cd ws
bmake all

bin=$(find App -type f -name app | head -1)
[ -n "$bin" ] || { echo "app binary not found" >&2; exit 1; }

libdir=$(find Lib/build -type d -name lib | head -1)
[ -n "$libdir" ] || { echo "Lib build lib dir not found" >&2; exit 1; }

out=$(DYLD_LIBRARY_PATH="$libdir" LD_LIBRARY_PATH="$libdir" "$bin")
[ "$out" = "same-ws-lib" ] || { echo "expected 'same-ws-lib', got '$out'" >&2; exit 1; }

echo "add-prereq-same-ws-link OK ($out)"
