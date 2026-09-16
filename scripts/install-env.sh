#!/bin/sh
# install-env.sh — sets MAKESYSPATH so any out-of-tree project can find
# Bmake It's own mk/ role files without per-invocation flags
# (install-env-script-req). User-level by default: appends an idempotent,
# clearly-delimited block to the invoking user's own shell rc file.
# --system (Linux only): writes /etc/profile.d/bmake-it.sh instead, one
# file, no per-user dotfile edits, needs root. --uninstall removes
# exactly the block this script added, nothing else.
#
# Why MAKESYSPATH and not MAKEFLAGS=-I: a search path is the correct
# conceptual fit for shared/reusable make files -- what real system
# includes (<bsd.prog.mk>-style) already use, and what other bsd-make
# tooling on the same machine already relies on
# (bmk-mkdir-discovery-via-makesyspath). The default system path is
# captured once, here, via `bmake -f /dev/null -V .SYSPATH` -- the
# -f /dev/null is required, not optional: querying .SYSPATH normally
# parses whatever makefile happens to be in the current directory first,
# so a stray or broken makefile anywhere (including $HOME) would corrupt
# the captured value. The written rc-file line still respects an
# already-set MAKESYSPATH at each shell startup (via ${MAKESYSPATH:-...}),
# it just doesn't re-run bmake on every new shell for that.
#
# No changes needed to mk/*.mk itself: BMK_MKDIR already auto-computes
# correctly via ${.PARSEDIR} regardless of whether a role file was found
# via a local relative path or via MAKESYSPATH -- verified against a
# real out-of-tree project with zero local Bmake It files.
#
# @impl 0f87-6aaa-d6a5-b4df
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_MK=$(cd "$SCRIPT_DIR/../mk" && pwd)

MARK_BEGIN="# >>> bmake-it >>>"
MARK_END="# <<< bmake-it <<<"

MODE=user
ACTION=install
ASSUME_YES=no

usage() {
    echo "usage: $0 [--system] [--uninstall] [-y|--yes]" >&2
}

for arg in "$@"; do
    case "$arg" in
        --system) MODE=system ;;
        --uninstall) ACTION=uninstall ;;
        -y|--yes) ASSUME_YES=yes ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unrecognized argument: $arg" >&2; usage; exit 1 ;;
    esac
done

command -v bmake >/dev/null 2>&1 || {
    echo "error: bmake not found on PATH -- install it first (see README.md Prerequisites)" >&2
    exit 1
}

confirm() {
    [ "$ASSUME_YES" = yes ] && return 0
    printf "Proceed? [y/N] "
    read -r reply
    case "$reply" in
        y|Y|yes|YES) return 0 ;;
        *) echo "Aborted, nothing changed."; exit 1 ;;
    esac
}

# Remove any existing bmake-it block from a file, in place. No-op if the
# file or the block doesn't exist.
strip_block() {
    file=$1
    [ -f "$file" ] || return 0
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        !skip { print }
    ' "$file" > "$file.bmakeit.tmp"
    mv "$file.bmakeit.tmp" "$file"
}

if [ "$ACTION" = install ]; then
    DEFAULT_SYSPATH=$(bmake -f /dev/null -V .SYSPATH 2>/dev/null) || {
        echo "error: 'bmake -f /dev/null -V .SYSPATH' failed -- cannot determine bmake's own default system path" >&2
        exit 1
    }
    MAKESYSPATH_VALUE="$REPO_MK:\${MAKESYSPATH:-$DEFAULT_SYSPATH}"
fi

block_sh() {
    printf '%s\n' "$MARK_BEGIN"
    printf '# Added by bmake-it/scripts/install-env.sh -- do not edit by hand,\n'
    printf '# re-run the script instead (safe: it replaces this block in place).\n'
    printf 'export MAKESYSPATH="%s"\n' "$MAKESYSPATH_VALUE"
    printf '%s\n' "$MARK_END"
}

block_fish() {
    # fish has no POSIX ${VAR:-default} expansion -- $MAKESYSPATH_VALUE
    # (which embeds that syntax verbatim for the sh/bash/zsh case) is NOT
    # reused here. fish's own idiom for "preserve if set, else default"
    # is an explicit set -q / if / else, not inline substitution.
    printf '%s\n' "$MARK_BEGIN"
    printf '# Added by bmake-it/scripts/install-env.sh -- do not edit by hand,\n'
    printf '# re-run the script instead (safe: it replaces this block in place).\n'
    printf 'if set -q MAKESYSPATH\n'
    printf '    set -gx MAKESYSPATH "%s:$MAKESYSPATH"\n' "$REPO_MK"
    printf 'else\n'
    printf '    set -gx MAKESYSPATH "%s:%s"\n' "$REPO_MK" "$DEFAULT_SYSPATH"
    printf 'end\n'
    printf '%s\n' "$MARK_END"
}

user_rc() {
    shell_name=$(basename "${SHELL:-sh}")
    case "$shell_name" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash) echo "$HOME/.bashrc" ;;
        fish) echo "$HOME/.config/fish/config.fish" ;;
        *)    echo "$HOME/.profile" ;;
    esac
}

install_user() {
    rc=$(user_rc)
    shell_name=$(basename "${SHELL:-sh}")
    echo "About to modify: $rc"
    echo "Will set: MAKESYSPATH=\"$MAKESYSPATH_VALUE\""
    confirm
    mkdir -p "$(dirname "$rc")"
    touch "$rc"
    strip_block "$rc"
    if [ "$shell_name" = fish ]; then
        { printf '\n'; block_fish; } >> "$rc"
    else
        { printf '\n'; block_sh; } >> "$rc"
    fi
    echo "===> updated $rc -- open a new shell, or run: . $rc"
}

uninstall_user() {
    rc=$(user_rc)
    if [ ! -f "$rc" ] || ! grep -qF "$MARK_BEGIN" "$rc" 2>/dev/null; then
        echo "nothing to remove in $rc"
        exit 0
    fi
    echo "About to remove the bmake-it block from: $rc"
    confirm
    strip_block "$rc"
    echo "===> removed bmake-it block from $rc"
}

install_system() {
    [ "$(uname -s)" = "Linux" ] || {
        echo "error: --system is only implemented for Linux (/etc/profile.d/) -- macOS/Windows system-level setup is not yet designed, use the default user-level install instead" >&2
        exit 1
    }
    [ "$(id -u)" = 0 ] || {
        echo "error: --system needs root -- re-run with sudo" >&2
        exit 1
    }
    target=/etc/profile.d/bmake-it.sh
    echo "About to write: $target"
    echo "Will set: MAKESYSPATH=\"$MAKESYSPATH_VALUE\""
    confirm
    block_sh > "$target"
    chmod 644 "$target"
    echo "===> wrote $target -- takes effect for every new login shell"
}

uninstall_system() {
    target=/etc/profile.d/bmake-it.sh
    [ -f "$target" ] || { echo "nothing to remove: $target does not exist"; exit 0; }
    [ "$(id -u)" = 0 ] || {
        echo "error: --system --uninstall needs root -- re-run with sudo" >&2
        exit 1
    }
    echo "About to remove: $target"
    confirm
    rm -f "$target"
    echo "===> removed $target"
}

if [ "$MODE" = system ]; then
    if [ "$ACTION" = uninstall ]; then uninstall_system; else install_system; fi
else
    if [ "$ACTION" = uninstall ]; then uninstall_user; else install_user; fi
fi
