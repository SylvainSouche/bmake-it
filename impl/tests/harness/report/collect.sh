#!/bin/sh
# collect.sh <logs-dir> <results-file>
# Aggregates every *.log.status file (written by the build/test scripts)
# into one results file, sorted by name.
set -eu
LOGS="${1:?usage: collect.sh <logs-dir> <results-file>}"
OUT="${2:?usage: collect.sh <logs-dir> <results-file>}"

{
    echo "=== Bmake It matrix results ==="
    echo "generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    for f in "$LOGS"/*.log.status; do
        [ -f "$f" ] || continue
        name=$(basename "$f" .log.status)
        printf '%-40s %s\n' "$name" "$(cat "$f")"
    done | sort
} > "$OUT"
