#!/bin/sh
# man-pages-for-mk-files-req. Every mk/mk.*.mk has a page that names its settings
# and targets; the pages resolve and are clean under the lint that is here.
# Runs against the tree under test: BMK_MKDIR's parent.
set -eu
. "$BMK_TESTLIB"
c="$BMK_MKDIR/../tests/harness/check-man.sh"
[ -f "$c" ] || { echo "skip: no $c in this tree" >&2; exit 77; }
[ -d "$BMK_MKDIR/../man" ] || { echo "skip: no man/ beside $BMK_MKDIR (a guest that was sent only mk/ scripts/ tests/)" >&2; exit 77; }
sh "$c"
