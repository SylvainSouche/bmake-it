#!/bin/sh
# inputs-hash-rebuild-req: bmake has no notion that a .o was compiled with
# different flags than requested -- `bmake` then `bmake SANITIZE=address`
# must actually recompile every object (not silently reuse stale, non-
# instrumented ones) and the resulting binary must genuinely crash under
# ASan on a real heap-buffer-overflow, not just accept the flag silently.
set -eu
cd ws/Fw

bmake >build1.log 2>&1
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]

# Plain build: the bug is real but silent without instrumentation.
"$bin" >run1.log 2>&1
grep -q "no crash" run1.log

# SANITIZE=address: objects must actually recompile with the flag, not
# just relink stale ones.
bmake SANITIZE=address >build2.log 2>&1
grep -q -- "-c .*buf\.c" build2.log
grep -q -- "-fsanitize=address" build2.log

# Now the same binary must genuinely crash under ASan.
if "$bin" >run2.log 2>&1; then
    echo "expected an ASan crash on the real heap-buffer-overflow, got a clean exit" >&2
    cat run2.log >&2
    exit 1
fi
grep -q "AddressSanitizer: heap-buffer-overflow" run2.log

echo "inputs-hash-rebuild OK"
