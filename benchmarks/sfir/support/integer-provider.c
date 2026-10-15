#define _POSIX_C_SOURCE 200809L
#include "integer-provider.h"
#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ---- Input transport owns decimal text; Scheme owns all arithmetic ----

static int64_t inputs[3], count;
static char **expected;
#ifndef OBSERVE_BARRIERS
#define OBSERVE_BARRIERS 1
#endif
#if OBSERVE_BARRIERS
static uint64_t barriers;
#endif
int64_t load_input(const char *path) {
    FILE *input = fopen(path, "r"); assert(input);
    int64_t repetitions;
    assert(fscanf(input, "%" SCNd64, &repetitions) == 1);
    for (unsigned index = 0; index < 3; index++) assert(fscanf(input, "%" SCNd64, &inputs[index]) == 1);
    assert(fscanf(input, "%" SCNd64 "\n", &count) == 1 && count >= 0);
    expected = calloc((size_t)count, sizeof(*expected)); assert(expected);
    for (int64_t index = 0; index < count; index++) {
        size_t capacity = 0; assert(getline(&expected[index], &capacity, input) > 0);
        expected[index][strcspn(expected[index], "\n")] = 0;
    }
    assert(fgetc(input) == EOF); fclose(input); return repetitions;
}
void free_input(void) {
    for (int64_t index = 0; index < count; index++) free(expected[index]);
    free(expected);
}
int64_t input_i64(int32_t index) { assert(index >= 0 && index < 3); return inputs[index]; }
int64_t expected_count(void) { return count; }
int64_t expected_length(int64_t index) {
    assert(index >= 0 && index < count); return (int64_t)strlen(expected[index]);
}
uint32_t expected_character(int64_t index, int64_t at) {
    assert(index >= 0 && index < count && at >= 0 && (size_t)at < strlen(expected[index]));
    return (unsigned char)expected[index][at];
}
int64_t hide_i64(int64_t value) {
#if OBSERVE_BARRIERS
    barriers++;
#endif
    return value;
}
uint64_t barrier_count(void) {
#if OBSERVE_BARRIERS
    return barriers;
#else
    return 0;
#endif
}
void emit_character(uint32_t scalar) { assert(scalar < 128); putchar((int)scalar); }
