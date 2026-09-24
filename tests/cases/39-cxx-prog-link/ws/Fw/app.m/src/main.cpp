#include <iostream>
#include <string>
#include <stdexcept>

int main() {
    std::string s = "cxx link works";
    std::cout << s << std::endl;
    // Exercises real C++ runtime support (___cxa_throw/___gxx_personality_v0
    // and friends) -- exactly what linking with ${CC} instead of ${CXX}
    // leaves undefined (cxx-link-driver-selection-req).
    try {
        throw std::runtime_error("exception path ok");
    } catch (const std::exception& e) {
        std::cout << e.what() << std::endl;
    }
    return 0;
}
