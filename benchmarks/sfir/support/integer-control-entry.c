#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t bench(int64_t) __asm__("wasm.bench");
extern void observe(void) __asm__("wasm.observe");
int64_t load_input(const char *);
void free_input(void);
uint64_t barrier_count(void);

// ---- Initialization precedes computation and its complete result predicate ----

int main(int argc, char **argv) {
    assert(argc == 2 || argc == 3);
    const char *mode = argc == 3 ? argv[2] : "--validate";
    int timed = strcmp(mode, "--time") == 0;
    native_host_init(argc, argv); native_module_init();
    int64_t count = load_input(argv[1]); guest_main();
    struct timespec before, after;
    if (timed) assert(clock_gettime(CLOCK_MONOTONIC, &before) == 0);
    int64_t result = bench(count);
    if (timed) assert(clock_gettime(CLOCK_MONOTONIC, &after) == 0);
    assert(result == (count > 0 && strcmp(mode, "--reject") != 0));
    assert(barrier_count() == 3 * (uint64_t)count);
    if (strcmp(mode, "--probe") != 0) observe();
    if (timed) {
        double seconds = (double)(after.tv_sec - before.tv_sec) + (double)(after.tv_nsec - before.tv_nsec) / 1e9;
        printf("+!CSVLINE!+snail-integer,native:%lld,%.9f\n", (long long)count, seconds);
    }
    free_input(); return native_finish(0);
}
