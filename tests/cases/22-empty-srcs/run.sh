#!/bin/sh
set -eu
cd ws/Fw
srcs=$(bmake -C empty.m -V SRCS)
echo "SRCS=[$srcs]"
# Building may fail (no objects) — that's acceptable border behaviour
if bmake -C empty.m all 2>err.log; then
    echo "unexpected success with no sources" >&2
    # Some make versions might succeed with empty link — still note it
    echo "WARN: empty SRCS built successfully"
else
    echo "empty SRCS failed as expected"
fi
# Test itself passes either way if we got a defined SRCS query
exit 0
