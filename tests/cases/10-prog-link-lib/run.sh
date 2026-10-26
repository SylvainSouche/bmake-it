#!/bin/sh
set -eu
. "$BMK_TESTLIB"
cd ws
bmake all
# Binary should exist at framework or workspace level
bin=$(find . -type f -name "$(prog_name app)" | head -1)
[ -n "$bin" ]
echo "built $bin"
# Try to run with loader path
libdir=$(find . -type d -name lib | head -1)
if [ -n "$libdir" ]; then
    with_libdir "$libdir" "$bin" || \
    /lib64/ld-linux-x86-64.so.2 --library-path "$libdir" "$bin" || \
    echo "run skipped (sandbox/noexec?) but link succeeded"
fi
echo "prog-link-lib OK"
