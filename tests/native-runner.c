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
void drop_array(uint32_t) __asm__("snail:drop-array");
void drop_array(uint32_t id) { (void)id; abort(); }

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
extern uint32_t storage_check(uint32_t) __asm__("wasm.storage-check");
extern void storage_trap(uint32_t) __asm__("wasm.storage-trap");
extern uint64_t storage_u8(uint32_t, uint32_t) __asm__("wasm.storage-u8");
extern uint64_t storage_u16(uint32_t, uint32_t) __asm__("wasm.storage-u16");
extern uint64_t storage_i32(uint32_t, uint32_t) __asm__("wasm.storage-i32");
extern uint64_t storage_f32(uint32_t, uint32_t) __asm__("wasm.storage-f32");
extern uint64_t storage_f64(uint32_t, uint64_t) __asm__("wasm.storage-f64");
extern uint64_t static_u8(void) __asm__("wasm.storage-static-u8");
extern uint64_t static_u16(void) __asm__("wasm.storage-static-u16");
extern uint64_t static_i32(void) __asm__("wasm.storage-static-i32");
extern uint64_t static_f32(void) __asm__("wasm.storage-static-f32");
extern uint64_t static_f64(void) __asm__("wasm.storage-static-f64");
extern uint64_t global_f32_bits(void) __asm__("wasm.storage-global-f32-bits");
extern uint32_t storage_identity(void) __asm__("wasm.storage-identity");
extern uint64_t storage_roots(void) __asm__("wasm.storage-roots");

// No allocation occurs while inspecting a returned reference. Native byte order
// applies to both the expected C values and the mechanically lowered payload.
static void check_payload(uint64_t reference, const void *expected, size_t length, size_t width) {
    const uint64_t *words = (const uint64_t *)(uintptr_t)reference;
    assert(words[1] == length);
    assert(memcmp(words + 2, expected, length * width) == 0);
}

static void check_array_storage(void) {
    const uint8_t bytes[] = {0x45, 0x45, 0x45};
    const uint16_t halves[] = {0x2345, 0x2345, 0x2345};
    const uint32_t integers[] = {0x12345, 0x12345, 0x12345};
    const uint32_t floats[] = {0x80000000, 0x80000000, 0x80000000};
    const uint64_t doubles[] = {UINT64_C(0x8000000000000000), UINT64_C(0x8000000000000000)};
    check_payload(storage_u8(3, 0x12345), bytes, 3, 1);
    check_payload(storage_u16(3, 0x12345), halves, 3, 2);
    check_payload(storage_i32(3, 0x12345), integers, 3, 4);
    check_payload(storage_f32(3, 0x80000000), floats, 3, 4);
    check_payload(storage_f64(2, doubles[0]), doubles, 2, 8);
    const uint32_t float_nan[] = {0x7fc12345, 0x7fc12345};
    const uint64_t double_nan[] = {UINT64_C(0x7ff8000000001234), UINT64_C(0x7ff8000000001234)};
    check_payload(storage_f32(2, float_nan[0]), float_nan, 2, 4);
    check_payload(storage_f64(2, double_nan[0]), double_nan, 2, 8);
    check_payload(storage_u8(0, 42), bytes, 0, 1);
    const uint8_t fixed_bytes[] = {255, 52, 128};
    const uint16_t fixed_halves[] = {65535, 9029, 32768};
    const uint32_t fixed_integers[] = {UINT32_MAX, 42, INT32_MAX}, zeros[] = {0, 0, 0};
    const uint64_t fixed_doubles[] = {UINT64_C(0x8000000000000000), UINT64_C(0x3ff8000000000000),
                                    UINT64_C(0x7ff8000000001234)};
    const uint32_t global_floats[] = {0x80000000, 0x7fc12345};
    check_payload(static_u8(), fixed_bytes, 3, 1);
    check_payload(static_u16(), fixed_halves, 3, 2);
    check_payload(static_i32(), fixed_integers, 3, 4);
    check_payload(static_f32(), zeros, 3, 4);
    check_payload(static_f64(), fixed_doubles, 3, 8);
    check_payload(global_f32_bits(), global_floats, 2, 4);
    assert(storage_identity() == 1 && storage_roots() == 77);
    assert(storage_check(0x12345) == 1);
}

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
    if (argc == 3 && !strcmp(argv[1], "storage-trap")) { storage_trap(strtoul(argv[2], NULL, 10)); return 2; }
    if (argc > 1 && !strcmp(argv[1], "subtype-trap")) { read_right(left(41)); return 2; }
    if (argc > 1) { trap(strtoul(argv[1], NULL, 10)); return 2; }
    assert(check() == 0);
    check_array_storage();
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
