#define _POSIX_C_SOURCE 200809L
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int32_t fibonacci(int32_t n, int32_t a, int32_t b);

static double seconds(struct timespec value) {
    return value.tv_sec + value.tv_nsec * 1e-9;
}

static int64_t workload(int count) {
    int64_t checksum = 0;
    for (int repeat = 0; repeat < count; ++repeat) {
        for (int n = 22; n <= 25; ++n) checksum += (n + 1) * fibonacci(n, 0, 1);
    }
    return checksum;
}

int main(int argc, char **argv) {
    int count = argc == 2 ? atoi(argv[1]) : 1048576;
    struct timespec start, finish;
    if (count <= 0 || fibonacci(10, 2, 3) != 233 || fibonacci(46, 0, 1) != 1836311903) return 1;
    if (workload(count) != INT64_C(4204971) * count) return 1;
    clock_gettime(CLOCK_MONOTONIC, &start);
    int64_t checksum = workload(count);
    clock_gettime(CLOCK_MONOTONIC, &finish);
    if (checksum != INT64_C(4204971) * count) return 1;
    printf("checksum: %" PRId64 "\nelapsed: %.9f s; repetitions: %d\n",
           checksum, seconds(finish) - seconds(start), count);
    return 0;
}
