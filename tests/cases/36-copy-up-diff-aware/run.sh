#!/bin/sh
# copy-up-collision-diff-aware-req: two frameworks independently producing
# a same-named share/ artifact -- identical content copies silently, but
# differing content emits a warning and still succeeds (overwrite, not a
# hard error, last-copied-wins).
set -eu
cd ws

bmake >out.log 2>&1 || { echo "build should succeed despite the collision" >&2; cat out.log >&2; exit 1; }

# genuine collision: differing content -> warning, build still proceeds
grep -qi "collision.*conflict.txt" out.log

# identical content -> silent, no warning naming this file
! grep -qi "collision.*identical.txt" out.log

sharedir=$(find build -type d -name share | head -1)
[ -n "$sharedir" ] || { echo "workspace share dir not found" >&2; exit 1; }

# identical file: exact expected content regardless of copy order
[ "$(cat "$sharedir/identical.txt")" = "shared content" ]

# conflicting file: last-copied-wins -- either source is acceptable, but
# it must be one of the two, not empty/corrupted
content=$(cat "$sharedir/conflict.txt")
[ "$content" = "from FwA" ] || [ "$content" = "from FwB" ]

echo "copy-up-diff-aware OK (conflict.txt = '$content')"
