#include "cxxhelper.h"
#include <string>
#include <stdexcept>

const char *cxxhelper_greet(void) {
    // Real C++ runtime use behind a C-callable facade: std::string and a
    // caught exception, both needing ___cxa_throw/___gxx_personality_v0 at
    // link time even though the CALLER (app.m) is pure C.
    static std::string s;
    try {
        throw std::runtime_error("ignored");
    } catch (const std::exception&) {
        s = "hello from c++ static lib";
    }
    return s.c_str();
}
