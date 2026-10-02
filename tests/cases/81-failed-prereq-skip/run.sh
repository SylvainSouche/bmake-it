#!/bin/sh
# failed-prereq-framework-skip-req (lasviewer round 5, item 2): frameworks
# A <- B <- C plus an independent D. A fails to compile. B and C must be
# skipped with a one-line reason (C also names the root cause), never
# attempted; D still builds (keep-going); the exit status is non-zero; and
# the final summary lists the root failure (A) before the skipped ones.
set -eu
cd ws
if bmake >build.log 2>&1; then
    echo "expected the workspace build to fail" >&2
    exit 1
fi

grep -q "===> framework B skipped: prerequisite A failed" build.log
grep -q "===> framework C skipped: prerequisite B failed (root cause: A)" build.log

# Skipped means never attempted.
if grep -q "===> building framework B" build.log || grep -q "===> building framework C" build.log; then
    echo "a skipped framework was built anyway" >&2
    exit 1
fi
if [ -d B/app.m/build ] || [ -d C/app.m/build ]; then
    echo "a skipped framework left build output" >&2
    exit 1
fi

# The independent framework still builds.
grep -q "===> building framework D" build.log
[ -n "$(find D -type f -name app | head -1)" ]

# Summary: root failure first, then the skipped frameworks.
grep -q "workspace BUILD FAILED: A B C" build.log
root_line=$(grep -n "     A -- see" build.log | head -1 | cut -d: -f1)
skip_line=$(grep -n "     B -- skipped, root cause: A" build.log | head -1 | cut -d: -f1)
[ -n "$root_line" ] && [ -n "$skip_line" ] && [ "$root_line" -lt "$skip_line" ]

echo "failed-prereq-skip OK"
