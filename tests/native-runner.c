// Execute lowered Wasm datums, including GC and native stack invariants.
#include <assert.h>
#ifdef SNAIL_PRECISE_GC
#include "precise-gc.h"
#else
#include <gc/gc.h>
#endif
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern void native_poll_finalizers(void);
extern uint64_t native_finalizer_count(void);

#ifdef SNAIL_NATIVE_PROGRAM
extern int snail_cli_main(void);
extern uint32_t live_roots(void) __asm__("wasm-global.awi_live_roots");
extern uint32_t atom(uint32_t) __asm__("wasm.atom");
extern uint32_t kind(uint32_t) __asm__("wasm.kind");
extern uint32_t atom_value(uint32_t) __asm__("wasm.atom_value");
extern uint32_t same(uint32_t, uint32_t) __asm__("wasm.same");
extern uint32_t identity_hash(uint32_t) __asm__("wasm.identity_hash");
extern void release(uint32_t) __asm__("wasm.release");
extern uint32_t literal_symbol_names(void) __asm__("wasm.literal_symbol_names");
extern uint32_t length(uint32_t) __asm__("wasm.length");
extern uint32_t at(uint32_t, uint32_t) __asm__("wasm.at");
extern uint32_t char_at(uint32_t, uint32_t) __asm__("wasm.char_at");

static void check_symbol_tags(void) {
    const uint32_t ids[] = {0, 0x3fffffff, 0x40000000, 0x7fffffff};
    for (size_t i = 0; i < sizeof(ids) / sizeof(ids[0]); i++) {
        uint32_t tag = ids[i] | 0x80000000;
        uint32_t a = atom(tag), b = atom(tag), character = atom(256 + 955);
        assert(kind(a) == 10 && atom_value(a) == tag && same(a, b));
        assert(!same(a, character) && identity_hash(a) == identity_hash(b));
        release(a); release(b); release(character);
    }
}

static void check_symbol_names(void) {
    uint32_t names = literal_symbol_names();
    for (uint32_t id = 0; id < length(names); id++) {
        uint32_t name = at(names, id), symbol = atom(id | 0x80000000);
        assert(length(name) == length(symbol));
        for (uint32_t index = 0; index < length(name); index++)
            assert(char_at(name, index) == char_at(symbol, index));
        release(name); release(symbol);
    }
    release(names);
}

int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    assert(snail_cli_main() == 0);
    check_symbol_tags();
    check_symbol_names();
    // Returned Rust callbacks release every temporary AWI handle.
    assert(live_roots() == 3);
    for (int i = 0; i < 5; i++) { GC_gcollect(); native_poll_finalizers(); }
    if (argc > 1 && !strcmp(argv[1], "finalizers")) assert(native_finalizer_count() >= 64);
    return 0;
}
#else
// The instruction fixture has no Rust services or resource wrappers.
void snail_cli_report_failure(void) {}
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
    assert(tail(2000000) == 42);
    assert(root(500) == 99);
    assert(tail_gc(20000) == 42);
    assert(gc_operands() == 42);
#ifdef SNAIL_PRECISE_GC
    assert(native_roots == NULL);
#endif
    assert(GC_get_gc_no() > 1);
    return 0;
}
#endif
