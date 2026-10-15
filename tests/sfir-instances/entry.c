#include <assert.h>
#include <stdint.h>

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern int64_t guest_main(void) __asm__("wasm.main");
// ---- Execute initialization; the provider records effects before any trap ----

int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    assert(guest_main() == 42);
    return native_finish(0);
}
