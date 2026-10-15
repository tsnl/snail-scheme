// A separate non-LTO provider counts only scalar boundary activity.
// Its expectation flip is excluded from the measured provider and executable.
#include "benchmark.h"
#include "benchmark-values.h"
#include <stdio.h>
#include <stdlib.h>

static uint64_t input_reads, expected_reads, hides;

// ---- Canonical inputs with a controlled final-cell mismatch ----

int64_t input_i64(int32_t index) {
    if (index != 0 && index != 1) exit(2);
    input_reads++;
    return 11;
}

int64_t expected_i64(int64_t index) {
    if (index < 0 || (uint64_t)index >= sizeof(expected_grid) / sizeof(expected_grid[0])) exit(2);
    expected_reads++;
    return expected_grid[index] ^ (index == 133 && getenv("SNAIL_MAZEFUN_FLIP_LAST") != NULL);
}

int64_t hide_i64(int64_t value) {
    hides++;
    return value;
}

// ---- Cumulative snapshots outside the diagnostic workload clock ----

void benchmark_report(const char *phase) {
    fprintf(stderr, "benchmark phase=%s input_reads=%llu expected_reads=%llu hides=%llu\n", phase,
            (unsigned long long)input_reads, (unsigned long long)expected_reads, (unsigned long long)hides);
}
