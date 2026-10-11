#define _POSIX_C_SOURCE 200809L
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int32_t fibonacci(int32_t n, int32_t offset);

static double seconds(struct timespec value) {
    return value.tv_sec + value.tv_nsec * 1e-9;
}

int main(int argc, char **argv) {
    int count = argc == 2 ? atoi(argv[1]) : 64;
    int64_t checksum = 0;
    struct timespec start, finish;
    for (int n = 0; n <= 12; ++n) (void)fibonacci(n, 0);
    clock_gettime(CLOCK_MONOTONIC, &start);
    for (int repeat = 0; repeat < count; ++repeat) {
        for (int n = 22; n <= 25; ++n) checksum += (n + 1) * fibonacci(n, 0);
    }
    clock_gettime(CLOCK_MONOTONIC, &finish);
    if (count <= 0 || checksum != INT64_C(4204971) * count) return 1;
    printf("checksum: %" PRId64 "\nelapsed: %.9f s; repetitions: %d\n",
           checksum, seconds(finish) - seconds(start), count);
    return 0;
}
