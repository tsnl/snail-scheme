#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern int32_t sfir_main(void) __asm__("wasm.main");
extern void constant_arithmetic(int32_t) __asm__("wasm.constant-arithmetic");
extern int32_t calculate_i32(int32_t, int32_t, int32_t, int32_t) __asm__("wasm.calculate-i32");
extern int64_t calculate_i64(int32_t, int32_t, int64_t, int64_t) __asm__("wasm.calculate-i64");
extern float calculate_f32(int32_t, int32_t, float, float) __asm__("wasm.calculate-f32");
extern double calculate_f64(int32_t, int32_t, double, double) __asm__("wasm.calculate-f64");
extern void discard_i32(int32_t, int32_t, int32_t, int32_t, int32_t) __asm__("wasm.discard-i32");
extern void discard_i64(int32_t, int32_t, int32_t, int64_t, int64_t) __asm__("wasm.discard-i64");
extern void discard_f32(int32_t, int32_t, int32_t, float, float) __asm__("wasm.discard-f32");
extern void discard_f64(int32_t, int32_t, int32_t, double, double) __asm__("wasm.discard-f64");

// ---- The supplied expected value is independent of native arithmetic ----

static int same_float(double value, const char *text) {
    double expected = strtod(text, NULL);
    if (isnan(expected)) return isnan(value);
    return value == expected && (value != 0 || !!signbit(value) == !!signbit(expected));
}

static int check_value(const char *kind, int32_t route, int32_t operation,
                       const char *left, const char *right, const char *expected) {
    if (!strcmp(kind, "i32"))
        return calculate_i32(route, operation, (int32_t)strtol(left, NULL, 10), (int32_t)strtol(right, NULL, 10)) == strtoll(expected, NULL, 10);
    if (!strcmp(kind, "i64"))
        return calculate_i64(route, operation, strtoll(left, NULL, 10), strtoll(right, NULL, 10)) == strtoll(expected, NULL, 10);
    if (!strcmp(kind, "f32")) return same_float(calculate_f32(route, operation, strtof(left, NULL), strtof(right, NULL)), expected);
    return same_float(calculate_f64(route, operation, strtod(left, NULL), strtod(right, NULL)), expected);
}

static int discard_value(const char *kind, int32_t selected, int32_t route,
                         int32_t operation, const char *left, const char *right) {
    if (!strcmp(kind, "i32")) discard_i32(selected, route, operation, (int32_t)strtol(left, NULL, 10), (int32_t)strtol(right, NULL, 10));
    else if (!strcmp(kind, "i64")) discard_i64(selected, route, operation, strtoll(left, NULL, 10), strtoll(right, NULL, 10));
    else if (!strcmp(kind, "f32")) discard_f32(selected, route, operation, strtof(left, NULL), strtof(right, NULL));
    else discard_f64(selected, route, operation, strtod(left, NULL), strtod(right, NULL));
    return 1;
}

int main(int argc, char **argv) {
    native_host_init(argc, argv);
    setvbuf(stdout, NULL, _IONBF, 0);
    native_module_init();
    if (sfir_main() != 42 || argc != 8) return native_finish(2);
    int32_t route = (int32_t)strtol(argv[3], NULL, 10), operation = (int32_t)strtol(argv[4], NULL, 10);
    if (!strcmp(argv[1], "constant")) { constant_arithmetic(operation); return native_finish(0); }
    int valid = !strcmp(argv[1], "value") ? check_value(argv[2], route, operation, argv[5], argv[6], argv[7])
        : discard_value(argv[2], !strcmp(argv[1], "discard"), route, operation, argv[5], argv[6]);
    return native_finish(valid ? 0 : 2);
}
