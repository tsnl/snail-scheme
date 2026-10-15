// This separate entry records boundary counts and an expected negative control.
#include <stdint.h>
#include <stdio.h>
#include <time.h>

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void benchmark_report(const char *);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t guest_bench(int64_t) __asm__("wasm.bench");

// ---- Snapshot setup and full work separately ----

int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    guest_main();
    benchmark_report("setup");
    struct timespec start, end;
    if (clock_gettime(CLOCK_MONOTONIC, &start)) return native_finish(2);
    int64_t result = guest_bench(10000);
    int correct = result == 1;
    if (clock_gettime(CLOCK_MONOTONIC, &end)) return native_finish(2);
    benchmark_report("workload-end");
    double seconds = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
    int status = native_finish(correct ? 0 : 1);
    printf("{\"seconds\":%.9f,\"result\":\"%lld\"}\n", seconds, (long long)result);
    return status;
}
