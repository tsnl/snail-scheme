// Counter snapshots are outside the unchanged bench(50) workload clock.
#include <stdint.h>
#include <stdio.h>
#include <time.h>

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void native_diagnostic_report(const char *);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t guest_bench(int64_t) __asm__("wasm.bench");

// ---- Setup, full workload and cleanup ----

int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    guest_main();
    native_diagnostic_report("setup");
    struct timespec start, end;
    if (clock_gettime(CLOCK_MONOTONIC, &start)) return native_finish(2);
    if (guest_bench(50) != 1) return native_finish(1);
    if (clock_gettime(CLOCK_MONOTONIC, &end)) return native_finish(2);
    native_diagnostic_report("workload-end");
    double seconds = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
    int status = native_finish(0);
    native_diagnostic_report("finish");
    if (!status) printf("{\"seconds\":%.9f,\"result\":\"1\"}\n", seconds);
    return status;
}
