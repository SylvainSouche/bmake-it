#!/bin/sh
# @impl 0f87-6a98-7829-d674
# run-tests.sh — pure-shell orchestrator for Bmake It unit tests.
# Does NOT use make for orchestration. Each test gets a fresh bmake
# subprocess with MAKEFLAGS/MAKELEVEL/MFLAGS cleared.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
TESTS_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ARCHIVES_DIR="${ARCHIVES_DIR:-$TESTS_ROOT/archives}"
BMK_ROOT=$(CDPATH= cd -- "$TESTS_ROOT/.." && pwd)
BMK_MKDIR="${BMK_MKDIR:-$BMK_ROOT/mk}"
BMK_SCRIPTS="${BMK_SCRIPTS:-$BMK_ROOT/scripts}"

_SYS_MK="${BMK_SYS_MK:-}"
if [ -z "$_SYS_MK" ]; then
    for d in /opt/local/share/mk /usr/share/mk /usr/local/share/mk; do
        if [ -f "$d/sys.mk" ]; then _SYS_MK=$d; break; fi
    done
fi
if [ -z "$_SYS_MK" ]; then
    echo "run-tests.sh: cannot locate sys.mk (set BMK_SYS_MK=)" >&2
    exit 2
fi

BMAKE="${BMAKE:-bmake}"
# @impl 0f87-6a98-5f76-2a44
case "$BMAKE" in
    /*) ;; # already absolute
    *)
        # Resolve to an absolute path before it's baked into the bmake
        # wrapper below. The wrapper is installed on PATH *as* `bmake`, so a
        # bare (non-absolute) $BMAKE bakes in a self-reference: the wrapper's
        # own exec line resolves "bmake" back to itself and recurses forever.
        _resolved=$(command -v "$BMAKE" 2>/dev/null || true)
        if [ -z "$_resolved" ]; then
            echo "run-tests.sh: cannot find '$BMAKE' on PATH (set BMAKE=/absolute/path/to/bmake)" >&2
            exit 2
        fi
        BMAKE="$_resolved"
        ;;
esac
KEEP_FAILED="${KEEP_FAILED:-0}"
FILTER="${1:-}"
# Runs the whole suite under a non-default TOOLCHAIN (e.g. TOOLCHAIN=gcc)
# when set. Baked into the wrapper as an environment default, not a
# command-line override, so a test that sets TOOLCHAIN= itself on its own
# bmake invocation (case 13-target-key does) still wins -- normal make
# override precedence (command line beats environment).
TOOLCHAIN="${TOOLCHAIN:-}"

pass=0; fail=0; skip=0; errors=0

WORKDIR_BASE=$(mktemp -d "${TMPDIR:-/tmp}/bmk-tests.XXXXXX")
WRAPDIR=$(mktemp -d "${TMPDIR:-/tmp}/bmk-wrap.XXXXXX")
trap 'rm -rf "$WORKDIR_BASE" "$WRAPDIR"' EXIT INT TERM

cat > "$WRAPDIR/bmake" << EOF
#!/bin/sh
exec env -u MAKEFLAGS -u MAKELEVEL -u MFLAGS \\
    MAKESYSPATH="${BMK_MKDIR}:${_SYS_MK}" \\
    BMK_MKDIR="${BMK_MKDIR}" \\
    ${TOOLCHAIN:+TOOLCHAIN="$TOOLCHAIN"} \\
    ${BMAKE} -m "${BMK_MKDIR}" -m "${_SYS_MK}" BMK_MKDIR="${BMK_MKDIR}" "\$@"
EOF
chmod +x "$WRAPDIR/bmake"

echo "=== Bmake It test runner ==="
echo "BMK_MKDIR=$BMK_MKDIR"
echo "sys.mk from $_SYS_MK"
echo "archives: $ARCHIVES_DIR"
echo "work:     $WORKDIR_BASE"
[ -n "$TOOLCHAIN" ] && echo "TOOLCHAIN=$TOOLCHAIN (forced for whole suite)"
echo

for archive in "$ARCHIVES_DIR"/*.tar.gz "$ARCHIVES_DIR"/*.tgz; do
    [ -f "$archive" ] || continue
    name=$(basename "$archive" | sed 's/\.tar\.gz$//;s/\.tgz$//')
    if [ -n "$FILTER" ]; then
        case "$name" in *"$FILTER"*) ;; *) continue ;; esac
    fi

    wdir="$WORKDIR_BASE/$name"
    mkdir -p "$wdir"
    printf '%-40s ' "$name"

    if ! tar -xzf "$archive" -C "$wdir" 2>/dev/null; then
        echo "ERROR (extract)"
        errors=$((errors + 1))
        continue
    fi

    if [ -d "$wdir/$name" ]; then
        tdir="$wdir/$name"
    else
        tdir="$wdir"
    fi

    if [ ! -f "$tdir/run.sh" ]; then
        echo "ERROR (no run.sh)"
        errors=$((errors + 1))
        continue
    fi
    chmod +x "$tdir/run.sh" 2>/dev/null || true

    log="$WORKDIR_BASE/$name.log"
    status=0
    (
        cd "$tdir"
        unset MAKEFLAGS MAKELEVEL MFLAGS MAKE 2>/dev/null || true
        export BMK_MKDIR BMK_SCRIPTS
        export MAKESYSPATH="${BMK_MKDIR}:${_SYS_MK}"
        export PATH="$WRAPDIR:$PATH"
        sh ./run.sh
    ) >"$log" 2>&1 || status=$?

    if [ "$status" -eq 0 ]; then
        echo "PASS"
        pass=$((pass + 1))
        rm -rf "$wdir" "$log"
    elif [ "$status" -eq 77 ]; then
        echo "SKIP"
        skip=$((skip + 1))
        rm -rf "$wdir" "$log"
    else
        echo "FAIL (exit $status)"
        fail=$((fail + 1))
        echo "---- log: $name ----" >&2
        tail -n 50 "$log" >&2 || true
        echo "---- end ----" >&2
        if [ "$KEEP_FAILED" != "1" ]; then
            rm -rf "$wdir"
        else
            echo "(kept $wdir)" >&2
        fi
        rm -f "$log"
    fi
done

echo
echo "=== summary ==="
echo "pass=$pass  fail=$fail  skip=$skip  error=$errors"

if [ "$fail" -gt 0 ] || [ "$errors" -gt 0 ]; then
    exit 1
fi
exit 0
