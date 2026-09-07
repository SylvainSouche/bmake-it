#!/bin/sh
set -eu
cd ws/Fw
if sh "${BMK_SCRIPTS}/gen-mod-order.sh" .order.mk 2>err.log; then
    echo "expected cycle failure" >&2
    cat .order.mk >&2 || true
    exit 1
fi
grep -qi cycle err.log
echo "cycle detected as expected"
