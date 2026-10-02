#!/bin/sh
# ldflags-dedup-hook-timing-fix-req: a regression found in real use
# (lasviewer round 4, against bmake-it main 173f44a). The previous
# duplicate-linkdeps-fix (impl-duplicate-linkdeps-fix, now superseded)
# computed its LDFLAGS dedup as a top-level `!=` assignment, which runs
# at PARSE time -- before mk.local.mk's own "local"-phase post-hooks
# (local.mk, local.<target>.mk, ...) are even .include'd. Anything a
# post-hook added to LDFLAGS (the real use case: a `local.macos.mk`
# adding `-framework OpenGL` and friends) silently never reached the
# link line. The same loop also compared one word at a time, so a
# flag+argument pair like `-framework X` lost its argument or its
# repeated flag whenever either half collided with another token.
#
# This test proves both bugs are fixed: a `mk/local.mk` post-hook's
# `LDFLAGS += -lm` reaches the actual link command (not just the
# module's own pre-existing `LDFLAGS+=-lm`), and the two are still
# correctly deduped to exactly one `-lm` (proving the dedup logic
# itself, now scoped to -l*/-L*/-Wl,-rpath,*, still works across a
# pre-existing and a hook-contributed occurrence). On macOS, a second
# build swaps the hook to a real two-word `-framework X` pair (the
# exact real-world symptom) and proves both frameworks survive intact,
# including via `otool -L` on the actual linked binary.
set -eu
cd ws

mkdir -p Fw/app.m/mk
echo 'LDFLAGS += -lm' > Fw/app.m/mk/local.mk

bmake >build1.log 2>&1
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
out=$("$bin")
echo "$out" | grep -q "^2$"

# The echoed link command (mk.prog.mk's recipe now echoes it) must show
# the hook's own -lm actually reached the link line -- and exactly once,
# not twice, even though it's contributed from two different timing
# points (the module's own pre-existing LDFLAGS+=-lm, and the post-hook's
# LDFLAGS += -lm). -lm only ever appears on the link line, never a
# compile line, so this is unambiguous.
link_line=$(grep -- "-lm" build1.log | tail -1)
[ -n "$link_line" ]
count=$(printf '%s\n' "$link_line" | grep -o -- '-lm' | wc -l | tr -d ' ')
[ "$count" = "1" ]

# --- macOS-only: the exact real-world symptom, a two-word `-framework
# X` flag pair surviving a post-hook and the dedup pass intact ----------
if [ "$(uname -s)" = "Darwin" ]; then
    echo 'LDFLAGS += -framework CoreFoundation -framework IOKit' > Fw/app.m/mk/local.mk
    ( cd Fw/app.m && bmake clean >/dev/null 2>&1 )
    bmake >build2.log 2>&1
    bin=$(find . -type f -name app | head -1)
    [ -n "$bin" ]

    link_line2=$(grep -- "-framework" build2.log | tail -1)
    [ -n "$link_line2" ]
    # Both pairs must survive adjacent and intact -- the old bug deduped
    # the SECOND bare "-framework" keyword as a duplicate single word,
    # leaving its own argument (IOKit) a bare, framework-less word.
    printf '%s\n' "$link_line2" | grep -q -- "-framework CoreFoundation"
    printf '%s\n' "$link_line2" | grep -q -- "-framework IOKit"

    otool -L "$bin" | grep -q "CoreFoundation"
    otool -L "$bin" | grep -q "IOKit"
fi

echo "ldflags-hook-timing OK"
