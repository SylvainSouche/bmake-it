#include "greet.h"
#include <iostream>
#include <stdexcept>

int main() {
    std::cout << greet("world") << std::endl;
    try {
        greet("");
    } catch (const std::exception& e) {
        std::cout << "caught: " << e.what() << std::endl;
    }
    return 0;
}
