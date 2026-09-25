#!/bin/sh
# import-link-transitivity-req: a THREE-level, purely-compiled static
# chain (app -> libb -> libc) -- app.m declares only LIBS=b, deliberately
# never LIBS=c, proving libb's own transitive dependency on libc follows
# it automatically. D2 applies to compiled libraries too, not just
# imported ones -- this is the case that proves it, distinct from the
# pkg-config/Libs.private case tests 47/48 already cover.
set -eu
cd ws
bmake >build.log 2>&1

bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
out=$("$bin")
echo "$out" | grep -q "c-value"

# libb's own linkdeps file must record its dependency on libc.
linkdeps=$(find . -name libb.linkdeps | head -1)
[ -n "$linkdeps" ]
grep -q -- "-lc" "$linkdeps"

# app's own final link line must include -lc even though app.m's
# makefile never says LIBS=c.
grep -q -- "-lb.*-lc\|-lc.*-lb" build.log

echo "link-transitivity-compiled OK"
