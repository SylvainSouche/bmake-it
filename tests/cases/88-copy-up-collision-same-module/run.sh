#!/bin/sh
# copy-up-collision-different-modules-only-req (lasviewer round 6, item 6):
# after a legitimate one-source edit, relinking a program printed
# "copy-up collision: 'lasviewer' differs ... overwriting" at module AND
# framework level. A rebuilt artefact is expected to differ from its
# previous copy; the warning is for two DIFFERENT producers writing the
# same name. (a) editing a module and rebuilding is silent; (b) a second
# module producing the same program name still warns.
set -eu
cd ws

bmake >build1.log 2>&1
if grep -q "copy-up collision" build1.log; then echo "collision on a first build" >&2; exit 1; fi

# (a) legitimate rebuild: same module, different bytes.
sleep 1
echo 'int main(void){return 7;}' > Fw/a.m/src/main.c
bmake >build2.log 2>&1
if grep -q "copy-up collision" build2.log; then
    echo "a module overwriting its own output warned:" >&2
    grep "copy-up collision" build2.log >&2; exit 1
fi
# ... and the new program really is what is in the workspace bin.
bin=$(find build -type f -name app -path "*/bin/*" | head -1)
[ -n "$bin" ]
rc=0; "$bin" || rc=$?
[ "$rc" = 7 ]

# (b) a DIFFERENT module producing the same program name collides.
mkdir -p Fw/b.m/src
printf 'PROG=app\n.include <mk.prog.mk>\n' > Fw/b.m/makefile
echo 'int main(void){return 9;}' > Fw/b.m/src/main.c
sleep 1
bmake >build3.log 2>&1 || true
grep -q "copy-up collision: 'app' differs" build3.log

echo "copy-up-collision-same-module OK"
