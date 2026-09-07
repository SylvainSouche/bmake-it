#!/bin/sh
set -eu
cd ws
# Full workspace build must not try to enter A as a module of B etc.
bmake all
mods=$(bmake -C B -V SUBDIR_MODULES)
echo "B modules=$mods"
echo "$mods" | grep -q 'mod.m'
# Must not list framework names as modules
echo "$mods" | grep -qv '^A$' || true
case " $mods " in
  *" A "*|*" B "*) echo "framework name leaked into module list: $mods" >&2; exit 1 ;;
esac
echo "subdir isolation OK"
