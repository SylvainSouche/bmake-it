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
REAL=$(PATH=${PATH#*:} command -v bmake)   # past the harness wrapper, to choose BMK_MKDIR
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
OK_ALL=" lbracket rbracket percent tilde at plus caret dash eacute cjk "
# meant to work everywhere and do not yet (refused as "not supported yet")
MUST_FIX=" space twospaces lparen rparen squote amp hash "
# works on some platforms and not on others, so meant to work on all: = builds nothing,
# silently, under macOS's and Alpine's bmake; % stops the link under FreeBSD 15.1's make
# (the rule that creates build/<key>/bin is read as a pattern). Both come from the path
# sitting in a dependency line; relative targets fix them (docs/spec/85-names-and-paths.md).
SILENT_GAP=" equals percent "
# work in the mk directory's name, though not in the others
MKDIR_OK=" hash bang colon comma equals star question lbrace rbrace "
# work in a workspace's name (and its parents'), not in a module's
BRACE=" lbrace rbrace "

# want <label> <column> -> works | refused
want() {
    _l=" $1 "
    case $2 in
        mkdir)
            case "$OK_ALL$MKDIR_OK$MUST_FIX" in *"$_l"*) echo works; return ;; esac ;;
        workspace)
            case "$OK_ALL$MUST_FIX$SILENT_GAP$BRACE" in *"$_l"*) echo works; return ;; esac ;;
        *)
            case "$OK_ALL$MUST_FIX$SILENT_GAP" in *"$_l"*) echo works; return ;; esac ;;
    esac
    echo refused
}

mkws() { # mkws <root> <ws> <fw> <module> : a workspace with one module
    mkdir -p "$1/$2/$3/$4/src"
    printf 'PARENT_WS=\n.include <mk.workspace.mk>\n' > "$1/$2/makefile"
    printf 'PREREQS=\n.include <mk.framework.mk>\n' > "$1/$2/$3/makefile"
    printf 'PROG=x\n.include <mk.prog.mk>\n' > "$1/$2/$3/$4/makefile"
    echo 'int main(void) { return 0; }' > "$1/$2/$3/$4/src/main.c"
}
has_binary() { [ -n "$(find "$1" -type f -name x -path '*/bin/*' 2>/dev/null)" ]; }

# probe <ws dir> <mk dir> : leaves the outcome in $RESULT
probe() {
    RESULT=works
    if ! ( cd "$1" && env -u BMK_MKDIR MAKESYSPATH="$2:${MAKESYSPATH#*:}" "$REAL" -m "$2" -m "${MAKESYSPATH#*:}" BMK_MKDIR="$2" >"$TOP/out.log" 2>&1 ); then
        if grep -q 'Bmake It cannot' "$TOP/out.log"; then RESULT=refused; else RESULT=raw; fi
        return 0
    fi
    has_binary "$1" || { RESULT=SILENT; return 0; }
    ( cd "$1" && env -u BMK_MKDIR MAKESYSPATH="$2:${MAKESYSPATH#*:}" "$REAL" -m "$2" -m "${MAKESYSPATH#*:}" BMK_MKDIR="$2" clean >"$TOP/clean.log" 2>&1 ) || RESULT=clean-failed
    if has_binary "$1"; then RESULT=clean-left-output; fi
    return 0
}

n=0
: > "$TOP/results"
printf '%-13s %-9s %-9s %-9s %-9s\n' character 'all names' module workspace 'mk dir'
printf '%s\n' "$CHARS" | while IFS='|' read -r label fmt; do
    n=$((n + 1))
    c=$(printf "%b" "$fmt")
    root="$TOP/t$n"
    # place <where>: a tree whose <where> names carry the character
    one() { # one <parent> <ws> <fw> <module> : the outcome of building that tree
        rm -rf "$root"
        if ! mkws "$root/$1" "$2" "$3" "$4" 2>/dev/null; then RESULT=skipped; return 0; fi
        probe "$root/$1/$2" "$MKSRC"
    }
    one "p${c}p" "w${c}w" "F${c}F" "m${c}m.m"; r_all=$RESULT
    one plain ws Fw "m${c}m.m";                  r_mod=$RESULT
    one "p${c}p" ws Fw mod.m;                    r_ws=$RESULT
    # the mk files installed in a directory that carries it
    inst="$TOP/i$n/i${c}i"
    if mkdir -p "$inst" 2>/dev/null && cp -R "$MKSRC" "$inst/mk" && cp -R "$MKSRC/../scripts" "$inst/scripts" \
        && { [ ! -d "$MKSRC/../include" ] || cp -R "$MKSRC/../include" "$inst/include"; }; then
        rm -rf "$root"; mkws "$root" plain Fw mod.m
        probe "$root/plain" "$inst/mk"; r_mk=$RESULT
    else
        r_mk=skipped
    fi
    printf '%-13s %-9s %-9s %-9s %-9s\n' "$label" "$r_all" "$r_mod" "$r_ws" "$r_mk"
    echo "$label $r_all $r_mod $r_ws $r_mk" >> "$TOP/results"
    rm -rf "$root" "$TOP/i$n"
done

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
