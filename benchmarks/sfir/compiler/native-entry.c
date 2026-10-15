#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t configured_count(void) __asm__("wasm.configured-count");
extern int64_t observe(void) __asm__("wasm.observe");
extern int64_t observe_fatal(void) __asm__("wasm.observe-fatal");
extern int64_t bench(int64_t) __asm__("wasm.bench");
extern int32_t close_all(void) __asm__("snail:io/close-all");
extern int64_t benchmark_barriers(void);

// ---- Each diagnostic is executed by the compiled SFIR program ----

int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    guest_main();
    assert(configured_count() == 2000);
    if (argc > 1 && strcmp(argv[1], "fatal") == 0) {
        observe_fatal();
        assert(!"fatal compiler handler returned");
    }
    assert(observe() == 22 && benchmark_barriers() == 0);
    puts("22");
    assert(bench(2000) == 1 && benchmark_barriers() == 6000);
    assert(close_all() == 0);
    puts("canonical2000 passed");
    return native_finish(0);
}
