#!/bin/sh
# run-exec.sh SHIMDIR PROGRAM [ARGS...] -- the last step of `bmake run`
# (run-build-environment-req, run-shell-keeps-environment-req).
#
# The caller has already exported the build environment: PATH, the library
# search variable named by BMK_LIBVAR, BMK_BINDIR / BMK_LIBDIR (the bin and
# lib chains, colon-separated). For an ordinary program this just execs it.
#
# For an INTERACTIVE shell (sh, dash, ash, ksh, mksh, bash, zsh with no
# arguments, or only -i/-l) the environment must reach the user intact: an
# interactive shell reads its own startup files (ENV for the sh family,
# ~/.bashrc, ~/.zshrc), and those routinely reset PATH. The user's files are
# still run -- nothing is suppressed or replaced -- and the build entries
# are re-asserted at the front of PATH and the library variable AFTER them,
# so a project binary still shadows a system one. Login shells read
# .profile before any of this and are not handled (documented).
# @impl 0f87-6ac1-4ffc-37ef
set -eu

shimdir=$1; prog=$2; shift 2

interactive=no
if [ $# -eq 0 ]; then
    interactive=yes
elif [ $# -eq 1 ]; then
    case "$1" in -i|-l) interactive=yes ;; esac
fi
kind=other
if [ "$interactive" = yes ]; then
    case "${prog##*/}" in
        sh|dash|ash|ksh|mksh) kind=posix ;;
        bash) kind=bash ;;
        zsh) kind=zsh ;;
    esac
fi
# The library variable is set only here, in the final exec: macOS strips
# DYLD_* from a process launched through a SIP-protected /bin/sh, so it
# cannot be carried through this script as an ordinary exported variable.
_launch() {
    if [ -n "${BMK_LIBVAL:-}" ] && [ "${BMK_LIBVAR:-PATH}" != PATH ]; then
        exec env "$BMK_LIBVAR=$BMK_LIBVAL" "$@"
    fi
    exec "$@"
}
[ "$kind" = other ] && _launch "$prog" "$@"

mkdir -p "$shimdir"

# Puts our chain first and drops its entries from the rest, keeping the
# user's own order for everything else.
cat > "$shimdir/reassert.sh" <<'EOF'
_bmk_front() {
    _bmk_new=$2; _bmk_ifs=$IFS; IFS=:
    for _bmk_e in $1; do
        [ -n "$_bmk_e" ] || continue
        case ":$2:" in *":$_bmk_e:"*) continue ;; esac
        _bmk_new="$_bmk_new:$_bmk_e"
    done
    IFS=$_bmk_ifs
    printf '%s' "$_bmk_new"
}
if [ "${BMK_LIBVAR:-PATH}" = PATH ]; then
    PATH=$(_bmk_front "$PATH" "$BMK_BINDIR:$BMK_LIBDIR")
else
    PATH=$(_bmk_front "$PATH" "$BMK_BINDIR")
    eval "_bmk_cur=\${$BMK_LIBVAR:-}"
    eval "$BMK_LIBVAR=\$(_bmk_front \"\$_bmk_cur\" \"\$BMK_LIBDIR\")"
    export "$BMK_LIBVAR"
fi
export PATH
unset -f _bmk_front 2>/dev/null || true
EOF

case "$kind" in
posix)
    # The sh family reads $ENV when interactive; run the user's, then ours.
    cat > "$shimdir/env.sh" <<'EOF'
if [ -n "${BMK_USER_ENV:-}" ] && [ -r "$BMK_USER_ENV" ]; then . "$BMK_USER_ENV"; fi
. "$BMK_SHIMDIR/reassert.sh"
EOF
    BMK_USER_ENV=${ENV:-}; BMK_SHIMDIR=$shimdir; ENV=$shimdir/env.sh
    export BMK_USER_ENV BMK_SHIMDIR ENV
    _launch "$prog" "$@"
    ;;
bash)
    cat > "$shimdir/bashrc" <<'EOF'
[ -r /etc/bash.bashrc ] && . /etc/bash.bashrc
[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"
. "$BMK_SHIMDIR/reassert.sh"
EOF
    BMK_SHIMDIR=$shimdir; export BMK_SHIMDIR
    _launch "$prog" --rcfile "$shimdir/bashrc" "$@"
    ;;
zsh)
    mkdir -p "$shimdir/zdot"
    cat > "$shimdir/zdot/.zshenv" <<'EOF'
[ -r "${BMK_USER_ZDOTDIR:-$HOME}/.zshenv" ] && . "${BMK_USER_ZDOTDIR:-$HOME}/.zshenv"
EOF
    cat > "$shimdir/zdot/.zshrc" <<'EOF'
[ -r "${BMK_USER_ZDOTDIR:-$HOME}/.zshrc" ] && . "${BMK_USER_ZDOTDIR:-$HOME}/.zshrc"
. "$BMK_SHIMDIR/reassert.sh"
EOF
    BMK_USER_ZDOTDIR=${ZDOTDIR:-$HOME}; BMK_SHIMDIR=$shimdir; ZDOTDIR=$shimdir/zdot
    export BMK_USER_ZDOTDIR BMK_SHIMDIR ZDOTDIR
    _launch "$prog" "$@"
    ;;
esac
