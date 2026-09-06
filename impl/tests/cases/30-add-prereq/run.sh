#!/bin/sh
set -eu
cd fw

bmake add-prereq FW=Sys
grep -q '^PREREQS= Sys$' makefile

bmake add-prereq FW=Net
grep -q '^PREREQS= Sys Net$' makefile

if bmake add-prereq 2>err.log; then
    echo "add-prereq without FW= should have failed" >&2
    exit 1
fi
grep -qi usage err.log

echo "add-prereq OK"
