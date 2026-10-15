// Canonical Ray inputs. This provider is a separate non-LTO object, so inputs
// and iteration barriers stay opaque to the guest's optimizing compiler.
#include "benchmark.h"
#include <stdio.h>
#include <stdlib.h>

static const char output_path[] = "outputs/ray.output";

// ---- Typed benchmark imports ----

static void invalid_input(void) {
    fputs("invalid Ray benchmark input index\n", stderr);
    exit(2);
}

int64_t input_i64(int32_t index) {
    if (index != 0 && index != 1) invalid_input();
    return 1;
}

double input_f64(int32_t index) {
    return (double)input_i64(index);
}

int64_t hide_i64(int64_t value) { return value; }
double hide_f64(double value) { return value; }
uint32_t barrier(void) { return 1; }
int64_t path_length(void) { return sizeof(output_path) - 1; }

uint32_t path_character(int64_t index) {
    if (index < 0 || (uint64_t)index >= sizeof(output_path) - 1) invalid_input();
    return (unsigned char)output_path[index];
}
