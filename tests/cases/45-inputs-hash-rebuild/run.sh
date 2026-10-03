#!/bin/sh
# inputs-hash-rebuild-req: bmake has no notion that a .o was compiled with
# different flags than requested -- `bmake` then `bmake SANITIZE=address`
# must actually recompile every object (not silently reuse stale, non-
# instrumented ones) and the resulting binary must genuinely crash under
# ASan on a real heap-buffer-overflow, not just accept the flag silently.
set -eu
cd ws/Fw
# Skip where an ASan binary cannot be linked at all with the compiler bmake
# itself uses (Ubuntu 24.04 aarch64's clang 18 package lacks
# libclang_rt.asan_static): nothing to test then. Probe with bmake's own CC,
# not `cc` -- on Linux that is gcc, which can.
_cc=$(bmake -V '${CC}')
_t=$(mktemp)
if ! printf 'int main(void){return 0;}' | $_cc -fsanitize=address -x c - -o "$_t" >/dev/null 2>&1; then
    rm -f "$_t"; exit 77
fi
rm -f "$_t"

bmake >build1.log 2>&1
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]

# Plain build: the bug is real but silent without instrumentation.
"$bin" >run1.log 2>&1
grep -q "no crash" run1.log

# SANITIZE=address: objects must actually recompile with the flag, not
# just relink stale ones.
# bmake compares mtimes at one-second granularity on some hosts (Debian's
# bmake 20200710): a flag change in the same second as the previous build
# would rebuild nothing. Pause so this tests the inputs hash, not the clock.
sleep 1
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
