#include <inttypes.h>
#include <stdio.h>
#include <string.h>
extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t observe_once(void) __asm__("wasm.observe-once");
extern int64_t work_probe(void) __asm__("wasm.work-probe");
extern int64_t semantics_probe(void) __asm__("wasm.semantics-probe");
int main(int argc, char **argv) {
    native_host_init(argc, argv); native_module_init(); guest_main();
    const char *mode = argc > 1 ? argv[1] : "observe-once";
    int64_t result = !strcmp(mode, "semantics-probe") ? semantics_probe() :
                     !strcmp(mode, "work-probe") ? work_probe() : observe_once();
    int status = native_finish(0);
    printf("result:%" PRId64 "\n", result);
    return status;
}
