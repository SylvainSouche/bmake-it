#!/bin/sh
# Nothing outlives its use: the runner's and each case's temporary directories,
# the order scripts' temporary files, and cl.exe's objects.
# @impl 7854-6ae9-ff93-1d73
set -eu
. "$BMK_TESTLIB"
ROOT=$PWD
RUNNER=$(dirname "$BMK_TESTLIB")/run-tests.sh
mkdir t
pack() { # pack <case name> <run.sh text>
    mkdir -p "src/$1" arch
    printf '%s\n' "$2" > "src/$1/run.sh"
    tar -czf "arch/$1.tar.gz" -C src "$1"
}

# A case leaving a file and a directory behind: said, and gone.
pack 1-leaves 'mktemp >/dev/null; mktemp -d >/dev/null'
TMPDIR=$ROOT/t ARCHIVES_DIR=$ROOT/arch sh "$RUNNER" > run.log 2>&1 || { cat run.log; echo "the run failed"; exit 1; }
grep -q 'left in its temporary directory: tmp\.' run.log || { cat run.log; echo "the leftover was not named"; exit 1; }
grep -q '^temp-left=1 ' run.log || { cat run.log; echo "the summary does not count it"; exit 1; }
[ -z "$(ls -A t)" ] || { ls -A t; echo "a run left that in TMPDIR"; exit 1; }

# TERM ends the run after the running case, and cleans up.
rm -rf arch src
export STARTED="$ROOT/started" SECOND="$ROOT/second"
pack 1-slow 'touch "$STARTED"; sleep 3'
pack 2-after 'touch "$SECOND"'
TMPDIR=$ROOT/t ARCHIVES_DIR=$ROOT/arch sh "$RUNNER" > term.log 2>&1 &
pid=$!
i=0
while [ ! -f started ]; do
    i=$((i + 1))
    [ "$i" -lt 120 ] || { kill "$pid" 2>/dev/null; cat term.log; echo "the first case never started"; exit 1; }
    sleep 1
done
kill -TERM "$pid"
rc=0; wait "$pid" || rc=$?
[ "$rc" -eq 143 ] || { cat term.log; echo "exit $rc after TERM, not 143"; exit 1; }
[ ! -f second ] || { cat term.log; echo "the run went on to the next case after TERM"; exit 1; }
[ -z "$(ls -A t)" ] || { ls -A t; echo "TERM left that in TMPDIR"; exit 1; }

# An order script that cannot rename its output leaves no temporary file.
mkdir -p shim empty
printf '#!/bin/sh\nexit 1\n' > shim/mv
chmod +x shim/mv
for s in gen-mod-order gen-fw-order; do
    rc=0
    ( cd empty && PATH="$ROOT/shim:$PATH" sh "$BMK_SCRIPTS/$s.sh" ".$s.mk" ) 2>/dev/null || rc=$?
    [ "$rc" -ne 0 ] || { echo "$s: expected to fail with mv failing"; exit 1; }
    [ -z "$(ls -A empty)" ] || { ls -A empty; echo "$s left that"; exit 1; }
done

# cl.exe's objects of a compile-and-link are not left in the current directory.
if msvc_runtime; then
    mkdir -p obj/out
    echo 'int main(void){return 0;}' > obj/main.c
    ( cd obj && "$CC" -o out/app.exe main.c ) > cl.log 2>&1 || { cat cl.log; echo "compile-and-link failed"; exit 1; }
    [ -f obj/out/app.exe ] || { cat cl.log; echo "no program"; exit 1; }
    [ ! -f obj/main.obj ] || { cat cl.log; echo "main.obj left beside the source"; exit 1; }
fi
echo OK
