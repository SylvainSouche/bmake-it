#!/bin/sh
# @impl 0f87-6a98-5f76-2a44
# REQ-nested-invocation-reentrancy-guard-req: BMAKE must be an absolute path
# before any nested invocation -- a bare name can resolve back to a wrapper
# of this same script's caller (or, worse, to itself), causing unbounded
# self-recursion. The output file is written via a temp-file-then-rename so a
# concurrent or nested invocation of this same directory's discovery never
# observes a half-written or momentarily-deleted cache.
set -eu
OUT="${1:-.gen-mod-order.mk}"
BMAKE="${BMAKE:-bmake}"
case "$BMAKE" in
    /*) ;;
    *)
        _resolved=$(command -v "$BMAKE" 2>/dev/null || true)
        [ -n "$_resolved" ] && BMAKE="$_resolved"
        ;;
esac

# Each module is queried in its own directory (gen-mod-order-correct-
# curdir-req, see bmk-query.sh).
# single-module-visit-req (lasviewer round 5, item 3): all of LIBS/LIB/PROG
# in ONE bmake run (-V a -V b -V c, one output line each). It used to run
# once per variable -- three full parses of the module's makefile chain
# (IMPORT= resolution and pkg-config included) per module, ~2.5s for a
# four-module framework, before the first module was even entered.
# @impl 0f87-6abf-aeba-b9eb
BMK_PROG=gen-mod-order
. "$(dirname "$0")/bmk-query.sh"

# leftover-module-dir-skipped-and-cleaned-req: a leftover (no makefile, only
# build output) is not a module -- say so and go on.
# @impl 7854-6ad2-021e-2621
mods=""
for d in *.m; do
    [ -d "$d" ] || continue
    if bmk_is_leftover "$d"; then
        echo "gen-mod-order: warning: skipping $(pwd)/$d -- no makefile, only build output (left over, e.g. a module removed by git switch whose gitignored build/ kept the directory); \`bmake clean\` in $(pwd) removes it" >&2
        continue
    fi
    name="${d%.m}"
    mods="$mods $name"
done

if [ -z "$mods" ]; then
    echo "MODULE_SUBDIR=" > "$OUT.tmp.$$"
    mv -f "$OUT.tmp.$$" "$OUT"
    exit 0
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

if [ -n "${BMK_MKDIR:-}" ]; then
    bmk_find_sys_mk || exit 1
fi

# @impl 7854-6ad0-c7d9-13f6
for name in $mods; do
    if [ ! -f "${name}.m/makefile" ]; then
        echo "gen-mod-order: error: module directory $(pwd)/${name}.m has no makefile but is not just build output (it holds: $(ls -A "${name}.m" | tr '\n' ' ')) -- every *.m directory is a module and needs one" >&2
        exit 1
    fi
    _q=$(bmk_query "${name}.m/makefile" "LIBS LIB PROG REQUIRES IMPORT") || exit 1
    libs=$(printf '%s\n' "$_q" | sed -n 1p)
    libid=$(printf '%s\n' "$_q" | sed -n 2p)
    progid=$(printf '%s\n' "$_q" | sed -n 3p)
    # requires-preflight-req: modules the preflight must ask about -- a
    # REQUIRES=, an IMPORT=, or grammar sources (yacc/lex) -- the others
    # cannot lack anything it checks.
    _chk=$(printf '%s\n' "$_q" | sed -n '4,5p' | tr -d ' \n')
    if [ -z "$_chk" ] && find "${name}.m/src" \( -name '*.y' -o -name '*.yy' -o -name '*.l' -o -name '*.ll' \) 2>/dev/null | grep -q .; then
        _chk=grammar
    fi
    [ -z "$_chk" ] || echo "${name}.m" >> "$tmpdir/check"
    ids="$name"
    [ -n "$libid" ] && ids="$ids $libid lib${libid}"
    [ -n "$progid" ] && ids="$ids $progid"
    if [ -n "${BMK_DEBUG:-}" ]; then
        echo "gen-mod-order: $name LIBS=[$libs] LIB=[$libid] PROG=[$progid]" >&2
    fi
    echo "$libs" > "$tmpdir/dep_${name}"
    echo "$ids" > "$tmpdir/ids_${name}"
done

is_satisfied() {
    dep="$1"
    for s in $sorted; do
        for id in $(cat "$tmpdir/ids_${s}"); do
            [ "$id" = "$dep" ] && return 0
        done
    done
    return 1
}

is_local() {
    dep="$1"
    for m in $mods; do
        for id in $(cat "$tmpdir/ids_${m}"); do
            [ "$id" = "$dep" ] && return 0
        done
    done
    return 1
}

remaining="$mods"
sorted=""
progress=1

while [ -n "$remaining" ] && [ "$progress" = "1" ]; do
    progress=0
    still_remaining=""
    for name in $remaining; do
        deps=$(cat "$tmpdir/dep_${name}")
        ready=1
        for dep in $deps; do
            if is_local "$dep"; then
                if ! is_satisfied "$dep"; then
                    ready=0
                fi
            fi
        done
        if [ "$ready" = "1" ]; then
            sorted="$sorted $name"
            progress=1
        else
            still_remaining="$still_remaining $name"
        fi
    done
    remaining="$still_remaining"
done

if [ -n "$remaining" ]; then
    echo "gen-mod-order.sh: dependency cycle detected among:$remaining" >&2
    exit 1
fi

# module-skipped-after-failed-prereq-req: each module's dependencies within
# the framework (MODULE_DEPS.<m>.m), so a module whose prerequisite failed is
# skipped with that reason instead of failing on its missing headers.
# @impl 7854-6ae3-0a48-eaaa
# (prints nothing, and still succeeds, for a library from outside the
# framework: under set -e a failing $(...) would end the script)
local_mod_of() {
    for _lm in $mods; do
        for id in $(cat "$tmpdir/ids_${_lm}"); do
            [ "$id" = "$1" ] && { echo "$_lm"; return 0; }
        done
    done
    return 0
}
{
    echo "# generated by gen-mod-order.sh — do not edit"
    printf 'MODULE_SUBDIR='
    for name in $sorted; do
        printf ' %s.m' "$name"
    done
    printf '\n'
    echo "# order:$sorted"
    printf 'MODULE_CHECK=%s\n' "$(cat "$tmpdir/check" 2>/dev/null | tr '\n' ' ')"
    for name in $sorted; do
        printf 'MODULE_DEPS.%s.m=' "$name"
        for dep in $(cat "$tmpdir/dep_${name}"); do
            m=$(local_mod_of "$dep")
            [ -z "$m" ] || [ "$m" = "$name" ] || printf ' %s.m' "$m"
        done
        printf '\n'
    done
} > "$OUT.tmp.$$"
mv -f "$OUT.tmp.$$" "$OUT"
