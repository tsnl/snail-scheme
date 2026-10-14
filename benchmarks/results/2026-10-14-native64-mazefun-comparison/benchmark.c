// Canonical scalar imports are opaque to the guest: compile without LTO.
#include "benchmark.h"
#include "benchmark-values.h"
#include <stdio.h>
#include <stdlib.h>

// ---- Typed benchmark imports ----

static void invalid_input(void) {
    fputs("invalid Mazefun benchmark input index\n", stderr);
    exit(2);
}

int64_t input_i64(int32_t index) {
    if (index != 0 && index != 1) invalid_input();
    return 11;
}

int64_t expected_i64(int64_t index) {
    if (index < 0 || (uint64_t)index >= sizeof(expected_grid) / sizeof(expected_grid[0])) invalid_input();
    return expected_grid[index];
}

int64_t hide_i64(int64_t value) { return value; }
