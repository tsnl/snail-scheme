// Execute translated Wasm directly, including GC and native stack invariants.
#include <assert.h>
#include <gc/gc.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern void native_poll_finalizers(void);
extern uint64_t native_finalizer_count(void);

#ifdef SNAIL_NATIVE_PROGRAM
extern void start(void) __asm__("wasm._start");
extern uint32_t live_roots(void) __asm__("wasm-global.awi_live_roots");

int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    start();
    // Returned Rust callbacks release every temporary AWI handle.
    assert(live_roots() == 3);
    for (int i = 0; i < 5; i++) { GC_gcollect(); native_poll_finalizers(); }
    if (argc > 1 && !strcmp(argv[1], "finalizers")) assert(native_finalizer_count() >= 64);
    return 0;
}
#else
extern uint32_t check(void) __asm__("wasm.check");
extern uint64_t tail(uint32_t) __asm__("wasm.tail");
extern uint64_t root(uint32_t) __asm__("wasm.root");
extern void trap(uint32_t) __asm__("wasm.trap");
extern int32_t i31_signed(int32_t) __asm__("wasm.i31-s");
extern uint32_t i31_unsigned(int32_t) __asm__("wasm.i31-u");

int main(int argc, char **argv) {
    struct rlimit stack = {256 * 1024, 256 * 1024};
    assert(setrlimit(RLIMIT_STACK, &stack) == 0);
    native_host_init(argc, argv);
    native_module_init();
    if (argc > 1) { trap(strtoul(argv[1], NULL, 10)); return 2; }
    assert(check() == 0);
    assert(i31_signed(INT32_MIN) == 0);
    assert(i31_signed(1073741824) == -1073741824);
    assert(i31_signed(-1) == -1);
    assert(i31_unsigned(-1) == 2147483647);
    assert(tail(2000000) == 42);
    assert(root(500) == 99);
    assert(GC_get_gc_no() > 1);
    return 0;
}
#endif
