#include "native-mixed.h"
#include <assert.h>

int64_t mixed_scalar(int32_t a, int64_t b, float c, double d) {
    assert(a == -17 && b == INT64_MIN + 7 && c == 1.25f && d == -2.5);
    return INT64_MAX - 5;
}
float scalar_f32(float value) { assert(value == 1.25f); return value; }
double scalar_f64(int64_t value, double real) {
    assert(value == INT64_MAX - 5 && real == -2.5);
    return 3.5;
}
int32_t scalar_i32(int32_t value) { return value; }
void scalar_unit(int32_t value) { assert(value == 0x1f600); }
