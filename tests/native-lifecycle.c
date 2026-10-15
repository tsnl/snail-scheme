#include "native-cleanup-observer.h"
extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void guest_main(void) __asm__("wasm.main");
int main(int argc, char **argv) {
    assert(atexit(observe_cleanup) == 0);
    native_host_init(argc, argv);
    native_module_init();
    guest_main();
    return native_finish(0);
}
