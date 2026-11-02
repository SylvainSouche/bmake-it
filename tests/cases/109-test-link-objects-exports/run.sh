#!/bin/sh
# test-link-objects-req, msvc-explicit-export-limits-exports-req. A library
# that exports only part of what it defines: its tests reach the rest with
# TEST_LINK=objects, and cannot with the default. MSVC's generated export list
# exported everything anyway, hiding the difference (OpenRider, 2026-11-02).
# Needs kyua and ATF.
set -eu
. "$BMK_TESTLIB"
need_tool kyua "bmake test runs the tests through it"
atf_bundled || atf_pc --exists atf-c 2>/dev/null || exit 77

mkdir -p ws/Fw/libtwo.m/src ws/Fw/libtwo.m/tests ws/Fw/liball.m/src
printf 'PARENT_WS=\n.include "mk.workspace.mk"\n' > ws/makefile
printf 'PREREQS=\n.include <mk.framework.mk>\n' > ws/Fw/makefile

cat > ws/Fw/libtwo.m/makefile <<'EOF'
LIB=two
LIB_SHARED=YES
SHLIB_MAJOR=1
TESTS_C=two_test
TEST_LINK=objects
.include <mk.lib.mk>
EOF
cat > ws/Fw/libtwo.m/src/two.c <<'EOF'
#if defined(_WIN32) || defined(__CYGWIN__)
#define PUBLIC __declspec(dllexport)
#define INTERNAL
#else
#define PUBLIC __attribute__((visibility("default")))
#define INTERNAL __attribute__((visibility("hidden")))
#endif
INTERNAL int two_internal(void) { return 2; }
PUBLIC int two_public(void) { return two_internal(); }
EOF
cat > ws/Fw/libtwo.m/tests/two_test.c <<'EOF'
#include <atf-c.h>
int two_internal(void);
ATF_TC_WITHOUT_HEAD(inner);
ATF_TC_BODY(inner, tc) { ATF_REQUIRE_EQ(2, two_internal()); }
ATF_TP_ADD_TCS(tp) { ATF_TP_ADD_TC(tp, inner); return atf_no_error(); }
EOF
cat > ws/Fw/liball.m/makefile <<'EOF'
LIB=all
LIB_SHARED=YES
SHLIB_MAJOR=1
.include <mk.lib.mk>
EOF
cat > ws/Fw/liball.m/src/all.c <<'EOF'
int all_one(void) { return 1; }
int all_two(void) { return 2; }
EOF

cd ws
# --- objects: the test reaches the internal ---------------------------------------
bmake test >objects.log 2>&1 || { cat objects.log >&2; echo "TEST_LINK=objects should link and pass" >&2; exit 1; }
grep -q 'two_test:inner  *->  *passed' objects.log || { cat objects.log >&2; exit 1; }

# --- library: the same test cannot link, the internal is not exported ---------------
rc=0; ( cd Fw/libtwo.m && bmake test TEST_LINK=library >../../library.log 2>&1 ) || rc=$?
[ $rc != 0 ] || { cat library.log >&2; echo "with TEST_LINK=library the internal must not link" >&2; exit 1; }

# --- a bad value is an error ----------------------------------------------------------
rc=0; ( cd Fw/libtwo.m && bmake TEST_LINK=objs >../../bad.log 2>&1 ) || rc=$?
[ $rc != 0 ] && grep -q 'TEST_LINK=objs: expected library' bad.log || {
    cat bad.log >&2; echo "a misspelt TEST_LINK must be an error" >&2; exit 1; }

# --- Windows: what each DLL exports, on every runtime ----------------------------------
if [ "$BMK_T_OS" = win ] && command -v objdump >/dev/null 2>&1; then
    exports() {
        d=$(find Fw -name "*$1*.dll" | head -1)
        [ -n "$d" ] || { echo "no DLL for $1" >&2; exit 1; }
        LC_ALL=C objdump -p "$d"
    }
    t=$(exports two)
    printf '%s\n' "$t" | grep -q 'two_public' || { printf '%s\n' "$t" >&2; echo "two_public must be exported" >&2; exit 1; }
    ! printf '%s\n' "$t" | grep -q 'two_internal' || { echo "an explicit dllexport limits the exports: two_internal must not be" >&2; exit 1; }
    a=$(exports all)
    printf '%s\n' "$a" | grep -q 'all_one' && printf '%s\n' "$a" | grep -q 'all_two' || {
        printf '%s\n' "$a" >&2; echo "a DLL with no explicit export exports what it defines" >&2; exit 1; }
fi

echo "test-link-objects-exports OK"
