#include "greet.h"
#include <stdexcept>

std::string greet(const std::string& name) {
    if (name.empty()) {
        // Exercises real C++ runtime support inside the SHARED library
        // itself, not just the consuming program.
        throw std::invalid_argument("empty name");
    }
    return "hello, " + name;
}
