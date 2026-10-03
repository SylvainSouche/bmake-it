#!/bin/sh
# framework-level-constraint-req, excluded-dependency-error-req: a
# framework-level PLATFORMS= skips the whole framework (none of its modules
# is entered, so an unresolvable import inside never runs); a framework that
# needs an excluded one and is not itself excluded is an ERROR naming both,
# while one that is itself excluded is just skipped; and a module that
# links a library its sibling excluded gets an error naming the library.
set -eu
cd ws
OS=$(bmake -V '${TARGET}')

mkfw() {  # name prereqs extra-lines
    mkdir -p "$1/app.m/src"
    printf 'PREREQS=%s\n%s\n.include <mk.framework.mk>\n' "$2" "$3" > "$1/makefile"
    printf 'PROG=app\n.include <mk.prog.mk>\n' > "$1/app.m/makefile"
    echo 'int main(void){return 0;}' > "$1/app.m/src/main.c"
}
# FwA: excluded here; holds a module that would fail if it were entered.
mkfw FwA "" "PLATFORMS=-$OS"
printf 'LIB=zzz\nIMPORT=pkg:does-not-exist-zzz\n.include <mk.lib.mk>\n' > FwA/app.m/makefile
mkfw FwB FwA ""                      # needs FwA, not excluded -> error
mkfw FwC FwA "PLATFORMS=-$OS"        # needs FwA but excluded itself -> skipped
mkfw FwD "" ""                       # independent

rc=0; bmake >build1.log 2>&1 || rc=$?
[ $rc != 0 ] || { echo "expected a failure (FwB needs excluded FwA)" >&2; exit 1; }
grep -q "===> framework FwA skipped: PLATFORMS excludes" build1.log
grep -q "===> framework FwB cannot be built: it needs FwA, which is not built here" build1.log
grep -q "give FwB the same PLATFORMS=/TOOLCHAINS=" build1.log
grep -q "===> framework FwC skipped: PLATFORMS excludes" build1.log
grep -q "===> building framework FwD" build1.log
[ -n "$(find FwD -type f -name app -path '*/bin/*' | head -1)" ]
[ ! -d FwA/app.m/build ] || { echo "an excluded framework's module was entered" >&2; exit 1; }
[ ! -d FwB/app.m/build ] || { echo "FwB was built" >&2; exit 1; }
# Only FwB is a failure; the excluded frameworks are not.
grep -q "workspace BUILD FAILED: FwB" build1.log
if grep "workspace BUILD FAILED" build1.log | grep -q "FwA\|FwC"; then
    echo "an excluded framework was reported as failed" >&2; exit 1
fi

# Without FwB, exclusions alone are not a failure.
rm -rf FwB
bmake >build2.log 2>&1 || { echo "exclusions alone must not fail the build" >&2; tail -5 build2.log >&2; exit 1; }
grep -q "framework FwA skipped" build2.log

# A module that links a library its sibling excluded.
mkdir -p FwD/libx.m/src
echo 'int x_fn(void){return 1;}' > FwD/libx.m/src/x.c
printf 'LIB=x\nPLATFORMS=-%s\n.include <mk.lib.mk>\n' "$OS" > FwD/libx.m/makefile
printf 'PROG=app\nLIBS=x\n.include <mk.prog.mk>\n' > FwD/app.m/makefile
printf 'int x_fn(void);\nint main(void){return x_fn();}\n' > FwD/app.m/src/main.c
rm -rf FwD/build FwD/*.m/build
rc=0; bmake >build3.log 2>&1 || rc=$?
[ $rc != 0 ] || { echo "expected app.m to fail linking an excluded library" >&2; exit 1; }
grep -q "cannot link app: library x is not built here" build3.log
grep -q "give it the same PLATFORMS=/TOOLCHAINS=" build3.log

echo "platform-constraints-workspace OK"
