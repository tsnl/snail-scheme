// Because this interpreter relies on a lot of boxing, we offer a permanent stack allocator that is de-allocated when
// the program exits.
// This bounds the program's memory usage to a hard limit (including the run-time) while ensuring boxed objects are 
// allocated beside each other when allocated in sequence.
// The GC heap can be a sub-range of this stack since this address range is stable.

#include <cstddef>

void* heap_allocate(size_t size_in_bytes);
void heap_mark_in_use(void* ptr);
void heap_sweep();
