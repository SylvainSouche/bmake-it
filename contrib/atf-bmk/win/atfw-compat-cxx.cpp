// atfw-compat-cxx.cpp -- the entry point of a C++ test program for a
// native Windows runtime: atfw_enter, as for C test programs
// (atfw-compat.c), then ATF's own run_tp, renamed when building tests.cpp
// (-DATFW_TESTS_CPP).
#include <vector>

#include "atf-c++/tests.hpp"

extern "C" void atfw_enter(int, char **);

namespace atf {
namespace tests {
typedef std::vector< tc * > tc_vector;  // (as in tests.cpp)
int atfw_posix_run_tp(int, char**, void (*)(tc_vector&));

int
run_tp(int argc, char** argv, void (*add_tcs)(tc_vector&))
{
    atfw_enter(argc, argv);
    return atfw_posix_run_tp(argc, argv, add_tcs);
}
} // namespace tests
} // namespace atf
