#!/bin/sh
# unknown-toolchain-names-valid-ones-req: TOOLCHAIN=clang used to end in
# "Could not find mk.toolchain.clang.mk" -- nothing said that the clang toolchain
# is called llvm (found building OpenRider on NetBSD). An unknown name must say it
# is unknown, list the toolchains that exist, and translate the common aliases.
set -eu
cd ws/Fw/mod.m
check() { # check <name> <expected-hint-or-empty>
    out=$(bmake TOOLCHAIN="$1" -V CC 2>&1 || true)
    echo "$out" | grep -q "TOOLCHAIN=$1: there is no toolchain of that name" \
        || { echo "TOOLCHAIN=$1: expected the 'no toolchain of that name' error, got:" >&2; echo "$out" >&2; exit 1; }
    echo "$out" | grep -q "Known: llvm" || { echo "TOOLCHAIN=$1: valid names not listed:" >&2; echo "$out" >&2; exit 1; }
    if echo "$out" | grep -q "Could not find mk.toolchain"; then
        echo "TOOLCHAIN=$1: still reported as a missing include file" >&2; exit 1
    fi
    [ -z "$2" ] || echo "$out" | grep -q "$2" \
        || { echo "TOOLCHAIN=$1: expected the hint '$2', got:" >&2; echo "$out" >&2; exit 1; }
}
check clang "called llvm: use TOOLCHAIN=llvm"
check gnu   "called gcc: use TOOLCHAIN=gcc"
check cl    "called msvc: use TOOLCHAIN=msvc"
check bogus ""
# a valid name is not an error
bmake TOOLCHAIN=llvm -V CC >/dev/null 2>&1 || { echo "TOOLCHAIN=llvm must still work" >&2; exit 1; }
echo "unknown-toolchain-message OK"
