#include <assert.h>
#include <stdint.h>
#include <string.h>

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern void initialize(void) __asm__("wasm.main");
extern int32_t invoke(int32_t) __asm__("wasm.entry");

static int32_t count;
int32_t entry_tick(void) { return ++count; }
// This fixture owns no Rust services or resource wrappers.
int snail_native_cleanup(void) { return 0; }

int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    assert(count == 0);
    if (argc > 1 && !strcmp(argv[1], "early")) return invoke(1);
    initialize();
    assert(count == 1);
    assert(invoke(1) == 42 && invoke(2) == 43);
    if (argc > 1 && !strcmp(argv[1], "repeat")) initialize();
    assert(count == 1);
    return 0;
}
