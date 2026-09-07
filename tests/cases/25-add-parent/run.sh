#!/bin/sh
set -eu
cd ws

bmake add-parent WS=/abs/path/to/parent
grep -q '^PARENT_WS=/abs/path/to/parent$' makefile

if bmake add-parent 2>err.log; then
    echo "add-parent without WS= should have failed" >&2
    exit 1
fi
grep -qi usage err.log

echo "add-parent OK"
