// Native host for lowered Wasm: exact roots, checked operations and cleanup.
// Compiled code publishes managed roots; Rust services own scalar resources.
// Managed references, native C pointers and scalar handles stay distinct.

#define _GNU_SOURCE
#include "precise-gc.h"
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if UINTPTR_MAX != UINT64_MAX
#error "The native Wasm backend requires a 64-bit address space"
#endif

// ---- Traps and collection ----

extern int snail_native_cleanup(void);
static uint64_t released_resources;
void native_resource_released(void) { released_resources++; }
uint64_t native_resource_release_count(void) { return released_resources; }

// Every runtime service drops its resource borrow before an allocation or
// callback. Cleanup closes owned files without calling guest code or releasing
// roots. Expected failure never unwinds or longjmps through Rust frames.
int native_finish(int status) {
    if (snail_native_cleanup() && !status) status = 1;
    return status;
}

_Noreturn void native_fail(const char *message) {
    fprintf(stderr, "%s\n", message);
    exit(native_finish(1));
}

_Noreturn void native_trap(void) { native_fail("WebAssembly trap"); }

// This boundary accepts a native pointer and size_t; it is deliberately not
// the Wasm memory32 diagnostics import with the same conceptual purpose.
_Noreturn void native_report_error(const uint8_t *bytes, size_t length) {
    fputs("snail-sfir: ", stderr);
    fwrite(bytes, 1, length, stderr);
    fputc('\n', stderr);
    exit(native_finish(1));
}

// A tail call unlinks before transfer. The callee links before any collection.
// Collecting calls see every live translated frame. There is no asynchronous GC.
NativeRoots *volatile native_roots;
static uint64_t root_depth, peak_root_depth;
void native_roots_reset_peak(void) { peak_root_depth = root_depth; }
uint64_t native_roots_peak(void) { return peak_root_depth; }
void native_roots_enter(NativeRoots *frame, uint64_t capacity) {
    frame->capacity = capacity;
    frame->count = 0;
    if (!capacity) return;
    frame->previous = native_roots;
    native_roots = frame;
    if (++root_depth > peak_root_depth) peak_root_depth = root_depth;
}
void native_roots_leave(NativeRoots *frame) {
    if (frame->capacity) {
        native_roots = frame->previous;
        root_depth--;
    }
}

static uint64_t allocations, collection_interval;

static void *try_allocate(uint64_t size) {
    if (collection_interval && ++allocations % collection_interval == 0) native_gc_collect();
    return native_gc_alloc(size);
}

__attribute__((always_inline)) uint64_t native_alloc(uint64_t size) {
    void *object = try_allocate(size);
    if (!object) native_fail("native GC arena exhausted (SNAIL_GC_HEAP_BYTES)");
    return (uintptr_t)object;
}

static uint64_t *object_words(uint64_t reference) {
    if (!reference || (reference & 1)) native_trap();
    return (uint64_t *)(uintptr_t)reference;
}

extern const uint64_t native_gc_parents[], native_gc_parents_count;

uint32_t native_ref_test(uint64_t reference, int64_t type, uint32_t nullable, uint32_t exact) {
    if (!reference) return nullable;
    if (type == -1) return (reference & 1) || ((object_words(reference)[0] & 3) != 0);
    if (type == -2) return reference & 1;
    if ((reference & 1) || type == -6) return 0;
    uint64_t actual = object_words(reference)[0];
    if (type < 0) return (actual & 3) == (type == -3 ? 2 : type == -4 ? 3 : 0);
    while (actual != (uint64_t)type && !exact && actual) {
        uint64_t index = (actual >> 2) - 1;
        if (index >= native_gc_parents_count) native_trap();
        actual = native_gc_parents[index];
    }
    return actual == (uint64_t)type;
}

// ---- GC arrays and rooted tables ----

// Arrays have two eight-byte header words, then tightly stored Wasm elements.
// LLVM supplies a constant stride from the validated storage type: 1/2/4/8
// bytes for numeric elements, always eight for references. Lengths remain
// unsigned wasm32. The collector traces only reference arrays; their layout
// is unchanged. Translated frames and tables expose live references to the GC.

static void array_fill(void *payload, uint32_t length, uint64_t initial, uint32_t stride) {
    // Typed stores retain the low bits on either native byte order. No allocation
    // or callback occurs while the newly allocated object is being initialized.
    switch (stride) {
    case 1: memset(payload, (uint8_t)initial, length); break;
    case 2: for (uint32_t i = 0; i < length; i++) ((uint16_t *)payload)[i] = (uint16_t)initial; break;
    case 4: for (uint32_t i = 0; i < length; i++) ((uint32_t *)payload)[i] = (uint32_t)initial; break;
    case 8: for (uint32_t i = 0; i < length; i++) ((uint64_t *)payload)[i] = initial; break;
    default: native_trap();
    }
}

uint64_t native_array_new(uint64_t type, uint32_t length, uint64_t initial, uint32_t stride) {
    uint64_t reference = native_alloc(16 + (uint64_t)length * stride);
    uint64_t *words = object_words(reference);
    words[0] = type;
    words[1] = length;
    array_fill(words + 2, length, initial, stride);
    return reference;
}

uint32_t native_array_length(uint64_t reference) {
    return (uint32_t)object_words(reference)[1];
}

void *native_array_slot(uint64_t reference, uint32_t index, uint32_t stride) {
    uint64_t *words = object_words(reference);
    if (index >= words[1]) native_trap();
    return (uint8_t *)(words + 2) + (uint64_t)index * stride;
}

void native_array_copy(uint64_t target, uint32_t to, uint64_t source,
                       uint32_t from, uint32_t count, uint32_t stride) {
    uint64_t *destination = object_words(target), *origin = object_words(source);
    if ((uint64_t)to + count > destination[1] || (uint64_t)from + count > origin[1])
        native_trap();
    memmove((uint8_t *)(destination + 2) + (uint64_t)to * stride,
            (uint8_t *)(origin + 2) + (uint64_t)from * stride, (uint64_t)count * stride);
}

// Headerless table buffers have explicit ownership outside the GC arena.
// The collector enumerates current cells through the permanent table identity.
static uint64_t *table_allocate(uint64_t bytes) {
    return calloc(1, bytes ? bytes : 1);
}

void native_table_init(NativeTable *table, uint32_t length, uint32_t maximum) {
    if (length > maximum) native_trap();
    table->values = table_allocate((uint64_t)length * 8);
    if (!table->values) native_trap();
    table->length = length;
    table->maximum = maximum;
}

void native_table_check(NativeTable *table, uint32_t offset, uint32_t count) {
    // Empty active element segments still validate their offset at instantiation.
    if ((uint64_t)offset + count > table->length) native_trap();
}

void *native_table_slot(NativeTable *table, uint32_t index) {
    native_table_check(table, index, 1);
    return &table->values[index];
}

uint32_t native_table_size(NativeTable *table) { return table->length; }

uint32_t native_table_grow(NativeTable *table, uint64_t initial, uint32_t delta) {
    uint32_t old = table->length;
    if (!delta) return old;
    if ((uint64_t)old + delta > table->maximum) return UINT32_MAX;
    uint64_t *values = table_allocate(((uint64_t)old + delta) * 8);
    if (!values) return UINT32_MAX;
    memcpy(values, table->values, (size_t)old * 8);
    for (uint64_t i = old; i < (uint64_t)old + delta; i++) values[i] = initial;
    free(table->values);
    table->values = values;
    table->length = old + delta;
    return old;
}

// ---- Defined numeric boundaries ----

// LLVM division and float-to-integer conversion are undefined at boundaries
// where Wasm requires a trap. Guard in C before executing the native operation.
#define SIGNED_DIVISION(TYPE, NAME, MINIMUM)                                   \
    TYPE native_##NAME##_div_s(TYPE a, TYPE b) {                              \
        if (!b || (a == MINIMUM && b == -1)) native_trap();                    \
        return a / b;                                                        \
    }                                                                        \
    TYPE native_##NAME##_rem_s(TYPE a, TYPE b) {                              \
        if (!b) native_trap();                                                \
        return (a == MINIMUM && b == -1) ? 0 : a % b;                         \
    }
SIGNED_DIVISION(int32_t, i32, INT32_MIN)
SIGNED_DIVISION(int64_t, i64, INT64_MIN)

#define TRUNCATIONS(FLOAT, SOURCE)                                            \
    int32_t native_i32_trunc_##SOURCE##_s(FLOAT x) {                           \
        double y = trunc((double)x);                                         \
        if (!(y >= -0x1p31 && y < 0x1p31)) native_trap();                     \
        return (int32_t)y;                                                    \
    }                                                                        \
    uint32_t native_i32_trunc_##SOURCE##_u(FLOAT x) {                          \
        double y = trunc((double)x);                                         \
        if (!(y >= 0 && y < 0x1p32)) native_trap();                           \
        return (uint32_t)y;                                                   \
    }                                                                        \
    int64_t native_i64_trunc_##SOURCE##_s(FLOAT x) {                           \
        double y = trunc((double)x);                                         \
        if (!(y >= -0x1p63 && y < 0x1p63)) native_trap();                     \
        return (int64_t)y;                                                    \
    }                                                                        \
    uint64_t native_i64_trunc_##SOURCE##_u(FLOAT x) {                          \
        double y = trunc((double)x);                                         \
        if (!(y >= 0 && y < 0x1p64)) native_trap();                           \
        return (uint64_t)y;                                                   \
    }
TRUNCATIONS(float, f32)
TRUNCATIONS(double, f64)

// ---- Process initialization ----

void native_host_init(int argc, char **argv) {
    (void)argc;
    (void)argv;
    native_gc_init();
    const char *interval = getenv("SNAIL_NATIVE_GC_INTERVAL");
    if (interval) collection_interval = strtoull(interval, NULL, 10);
}
