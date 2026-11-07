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
#   later    the character is meant to work (a space in C:\Program Files, an
#            apostrophe in John's Documents) and does not yet: refused with
#            that said, so it is a plain message and not a shell error
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
        if [ "$_role" = module ]; then
            case $_n in
                *\{*|*\}*) printf 'a brace, which cannot be part of a module name (the module order file is written with the name as a variable name)'; return 1 ;;
            esac
        fi
    fi
    # meant to work, not yet: refused with that said
    case $_n in
        *" "*) _w="a space" ;;
        *\(*)  _w="a left parenthesis" ;;
        *\)*)  _w="a right parenthesis" ;;
        *\'*)  _w="an apostrophe" ;;
        *\&*)  _w="an ampersand" ;;
        *)     _w="" ;;
    esac
    if [ "$_role" != mkdir ]; then
        case $_n in *\#*) _w="a hash sign" ;; esac
    fi
    if [ -n "$_w" ]; then
        printf '%s, which Bmake It is meant to support and does not yet' "$_w"
        return 1
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
BMK_NAME_HELP="Letters, digits and . _ - + @ % ~ ^ [ ] = and non-ASCII letters work in a directory name; rename the directory (docs/spec/85-names-and-paths.md)."
