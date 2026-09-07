#!/bin/sh
set -eu
cd ws/Fw
bmake -C libh.m all
bmake -C libh.m copy-up
if bmake -C user.m all 2>err.log; then
    echo "FAIL: private header visible via LIBS" >&2
    exit 1
fi
echo "LIBS-does-not-expose-headers OK"
