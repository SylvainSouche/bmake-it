# bmk-query.sh -- sourced (not run) by gen-mod-order.sh and gen-fw-order.sh.
# Shared by both so that finding sys.mk and running a nested -V query, and
# above all FAILING LOUDLY when either goes wrong, is written once.
#
# Callers set, before sourcing:
#   BMK_PROG  -- name used in messages (gen-mod-order, gen-fw-order)
#   BMAKE     -- absolute path of the bmake to run
#   tmpdir    -- scratch directory (holds each query's captured output)
#
# @impl 7854-6ad0-c2da-f4ce
# order-query-sys-mk-located-req: a nested query needs bmake's own system
# rules (sys.mk). Their location differs per host -- /usr/share/mk (BSDs),
# /usr/share/bmake/mk (Cygwin, Debian), /opt/local/share/mk (MacPorts), ...
# -- and a hardcoded list missed Cygwin entirely (2026-10-15), after first
# missing every non-macOS host (2026-08-31). Look where the invoking bmake
# itself looks first (the MAKESYSPATH our caller built from .SYSPATH), then
# the known install directories; finding none is an error naming them all.
bmk_find_sys_mk() {
    if [ -n "${BMK_SYS_MK:-}" ]; then
        if [ -f "$BMK_SYS_MK/sys.mk" ]; then
            BMK_SYS_MK_DIR=$BMK_SYS_MK
            return 0
        fi
        echo "$BMK_PROG: error: BMK_SYS_MK=$BMK_SYS_MK contains no sys.mk" >&2
        return 1
    fi
    _searched=""
    _old_ifs=$IFS
    IFS=:
    for _d in ${MAKESYSPATH:-}; do
        IFS=$_old_ifs
        [ -n "$_d" ] || continue
        _searched="$_searched $_d"
        if [ -f "$_d/sys.mk" ]; then
            BMK_SYS_MK_DIR=$_d
            return 0
        fi
    done
    IFS=$_old_ifs
    for _d in /usr/share/mk /usr/share/bmake/mk /opt/local/share/mk \
              /usr/local/share/mk /usr/pkg/share/mk /opt/pkg/share/mk; do
        _searched="$_searched $_d"
        if [ -f "$_d/sys.mk" ]; then
            BMK_SYS_MK_DIR=$_d
            return 0
        fi
    done
    {
        echo "$BMK_PROG: error: cannot find bmake's system rules (sys.mk)."
        echo "    searched:$_searched"
        echo "    \`$BMAKE -r -f /dev/null -V .SYSPATH\` prints where your bmake looks;"
        echo "    set BMK_SYS_MK=<the directory holding sys.mk> to name it explicitly."
    } >&2
    return 1
}

# @impl 7854-6ad0-c2da-1218
# order-query-failure-is-error-req: run `bmake -V <var> ...` on one
# makefile and print one line per variable. If bmake fails, say which
# makefile, which variables, and quote bmake's own output -- then return
# non-zero, which the caller turns into a failed generation. Never `|| true`:
# a swallowed failure looks exactly like "no dependencies", and the build
# then goes on in the wrong order and dies somewhere far less explicable.
#
# .CURDIR must be the queried makefile's own directory (gen-mod-order-
# correct-curdir-req): cd there first, exactly as a real recursive
# ${MAKE} -C <dir> build would see it.
# @impl 0f87-6ab5-8d38-83ac
bmk_query() {
    _mf=$1
    _vars=$2
    _vargs=""
    for _v in $_vars; do _vargs="$_vargs -V $_v"; done
    _dir=$(dirname "$_mf")
    _file=$(basename "$_mf")
    if [ -n "${BMK_MKDIR:-}" ]; then
        if (
            cd "$_dir" &&
            env -u MAKEFLAGS -u MAKELEVEL -u MFLAGS \
                MAKESYSPATH="${BMK_MKDIR}:${BMK_SYS_MK_DIR}" \
                BMK_MKDIR="$BMK_MKDIR" \
                "$BMAKE" -m "$BMK_MKDIR" -m "$BMK_SYS_MK_DIR" \
                BMK_MKDIR="$BMK_MKDIR" \
                -f "$_file" $_vargs
        ) >"$tmpdir/query.out" 2>"$tmpdir/query.err"; then
            cat "$tmpdir/query.out"
            return 0
        fi
    else
        if (
            cd "$_dir" &&
            env -u MAKEFLAGS -u MAKELEVEL -u MFLAGS \
                "$BMAKE" -f "$_file" $_vargs
        ) >"$tmpdir/query.out" 2>"$tmpdir/query.err"; then
            cat "$tmpdir/query.out"
            return 0
        fi
    fi
    {
        echo "$BMK_PROG: error: cannot read$(printf ' %s=' $_vars) from $_mf -- this bmake query failed:"
        echo "    (cd $_dir && $BMAKE -f $_file$_vargs)"
        cat "$tmpdir/query.err" "$tmpdir/query.out" | sed '/^$/d; s/^/    | /'
    } >&2
    return 1
}
