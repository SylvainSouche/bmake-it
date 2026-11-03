#!/bin/sh
# check-man.sh: the manual pages against mk/. man-pages-for-mk-files-req.
#   - every mk/mk.*.mk has a page, and every page a file (a .so page counts)
#   - every variable a file sets with ?=, which is what makes it a setting, is
#     named in that file's page (internal _NAMES are not settings)
#   - every target a role file defines is named in its page
#   - every .Xr to a bmake-it page resolves
#   - the pages are clean under mandoc -Tlint if it is here, and groff if it is
# Exits 1 naming each problem. Run by case 113, and so on every matrix cell.
# @impl 7854-6ae9-90fb-b9d5
set -u
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
MAN=$ROOT/man
bad=0
say() { echo "check-man: $*" >&2; bad=$((bad + 1)); }

[ -d "$MAN/man5" ] || { say "no $MAN/man5"; exit 1; }

for f in "$ROOT"/mk/mk.*.mk; do
    b=$(basename "$f")
    p=$MAN/man5/$b.5
    [ -f "$p" ] || { say "$b has no page ($p)"; continue; }
    # a one-line .so page: the variables are checked against the page it names
    if grep -q '^\.so ' "$p"; then p=$MAN/$(sed -n 's/^\.so //p' "$p"); fi
    [ -f "$p" ] || { say "$b: its .so names a page that is not there"; continue; }

    for v in $(sed -n 's/^\.\{0,1\}[[:space:]]*\([A-Z][A-Z0-9_]*\)[[:space:]]*?=.*/\1/p' "$f" | sort -u); do
        grep -qw "$v" "$p" || say "$b sets $v with ?=, and its page does not name it"
    done
    for t in $(sed -n 's/^\([a-z][a-z0-9-]*\):.*/\1/p' "$f" | sort -u); do
        grep -qw "$t" "$p" || say "$b defines target $t, and its page does not name it"
    done
done

for p in "$MAN"/man5/*.5 "$MAN"/man7/*.7; do
    b=$(basename "$p")
    case "$b" in
        bmake-it.7|mk.paths.5) ;;
        *) [ -f "$ROOT/mk/${b%.5}" ] || say "$b documents a file that is not in mk/" ;;
    esac
    for x in $(sed -n 's/^.*Xr \(mk\.[a-z0-9.-]*\|bmake-it\) \([0-9]\).*/\1.\2/p' "$p" | sort -u); do
        [ -f "$MAN/man${x##*.}/$x" ] || say "$b refers to $x, which is not there"
    done
done

_lint=none
if command -v mandoc >/dev/null 2>&1; then
    _lint=mandoc
    # WARNING and above; a reference to a page of another package is a STYLE note
    out=$(cd "$MAN" && mandoc -Tlint -Wwarning man5/*.5 man7/*.7 2>&1) || true
    [ -z "$out" ] || { printf '%s\n' "$out" >&2; say "mandoc -Tlint is not clean"; }
elif command -v groff >/dev/null 2>&1; then
    _lint=groff
    for p in "$MAN"/man5/*.5 "$MAN"/man7/*.7; do
        grep -q '^\.so ' "$p" && continue
        out=$(LC_ALL=C groff -mdoc -Tutf8 -ww -z "$p" 2>&1) || true
        [ -z "$out" ] || { printf '%s\n' "$out" >&2; say "$(basename "$p"): groff warns"; }
    done
fi

if [ "$bad" -gt 0 ]; then echo "check-man: $bad problem(s)" >&2; exit 1; fi
echo "check-man: OK ($(ls "$MAN"/man5/*.5 "$MAN"/man7/*.7 | wc -l) pages, lint: $_lint)"
