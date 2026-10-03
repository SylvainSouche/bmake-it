#!/bin/sh
# import-link-transitivity-req: a THREE-level, purely-compiled static
# chain (app -> libb -> libcore) -- app.m declares only LIBS=b, deliberately
# never LIBS=core, proving libb's own transitive dependency on libcore follows
# it automatically. D2 applies to compiled libraries too, not just
# imported ones -- this is the case that proves it, distinct from the
# pkg-config/Libs.private case tests 47/48 already cover.
# The transitive library is named "core", not "c": on Linux -lc IS the C
# library, so a project library called "c" shadowed libc and every link
# failed with undefined printf/abort/__libc_start_main (macOS hid this --
# libSystem makes -lc a no-op).
set -eu
cd ws
bmake >build.log 2>&1

bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
out=$("$bin")
echo "$out" | grep -q "c-value"

# libb's own linkdeps file must record its dependency on libcore.
linkdeps=$(find . -name libb.linkdeps | head -1)
[ -n "$linkdeps" ]
grep -q -- "-lcore" "$linkdeps"

# app's own final link line must include -lcore even though app.m's
# makefile never says LIBS=core.
grep -q -- "-lb.*-lcore\|-lcore.*-lb" build.log

echo "link-transitivity-compiled OK"
