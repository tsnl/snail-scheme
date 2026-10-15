#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern void native_host_init(int argc, char **argv);
extern void native_module_init(void);
extern int native_finish(int status);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t checks(void) __asm__("wasm.compiler-collection-checks");
extern int64_t short_zip(void) __asm__("wasm.collection-short-zip");
extern int64_t missing_node(void) __asm__("wasm.collection-missing-node");
extern int64_t negative_index(void) __asm__("wasm.collection-negative-index");

// ---- Native64 invokes the same exports as the linked Wasm host ----

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    native_host_init(argc, argv);
    native_module_init();
    guest_main();
    if (!strcmp(argv[1], "compiler-collection-checks")) {
        if (checks() != 42) return native_finish(2);
        puts("PASS compiler collections: 42");
        return native_finish(0);
    }
    if (!strcmp(argv[1], "collection-short-zip")) short_zip();
    else if (!strcmp(argv[1], "collection-missing-node")) missing_node();
    else if (!strcmp(argv[1], "collection-negative-index")) negative_index();
    else return native_finish(2);
    fputs("negative control unexpectedly returned\n", stderr);
    return native_finish(2);
}
