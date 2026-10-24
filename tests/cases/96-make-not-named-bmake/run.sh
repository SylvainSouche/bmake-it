#!/bin/sh
# make-name-not-assumed-req: the product asks the make that is RUNNING (${MAKE}),
# never a command called "bmake". NetBSD's make is /usr/bin/make and there is no
# bmake there, so a `bmake -f fw/makefile -V PREREQS` silently read an empty
# PREREQS (its failure hidden by 2>/dev/null || true) and the prerequisite
# frameworks' include paths vanished (found building OpenRider on NetBSD).
# This workspace has PREREQS= with a header from the prerequisite. It is run
# through a copy of the make under test named xmake, with a trap "bmake" FIRST on
# PATH that records any call to it by name and fails -- so a platform that has a
# real bmake cannot hide the bug either.
set -eu
ROOT=$(pwd)
real=$(command -v bmake)
mkdir -p "$ROOT/bin" "$ROOT/trap"
cp "$real" "$ROOT/bin/xmake"
cat > "$ROOT/trap/bmake" <<TRAP
#!/bin/sh
echo "bmake was run by name: \$*" >> "$ROOT/bmake-called"
exit 127
TRAP
chmod +x "$ROOT/bin/xmake" "$ROOT/trap/bmake"
export PATH="$ROOT/trap:$ROOT/bin:$PATH"

cd ws
xmake all >build.log 2>&1 || { cat build.log >&2; echo "build failed under a make not named bmake" >&2; exit 1; }
if [ -e "$ROOT/bmake-called" ]; then
    echo "a makefile ran a command named bmake instead of \${MAKE}:" >&2
    cat "$ROOT/bmake-called" >&2
    exit 1
fi
echo "make-not-named-bmake OK"
