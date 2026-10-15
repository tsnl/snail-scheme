#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void guest_main(void) __asm__("wasm.main");
extern double trigonometry(int64_t, double) __asm__("wasm.trigonometry");

// ---- The same compiled Scheme worker calls Rust through native C linkage ----

int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    guest_main();
    for (int i = 1; i < argc; i++) {
        double value = strtod(argv[i], NULL);
        for (int64_t operation = 0; operation < 3; operation++)
            printf("%.17g\n", trigonometry(operation, value));
    }
    return native_finish(0);
}
