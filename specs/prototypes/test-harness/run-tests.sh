#!/bin/sh
# run-tests.sh — prototype test-harness driver for Bmake It.
#
# Deliberately NOT a make target: this script drives bmake from the
# OUTSIDE, so it keeps working even if the thing under test (mk.*.mk
# behavior) is partially broken, and so testing the build system isn't
# circularly dependent on the build system working correctly.
#
# For each test-case archive in cases/*.tar.gz:
#   1. mktemp a scratch directory
#   2. expand the archive into it
#   3. read that case's test.conf (DESCRIPTION, MAKE_ARGS, and one of
#      EXPECT_EXIT / EXPECT_FILE / EXPECT_OUTPUT_CONTAINS)
#   4. run bmake there with MAKE_ARGS
#   5. record PASS/FAIL against the expectation
#   6. delete the expanded scratch directory
#
# Usage: ./run-tests.sh [MAKESYSPATH]
#   MAKESYSPATH defaults to the FreeBSD share/mk checkout used during
#   this session's validation pass; override for a real target host.

set -u

CASES_DIR="$(cd "$(dirname "$0")/cases" && pwd)"
MAKESYSPATH="${1:-/home/claude/bsdmake-validation/fbsd-src/share/mk}"

pass=0
fail=0
total=0

for archive in "$CASES_DIR"/*.tar.gz; do
    [ -f "$archive" ] || continue
    total=$((total + 1))
    case_name=$(basename "$archive" .tar.gz)

    scratch=$(mktemp -d)
    tar -xzf "$archive" -C "$scratch"
    casedir="$scratch/$case_name"

    if [ ! -f "$casedir/test.conf" ]; then
        echo "FAIL  $case_name  (no test.conf found in archive)"
        fail=$((fail + 1))
        rm -rf "$scratch"
        continue
    fi

    DESCRIPTION=""
    MAKE_ARGS=""
    EXPECT_EXIT=""
    EXPECT_FILE=""
    EXPECT_OUTPUT_CONTAINS=""
    # shellcheck disable=SC1090
    . "$casedir/test.conf"

    outlog=$(mktemp)
    (
        cd "$casedir" || exit 127
        # shellcheck disable=SC2086
        bmake -m "$MAKESYSPATH" $MAKE_ARGS
    ) >"$outlog" 2>&1
    actual_exit=$?

    ok=1
    reason=""

    if [ -n "$EXPECT_EXIT" ] && [ "$actual_exit" != "$EXPECT_EXIT" ]; then
        ok=0
        reason="exit code $actual_exit, expected $EXPECT_EXIT"
    fi
    if [ -n "$EXPECT_FILE" ] && [ ! -f "$casedir/$EXPECT_FILE" ]; then
        ok=0
        reason="expected output file '$EXPECT_FILE' not produced"
    fi
    if [ -n "$EXPECT_OUTPUT_CONTAINS" ]; then
        for token in $EXPECT_OUTPUT_CONTAINS; do
            if ! grep -q "$token" "$outlog"; then
                ok=0
                reason="expected output to contain '$token'"
            fi
        done
    fi

    if [ "$ok" = "1" ]; then
        echo "PASS  $case_name  -- $DESCRIPTION"
        pass=$((pass + 1))
    else
        echo "FAIL  $case_name  -- $reason"
        echo "      (log: $outlog)"
        fail=$((fail + 1))
    fi

    # Cleanup: only remove the expanded scratch dir on PASS, so a FAIL
    # leaves evidence behind for inspection (outlog is left regardless).
    if [ "$ok" = "1" ]; then
        rm -f "$outlog"
    fi
    rm -rf "$scratch"
done

echo
echo "Results: $pass/$total passed, $fail failed"
[ "$fail" = "0" ]
