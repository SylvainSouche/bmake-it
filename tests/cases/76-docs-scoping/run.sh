#!/bin/sh
# bmake-docs-scoping-fix-req: three real bugs found running `bmake
# docs` on lasviewer, all exercised together:
#  - the workspace landing page is written under WS_DOCS_DIR
#    (build/docs/ by default), never colliding with a project's own
#    hand-written docs/ (found in real use: the landing page silently
#    overwrote content inside the project's own docs/);
#  - a framework with no public include/ (FwC: an app-only framework,
#    like a real Viewer) is skipped automatically, with one clear
#    message, instead of an empty Doxygen page plus "INPUT ... does
#    not exist"/"No files to be processed" warnings;
#  - DOCS=no (FwB) opts a framework out explicitly, just as cleanly.
# The landing page only links frameworks that actually got real docs.
set -eu
if ! command -v doxygen >/dev/null 2>&1; then
    echo "skip: doxygen not found on PATH" >&2
    exit 77
fi
ROOT=$(pwd)

mkdir -p "$ROOT/ws/docs"
echo "my own hand-written project docs -- must not be touched" > "$ROOT/ws/docs/README.md"

cd ws
bmake docs >docs1.log 2>&1

# The hand-written docs/ directory is untouched.
grep -q "must not be touched" docs/README.md

# The landing page lives under build/docs/, not docs/.
[ -f build/docs/index.html ]
[ ! -f docs/index.html ]

# FwA (has public include/) got real docs; FwB (DOCS=no) and FwC (no
# public include/) were both skipped, with a clear message each.
[ -f FwA/docs/html/index.html ]
[ ! -d FwB/docs ]
[ ! -d FwC/docs ]
grep -q "docs skipped for FwB: DOCS=no" docs1.log
grep -q "docs skipped for FwC: no public include/" docs1.log

# The landing page only links the framework that actually has docs.
grep -q "FwA" build/docs/index.html
if grep -q "FwB\|FwC" build/docs/index.html; then
    echo "expected the landing page to skip frameworks with no generated docs" >&2
    exit 1
fi

echo "docs-scoping OK"
