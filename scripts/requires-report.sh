#!/bin/sh
# requires-report.sh <list> -- print what the preflight found missing, then
# exit 1; exit 0 when nothing is (requires-preflight-req).
#
# <list>: one line per missing prerequisite, "<where> <entry>%<how>", written
# by mk.framework.mk's _check_requires from each module's _REQUIRES_REPORT
# (mk.requires.mk). <how>: header=a,b (prefixes tried), pkg, path, path=a,b,c, nopkgconfig=<cmd>,
# sysroot=<dir>, import, tool, query=<message, spaces as \037>. <where> "*"
# is the workspace itself (a tool `bmake test` needs).
#
# One list, before anything is built: a missing prerequisite must stop the
# build and say so, not be lost in the compile errors of every module that
# needed it (OpenRider on FreeBSD, 2026-10-29).
# @impl 7854-6ae3-0b4f-513f
set -u
list=$1
[ -s "$list" ] || exit 0

describe() {  # describe <how>
    case "$1" in
        header=*)      echo "header not found -- tried CC/CXX with the module's CFLAGS/CXXFLAGS, and <prefix>/include for: $(echo "${1#header=}" | sed 's/,/, /g')" ;;
        header)        echo "header not found -- tried CC/CXX with the module's CFLAGS/CXXFLAGS" ;;
        pkg)           echo "not found by pkg-config, nor as a program on PATH" ;;
        nopkgconfig=*) echo "not checked: ${1#nopkgconfig=} is not installed (install pkgconf / pkg-config)" ;;
        sysroot=*)     echo "not in the target's sysroot ${1#sysroot=} (pkg-config)" ;;
        path=*)        echo "none of $(echo "${1#path=}" | sed 's/,/, /g') is on PATH" ;;
        path)          echo "not found on PATH" ;;
        import)        echo "the import does not resolve (pkg-config, *_PREFIX, hooks, prefixes)" ;;
        atf)           echo "ATF library for this test module: no .pc file, and -l<it> does not link (FreeBSD: pkg install atf; NetBSD: pkg_add atf; Debian: apt install libatf-dev)" ;;
        atfrt=*)       echo "ATF library for this test module: only its run-time library is installed (${1#atfrt=}), not the headers and .pc file -- FreeBSD: that is the base system's FreeBSD-atf, pkg install atf; Debian: apt install libatf-dev" ;;
        tool)          echo "program not found on PATH" ;;
        query=*)       echo "could not be checked: $(printf '%s' "${1#query=}" | tr '\037' ' ')" ;;
        *)             echo "$1" ;;
    esac
}

{
    echo "===> missing prerequisites -- nothing was built:"
    sort -u "$list" | while read -r where item; do
        entry=${item%%%*}; how=${item#*%}
        [ "$where" = "*" ] && where="(bmake test)"
        printf '     %s: %s -- %s\n' "$where" "$entry" "$(describe "$how")"
    done
    if grep -q '%nopkgconfig=' "$list"; then
        echo "     pkg-config itself is missing: every library above went unchecked, they may well be installed."
    fi
    echo "     Install them with this host's package manager (README.md, Prerequisites), then build again."
} >&2
exit 1
