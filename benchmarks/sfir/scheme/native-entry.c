#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern uint64_t native_resource_release_count(void);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t configured_count(void) __asm__("wasm.configured-count");
extern int64_t observe(void) __asm__("wasm.observe");
extern int64_t bench(int64_t) __asm__("wasm.bench");
extern int64_t benchmark_barriers(void);

// ---- Probes precede the complete canonical sorting worker ----

int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    guest_main();
    uint64_t setup_closed = native_resource_release_count();
    int passed = configured_count() == 100000 && benchmark_barriers() == 0 && setup_closed == 1;
    int64_t probes = passed ? observe() : -1;
    uint64_t probes_closed = native_resource_release_count() - setup_closed;
    passed = passed && probes == 26 && benchmark_barriers() == 0 && probes_closed == 1;
    int64_t result = passed ? bench(100000) : -1;
    uint64_t worker_closed = native_resource_release_count() - setup_closed - probes_closed;
    passed = passed && result == 1 && benchmark_barriers() == 100000 && worker_closed == 0;
    int status = native_finish(passed ? 0 : 1);
    uint64_t cleanup_closed = native_resource_release_count() - setup_closed - probes_closed - worker_closed;
    printf("{\"probes\":%" PRId64 ",\"result\":%" PRId64 ",\"barriers\":%" PRId64 ",\"setup_closed\":%" PRIu64
           ",\"probes_closed\":%" PRIu64 ",\"worker_closed\":%" PRIu64 ",\"cleanup_closed\":%" PRIu64 "}\n",
           probes, result, benchmark_barriers(), setup_closed, probes_closed, worker_closed, cleanup_closed);
    return status || cleanup_closed != 0;
}
