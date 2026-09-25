#include <iostream>
/* consteval is a genuine C++20-only construct -- absent in C++17 and
 * earlier, present and usable from C++20 on. */
consteval int square(int x) { return x * x; }
int main(){ std::cout << square(4) << std::endl; return 0; }
