#!/bin/sh
# requires-header-form-req: REQUIRES=header:<path> is the deferred half
# of header-only-import-req's original two-part proposal (test 74 only
# implemented IMPORT_LIB=none). It checks that <path> is reachable via
# #include, by preprocessing (not compiling) a trivial translation unit
# with CC and the current CFLAGS/CXXFLAGS -- no package name, no CLI
# tool, just a header. Needed for a header-only library that ships no
# .pc file at all (glm on a distro with no optional compiled lib),
# where plain REQUIRES=glm has nothing to check via pkg-config or
# command -v.
#
# Uses a templated, namespaced header (not plain C) to prove the fix
# doesn't need to dispatch between CC and CXX: -E only preprocesses
# directives, so a C++-only body preprocesses fine even invoked in C
# mode.
set -eu
ROOT=$(pwd)
FAKE="$ROOT/fake/fakeheaders"

mkdir -p "$FAKE/include/vecmath"
cat > "$FAKE/include/vecmath/vec3.hpp" <<'EOF'
#pragma once
namespace vecmath {
template <typename T> struct Vec3 { T x, y, z; };
inline int ping() { return 42; }
}
EOF

cd ws

# --- positive case: header reachable via CXXFLAGS, mixed with a plain
# REQUIRES= software entry (pkg-config-found) to prove the two forms
# compose in one REQUIRES= list without interfering with each other --
mkdir -p "$ROOT/fake/bin"
cat > "$ROOT/fake/bin/reqtool" <<'EOF'
#!/bin/sh
echo "fake reqtool"
EOF
chmod +x "$ROOT/fake/bin/reqtool"
export PATH="$ROOT/fake/bin:$PATH"

cat > Fw/app.m/makefile <<EOF
PROG=app
REQUIRES=header:vecmath/vec3.hpp reqtool
CXXFLAGS+=-I$FAKE/include
.include <mk.prog.mk>
EOF

bmake >build1.log 2>&1
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
out=$("$bin")
echo "$out" | grep -q "^42$"

# --- same header, but reachable only via CFLAGS (not CXXFLAGS) -- proves
# the check searches both, not just one --
cat > Fw/app.m/makefile <<EOF
PROG=app
REQUIRES=header:vecmath/vec3.hpp
CFLAGS+=-I$FAKE/include
.include <mk.prog.mk>
EOF

cd Fw/app.m
bmake clean >/dev/null 2>&1
bmake all >../../build2.log 2>&1
cd ../..
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]

# --- negative case: the header genuinely isn't reachable (no -I at all)
# -- must fail at parse time, before any compile is attempted ------------
cat > Fw/app.m/makefile <<EOF
PROG=app
REQUIRES=header:vecmath/vec3.hpp
.include <mk.prog.mk>
EOF

cd Fw/app.m
bmake clean >/dev/null 2>&1
if bmake all 2>err.log; then
    echo "expected REQUIRES=header: with an unreachable header to fail the build" >&2
    exit 1
fi
grep -q "REQUIRES=header:vecmath/vec3.hpp" err.log
grep -q "header vecmath/vec3.hpp not found" err.log
if grep -q "main.o" err.log; then
    echo "expected the failure before any compile step, but one was attempted" >&2
    exit 1
fi
cd ../..

# --- negative case: a genuinely missing header name, distinct error from
# the software-name form's own message -----------------------------------
cat > Fw/app.m/makefile <<EOF
PROG=app
REQUIRES=header:does-not-exist-3f8a2b/missing.h
CXXFLAGS+=-I$FAKE/include
.include <mk.prog.mk>
EOF

cd Fw/app.m
bmake clean >/dev/null 2>&1
if bmake all 2>err2.log; then
    echo "expected REQUIRES=header: with a nonexistent header path to fail the build" >&2
    exit 1
fi
grep -q "REQUIRES=header:does-not-exist-3f8a2b/missing.h" err2.log
cd ../..

echo "requires-header-form OK"
