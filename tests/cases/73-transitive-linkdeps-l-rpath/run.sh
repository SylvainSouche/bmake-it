#!/bin/sh
# transitive-linkdeps-missing-L-fix-req: a .linkdeps consumer two hops
# removed from where a transitive dependency actually lives must still
# both LINK and RUN -- app.m here lists only Fw2 (mid) in its own
# PREREQS=/LIBS=, never Fw1 (base) directly, so the only way it can
# find base's own directory is via mid's own .linkdeps carrying both
# -L<dir> (link time) and -Wl,-rpath,<dir> (run time) forward. Found in
# real use (lasviewer): ".linkdeps reach consumers without the
# directory of the libraries they name -- harmless only because Viewer
# lists GIS directly", i.e. it worked only by coincidence. Proven here
# by actually RUNNING the result, not just linking it -- a -L-only fix
# links but dyld still can't load a shared transitive dependency found
# only this way.
set -eu
. "$BMK_TESTLIB"
ROOT=$(pwd)

cd ws
bmake >build1.log 2>&1
bin=$(find . -path "*Fw3/app.m*" -name "$(prog_name app)" | head -1)
[ -n "$bin" ]
if [ "$BMK_T_OS" = win ]; then
    # Windows has no rpath: the loader searches PATH, so the run needs the
    # framework lib directories there -- the link half is still proven above.
    libs=$(find . -type d -path "*/build/*/lib" | tr '\n' ':')
    out=$(with_libdir "${libs%:}" "$bin")
else
    out=$("$bin")
fi
echo "$out" | grep -q "base"

echo "transitive-linkdeps-l-rpath OK"
