#!/bin/sh
# ci-report.sh <cell>: why a cell failed, as a GitHub Actions annotation --
# shown on the run's page, where a job's log and artifacts need a sign-in.
# The matrix's line for the cell, its failed cases, the end of its log.
# @impl 7854-6ae8-d1e7-04b9
cell=${1:?usage: ci-report.sh <cell>}
HARNESS_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$HARNESS_DIR/lib/env.sh"
log="$BMK_CACHE/logs/$cell.log"
{
    grep "^$cell	" "$BMK_CACHE/results/matrix.tsv" 2>/dev/null || echo "no result recorded for $cell"
    if [ -f "$log" ]; then
        grep -E ' (FAIL|ERROR)' "$log"
        # each failed case's own output, as run-tests.sh printed it
        sed -n '/^---- log: /,/^---- end ----/p' "$log"
        grep -q '^---- log: ' "$log" || { echo "--- end of $log"; tail -n 40 "$log"; }
    else
        echo "--- no log: $log"
        ls -la "$BMK_CACHE/logs" 2>&1
    fi
} | cut -c1-300 | sed 's/%/%25/g' | awk 'BEGIN { printf "::error title=%s::", "'"$cell"'" } { printf "%s%%0A", $0 } END { print "" }'
