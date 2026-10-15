#include "scalar-provider.h"
#include "case-config.h"
#include <inttypes.h>
#include <stdio.h>

// ---- Scalar configuration mirrors the Wasm host's external input services ----

#ifndef OBSERVE_BARRIERS
#define OBSERVE_BARRIERS 1
#endif
static int64_t observed_barriers;
static void observe_barrier(void) {
#if OBSERVE_BARRIERS
    observed_barriers++;
#endif
}
int64_t input_i64(int32_t index) { return input_integers[index]; }
double input_f64(int32_t index) { return input_reals[index]; }
int64_t vector_length(int32_t index) { return vector_sizes[index]; }
int64_t vector_i64(int32_t index, int64_t element) { return vector_integers[vector_offsets[index] + element]; }
double vector_f64(int32_t index, int64_t element) { return vector_reals[vector_offsets[index] + element]; }
int64_t expected_length(void) { return expected_size; }
int64_t expected_i64(int64_t index) { return expected_integers[index]; }
double expected_f64(int64_t index) { return expected_reals[index]; }
double tolerance(void) { return expected_tolerance; }
int64_t count(void) { return configured_count; }
int64_t hide_i64(int64_t value) { observe_barrier(); return value; }
double hide_f64(double value) { observe_barrier(); return value; }
int32_t barrier(void) { observe_barrier(); return 1; }
int64_t benchmark_barriers(void) { return observed_barriers; }
void benchmark_reset_barriers(void) { observed_barriers = 0; }

// ---- Pathname constants use Unicode scalar values, matching the Wasm host ----

#if PATH_ARGUMENTS == 1
int64_t path_length(int32_t which) { return path_sizes[which]; }
uint32_t path_character(int32_t which, int64_t index) { return path_characters[path_offsets[which] + index]; }
#elif PATH_ARGUMENTS == 0
int64_t path_length(void) { return path_sizes[0]; }
uint32_t path_character(int64_t index) { return path_characters[index]; }
#endif

// ---- Complete diagnostic output remains inside the workload ----

void write_character(uint32_t value) {
    if (value < 128) { putchar((int)value); return; }
    unsigned width = value < 2048 ? 2 : value < 65536 ? 3 : 4;
    const unsigned first[] = {0, 0, 192, 224, 240};
    putchar((int)(first[width] | (value >> (6 * (width - 1)))));
    for (unsigned index = width - 1; index; index--)
        putchar((int)(128 | ((value >> (6 * (index - 1))) & 63)));
}

void write_char(uint32_t value) { write_character(value); }

void print_text(int64_t index) { fputs(diagnostic_text[index], stdout); }
void print_size(int64_t index, int64_t value) {
    printf("%s%" PRId64 "%s", diagnostic_prefix[index], value, diagnostic_suffix[index]);
}
void print_construction(int64_t iterations, int64_t depth) {
    printf("Creating %" PRId64 " trees of depth %" PRId64, iterations, depth);
}
