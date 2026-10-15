#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern int32_t sfir_main(void) __asm__("wasm.main");
extern int32_t effect_count(void) __asm__("wasm.effect-count");
extern int32_t narrow_integer(int32_t, int64_t) __asm__("wasm.narrow-integer");
extern float narrow_float(int32_t, double) __asm__("wasm.narrow-float");

// ---- The caller supplies values and independently computed expected results ----

static int check_float(int32_t indirect, const char *input, const char *expected) {
    float actual = narrow_float(indirect, strtod(input, NULL));
    float target = strtof(expected, NULL);
    return isnan(target) ? isnan(actual)
                         : actual == target && (target != 0 || !!signbit(actual) == !!signbit(target));
}

int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    if (sfir_main() != 42 || argc != 5) return native_finish(2);
    int32_t indirect = (int32_t)strtol(argv[2], NULL, 10);
    int valid = !strcmp(argv[1], "integer")
        ? narrow_integer(indirect, strtoll(argv[3], NULL, 10)) == strtoll(argv[4], NULL, 10)
        : check_float(indirect, argv[3], argv[4]);
    return native_finish(valid && effect_count() == 1 ? 0 : 2);
}
