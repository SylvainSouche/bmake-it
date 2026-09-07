#!/bin/sh
# diff-aware-copy.sh SRC DEST — recursive copy-up with a diff-aware
# collision policy (REQ-copy-up-collision-diff-aware-req):
#   - SRC missing: no-op, not an error (the source stage may legitimately
#     not exist, e.g. a module with no share/ resources).
#   - destination file absent, or present and byte-identical to the
#     source: copy proceeds silently.
#   - destination file present and differs from the source: a warning
#     naming the file is printed to stderr, but the copy still proceeds
#     (overwrite, last-copied-wins) -- this is not a hard error.
#
# @impl 0f87-6a98-8ee9-ae83
set -eu

SRC=${1:?usage: diff-aware-copy.sh SRC DEST}
DEST=${2:?usage: diff-aware-copy.sh SRC DEST}
SRC=${SRC%/}
DEST=${DEST%/}

[ -d "$SRC" ] || exit 0
mkdir -p "$DEST"

find "$SRC" \( -type f -o -type l \) | while IFS= read -r f; do
    rel=${f#"$SRC"/}
    dest="$DEST/$rel"
    if [ -e "$dest" ] && ! cmp -s "$f" "$dest" 2>/dev/null; then
        echo "warning: copy-up collision: '$rel' differs between source and destination -- overwriting $dest" >&2
    fi
    mkdir -p "$(dirname "$dest")"
    cp -a "$f" "$dest"
done
