#!/bin/sh
# aggregation-failure-exit-code-req, test side: a workspace with one
# genuinely failing test and one genuinely passing one -- the good
# module's test still runs (FAIL_FAST=no, the default), but `bmake test`
# must exit non-zero and name the failed module, at both framework and
# workspace level. With FAIL_FAST=yes it must stop before the good
# module's test is even attempted.
set -eu
cd ws
bmake >build.log 2>&1

if bmake test >run1.log 2>&1; then
    echo "expected non-zero exit with a failing test present" >&2
    cat run1.log >&2
    exit 1
fi
good_xml=$(find Fw/goodtest.m -name test-results.xml | head -1)
[ -n "$good_xml" ] || { echo "goodtest.m should still have run its test" >&2; exit 1; }
! grep -qE '<(failure|error)' "$good_xml"
bad_xml=$(find Fw/badtest.m -name test-results.xml | head -1)
[ -n "$bad_xml" ] || { echo "badtest.m test-results.xml missing" >&2; exit 1; }
grep -qE '<(failure|error)' "$bad_xml"
grep -q "framework Fw TEST FAILED" run1.log
grep -q "badtest.m" run1.log
grep -q "workspace TEST FAILED" run1.log

if bmake test FAIL_FAST=yes >run2.log 2>&1; then
    echo "expected non-zero exit with FAIL_FAST=yes too" >&2
    exit 1
fi
if grep -qE '(===> test results:.*goodtest)' run2.log; then
    echo "FAIL_FAST=yes should have stopped before goodtest.m's test was attempted" >&2
    exit 1
fi

echo "aggregation-test-failure-exit-code OK"
