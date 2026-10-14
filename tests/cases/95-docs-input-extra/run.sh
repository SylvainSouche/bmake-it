#!/bin/sh
# docs-input-extra-warn-knobs-req: opt-in Doxygen knobs in mk.docs.mk.
#  - FwA has no public include/ but sets DOC_INPUT_EXTRA (local/include
#    and a module's src/): it is documented rather than skipped, from
#    headers only (FILE_PATTERNS -- the module's .c is not scanned), and
#    DOC_WARN_IF_UNDOCUMENTED=YES makes Doxygen name the one
#    undocumented entity in local/include, and nothing else;
#  - FwB sets nothing: its Doxyfile is exactly the previous one (INPUT
#    is include/ only, WARN_IF_UNDOCUMENTED = NO, no FILE_PATTERNS, no
#    EXTRACT_PRIVATE) -- the knobs are backward-compatible;
#  - FwC sets DOC_EXTRACT_PRIVATE=YES, passed through to the Doxyfile.
set -eu
if ! command -v doxygen >/dev/null 2>&1; then
    echo "skip: doxygen not found on PATH" >&2
    exit 77
fi

cd ws
bmake docs >docs.log 2>&1

# FwA: documented from DOC_INPUT_EXTRA alone, not skipped.
[ -f FwA/docs/html/index.html ]
if grep -q "docs skipped for FwA" docs.log; then
    echo "expected FwA (DOC_INPUT_EXTRA set) to be documented, not skipped" >&2
    exit 1
fi
grep -q "^INPUT = [^ ]*/FwA/local/include .*/FwA/liba.m/src$" FwA/docs/Doxyfile
grep -q "^FILE_PATTERNS = \*\.h" FwA/docs/Doxyfile
grep -q "^WARN_IF_UNDOCUMENTED = YES$" FwA/docs/Doxyfile
grep -q "a_private_documented" FwA/docs/FwA.tag

# Exactly one undocumented-entity warning: the local/include one.
grep -q "a_undocumented_local.*not documented" docs.log
if grep -q "a_undocumented_source" docs.log; then
    echo "expected .c sources outside FILE_PATTERNS to be left unscanned" >&2
    exit 1
fi
if grep "not documented" docs.log | grep -qv "a_undocumented_local"; then
    echo "unexpected undocumented-entity warning:" >&2
    grep "not documented" docs.log >&2
    exit 1
fi

# FwB: defaults reproduce the previous Doxyfile.
grep -q "^INPUT = [^ ]*/FwB/include$" FwB/docs/Doxyfile
grep -q "^WARN_IF_UNDOCUMENTED = NO$" FwB/docs/Doxyfile
if grep -q "^FILE_PATTERNS\|^EXTRACT_PRIVATE" FwB/docs/Doxyfile; then
    echo "expected no FILE_PATTERNS/EXTRACT_PRIVATE by default" >&2
    exit 1
fi

# FwC: DOC_EXTRACT_PRIVATE passed through.
grep -q "^EXTRACT_PRIVATE = YES$" FwC/docs/Doxyfile

echo "docs-input-extra OK"
