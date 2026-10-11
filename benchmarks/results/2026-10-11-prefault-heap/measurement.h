// Experiment counters: setup precedes module initialization and Scheme timers.
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>

static struct rusage after_heap_setup;

static double heap_clock(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return time.tv_sec + time.tv_nsec * 1e-9;
}

static double usage_seconds(struct timeval time) {
    return time.tv_sec + time.tv_usec * 1e-6;
}

static void report_after_heap_setup(void) {
    struct rusage end;
    getrusage(RUSAGE_SELF, &end);
    fprintf(stderr, "HEAP_RUN user_s=%.6f system_s=%.6f minor_faults=%ld major_faults=%ld rss_kib=%ld\n",
            usage_seconds(end.ru_utime) - usage_seconds(after_heap_setup.ru_utime),
            usage_seconds(end.ru_stime) - usage_seconds(after_heap_setup.ru_stime),
            end.ru_minflt - after_heap_setup.ru_minflt,
            end.ru_majflt - after_heap_setup.ru_majflt, end.ru_maxrss);
}

static void record_heap_setup(double started) {
    getrusage(RUSAGE_SELF, &after_heap_setup);
    fprintf(stderr, "HEAP_SETUP seconds=%.6f minor_faults=%ld rss_kib=%ld\n",
            heap_clock() - started, after_heap_setup.ru_minflt, after_heap_setup.ru_maxrss);
    atexit(report_after_heap_setup);
}

static void prefault_memory(void *memory, size_t bytes) {
    volatile unsigned char *pages = memory;
    size_t page_size = (size_t)sysconf(_SC_PAGESIZE);
    for (size_t offset = 0; offset < bytes; offset += page_size) pages[offset] = 0;
    if (bytes) pages[bytes - 1] = 0;
}
