#!/bin/sh
# path-characters-supported-req: a name travels through make as ONE word, written
# with the characters make or the shell would read (space, #, ', &, (, ), =, [, ],
# ~, {, } and % itself) as %XX. The make side (_BMK_ENC, _BMK_ENCW, _BMK_DEC in
# mk.common.mk) and the shell side (bmk_enc, bmk_dec in scripts/bmk-names.sh) are
# two implementations of one scheme and must agree on every name, on every make:
#   - the shell round trip gives the name back
#   - make encodes a directory (one string, spaces and all) to the same word
#   - make encodes a name as the user writes it in PREREQS= / PARENT_WS= (a
#     backslash before a space, an apostrophe, a hash sign) to the same word
#   - make decodes the word to the name, two adjacent spaces included (every
#     modifier after a space is in a value splits it again and joins with ONE)
#   - a list of several names stays several words
set -eu
REAL=${BMK_REAL_MAKE:-$(PATH=${PATH#*:} command -v bmake)}   # past the harness wrapper, so BMK_MKDIR can be unset
. "$BMK_MKDIR/../scripts/bmk-names.sh"
mkdir work && cd work
printf '.include "mk.common.mk"\nall: ;@:\n' > enc.mk
mk() { env -u BMK_MKDIR "$REAL" -f enc.mk "$@"; }

NAMES="$(printf '%s\n' \
    'plain-name.m' 'My Framework' 'C#z' '#lead' 'M(1)' "John's" 'R&D' 'x=y' '50% off' '%20' '%2520' \
    '[br]ack' 'a~b' '{e}' 'two  spaces' 'a   b' '日本é' 'Fw (x86)' "it's (a) & #b")"

bad=0
say() { echo "FAIL: $*" >&2; bad=1; }
printf '%s\n' "$NAMES" | while IFS= read -r n; do
    e=$(bmk_enc "$n")
    case $e in *[[:space:]]*|*"'"*|*'#'*|*'&'*|*'('*|*')'*|*'='*|*'['*|*']'*|*'~'*|*'{'*|*'}'*)
        say "bmk_enc('$n') = '$e' still has a character make or the shell reads" ;; esac
    [ "$(bmk_dec "$e")" = "$n" ] || say "bmk_dec(bmk_enc('$n')) = '$(bmk_dec "$e")'"
    m=$(mk -V '${RAW:${_BMK_ENCW}}' RAW="$n") || say "make could not encode '$n'"
    [ "$m" = "$e" ] || say "make encodes the directory '$n' as '$m', the shell as '$e'"
    d=$(mk -V '${E:${_BMK_DEC}}' E="$e") || say "make could not decode '$e'"
    [ "$d" = "$n" ] || say "make decodes '$e' to '$d', not '$n'"
    printf 'PRE = %s\n.include "mk.common.mk"\nall: ;@:\n' "$(bmk_wl "$n")" > list.mk
    l=$(env -u BMK_MKDIR "$REAL" -f list.mk -V '${PRE:${_BMK_ENC}}') || say "make could not read the list '$(bmk_wl "$n")'"
    [ "$l" = "$e" ] || say "PREREQS= written '$(bmk_wl "$n")' is '$l' in make, '$e' in the shell"
    # the same name inside a variable name, as the module order file does
    printf 'K.%s = ok\n.include "mk.common.mk"\nall: ;@:\n' "$e" > key.mk
    [ "$(env -u BMK_MKDIR "$REAL" -f key.mk -V "\${K.$e}")" = ok ] || say "'$e' is not usable in a variable name"
    [ "$bad" = 0 ] || exit 1
done

# several names stay several words, and decode one by one
printf 'PRE = %s %s %s\n.include "mk.common.mk"\nall: ;@:\n' "$(bmk_wl 'My Fw')" 'plain' "$(bmk_wl "it's")" > many.mk
[ "$(env -u BMK_MKDIR "$REAL" -f many.mk -V '${PRE:${_BMK_ENC}:[#]}')" = 3 ] \
    || { echo "FAIL: a list of three names is not three words" >&2; exit 1; }
[ "$(env -u BMK_MKDIR "$REAL" -f many.mk -V '${PRE:${_BMK_ENC}:@w@<${w:${_BMK_DEC}}>@}')" = "<My Fw> <plain> <it's>" ] \
    || { echo "FAIL: the three names do not decode one by one" >&2; exit 1; }
echo "name-encoding OK"
