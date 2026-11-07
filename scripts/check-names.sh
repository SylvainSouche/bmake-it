#!/bin/sh
# check-names.sh -- stop a build in a directory whose name, or whose mk
# directory's name, Bmake It cannot carry (path-characters-refused-upfront-req).
#
# Reads the directory being built from the shell (pwd -P, make's .CURDIR is
# not used: make expands the *value* of a variable again when it is used, so a
# $ in a directory name is gone before any makefile text sees it) and the mk
# directory from BMK_MKDIR in the environment -- never a command-line argument:
# a path with a quote or a space in it is exactly what this must read safely.
# Prints one message and exits 1 when a name is refused, nothing and 0
# otherwise. $ is doubled in the message so that make's .error does not expand
# it again.
# @impl 0f87-6aee-e982-0f20
. "$(dirname "$0")/bmk-names.sh"
say() { printf '%s\n' "$1" | sed 's/\$/$$/g'; }
_here=$(pwd -P)
if ! _m=$(bmk_path_problem "$_here" path); then
    say "Bmake It cannot build in $_here: $_m. $BMK_NAME_HELP"
    exit 1
fi
if [ -n "${BMK_MKDIR:-}" ] && ! _m=$(bmk_path_problem "$BMK_MKDIR" mkdir); then
    say "Bmake It cannot use the mk files in $BMK_MKDIR: $_m. $BMK_NAME_HELP"
    exit 1
fi
exit 0
