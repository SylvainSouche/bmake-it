#!/bin/sh
# diff-aware-copy.sh SRC DEST [PRODUCER] — recursive copy-up with a
# diff-aware collision policy (REQ-copy-up-collision-diff-aware-req,
# copy-up-collision-different-modules-only-req):
#   - SRC missing: no-op, not an error (the source stage may legitimately
#     not exist, e.g. a module with no share/ resources).
#   - destination file absent, or present and byte-identical to the
#     source: copy proceeds silently.
#   - destination file present and differs: it is a COLLISION only if a
#     different producer wrote it. The previous producer of each name is
#     recorded in <dirname DEST>/.copy-up-origin/<basename DEST>.tsv --
#     beside DEST, not inside it, so it is never shipped by install. The
#     same producer overwriting its own earlier output (a legitimately
#     rebuilt program or library) is silent: a rebuilt artefact is
#     expected to differ from its previous copy. A name with no recorded
#     producer (written before provenance existed, or by hand) still
#     warns, conservatively.
#     A collision prints a warning naming the file to stderr, and the copy
#     still proceeds (overwrite, last-copied-wins) -- not a hard error.
#   PRODUCER defaults to SRC, which is distinct per module and per
#   framework, so existing callers need no change.
#
# @impl 0f87-6a98-8ee9-ae83
# @impl 0f87-6ac0-c275-07a6
set -eu

SRC=${1:?usage: diff-aware-copy.sh SRC DEST [PRODUCER]}
DEST=${2:?usage: diff-aware-copy.sh SRC DEST [PRODUCER]}
SRC=${SRC%/}
DEST=${DEST%/}
PRODUCER=${3:-$SRC}

[ -d "$SRC" ] || exit 0
mkdir -p "$DEST"

MANDIR=$(dirname "$DEST")/.copy-up-origin
MAN="$MANDIR/$(basename "$DEST").tsv"
mkdir -p "$MANDIR"
[ -f "$MAN" ] || : > "$MAN"
NEW=$(mktemp)
trap 'rm -f "$NEW"' EXIT

find "$SRC" \( -type f -o -type l \) | while IFS= read -r f; do
    rel=${f#"$SRC"/}
    dest="$DEST/$rel"
    if [ -e "$dest" ] && ! cmp -s "$f" "$dest" 2>/dev/null; then
        prev=$(awk -F'\t' -v r="$rel" '$1==r {p=$2} END {print p}' "$MAN")
        if [ "$prev" != "$PRODUCER" ]; then
            echo "warning: copy-up collision: '$rel' differs between source and destination -- overwriting $dest" >&2
        fi
    fi
    mkdir -p "$(dirname "$dest")"
    cp -a "$f" "$dest"
    printf '%s\t%s\n' "$rel" "$PRODUCER" >> "$NEW"
done

# Nothing copied: nothing to record. Otherwise update existing entries IN
# PLACE and append only names not seen before -- a stable order, so a
# revisit that changed nothing rewrites nothing.
[ -s "$NEW" ] || exit 0
awk -F'\t' -v OFS='\t' 'NR==FNR {val[$1]=$2; next} {if ($1 in val) print $1, val[$1]; else print}' "$NEW" "$MAN" > "$MAN.tmp"
if [ -s "$MAN.tmp" ]; then
    awk -F'\t' -v OFS='\t' 'NR==FNR {have[$1]=1; next} !($1 in have)' "$MAN.tmp" "$NEW" >> "$MAN.tmp"
else
    cat "$NEW" > "$MAN.tmp"
fi
# Replace only on change: an unchanged rebuild must write nothing at all.
if cmp -s "$MAN.tmp" "$MAN"; then rm -f "$MAN.tmp"; else mv -f "$MAN.tmp" "$MAN"; fi
