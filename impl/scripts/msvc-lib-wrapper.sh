#!/bin/sh
# msvc-lib-wrapper.sh — presents lib.exe as an `ar rcs ARCHIVE OBJS...`
# compatible AR, matching the one invocation shape mk.lib.mk actually
# uses. Only used for LIB_SHARED=NO (true static archives) -- the shared
# case's import library comes from link.exe's own /IMPLIB: instead (see
# msvc-cc-wrapper.sh), never from this script, to avoid both trying to
# produce the same *.lib path.
#
# @impl 0f87-6a98-96de-1865
set -eu

# First arg is ar's own flag bundle (always "rcs" as invoked from
# mk.lib.mk) -- lib.exe has no equivalent, so it's simply discarded.
shift

archive=$1
shift

winpath() {
    cygpath -w "$1"
}

objs=""
for o in "$@"; do
    objs="$objs \"$(winpath "$o")\""
done

eval "lib.exe /nologo /out:\"$(winpath "$archive")\" $objs"
