#!/bin/sh
# header-dependency-tracking-req: the fourth, previously-untested case --
# a PROMOTED GENERATED header (yacc -d output, INCL=-promoted to the
# framework's build/<KEY>/include/) triggers a cross-framework consumer
# to rebuild when it changes, exactly like a hand-written one. Same
# underlying mechanism (-MMD/-MP records whatever file the compiler
# actually opened, generated or not) but never directly exercised until
# this case.
set -eu
. "$BMK_TESTLIB"
need_tool yacc "the generated header comes from a yacc grammar"
cd ws

bmake >build1.log 2>&1
bin=$(find . -type f -name "$(prog_name app)" | head -1)
[ -n "$bin" ]
out=$(run_prog "$bin")
echo "$out" | grep -q "no-token-b"

# Regenerate the grammar with a new token -- the promoted grammar.h
# changes, main.c must recompile and pick up the new #define.
sleep 1
sed -i.bak 's/%token TOKEN_A/%token TOKEN_A\n%token TOKEN_B/' Gen/libgen.m/src/grammar.y
sed -i.bak 's/start: TOKEN_A ;/start: TOKEN_A TOKEN_B ;/' Gen/libgen.m/src/grammar.y
bmake >build2.log 2>&1
grep -q -- "-c .*main\.c" build2.log
out=$(run_prog "$bin")
echo "$out" | grep -q "has-token-b"

echo "header-dependency-generated OK"
