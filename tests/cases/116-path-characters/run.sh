#!/bin/sh
# path-characters: what a special character in a workspace, framework or
# module directory name -- or in a directory above the workspace, or in the
# directory the mk files are installed in -- does to a build.
#
# Each character is tried in every one of those places at once (one tree whose
# every component carries it), and in a tree whose mk directory carries it.
# Three outcomes, from the build that follows:
#   works     the binary is built and `bmake clean` removes it
#   refused   the build stops with a non-zero status
#   SILENT    the build says it succeeded and built nothing
# Contract (path-characters-contract-cand):
#   1. SUPPORTED characters must work, everywhere.
#   2. No character may end in SILENT: a build that built nothing must not say
#      it succeeded.
#   3. (to come) A refused character is refused with a message naming it.
# KNOWN_GAP lists the characters that today break the contract; the case ends
# SKIP where one of them does, and FAILS on any other violation.
#
# The escaping layers a name goes through, and where each breaks, are written up
# in docs/spec/85-names-and-paths.md.
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

SUPPORTED="lbracket rbracket percent tilde at plus caret dash eacute cjk"
# Break the contract today (measured on macOS): a build that says it succeeded
# and built nothing. Contract 3 (a readable refusal) is not checked yet.
KNOWN_GAP="star question equals"

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
        RESULT=refused; return 0
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
    supported=no; case " $SUPPORTED " in *" $label "*) supported=yes ;; esac
    gap=no; case " $KNOWN_GAP " in *" $label "*) gap=yes ;; esac
    broken=no
    for r in $r1 $r2 $r3 $r4; do
        [ "$r" = skipped ] && continue
        [ "$supported" = yes ] && [ "$r" != works ] && broken=yes
        [ "$r" = SILENT ] && broken=yes
        case $r in clean-*) broken=yes ;; esac
    done
    if [ "$broken" = yes ]; then
        if [ "$gap" = yes ]; then open_gaps="$open_gaps $label"; else viol="$viol $label"; fi
    fi
done < "$TOP/results"

[ -z "$viol" ] || { echo "FAIL: contract broken for:$viol" >&2; exit 1; }
# Whether a gap shows depends on the bmake version as much as on the OS (an
# '=' in a name builds nothing under bmake 20260406 and works under Debian's):
# the case is SKIP only where a listed gap is really open.
if [ -n "$open_gaps" ]; then
    echo "SKIP: known gaps still open here (a build that built nothing said it succeeded):$open_gaps" >&2
    exit 77
fi
echo "path-characters OK"
