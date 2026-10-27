#!/bin/sh
# run-build-environment-req, run-shell-keeps-environment-req
# (run-any-program-in-build-env-dec): `bmake run PROGRAM=<x>` runs ANY program
# through the build environment. PATH = workspace bin, each PARENT_WS bin,
# then the caller's PATH; the library variable and BMK_* describe the same
# chains; PROGRAM=sh is an interactive subshell; and the launched shell's
# own startup files must not override that environment.
set -eu
. "$BMK_TESTLIB"
ROOT=$(pwd)
cd ws
bmake >build.log 2>&1
KEY=$(bmake -V '${OS_ARCH}')
BIN="$PWD/build/$KEY/bin"; LIB="$PWD/build/$KEY/lib"; SHARE="$PWD/build/$KEY/share"

# --- a program, with arguments, found through the workspace bin ------------------
out=$(run_prog bmake run PROGRAM=showenv ARGS="BMK_TARGET BMK_BINDIR")
echo "$out" | grep -q "^BMK_TARGET=$KEY$"
echo "$out" | grep -q "^BMK_BINDIR=$BIN$"
# ... also from inside a module directory (it walks up to the workspace root)
( cd Fw/showenv.m && run_prog bmake run PROGRAM=showenv ARGS="BMK_TARGET" ) | grep -q "^BMK_TARGET=$KEY$"

# --- PATH, the library variable and the chains ----------------------------------
out=$(run_prog bmake run PROGRAM=showenv ARGS="PATH LIBVAR BMK_LIBDIR BMK_SHAREDIR BMK_LIBVAR")
v=$(libpath_var)
if [ "$v" = PATH ]; then
    # Windows: the loader searches PATH itself, so the lib chain is prepended
    # to PATH too -- lib first, then bin, then the caller's PATH
    echo "$out" | grep -q "^PATH=$LIB:$BIN:"
else
    echo "$out" | grep -q "^PATH=$BIN:"             # workspace bin first, caller's PATH after
fi
echo "$out" | grep -q "^LIBVAR=$LIB"                # library variable = lib chain first
echo "$out" | grep -q "^BMK_LIBDIR=$LIB$"
echo "$out" | grep -q "^BMK_SHAREDIR=$SHARE$"
echo "$out" | grep -q "^BMK_LIBVAR=$v$"
# the caller's environment is inherited, not replaced
# (exported, not a prefix: `VAR=x function` does not export VAR to the
# function's commands in every sh -- FreeBSD's does not)
out=$(MY_INHERITED=yes; export MY_INHERITED; run_prog bmake run PROGRAM=showenv ARGS="MY_INHERITED")
echo "$out" | grep -q "^MY_INHERITED=yes$"
# an existing library path is kept after ours, with no empty trailing entry
# (not on macOS: a user-set DYLD_* is stripped by the recipe's own /bin/sh,
# before `run` can see it -- an OS rule, not ours; not on Windows either,
# where that variable is PATH itself and /keep/me alone would hide every tool)
if [ "$(uname -s)" != Darwin ] && [ "$v" != PATH ]; then
    out=$(env "$v=/keep/me" bmake run PROGRAM=showenv ARGS="LIBVAR" 2>&1)
    echo "$out" | grep -q "^LIBVAR=$LIB:/keep/me$"
fi
out=$(run_prog bmake run PROGRAM=showenv ARGS="LIBVAR")
case "$out" in *:) echo "an empty trailing library-path entry: $out" >&2; exit 1 ;; esac

# --- PARENT_WS: a program built only in a parent workspace is found --------------
PAR="$ROOT/parent"
mkdir -p "$PAR/Fw/pp.m/src"
printf 'PARENT_WS=\n.include <mk.workspace.mk>\n' > "$PAR/makefile"
printf 'PREREQS=\n.include <mk.framework.mk>\n' > "$PAR/Fw/makefile"
printf 'PROG=pp\n.include <mk.prog.mk>\n' > "$PAR/Fw/pp.m/makefile"
printf '#include <stdio.h>\nint main(void){puts("from the parent workspace");return 0;}\n' > "$PAR/Fw/pp.m/src/main.c"
( cd "$PAR" && bmake >build.log 2>&1 )
CHILD="$ROOT/child"; mkdir -p "$CHILD"
printf 'PARENT_WS=%s\n.include <mk.workspace.mk>\n' "$PAR" > "$CHILD/makefile"
( cd "$CHILD" && run_prog bmake run PROGRAM=pp ) | grep -q "from the parent workspace"
( cd "$CHILD" && run_prog bmake run PROGRAM=env ) | grep "^PATH=" | grep -q "$PAR/build/$KEY/bin"

# --- not found: an error naming the chain; run does not build ------------------------
rc=0; bmake run PROGRAM=no-such-program-zzz >nf.log 2>&1 || rc=$?
[ $rc != 0 ]
grep -q "no-such-program-zzz not found in $BIN" nf.log
grep -q "build first" nf.log
rc=0; bmake run >us.log 2>&1 || rc=$?
[ $rc != 0 ] && grep -q "usage: make run PROGRAM=" us.log

# --- an interactive shell: stdin passes through; its own startup files run, and
# must not override the environment -----------------------------------------------
HOME_T="$ROOT/home"; mkdir -p "$HOME_T"
cat > "$HOME_T/.shrc" <<'XEOF'
# a typical user rc that RESETS the search paths
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
MY_RC_RAN=yes; export MY_RC_RAN
XEOF
cp "$HOME_T/.shrc" "$HOME_T/.bashrc"
cp "$HOME_T/.shrc" "$HOME_T/.zshrc"

# control: without bmake run, that rc really does reset PATH (the problem is real)
ctl=$(echo 'echo "$PATH"' | env HOME="$HOME_T" ENV="$HOME_T/.shrc" sh -i 2>/dev/null | tail -1)
case "$ctl" in "$BIN"*) echo "control: the rc did not reset PATH, test proves nothing" >&2; exit 1 ;; esac

check_shell() {  # shell-name [env-var to point at the rc]
    command -v "$1" >/dev/null 2>&1 || return 0
    out=$(echo 'echo "PATH:$PATH"; echo "RC:$MY_RC_RAN"; exit 5' | env HOME="$HOME_T" ENV="$HOME_T/.shrc" bmake run PROGRAM="$1" ARGS=-i 2>/dev/null) || true
    echo "$out" | grep -q "^PATH:$BIN:" || { echo "$1: PATH was overridden by the shell's startup files: $out" >&2; exit 1; }
    echo "$out" | grep -q "^RC:yes$"  || { echo "$1: the user's own startup file did not run: $out" >&2; exit 1; }
}
check_shell sh
check_shell bash
check_shell zsh

# the shell's exit status is the program's: make reports it and fails
rc=0; echo 'exit 3' | env HOME="$HOME_T" bmake run PROGRAM=sh ARGS=-i >s.log 2>&1 || rc=$?
[ $rc != 0 ] && grep -q "Error code 3" s.log

echo "run-build-environment OK"
