#!/bin/sh
set -eu
cd ws
bmake all

# from the workspace root
out=$(bmake run PROGRAM=app)
echo "$out" | grep -q "Hello, Bmake It!"

# from a framework directory -- run: must walk up and delegate
out=$(cd Fw && bmake run PROGRAM=app)
echo "$out" | grep -q "Hello, Bmake It!"

# from a module directory, with ARGS= passthrough as separate words
out=$(cd Fw/app.m && bmake run PROGRAM=app ARGS="foo bar")
echo "$out" | grep -q "Hello, Bmake It!"
echo "$out" | grep -q "^arg: foo$"
echo "$out" | grep -q "^arg: bar$"

# missing PROGRAM=
if bmake run 2>err.log; then
    echo "run without PROGRAM= should have failed" >&2
    exit 1
fi
grep -qi usage err.log

# nonexistent program
if bmake run PROGRAM=nope 2>err.log; then
    echo "run with a nonexistent PROGRAM= should have failed" >&2
    exit 1
fi
grep -qi "does not exist" err.log

echo "run-target OK"
