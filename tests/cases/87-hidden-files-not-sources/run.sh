#!/bin/sh
# hidden-files-not-sources-req (lasviewer round 6, item 5): a tar
# extraction elsewhere leaves macOS AppleDouble sidecars (._main.c) beside
# the sources; they were auto-discovered and compiled ("source file is not
# valid UTF-8"). Dot-files and dot-directories under src/ are not source.
set -eu
cd ws
printf '\000\001\002 this is binary metadata, not C \377\376\n' > Fw/app.m/src/._main.c
printf 'this would not compile either\n' > Fw/app.m/src/._extra.cpp
mkdir -p Fw/app.m/src/.hidden
printf 'int hidden_dir_symbol(void) { return syntax error; }\n' > Fw/app.m/src/.hidden/x.c
bmake >build1.log 2>&1
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
"$bin" | grep -q "^ok$"
if grep -q '\._\|\.hidden' build1.log; then
    echo "a hidden file was compiled:" >&2; grep '\._\|\.hidden' build1.log >&2; exit 1
fi
echo "hidden-files-not-sources OK"
