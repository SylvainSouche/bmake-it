#!/bin/sh
# run-not-found.sh WS BINS PROGRAM BUILD_ROOT -- why `bmake run` cannot find
# PROGRAM (run-not-found-is-explained-req). Prints the error to stderr and
# exits 1.
#
# run looks in the workspace bin (where copy-up gathers every framework's
# programs), the parent workspaces' and PATH. A program that was built but
# never copied up -- its framework's build failed, e.g. on a .tst module that
# did not link -- is in <framework>/BUILD_ROOT/bin or in its module's own:
# "not found -- build first" was then wrong, the user HAD built it (OpenRider
# on FreeBSD, perf.tst and scale.tst failing, 2026-10-29). Say where it is
# and why it is not in the workspace.
# @impl 7854-6ae3-2cb6-9d43
set -u
ws=$1; bins=$2; prog=$3; broot=$4

found=""
for f in "$ws"/*/"$broot/bin/$prog" "$ws"/*/"$broot/bin/$prog.exe" \
         "$ws"/*/*.m/"$broot/bin/$prog" "$ws"/*/*.m/"$broot/bin/$prog.exe"; do
    [ -f "$f" ] && { found=$f; break; }
done

{
    echo "error: $prog not found in $(echo "$bins" | sed 's/:/, /g') or on PATH"
    if [ -z "$found" ]; then
        echo "       it is not built anywhere in this workspace -- build first (run does not build)"
        exit 1
    fi
    rel=${found#"$ws"/}; fw=${rel%%/*}
    echo "       it was built ($rel) but not copied into the workspace bin:"
    latest="$ws/$fw/$broot/runs/latest"
    if [ -f "$latest/build.failed" ]; then
        mods=$(sed -n "s/^===> framework $fw BUILD FAILED: *//p" "$latest/build.log" 2>/dev/null | tail -1)
        echo "       framework $fw's last build failed${mods:+ (modules: $mods)}, and a framework is copied up only when all of it builds"
        echo "       see $fw/$broot/runs/latest/build.log -- fix it, then build again"
    else
        echo "       framework $fw has not been copied up since -- build again from the workspace"
    fi
} >&2
exit 1
