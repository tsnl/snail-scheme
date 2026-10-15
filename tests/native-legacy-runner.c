#include "native-cleanup-observer.h"
#include "precise-gc.h"
#include <string.h>
extern void native_host_init(int, char **);
extern void native_module_init(void);
extern void native_poll_finalizers(void);
extern uint64_t native_finalizer_count(void);
extern int native_finish(int);
extern uint64_t guest_main(void) __asm__("wasm.snail_main");
int main(int argc, char **argv) {
    assert(atexit(observe_cleanup) == 0);
    native_host_init(argc, argv);
    native_module_init();
    guest_main();
    assert(!native_roots);
    native_gc_collect();
    native_poll_finalizers();
    if (argc > 1 && !strcmp(argv[1], "finalizers")) assert(native_finalizer_count() >= 64);
    int arrays = argc > 1 && !strcmp(argv[1], "arrays");
    if (arrays) assert(native_array_release_count() == 64);
    int status = native_finish(0);
    if (arrays) assert(native_array_release_count() == 65);
    return status;
}
