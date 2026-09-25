#!/bin/sh
# aggregation-failure-exit-code-req: a workspace with one broken and one
# good module -- the good module still builds (FAIL_FAST=no, the default,
# keeps going), but the workspace's own `bmake` must exit non-zero and
# name the broken module, at both framework and workspace level. With
# FAIL_FAST=yes it must stop before the good module is even attempted.
set -eu
cd ws

if bmake >run1.log 2>&1; then
    echo "expected non-zero exit with a broken module present" >&2
    cat run1.log >&2
    exit 1
fi
[ -f Fw/good.m/build/*/bin/good ] || { echo "good.m should still have been built" >&2; exit 1; }
[ ! -e Fw/bad.m/build/*/bin/bad ] || { echo "bad.m should not have produced a binary" >&2; exit 1; }
grep -q "framework Fw BUILD FAILED" run1.log
grep -q "bad.m" run1.log
grep -q "workspace BUILD FAILED" run1.log

bmake clean >/dev/null 2>&1

if bmake FAIL_FAST=yes >run2.log 2>&1; then
    echo "expected non-zero exit with FAIL_FAST=yes too" >&2
    exit 1
fi
if grep -q "building module good.m" run2.log; then
    echo "FAIL_FAST=yes should have stopped before good.m was attempted" >&2
    exit 1
fi

echo "aggregation-build-failure-exit-code OK"
