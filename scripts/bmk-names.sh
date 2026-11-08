# bmk-names.sh -- which characters a directory name may carry (sourced, never
# run). @impl-marker below.
#
# A name is judged where it was measured (docs/spec/85-names-and-paths.md):
#   bmk_name_problem <name> <role>   role: module | other | mkdir
# prints nothing and returns 0 when the name is fine; otherwise prints what is
# wrong, in words, and returns 1.
#
#   refused  the shell or make reads the character as syntax, and no quoting
#            can carry it through the whole chain of calls
#   (Space, ( ) ' & and # work: a name travels as a word with those written
#   %XX, see bmk_enc below.)
# @impl 0f87-6aee-e982-0f20

BMK_TAB=$(printf '\t')
BMK_NL=$(printf '\n_'); BMK_NL=${BMK_NL%_}

# bmk_name_problem <name> <role>
bmk_name_problem() {
    _n=$1 _role=$2
    # refused in every name
    case $_n in
        *"$BMK_TAB"*) _w="a tab" ;;
        *"$BMK_NL"*)  _w="a newline" ;;
        *\\*)         _w="a backslash" ;;
        *\"*)         _w="a double quote" ;;
        *\`*)         _w="a backquote" ;;
        *\$*)         _w="a dollar sign" ;;
        *\;*)         _w="a semicolon" ;;
        *\|*)         _w="a vertical bar" ;;
        *\<*)         _w="a less-than sign" ;;
        *\>*)         _w="a greater-than sign" ;;
        *)            _w="" ;;
    esac
    if [ -n "$_w" ]; then
        printf '%s, which the shell reads as syntax (no quoting carries it through every command Bmake It runs)' "$_w"
        return 1
    fi
    if [ "$_role" != mkdir ]; then
        case $_n in
            *\**) _w="an asterisk" ;;
            *\?*) _w="a question mark" ;;
            *!*)  _w="an exclamation mark" ;;
            *:*)  _w="a colon" ;;
            *,*)  _w="a comma" ;;
            *)    _w="" ;;
        esac
        if [ -n "$_w" ]; then
            printf '%s, which make or the linker reads as syntax (it ends a rule, is matched as a pattern, or splits a linker option)' "$_w"
            return 1
        fi
    fi
    return 0
}

# bmk_path_problem <path> <kind>   kind: path (the directory being built) | mkdir
# Checks every component; prints the message for the first that is not fine.
bmk_path_problem() {
    _p=$1 _kind=$2
    _oifs=$IFS; IFS=/; set -f
    # shellcheck disable=SC2086
    set -- $_p
    IFS=$_oifs; set +f
    for _c in "$@"; do
        [ -n "$_c" ] || continue
        _role=other
        if [ "$_kind" = mkdir ]; then _role=mkdir
        else case $_c in *.m|*.tst) _role=module ;; esac; fi
        if _why=$(bmk_name_problem "$_c" "$_role"); then continue; fi
        printf "the name '%s' contains %s" "$_c" "$_why"
        return 1
    done
    return 0
}

# bmk_refuse <name> <role>: for a script that has found a framework or module
# directory in the current directory -- stops it (exit 1) with the message.
bmk_refuse() {
    if _why=$(bmk_name_problem "$1" "$2"); then return 0; fi
    echo "${BMK_PROG:-bmake}: error: Bmake It cannot build in $(pwd)/$1: the name '$1' contains $_why. $BMK_NAME_HELP" >&2
    exit 1
}

# What does work, for the message.
BMK_NAME_HELP="Letters, digits, spaces and . _ - + @ % ~ ^ [ ] { } = # ' & ( ) and non-ASCII letters work in a directory name; rename the directory (docs/spec/85-names-and-paths.md)."

# A name travels through make as one word: make splits a value at a space,
# reads # as a comment and ' as a quote, and a variable name cannot carry =,
# so a name is written with each of those as %XX (percent-encoding; % itself
# is %25). mk.common.mk does the same in make (_BMK_ENC, _BMK_DEC): the two
# must agree, and case 117 checks that they do.
# @impl 0f87-6af0-c379-4dfe
#   bmk_enc <name>   the name as one make word
#   bmk_dec <word>   the name back
bmk_enc() {
    printf '%s\n' "$1" | LC_ALL=C sed -e 's/%/%25/g' -e 's/ /%20/g' -e 's/#/%23/g' -e "s/'/%27/g" \
        -e 's/&/%26/g' -e 's/(/%28/g' -e 's/)/%29/g' -e 's/=/%3D/g' -e 's/\[/%5B/g' -e 's/]/%5D/g' \
        -e 's/~/%7E/g' -e 's/{/%7B/g' -e 's/}/%7D/g'
}
bmk_dec() {
    printf '%s\n' "$1" | LC_ALL=C sed -e 's/%20/ /g' -e 's/%23/#/g' -e "s/%27/'/g" -e 's/%26/\&/g' \
        -e 's/%28/(/g' -e 's/%29/)/g' -e 's/%3D/=/g' -e 's/%5B/[/g' -e 's/%5D/]/g' -e 's/%7E/~/g' \
        -e 's/%7B/{/g' -e 's/%7D/}/g' -e 's/%25/%/g'
}

# bmk_wl <name>: the name as a user writes it in PREREQS= or PARENT_WS= -- a
# backslash before a space, an apostrophe and a hash sign (make reads those as a
# word end, a quote, the start of a comment).
bmk_wl() {
    printf '%s\n' "$1" | sed -e 's/ /\\ /g' -e "s/'/\\\\'/g" -e 's/#/\\#/g'
}

# bmk_atfsh_check <dir>: ATF's own shell library (libatf-sh.subr, ATF 0.23) cannot
# run a test script from a directory whose path has a space in it -- it tests the
# path unquoted -- so say so, before kyua reports every script "broken: Test
# program did not exit cleanly". Compiled tests (atf-c, atf-c++) are not affected.
# Prints the message and returns 1 when the directory has whitespace in its path.
bmk_atfsh_check() {
    case $1 in
        *[[:space:]]*)
            echo "error: Bmake It cannot run the shell-script tests (testcases/*.sh, TESTS_SH) in $1: the path has a space in it, and ATF's own shell library (libatf-sh.subr) does not handle one. Compiled tests (TESTS_C, TESTS_CXX, TEST_PROG) are not affected. Run bmake test from a workspace whose path has no space, or write the test in C or C++." >&2
            return 1 ;;
    esac
    return 0
}
