#!/bin/sh
# path-characters (path-characters-supported-req, path-characters-refused-
# upfront-req): what a special character in a workspace, framework or module
# directory name -- or in a directory above the workspace, or in the directory
# the mk files are installed in -- does to a build.
#
# Each character is tried in four places: every name at once, the module name
# only, the workspace name only (with a parent directory carrying it too), and
# the mk directory. The outcome of the build that follows:
#   works     the binary is built and `bmake clean` removes it
#   refused   the build stops, and says why in a message that begins
#             "Bmake It cannot" (the name, the character in words, what works)
#   raw       the build stops with some other error: never acceptable
#   SILENT    the build says it succeeded and built nothing: never acceptable
# Contract (docs/spec/85-names-and-paths.md): what works anywhere works
# everywhere, so a character that works is tested to work on every platform;
# the rest is refused upfront with an explanation. MUST_FIX lists the
# characters that are meant to work (space, parentheses, apostrophe, ampersand,
# hash; and = and % where a platform's make reads them as syntax) and do not yet: refused
# with "not supported yet" is a gap, the case ends SKIP while one is open. Any
# other deviation fails the case.
set -eu
REAL=${BMK_REAL_MAKE:-$(PATH=${PATH#*:} command -v bmake)}   # past the harness wrapper, to choose BMK_MKDIR
MKSRC=$BMK_MKDIR
TOP=$(pwd)

# label|printf format of the character(s) put inside each name
CHARS='space|\0040
tab|\0011
twospaces|\0040\0040
squote|\0047
dquote|\0042
backslash|\0134
dollar|\0044
dollarbrace|\0044{X}
dollarparen|\0044(X)
dollardollar|\0044\0044
backtick|\0140
lparen|\0050
rparen|\0051
lbracket|\0133
rbracket|\0135
lbrace|\0173
rbrace|\0175
star|\0052
question|\0077
hash|\0043
percent|\0045
amp|\0046
semi|\0073
pipe|\0174
lt|\0074
gt|\0076
tilde|\0176
bang|\0041
equals|\0075
colon|\0072
comma|\0054
at|\0100
plus|\0053
caret|\0136
dash|\0055
eacute|\0303\0251
cjk|\0346\0227\0245\0346\0234\0254'

# works in every place, on every platform
OK_ALL=" lbracket rbracket percent equals tilde at plus caret dash eacute cjk space twospaces lparen rparen squote amp hash lbrace rbrace "
# meant to work everywhere and do not yet (refused as "not supported yet"): none now.
# Space, parentheses, apostrophe, ampersand and hash joined OK_ALL when the shell and
# word-list layers were fixed, and braces with them (a name is an encoded word in a
# variable name now) (path-characters-supported-req); = and % were mixed-platform
# characters until the rules were made relative to the module directory
# (module-rules-relative-targets-req).
MUST_FIX=" "
SILENT_GAP=" "
# work in the mk directory's name, though not in the others
MKDIR_OK=" bang colon comma star question "

# want <label> <column> -> works | refused
want() {
    _l=" $1 "
    case $2 in
        mkdir)
            case "$OK_ALL$MKDIR_OK$MUST_FIX" in *"$_l"*) echo works; return ;; esac ;;
        workspace)
            case "$OK_ALL$MUST_FIX$SILENT_GAP" in *"$_l"*) echo works; return ;; esac ;;
        *)
            case "$OK_ALL$MUST_FIX$SILENT_GAP" in *"$_l"*) echo works; return ;; esac ;;
    esac
    echo refused
}

# a name as it is written in a word list (PREREQS=, PARENT_WS=): a backslash before a
# space, an apostrophe or a hash sign (make reads those as a word end, a quote, a comment)
wl() { printf '%s' "$1" | sed -e 's/ /\\ /g' -e "s/'/\\\\'/g" -e 's/#/\\#/g'; }

mkws() { # mkws <root> <ws> <fw> <module> : a workspace with one module
    mkdir -p "$1/$2/$3/$4/src"
    printf 'PARENT_WS=\n.include <mk.workspace.mk>\n' > "$1/$2/makefile"
    printf 'PREREQS=\n.include <mk.framework.mk>\n' > "$1/$2/$3/makefile"
    printf 'PROG=x\n.include <mk.prog.mk>\n' > "$1/$2/$3/$4/makefile"
    echo 'int main(void) { return 0; }' > "$1/$2/$3/$4/src/main.c"
}

# A fuller tree, for the places that are meant to work: a library in one
# framework, a program in a second framework that lists the first in PREREQS=
# and links the library; both modules carry the name's character. It reaches the
# library and program rules, the PREREQS= word list, the include and library
# search paths, the shared library and its run path, the copy-up and install.
mkws_rich() { # mkws_rich <root> <ws> <fw> <module>
    _fw2="B$3"
    mkdir -p "$1/$2/$3/lib$4/src" "$1/$2/$3/include" "$1/$2/$_fw2/$4/src"
    printf 'PARENT_WS=\n.include <mk.workspace.mk>\n' > "$1/$2/makefile"
    printf 'PREREQS=\n.include <mk.framework.mk>\n' > "$1/$2/$3/makefile"
    printf 'PREREQS=%s\n.include <mk.framework.mk>\n' "$(wl "$3")" > "$1/$2/$_fw2/makefile"
    printf 'LIB=g\nLIB_SHARED=YES\nSHLIB_MAJOR=1\n.include <mk.lib.mk>\n' > "$1/$2/$3/lib$4/makefile"
    printf 'void greet(void);\n' > "$1/$2/$3/include/greet.h"
    printf '#include "greet.h"\nvoid greet(void) {}\n' > "$1/$2/$3/lib$4/src/g.c"
    printf 'PROG=x\nLIBS=g\n.include <mk.prog.mk>\n' > "$1/$2/$_fw2/$4/makefile"
    printf '#include "greet.h"\nint main(void) { greet(); return 0; }\n' > "$1/$2/$_fw2/$4/src/main.c"
}
has_binary() { [ -n "$(find "$1" -type f \( -name x -o -name x.exe \) -path '*/bin/*' 2>/dev/null)" ]; }

# bm <mk dir> [bmake args]: bmake told where the mk files are. MAKESYSPATH is a
# colon-separated list, so a directory with a colon in its name goes by -m; and bmake
# passes a -m with a space in it to the sub-makes cut in two, so the others go by
# MAKESYSPATH. (Both are bmake's own: documented in docs/spec/85-names-and-paths.md.)
bm() {
    _mk=$1; shift
    case $_mk in
        *:*) env -u BMK_MKDIR MAKESYSPATH="${MAKESYSPATH#*:}" "$REAL" -m "$_mk" -m "${MAKESYSPATH#*:}" BMK_MKDIR="$_mk" "$@" ;;
        *)   env -u BMK_MKDIR MAKESYSPATH="$_mk:${MAKESYSPATH#*:}" "$REAL" BMK_MKDIR="$_mk" "$@" ;;
    esac
}

# probe <ws dir> <mk dir> : leaves the outcome in $RESULT
probe() {
    RESULT=works
    if ! ( cd "$1" && bm "$2" >"$LOGP.out" 2>&1 ); then
        if grep -q 'Bmake It cannot' "$LOGP.out"; then RESULT=refused; else RESULT=raw; fi
        # BMK_CASE_VERBOSE=1: say what a failure was (for working on one character)
        if [ "$RESULT" = raw ] && [ -n "${BMK_CASE_VERBOSE:-}" ]; then
            { echo "---- failed in $1:"; grep -v '^===>' "$LOGP.out" | head -14; } >&2
            for _l in "$1"/*/*/build/*/runs/*/build.log "$1"/*/build/*/runs/*/build.log; do
                [ -f "$_l" ] && { echo "---- $_l:"; head -8 "$_l"; } >&2
            done
        fi
        return 0
    fi
    has_binary "$1" || { RESULT=SILENT; return 0; }
    if [ -n "${RICH:-}" ]; then
        # install into a directory that carries the character too
        _dst="$TOP/dst$N${CHAR}dst"; rm -rf "$_dst"
        if ! ( cd "$1" && bm "$2" install DESTDIR="$_dst" >"$LOGP.install" 2>&1 ) \
            || [ -z "$(find "$_dst" -type f \( -name x -o -name x.exe \) 2>/dev/null)" ]; then
            RESULT=install-failed; rm -rf "$_dst"; return 0
        fi
        rm -rf "$_dst"
    fi
    ( cd "$1" && bm "$2" clean >"$LOGP.clean" 2>&1 ) || RESULT=clean-failed
    if has_binary "$1"; then RESULT=clean-left-output; fi
    return 0
}

# One character: its four places, the outcome of each in $TOP/res.<nn>.
do_char() { # do_char <n> <label> <fmt>
    N=$1; label=$2
    # On Windows a backslash is a path separator: the directory made is two
    # directories, and no name carries the character.
    case $(uname -s):$label in
        CYGWIN*:backslash|MSYS*:backslash)
            echo "$label skipped skipped skipped skipped" > "$TOP/res.$(printf %02d "$N")"
            return 0 ;;
    esac
    c=$(printf "%b" "$3")
    root="$TOP/t$N"; CHAR=$c; LOGP="$TOP/log.$N"
    one() { # one <column> <parent> <ws> <fw> <module> : the outcome of building that tree
        rm -rf "$root"; RICH=
        # the fuller tree where the build is meant to work, the small one where it is refused
        if [ "$(want "$label" "$1")" = works ]; then RICH=1; _mk=mkws_rich; else _mk=mkws; fi
        if ! $_mk "$root/$2" "$3" "$4" "$5" 2>/dev/null; then RESULT=skipped; return 0; fi
        probe "$root/$2/$3" "$MKSRC"
    }
    one names "p${c}p" "w${c}w" "F${c}F" "m${c}m.m"; r_all=$RESULT
    one module plain ws Fw "m${c}m.m";               r_mod=$RESULT
    one workspace "p${c}p" ws Fw mod.m;              r_ws=$RESULT
    # the mk files installed in a directory that carries it
    inst="$TOP/i$N/i${c}i"
    if mkdir -p "$inst" 2>/dev/null && cp -R "$MKSRC" "$inst/mk" && cp -R "$MKSRC/../scripts" "$inst/scripts" \
        && { [ ! -d "$MKSRC/../include" ] || cp -R "$MKSRC/../include" "$inst/include"; }; then
        rm -rf "$root"; RICH=; _mk=mkws
        if [ "$(want "$label" mkdir)" = works ]; then RICH=1; _mk=mkws_rich; fi
        $_mk "$root" plain Fw mod.m
        probe "$root/plain" "$inst/mk"; r_mk=$RESULT
    else
        r_mk=skipped
    fi
    echo "$label $r_all $r_mod $r_ws $r_mk" > "$TOP/res.$(printf %02d "$N")"
    rm -rf "$root" "$TOP/i$N"
}

# The characters are independent, so a few go at a time (BMK_CASE_JOBS, default 4).
JOBS=${BMK_CASE_JOBS:-4}
n=0; running=0
printf '%s\n' "$CHARS" | {
    while IFS='|' read -r label fmt; do
        n=$((n + 1))
        # BMK_CASE_CHARS="space hash": only these (a way to work on one character; the suite runs all)
        case " ${BMK_CASE_CHARS:-$label} " in *" $label "*) ;; *) continue ;; esac
        do_char "$n" "$label" "$fmt" &
        running=$((running + 1))
        if [ "$running" -ge "$JOBS" ]; then wait; running=0; fi
    done
    wait
}
printf '%-13s %-9s %-9s %-9s %-9s\n' character 'all names' module workspace 'mk dir'
cat "$TOP"/res.* > "$TOP/results"
while read -r label r1 r2 r3 r4; do
    printf '%-13s %-9s %-9s %-9s %-9s\n' "$label" "$r1" "$r2" "$r3" "$r4"
done < "$TOP/results"

viol=''; open_gaps=''
while read -r label r1 r2 r3 r4; do
    i=0
    for col in names module workspace mkdir; do
        i=$((i + 1)); eval "got=\$r$i"
        [ "$got" = skipped ] && continue
        exp=$(want "$label" "$col")
        if [ "$got" = "$exp" ]; then continue; fi
        # A $ in the mk directory's own name stops bmake itself ("Could not
        # find .../mk.common.mk": make expands it in the .include) before any
        # Bmake It file can run, so no message of ours can come first.
        case "$label:$col:$got" in dollar*:mkdir:raw) continue ;; esac
        case " $MUST_FIX$SILENT_GAP " in
            *" $label "*)
                # meant to work: refused ("not supported yet"), silent, or failing on this platform is an open gap
                if [ "$exp" = works ] && { [ "$got" = refused ] || [ "$got" = SILENT ] || [ "$got" = raw ]; }; then
                    open_gaps="$open_gaps $label"; continue
                fi ;;
        esac
        viol="$viol $label($col: wanted $exp, got $got)"
    done
done < "$TOP/results"

[ -z "$viol" ] || { echo "FAIL: contract broken:$viol" >&2; exit 1; }
if [ -n "$open_gaps" ]; then
    echo "SKIP: meant to work, not yet (refused as 'not supported yet', or built nothing):$(printf '%s\n' $open_gaps | sort -u | tr '\n' ' ')" >&2
    exit 77
fi
echo "path-characters OK"
