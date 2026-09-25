#!/bin/sh
# Simulates a compiler that does not support OpenMP at all -- rejects
# -fopenmp outright, otherwise behaves like a normal C/C++ compiler
# (delegates to the real one) so the probe's own trivial compile-check
# invocation is the only thing this needs to special-case.
for arg in "$@"; do
    case "$arg" in
        -fopenmp) echo "no-openmp-cc: unrecognized option -fopenmp" >&2; exit 1 ;;
    esac
done
exec "${REAL_CC:-cc}" "$@"
