#!/bin/sh
# atf-selftest.sh OUTDIR -- atf-bmk's own test suite (atf-bmk-self-test-
# req): bootstraps the ATF Bmake It carries and runs ATF 0.23's own tests
# against it, as released (contrib/atf-0.23: the atf-c and atf-c++ test
# programs, test-programs/), then atf-bmk's own layer tests
# (contrib/atf-bmk/tests), with Kyua. Not Bmake It's suite: that one tests
# the integration (bmake test), this one the library.
#
# Environment, as for scripts/atf-build.sh: CC, CXX, AR, TOOLCHAIN (msvc or
# not), ATF_BMK_MODE (posix or win). KYUA (default kyua).
#
#   1. builds atf-bmk into OUTDIR/atf (scripts/atf-build.sh)
#   2. builds the test programs into OUTDIR/tests, laid out as ATF installs
#      them, with their data files and Kyuafiles
#   3. runs them: kyua test, OUTDIR/results.txt and OUTDIR/test-results.xml
#   4. compares with contrib/atf-bmk/expected/<mode>.txt, the differences
#      from upstream that are known, each with its reason. Exit status 0 only
#      when nothing else differs: a test program that does not build, a
#      test case with another result than listed, and a listed difference
#      that no longer happens (the list is kept exact) are each reported.
# @impl 7854-6ae4-cee4-3405
set -eu

OUT=${1:?usage: atf-selftest.sh OUTDIR}
MODE=${ATF_BMK_MODE:-posix}
KYUA=${KYUA:-kyua}
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/../contrib/atf-0.23
BMK=$HERE/../contrib/atf-bmk
EXPECTED=$BMK/expected/$MODE.txt
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
A=$OUT/atf
T=$OUT/tests
LOG=$OUT/build.log

command -v "$KYUA" >/dev/null 2>&1 || { echo "error: atf-selftest: $KYUA is not installed -- the test programs are run by it" >&2; exit 1; }

# --- 1. the library ----------------------------------------------------------------
# ATF_BMK_MODE=installed: the same tests against the installed (upstream)
# ATF instead -- the baseline that tells this host's own behaviour (both
# fail) from a difference of atf-bmk (only atf-bmk fails).
if [ "$MODE" = installed ]; then
    _k=$(command -v "$KYUA")
    PKG_CONFIG_PATH="$(dirname "$(dirname "$_k")")/lib/pkgconfig:$(dirname "$(dirname "$_k")")/libdata/pkgconfig:/usr/local/lib/pkgconfig:/usr/local/libdata/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    export PKG_CONFIG_PATH
    pkg-config --exists atf-c atf-c++ || { echo "error: atf-selftest: ATF_BMK_MODE=installed, and pkg-config finds no installed atf-c/atf-c++" >&2; exit 1; }
    mkdir -p "$A"
    _inc=$(pkg-config --variable=includedir atf-c)
    {
        echo "#define ATF_BUILD_CC \"$CC\""
        echo "#define ATF_BUILD_CFLAGS \"\""
        echo "#define ATF_BUILD_CPP \"$CC -E\""
        echo "#define ATF_BUILD_CPPFLAGS \"-I$_inc\""
        echo "#define ATF_BUILD_CXX \"$CXX\""
        echo "#define ATF_BUILD_CXXFLAGS \"\""
        echo "#define ATF_INCLUDEDIR \"$_inc\""
        echo '#define PACKAGE_VERSION "0.23"'
        echo '#define PACKAGE_BUGREPORT "freebsd-testing@freebsd.org"'
    } > "$A/config.h"
else
    sh "$HERE/atf-build.sh" "$A"
fi

# --- 2. the test programs -----------------------------------------------------------
rm -rf "$T"; mkdir -p "$T"
: > "$LOG"
: > "$OUT/notbuilt.txt"
if [ "${TOOLCHAIN:-}" = msvc ]; then LIBC=$A/atf-c.lib; LIBCXX=$A/atf-c++.lib; else LIBC=$A/libatf-c.a; LIBCXX=$A/libatf-c++.a; fi
# what a test program of ATF's compiles with: the staged headers, and the
# sources' own for the detail/ helpers; ATF_BUILD_* and ATF_INCLUDEDIR from
# the library's config.h (posix) or here (win)
TCPPFLAGS="-I$A/include -I$SRC -DHAVE_CONFIG_H"
if [ "$MODE" = installed ]; then
    TCPPFLAGS="$(pkg-config --cflags atf-c++ atf-c) -I$SRC -DHAVE_CONFIG_H"
    LIBC=$(pkg-config --libs atf-c); LIBCXX=$(pkg-config --libs atf-c++)
fi
if [ "$MODE" = win ]; then
    {
        cat "$BMK/win/config.h"
        echo "#define ATF_BUILD_CC \"cc\""
        echo "#define ATF_BUILD_CFLAGS \"\""
        echo "#define ATF_BUILD_CPP \"cpp\""
        echo "#define ATF_BUILD_CPPFLAGS \"\""
        echo "#define ATF_BUILD_CXX \"c++\""
        echo "#define ATF_BUILD_CXXFLAGS \"\""
        echo "#define ATF_INCLUDEDIR \"$(cygpath -m "$A/include")\""
    } > "$OUT/config.h"
    CONFIG_H=$OUT/config.h
else
    CONFIG_H=$A/config.h
fi
# (ATF's makefiles pass these with -D: the helpers do not include config.h)
if [ "${TOOLCHAIN:-}" = msvc ]; then
    TCPPFLAGS="-I$(dirname "$CONFIG_H") $TCPPFLAGS /FI$(cygpath -m "$CONFIG_H")"
else
    TCPPFLAGS="-I$(dirname "$CONFIG_H") $TCPPFLAGS -include $CONFIG_H"
fi
# Windows: ATF's own tests expect POSIX declarations -- the test shim
# (contrib/atf-bmk/win/test-shim), for these tests only
if [ "$MODE" = win ]; then
    SHIM=$BMK/win/test-shim
    if [ "${TOOLCHAIN:-}" = msvc ]; then
        TCPPFLAGS="-I$(cygpath -m "$SHIM") -I$(cygpath -m "$BMK/win/msvc") $TCPPFLAGS /FI$(cygpath -m "$SHIM/atfw-test-shim.h")"
    else
        TCPPFLAGS="-I$SHIM $TCPPFLAGS -include $SHIM/atfw-test-shim.h"
    fi
fi
# (libatf-c's regex is C++ on Windows: a C program links the C++ runtime)
CXXRT=""
if [ "$MODE" = win ] && [ "${TOOLCHAIN:-}" != msvc ]; then
    CXXRT=$(echo 'int main(){return 0;}' | $CXX -x c++ - -o /dev/null -### 2>&1 | grep -o '"-lc++"\|"-lstdc++"' | head -1 | tr -d '"')
fi
LDEXTRA=""
case "$CC" in *mingw*|*w64*) LDEXTRA="-pthread" ;; esac
[ "$MODE" = win ] && [ "${TOOLCHAIN:-}" != msvc ] && LDEXTRA="-pthread -femulated-tls"

# prog <dir> <name> <c|c++> <sources...>: build one test program, or note it
# in notbuilt.txt with the first compiler error
prog() {
    d=$1; n=$2; l=$3; shift 3
    mkdir -p "$T/$d"
    srcs=""; for s in "$@"; do srcs="$srcs $SRC/$s"; done
    if [ "$l" = c ]; then
        cmd="$CC $TCPPFLAGS $srcs -o $T/$d/$n $HELPC $LIBC $CXXRT $LDEXTRA"
    else
        cmd="$CXX $TCPPFLAGS $srcs -o $T/$d/$n $HELPCXX $LIBCXX $LDEXTRA"
        [ "$MODE" = installed ] || cmd="$cmd $LIBC"
    fi
    echo "--- $d/$n: $cmd" >> "$LOG"
    # shellcheck disable=SC2086
    if ! $cmd >> "$LOG" 2>&1; then
        why=$(awk -v n="$d/$n" '/^--- / { this = index($0, "--- " n ":") == 1; next } this' "$LOG" | grep -iE 'error' | head -1 | sed "s|$SRC/||g" | cut -c1-200)
        echo "$d/$n not-built # ${why:-see build.log}" >> "$OUT/notbuilt.txt"
    fi
}

# the test helper libraries ATF's tests link
mkdir -p "$OUT/helpers"
HELPC=""; HELPCXX=""
echo "--- helpers" >> "$LOG"
# shellcheck disable=SC2086
if $CC $TCPPFLAGS -c "$SRC/atf-c/detail/test_helpers.c" -o "$OUT/helpers/test_helpers_c.o" >> "$LOG" 2>&1; then
    HELPC=$OUT/helpers/test_helpers_c.o
else
    echo "helpers/test_helpers.c not-built # every atf-c test program needs it" >> "$OUT/notbuilt.txt"
fi
# shellcheck disable=SC2086
if $CXX $TCPPFLAGS -c "$SRC/atf-c++/detail/test_helpers.cpp" -o "$OUT/helpers/test_helpers_cxx.o" >> "$LOG" 2>&1; then
    HELPCXX=$OUT/helpers/test_helpers_cxx.o
else
    echo "helpers/test_helpers.cpp not-built # every atf-c++ test program needs it" >> "$OUT/notbuilt.txt"
fi

for n in atf_c_test build_test check_test error_test macros_test tc_test tp_test utils_test; do
    prog atf-c $n c atf-c/$n.c
done
cp "$SRC/atf-c/macros_h_test.c" "$SRC/atf-c/unused_test.c" "$T/atf-c/"
for n in dynstr_test env_test fs_test list_test map_test process_test sanity_test text_test user_test; do
    prog atf-c/detail $n c atf-c/detail/$n.c
done
prog atf-c/detail process_helpers c atf-c/detail/process_helpers.c
prog atf-c/detail version_helper c atf-c/detail/version_helper.c
for n in atf_c++_test build_test check_test macros_test tests_test utils_test; do
    prog atf-c++ $n c++ atf-c++/$n.cpp
done
cp "$SRC/atf-c++/macros_hpp_test.cpp" "$SRC/atf-c++/unused_test.cpp" "$T/atf-c++/"
for n in application_test env_test exceptions_test fs_test process_test text_test; do
    prog atf-c++/detail $n c++ atf-c++/detail/$n.cpp
done
prog atf-c++/detail version_helper c++ atf-c++/detail/version_helper.cpp
prog test-programs c_helpers c test-programs/c_helpers.c
prog test-programs cpp_helpers c++ test-programs/cpp_helpers.cpp

# test-programs/*_test and sh_helpers: atf-sh scripts, the test program and
# common.sh, run by the installed atf-sh (Bmake It does not carry atf-sh)
ATFSH=$(command -v atf-sh 2>/dev/null || true)
for n in sh_helpers config_test expect_test meta_data_test result_test srcdir_test; do
    if [ -z "$ATFSH" ]; then
        echo "test-programs/$n not-built # atf-sh is not installed" >> "$OUT/notbuilt.txt"
        continue
    fi
    { echo "#! $ATFSH"; cat "$SRC/test-programs/$n.sh" "$SRC/test-programs/common.sh"; } > "$T/test-programs/$n"
    chmod +x "$T/test-programs/$n"
done

# atf-bmk's own tests (contrib/atf-bmk/tests): helpers built like ATF's
# test-programs (by SRC-relative path, so prog() is given ../atf-bmk/...),
# and atf-sh scripts driving them
BT=$BMK/tests
mkdir -p "$T/atf-bmk"
for h in "$BT"/*_helpers.c "$BT"/*_helpers.cpp; do
    [ -f "$h" ] || continue
    n=$(basename "$h"); n=${n%.*}
    case $h in *.cpp) l=c++ ;; *) l=c ;; esac
    prog atf-bmk "$n" $l "../atf-bmk/tests/$(basename "$h")"
done
for s in "$BT"/*_test.sh; do
    [ -f "$s" ] || continue
    n=$(basename "$s" .sh)
    if [ -z "$ATFSH" ]; then
        echo "atf-bmk/$n not-built # atf-sh is not installed" >> "$OUT/notbuilt.txt"
        continue
    fi
    { echo "#! $ATFSH"; cat "$s"; } > "$T/atf-bmk/$n"
    chmod +x "$T/atf-bmk/$n"
done

# The Kyuafiles: ATF's own, less what does not apply (pkg_config_test checks
# an installed atf-c.pc; atf-sh is not carried) and what was not built
for d in atf-c atf-c/detail atf-c++ atf-c++/detail test-programs; do
    {
        echo 'syntax(2)'
        echo 'test_suite("atf")'
        grep -o 'atf_test_program{name="[^"]*"}' "$SRC/$d/Kyuafile" | sed 's/.*name="\([^"]*\)".*/\1/' |
        while read -r n; do
            [ "$n" = pkg_config_test ] && continue
            grep -q "^$d/$n not-built" "$OUT/notbuilt.txt" && continue
            echo "atf_test_program{name=\"$n\"}"
        done
        case $d in atf-c|atf-c++) echo 'include("detail/Kyuafile")' ;; esac
    } > "$T/$d/Kyuafile"
done
{
    echo 'syntax(2)'
    echo 'test_suite("atf")'
    for s in "$T"/atf-bmk/*_test; do
        [ -f "$s" ] && echo "atf_test_program{name=\"$(basename "$s")\"}"
    done
} > "$T/atf-bmk/Kyuafile"
{
    echo 'syntax(2)'
    echo 'test_suite("atf")'
    echo 'include("atf-c/Kyuafile")'
    echo 'include("atf-c++/Kyuafile")'
    echo 'include("test-programs/Kyuafile")'
    echo 'include("atf-bmk/Kyuafile")'
} > "$T/Kyuafile"

# --- 3. run --------------------------------------------------------------------------
echo "===> running ATF 0.23's own tests against atf-bmk ($MODE): $T"
if [ "$MODE" = win ]; then ATFW_CYGROOT=$(cygpath -m /); export ATFW_CYGROOT; fi
rc=0
rm -f "$OUT/results.db"
(cd "$T" && $KYUA test -k Kyuafile --results-file="$OUT/results.db") > "$OUT/kyua.log" 2>&1 || rc=$?
(cd "$T" && $KYUA report-junit --results-file="$OUT/results.db" --output="$OUT/test-results.xml") >/dev/null 2>&1 || true
# "<program>:<case>  ->  <result>[: reason]  [time]" -> "<program>:<case> <result>[: reason]"
grep -E '^[^ ]+:[^ ]+  ->  ' "$OUT/kyua.log" | sed -E 's/  ->  / /; s/  \[[0-9.]+s\]$//' | sort > "$OUT/results.txt"
cat "$OUT/notbuilt.txt" | sed 's/ # .*//' >> "$OUT/results.txt"

# --- 4. compare with the expected differences ---------------------------------------
# expected/<mode>.txt: "<program>:<case> <result prefix> # reason" or
# "<dir>/<program> not-built # reason"; anything not listed must pass. A line
# starting "[<host>] " applies only on that host (uname -s, lower case,
# containing <host>): the host's own behaviour, which upstream ATF shows too.
: > "$OUT/regressions.txt"; : > "$OUT/stale.txt"; : > "$OUT/known.txt"
host=$(uname -s | tr 'A-Z' 'a-z')
exp_lines=""
if [ -f "$EXPECTED" ]; then
    exp_lines=$(grep -v '^[[:space:]]*\(#\|$\)' "$EXPECTED" | sed 's/[[:space:]]*#.*//' |
        while IFS= read -r l; do
            case "$l" in
                "["*"] "*) tag=${l%%]*}; tag=${tag#[}; case "$host" in *"$tag"*) echo "${l#*] }" ;; esac ;;
                *) echo "$l" ;;
            esac
        done || true)
fi
while IFS= read -r line; do
    id=${line%% *}; res=${line#* }
    exp=$(printf '%s\n' "$exp_lines" | awk -v id="$id" '$1 == id { $1 = ""; sub(/^ /, ""); print; exit }')
    if [ -n "$exp" ]; then
        case "$res" in
            "$exp"*) echo "$line" >> "$OUT/known.txt" ;;
            *) echo "$id: expected \"$exp\", got \"$res\"" >> "$OUT/regressions.txt" ;;
        esac
    else
        case "$res" in
            passed|skipped*) ;;
            *) echo "$id: $res" >> "$OUT/regressions.txt" ;;
        esac
    fi
done < "$OUT/results.txt"
printf '%s\n' "$exp_lines" | while read -r id exp; do
    [ -n "$id" ] || continue
    got=$(awk -v id="$id" '$1 == id { $1 = ""; sub(/^ /, ""); print; exit }' "$OUT/results.txt")
    case "$got" in
        "$exp"*) ;;
        "") echo "$id: listed as \"$exp\", but it did not run at all" >> "$OUT/stale.txt" ;;
        *) echo "$id: listed as \"$exp\", now \"$got\" -- update $EXPECTED" >> "$OUT/stale.txt" ;;
    esac
done

total=$(wc -l < "$OUT/results.txt" | tr -d ' ')
known=$(wc -l < "$OUT/known.txt" | tr -d ' ')
nreg=$(wc -l < "$OUT/regressions.txt" | tr -d ' ')
nstale=$(wc -l < "$OUT/stale.txt" | tr -d ' ')
echo "===> atf-bmk self-test ($MODE): $total results, $known known differences (expected/$MODE.txt), $nreg regressions, $nstale stale entries"
[ "$nreg" = 0 ] || { echo "regressions:"; sed 's/^/  /' "$OUT/regressions.txt"; }
[ "$nstale" = 0 ] || { echo "stale entries in expected/$MODE.txt:"; sed 's/^/  /' "$OUT/stale.txt"; }
echo "     results: $OUT/results.txt, JUnit: $OUT/test-results.xml, build log: $LOG"
[ "$nreg" = 0 ] && [ "$nstale" = 0 ]
