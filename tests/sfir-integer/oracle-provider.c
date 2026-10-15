#define _POSIX_C_SOURCE 200809L
#include "oracle.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ---- Scalar strings cross only the diagnostic boundary ----

char *arguments[2], *output;
size_t output_size;
static size_t output_capacity;
int64_t argument_length(int32_t index) {
    assert(index >= 0 && index < 2);
    return (int64_t)strlen(arguments[index]);
}
uint32_t argument_character(int32_t index, int64_t at) {
    assert(index >= 0 && index < 2 && at >= 0 && (size_t)at < strlen(arguments[index]));
    return (unsigned char)arguments[index][at];
}
void emit_character(uint32_t scalar) {
    assert(scalar < 128);
    if (output_size + 1 >= output_capacity) {
        output_capacity = output_capacity ? output_capacity * 2 : 128;
        output = realloc(output, output_capacity); assert(output);
    }
    output[output_size++] = (char)scalar;
    output[output_size] = 0;
}

