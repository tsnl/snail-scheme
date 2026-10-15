#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void guest_main(void) __asm__("wasm.main");
extern double unary(int64_t, double) __asm__("wasm.unary");
extern double binary(int64_t, double, double) __asm__("wasm.binary");
extern int64_t character(int64_t, uint32_t) __asm__("wasm.character");

// ---- Call the same typed exports through their native C signatures ----

int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    guest_main();
    if ((argc - 1) % 4) return native_finish(2);
    for (int i = 1; i < argc; i += 4) {
        int64_t operation = strtoll(argv[i + 1], NULL, 10);
        double left = strtod(argv[i + 2], NULL), right = strtod(argv[i + 3], NULL);
        if (!strcmp(argv[i], "unary")) printf("%.17g\n", unary(operation, left));
        else if (!strcmp(argv[i], "binary")) printf("%.17g\n", binary(operation, left, right));
        else if (!strcmp(argv[i], "character")) printf("%" PRId64 "\n", character(operation, (uint32_t)left));
        else return native_finish(3);
    }
    return native_finish(0);
}
