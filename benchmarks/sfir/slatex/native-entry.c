#include <assert.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern uint64_t native_resource_release_count(void);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t configured_count(void) __asm__("wasm.configured-count");
extern int64_t bench(int64_t) __asm__("wasm.bench");
extern int64_t benchmark_barriers(void);

// ---- Canonical worker and explicit resource lifetimes ----

int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    guest_main();
    assert(configured_count() == 500 && benchmark_barriers() == 0);
    assert(native_resource_release_count() == 1);
    assert(bench(500) == 1 && benchmark_barriers() == 500);
    assert(native_resource_release_count() == 94502);
    int status = native_finish(0);
    assert(native_resource_release_count() == 94502);
    puts("canonical 500; setup closed 1; worker closed 94501; cleanup closed 0");
    return status;
}
