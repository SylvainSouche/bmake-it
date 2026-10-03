#!/bin/sh
# fetch-build-prologue-terminated-req (lasviewer round 6, item 1):
# _FETCH_DEPLOY_EXPORT is spliced onto the _fetch_build: recipe line right
# before `case "$BUILD" in autotools) ...`. Off macOS its value was a bare
# ':' so the line became `: case ... in autotools) ...` -- case swallowed as
# an argument of ':' -- and dash (Ubuntu's /bin/sh) died with
# `Syntax error: ")" unexpected`: every FETCH_BUILD= module failed on
# Linux. macOS hid it because its value ends in ';'. The non-macOS values
# can be queried here for any TARGET, so this runs on every host.
set -eu
cd ws/Fw/libfoo.m
for t in linux freebsd netbsd macos; do
    v=$(bmake -V _FETCH_DEPLOY_EXPORT TARGET=$t 2>/dev/null)
    [ -n "$v" ] || { echo "no value for TARGET=$t" >&2; exit 1; }
    case "$v" in
        *\;) ;;
        *) echo "TARGET=$t: _FETCH_DEPLOY_EXPORT='$v' does not end in ';'" >&2; exit 1 ;;
    esac
    for sh in sh dash bash; do
        command -v "$sh" >/dev/null 2>&1 || continue
        out=$("$sh" -c "$v case cmake in autotools) echo wrong;; cmake) echo ok;; esac" 2>&1) || {
            echo "TARGET=$t under $sh: '$v case ...' is a syntax error: $out" >&2; exit 1; }
        [ "$out" = ok ] || { echo "TARGET=$t under $sh: got '$out'" >&2; exit 1; }
    done
done
echo "fetch-build-prologue-shell OK"
