#define _POSIX_C_SOURCE 200809L
#include "case-config.h"
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>

// ---- The same exported worker runs between monotonic clock reads ----

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void guest_main(void) __asm__("wasm.main");
#if CONFIGURED_COUNT
extern int64_t guest_configured_count(void) __asm__("wasm.configured-count");
#endif
#if FLOAT_RESULT
extern double guest_bench(int64_t) __asm__("wasm.bench");
#else
extern int64_t guest_bench(int64_t) __asm__("wasm.bench");
#endif

static double elapsed(struct timespec start, struct timespec finish) {
    return (double)(finish.tv_sec - start.tv_sec)
        + (double)(finish.tv_nsec - start.tv_nsec) / 1000000000.0;
}

// Setup, formatting and final resource cleanup are outside the workload clock.
// This atomic transition keeps the full result predicate before the end clock.
int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    guest_main();
#if CONFIGURED_COUNT
    if (guest_configured_count() != configured_count) return native_finish(1);
#endif
    struct timespec start, finish;
    if (clock_gettime(CLOCK_MONOTONIC, &start)) return native_finish(1);
#if FLOAT_RESULT
    double result = guest_bench(configured_count);
#else
    int64_t result = guest_bench(configured_count);
#endif
    int passed = result == expected_result;
    if (clock_gettime(CLOCK_MONOTONIC, &finish)) return native_finish(1);
    if (!passed) return native_finish(1);
#if FLOAT_RESULT
    printf("{\"result\":\"%.17g\",", result);
#else
    printf("{\"result\":\"%" PRId64 "\",", result);
#endif
    printf("\"seconds\":%.9f}\n", elapsed(start, finish));
    return native_finish(0);
}
