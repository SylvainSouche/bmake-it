#include <iostream>
#include <omp.h>
#include <set>
#include <mutex>
int main(){
    std::set<int> ids;
    std::mutex m;
    #pragma omp parallel for
    for (int i = 0; i < 8; i++) {
        std::lock_guard<std::mutex> lk(m);
        ids.insert(omp_get_thread_num());
    }
    std::cout << "threads used: " << ids.size() << std::endl;
    return ids.size() > 1 ? 0 : 1;
}
