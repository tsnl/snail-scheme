#include "heap.hh"

#include <cstdlib>

void* heap_allocate(size_t size_in_bytes) {
    // todo: replace with a real implementation
    return malloc(size_in_bytes);
}

void heap_mark_in_use(void* ptr) {
    // todo: implement me!
}
void heap_sweep() {
    // todo: implement me!
}