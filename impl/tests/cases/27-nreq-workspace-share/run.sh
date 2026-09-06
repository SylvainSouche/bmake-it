#!/bin/sh
set -eu
cd ws
mkdir -p share/common
echo "leaked" > share/common/leftover.txt

bmake >build.log 2>&1

if find build -name leftover.txt 2>/dev/null | grep -q .; then
    echo "workspace-root share/ was incorrectly overlaid into build output" >&2
    exit 1
fi

echo "no-workspace-level-share-source OK"
