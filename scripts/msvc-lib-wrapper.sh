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

# The MSVC environment, as msvc-cc-wrapper.sh takes it.
[ -z "${BMK_MSVC_BIN:-}" ] || PATH="$BMK_MSVC_BIN:$PATH"
[ -z "${BMK_MSVC_LIB:-}" ] || export LIB="$BMK_MSVC_LIB"
# lib.exe, or for TOOLCHAIN=llvm ABI=msvc "lld-link /lib" (BMK_MSVC_LIBEXE,
# set by mk.toolchain.msvc.mk: clang-msvc-toolchain-req)
LIBEXE=${BMK_MSVC_LIBEXE:-lib.exe}

# First arg is ar's own flag bundle (always "rcs" as invoked from
# mk.lib.mk) -- lib.exe has no equivalent, so it's simply discarded.
shift

archive=$1
shift

# (Cygwin's lld-link takes POSIX paths, lib.exe Windows ones: see
# msvc-cc-wrapper.sh)
if [ -n "${BMK_MSVC_LIBEXE:-}" ]; then
    winpath() { cygpath -ua "$1"; }
else
    winpath() { cygpath -w "$1"; }
fi

objs=""
for o in "$@"; do
    objs="$objs \"$(winpath "$o")\""
done

eval "$LIBEXE /nologo /out:\"$(winpath "$archive")\" $objs"
