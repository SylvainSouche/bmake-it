#!/bin/sh
set -eu
cd ws
bmake all
mkdir -p Fw/p.m/build/other-arch/obj
echo keep > Fw/p.m/build/other-arch/obj/x

# Plain `clean` touches only the current/selected target (clean-target-scope-req):
# the just-built target's objects go away, a different target key's output survives.
bmake -C Fw/p.m clean
if find Fw/p.m/build/*-*/obj -name '*.o' 2>/dev/null | grep -v '/other-arch/' | grep -q .; then
    echo "current target's objects not cleaned" >&2
    exit 1
fi
[ -f Fw/p.m/build/other-arch/obj/x ]
echo "scoped clean OK"

# `clean TARGET=all` is the explicit opt-in to wipe every target at once
# (clean-removes-all-derived-artifacts-req: "TARGET=all ... wipes build/
# output for every target present").
bmake all
mkdir -p Fw/p.m/build/other-arch/obj
echo keep > Fw/p.m/build/other-arch/obj/x
bmake -C Fw/p.m clean TARGET=all
if [ -f Fw/p.m/build/other-arch/obj/x ]; then
    echo "TARGET=all did not wipe other target keys" >&2
    exit 1
fi
if find Fw/p.m/build -mindepth 1 2>/dev/null | grep -q .; then
    echo "TARGET=all left build output behind" >&2
    exit 1
fi
echo "clean TARGET=all OK"
