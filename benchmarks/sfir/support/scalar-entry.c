#include "case-config.h"
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern uint64_t native_resource_release_count(void);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t benchmark_barriers(void);
extern void benchmark_reset_barriers(void);
#if CONFIGURED_COUNT
extern int64_t guest_configured_count(void) __asm__("wasm.configured-count");
#endif
#if FLOAT_RESULT
extern double guest_bench(int64_t) __asm__("wasm.bench");
#else
extern int64_t guest_bench(int64_t) __asm__("wasm.bench");
#endif

// The native route invokes the same exported worker and checks the same result
// as the Wasm host. Native module initialization precedes untimed main setup.
int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    guest_main();
    int64_t setup = benchmark_barriers();
    uint64_t setup_closed = native_resource_release_count();
    benchmark_reset_barriers();
#if CONFIGURED_COUNT
    if (guest_configured_count() != configured_count) return native_finish(1);
#endif
#if FLOAT_RESULT
    double result = guest_bench(configured_count);
    printf("{\"result\":\"%.17g\",", result);
#else
    int64_t result = guest_bench(configured_count);
    printf("{\"result\":\"%" PRId64 "\",", result);
#endif
    uint64_t worker_closed = native_resource_release_count() - setup_closed;
    int passed = result == expected_result && (expected_setup < 0 || setup == expected_setup)
        && benchmark_barriers() == expected_barriers
        && (expected_setup_closed < 0 || setup_closed == (uint64_t)expected_setup_closed)
        && (expected_worker_closed < 0 || worker_closed == (uint64_t)expected_worker_closed);
    int status = native_finish(passed ? 0 : 1);
    uint64_t cleanup_closed = native_resource_release_count() - setup_closed - worker_closed;
    printf("\"barriers\":%" PRId64 ",\"setup_closed\":%" PRIu64 ",\"worker_closed\":%" PRIu64
           ",\"cleanup_closed\":%" PRIu64 "}\n", benchmark_barriers(), setup_closed, worker_closed, cleanup_closed);
    return cleanup_closed ? 1 : status;
}
