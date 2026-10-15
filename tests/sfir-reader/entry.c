#include <inttypes.h>
#include <stdio.h>
extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t check(void) __asm__("wasm.check");
extern int32_t storage(void) __asm__("wasm.storage");
extern int64_t scan(void) __asm__("wasm.scan");

// ---- Initialize one actual native module and consume its complete stream ----

int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    guest_main();
    if (check() != 42 || !storage()) return native_finish(2);
    printf("result:%" PRId64 "\n", scan());
    return native_finish(0);
}
