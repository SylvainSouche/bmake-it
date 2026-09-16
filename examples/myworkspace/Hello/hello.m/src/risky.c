#include "risky.h"

/*
 * Sanitizer-catch fixture, not part of hello's normal `bmake run` demo
 * (main.c never calls this). A plain signed-integer overflow, undefined
 * behavior in C -- see tests/hello_test.cpp and
 * docs/spec/80-unit-testing.md. Under SANITIZE=undefined this aborts
 * with a UBSan report instead of silently wrapping.
 */
int risky_add(int a, int b)
{
    return a + b;
}
