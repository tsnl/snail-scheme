// Execute lowered Wasm datums, including GC and native stack invariants.
#include <assert.h>
#include "precise-gc.h"
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>

extern void native_host_init(int, char **);
extern void native_roots_reset_peak(void);
extern uint64_t native_roots_peak(void);
extern uint64_t left(int64_t) __asm__("wasm.left");
extern int64_t read_parent(uint64_t) __asm__("wasm.read-parent");
extern int64_t read_right(uint64_t) __asm__("wasm.read-right");
extern uint32_t same_left(uint64_t) __asm__("wasm.same-left");
extern uint32_t is_right(uint64_t) __asm__("wasm.is-right");
extern uint32_t cyclic(uint64_t) __asm__("wasm.cyclic");
extern void native_module_init(void);
extern void native_poll_finalizers(void);
extern uint64_t native_finalizer_count(void);

// The instruction fixture has no Rust services or resource wrappers.
int snail_native_cleanup(void) { return 0; }
void drop_resource(uint32_t, uint32_t) __asm__("snail:drop-resource");
void drop_resource(uint32_t kind, uint32_t id) { (void)kind; (void)id; abort(); }

extern uint32_t check(void) __asm__("wasm.check");
extern uint64_t tail(uint32_t) __asm__("wasm.tail");
extern uint64_t root(uint32_t) __asm__("wasm.root");
extern uint64_t tail_gc(uint32_t) __asm__("wasm.tail-gc");
extern uint64_t gc_operands(void) __asm__("wasm.gc-operands");
extern void trap(uint32_t) __asm__("wasm.trap");
extern int32_t i31_signed(int32_t) __asm__("wasm.i31-s");
extern uint32_t i31_unsigned(int32_t) __asm__("wasm.i31-u");
extern uint32_t i31_equal_negative(int32_t) __asm__("wasm.i31-eq-negative");
extern uint32_t sat_i32_f32_s(float) __asm__("wasm.sat-i32-f32-s");
extern uint32_t sat_i32_f32_u(float) __asm__("wasm.sat-i32-f32-u");
extern uint32_t sat_i32_f64_s(double) __asm__("wasm.sat-i32-f64-s");
extern uint32_t sat_i32_f64_u(double) __asm__("wasm.sat-i32-f64-u");
extern uint64_t sat_i64_f32_s(float) __asm__("wasm.sat-i64-f32-s");
extern uint64_t sat_i64_f32_u(float) __asm__("wasm.sat-i64-f32-u");
extern uint64_t sat_i64_f64_s(double) __asm__("wasm.sat-i64-f64-s");
extern uint64_t sat_i64_f64_u(double) __asm__("wasm.sat-i64-f64-u");

static void check_saturation(const char *input) {
    double number = strtod(input, NULL);
    float narrow = (float)number;
    printf("%" PRIu32 " %" PRIu32 " %" PRIu32 " %" PRIu32 " "
           "%" PRIu64 " %" PRIu64 " %" PRIu64 " %" PRIu64 "\n",
           sat_i32_f32_s(narrow), sat_i32_f32_u(narrow),
           sat_i32_f64_s(number), sat_i32_f64_u(number),
           sat_i64_f32_s(narrow), sat_i64_f32_u(narrow),
           sat_i64_f64_s(number), sat_i64_f64_u(number));
}

int main(int argc, char **argv) {
    struct rlimit stack = {256 * 1024, 256 * 1024};
    assert(setrlimit(RLIMIT_STACK, &stack) == 0);
    native_host_init(argc, argv);
    native_module_init();
    if (argc == 3 && !strcmp(argv[1], "saturate")) { check_saturation(argv[2]); return 0; }
    if (argc > 1 && !strcmp(argv[1], "subtype-trap")) { read_right(left(41)); return 2; }
    if (argc > 1) { trap(strtoul(argv[1], NULL, 10)); return 2; }
    assert(check() == 0);
    assert(i31_signed(INT32_MIN) == 0);
    assert(i31_signed(1073741824) == -1073741824);
    assert(i31_signed(-1) == -1);
    assert(i31_unsigned(-1) == 2147483647);
    assert(i31_signed(1073741823) == 1073741823);
    assert(i31_unsigned(1073741824) == 1073741824);
    assert(i31_signed(INT32_MAX) == -1);
    assert(i31_equal_negative(-1) && i31_equal_negative(INT32_MAX));
    assert(!i31_equal_negative(0));
    native_roots_reset_peak();
    assert(tail(getenv("SNAIL_NATIVE_TAIL_STRESS") ? 2000 : 2000000) == 42);
    assert(native_roots_peak() < 8);
    assert(root(500) == 99);
    native_roots_reset_peak();
    assert(tail_gc(20000) == 42);
    assert(native_roots_peak() < 8);
    assert(gc_operands() == 42);
    struct { NativeRoots *previous; uint64_t capacity, count, values[1]; } keep;
    native_roots_enter((NativeRoots *)&keep, 1);
    keep.values[0] = left(INT64_MIN); keep.count = 1;
    native_gc_collect();
    assert(read_parent(keep.values[0]) == INT64_MIN);
    assert(same_left(keep.values[0]) && !is_right(keep.values[0]));
    assert(cyclic(keep.values[0]));
    native_roots_leave((NativeRoots *)&keep);
    assert(native_roots == NULL);
    assert(native_gc_collections() > 1);
    return 0;
}
