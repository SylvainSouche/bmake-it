#!/bin/sh
# warn-macro-req / public-headers-system-req (D3): a module compiling
# vendored third-party source (WARN=none) builds with its own warnings
# suppressed; its framework's PUBLIC_HEADERS_SYSTEM=yes means a
# consumer in a DIFFERENT framework doesn't get flooded with warnings
# FROM the vendored public header either (-isystem) -- but the
# consumer's own code still reports its own warnings normally.
set -eu
cd ws
bmake >build.log 2>&1

# Vendor's own compile: -w present, and its deliberate unused-variable
# warning must not appear anywhere in the log.
grep -q -- " -w " build.log
if grep -q "unused_var\].*vendor\.c\|vendor\.c.*unused_var" build.log; then
    echo "Vendor's own warning should have been suppressed by WARN=none" >&2
    exit 1
fi

# App's compile: the vendored header is reached via -isystem, so no
# warning about vendor.h's own unused parameter leaks into App's build.
grep -q -- "-isystem" build.log
if grep -q "unused_param\|vendor_helper.*unused" build.log; then
    echo "Vendor's public header should not warn for a consumer via -isystem" >&2
    exit 1
fi

# App's OWN warning must still fire -- WARN=none/PUBLIC_HEADERS_SYSTEM
# only apply to Vendor, not to App's own code.
grep -q "unused variable 'app_unused_var'" build.log

echo "vendored-warn-suppression OK"
