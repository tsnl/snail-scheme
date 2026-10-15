#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t bench(int64_t) __asm__("wasm.bench");
extern void observe(void) __asm__("wasm.observe");
int64_t load_input(const char *);
void free_input(void);

// ---- The complete decimal predicate precedes the ending clock ----

int main(int argc, char **argv) {
    assert(argc == 2);
    native_host_init(argc, argv);
    native_module_init();
    int64_t count = load_input(argv[1]);
    guest_main();
    struct timespec start, finish;
    if (clock_gettime(CLOCK_MONOTONIC, &start)) return native_finish(1);
    int passed = bench(count) == 1;
    if (clock_gettime(CLOCK_MONOTONIC, &finish)) return native_finish(1);
    if (!passed) return native_finish(1);
    double seconds = (double)(finish.tv_sec - start.tv_sec)
        + (double)(finish.tv_nsec - start.tv_nsec) / 1000000000.0;
    observe();
    free_input();
    printf("{\"result\":\"1\",\"seconds\":%.9f}\n", seconds);
    return native_finish(0);
}
