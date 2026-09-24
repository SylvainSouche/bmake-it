#!/bin/sh
# header-dependency-tracking-req: -MMD -MP per source, conditionally
# .include'd -- a module-private header change AND a framework-public
# header reached only via PREREQS (not this module's own src/) both
# trigger exactly the affected object to rebuild; an unrelated rebuild
# with nothing changed recompiles nothing at all.
set -eu
cd ws

bmake >build1.log 2>&1
bin=$(find App -type f -name app | head -1)
[ -n "$bin" ]
out=$("$bin")
echo "$out" | grep -q "v1 L1"

# --- no-op rebuild: nothing changed, nothing should recompile ---
sleep 1
bmake >build2.log 2>&1
if grep -q "\-c .*main\.c" build2.log; then
    echo "no-op rebuild should not have recompiled main.c" >&2
    cat build2.log >&2
    exit 1
fi

# --- module-private header changes ---
sleep 1
sed -i.bak 's/L1/L2-CHANGED/' App/app.m/include/local.h
bmake >build3.log 2>&1
grep -q "\-c .*main\.c" build3.log
out=$("$bin")
echo "$out" | grep -q "v1 L2-CHANGED"

# --- framework-public header changes (Pub/include, reached only via
# App's PREREQS=Pub, not App/app.m's own src/ or include/) ---
sleep 1
sed -i.bak 's/v1/v2-CHANGED/' Pub/include/api.h
bmake >build4.log 2>&1
grep -q "\-c .*main\.c" build4.log
out=$("$bin")
echo "$out" | grep -q "v2-CHANGED L2-CHANGED"

echo "header-dependency-tracking OK"
