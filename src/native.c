// Native host for lowered Wasm datums: GC objects, traps and finalizers.
// SNAIL_PRECISE_GC selects this experiment's exact-root, nonmoving Immix host.
// Rust links natively and retains Scheme values through owned AWI handles.
// This host knows no Scheme representation beyond AWI's finalizer import.

#define _GNU_SOURCE
#include "precise-gc.h"
#ifndef SNAIL_PRECISE_GC
#include <gc/gc.h>
#endif
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if !defined(__linux__) || !defined(__x86_64__)
#error "The native Wasm backend currently supports x86-64 Linux"
#endif

// ---- Traps and collection ----

extern int snail_cli_main(void);
extern void snail_cli_report_failure(void);

_Noreturn void native_trap(void) {
    fputs("WebAssembly trap\n", stderr);
    snail_cli_report_failure();
    exit(1);
}

// A tail call unlinks before transfer. The callee links before any collection.
// Rust callbacks temporarily link above suspended guest frames. No async GC.
NativeRoots *volatile native_roots;
void native_roots_enter(NativeRoots *frame, uint64_t capacity) {
    frame->capacity = capacity;
    frame->count = 0;
    if (!capacity) return;
    frame->previous = native_roots;
    native_roots = frame;
}
void native_roots_leave(NativeRoots *frame) {
    if (frame->capacity) native_roots = frame->previous;
}

static uint64_t allocations, collection_interval;

static void *try_allocate(uint64_t size) {
    if (collection_interval && ++allocations % collection_interval == 0) GC_gcollect();
    void *object = GC_malloc(size);
    // Collector callbacks only queue scalar IDs. Calling Rust here
    // could reenter a borrowed RefCell, so cleanup waits for a host safepoint.
    GC_invoke_finalizers();
    GC_reachable_here(object);
    return object;
}

uint64_t native_alloc(uint64_t size) {
    void *object = try_allocate(size);
    if (!object) native_trap();
    return (uintptr_t)object;
}

static uint64_t *object_words(uint64_t reference) {
    if (!reference || (reference & 1)) native_trap();
    return (uint64_t *)(uintptr_t)reference;
}

uint32_t native_ref_test(uint64_t reference, int64_t type, uint32_t nullable) {
    if (!reference) return nullable;
    if (type == -1) return (reference & 1) || ((object_words(reference)[0] & 3) != 0);
    if (type == -2) return reference & 1;
    if ((reference & 1) || type == -6) return 0;
    uint64_t actual = object_words(reference)[0];
    if (type >= 0) return actual == (uint64_t)type;
    return (actual & 3) == (type == -3 ? 2 : type == -4 ? 3 : 0);
}

// ---- GC arrays and rooted tables ----

// Every array element has an eight-byte slot. Lengths remain unsigned wasm32.
// Reference slots contain raw BDWGC pointers or odd immediate words. Rust
// retains these objects through AWI handles in a scanned table.

uint64_t native_array_new(uint64_t type, uint32_t length, uint64_t initial) {
    uint64_t reference = native_alloc(16 + (uint64_t)length * 8);
    uint64_t *words = object_words(reference);
    words[0] = type;
    words[1] = length;
    for (uint32_t i = 0; i < length; i++) words[i + 2] = initial;
    return reference;
}

uint32_t native_array_length(uint64_t reference) {
    return (uint32_t)object_words(reference)[1];
}

void *native_array_slot(uint64_t reference, uint32_t index) {
    uint64_t *words = object_words(reference);
    if (index >= words[1]) native_trap();
    return &words[2 + (uint64_t)index];
}

void native_array_copy(uint64_t target, uint32_t to, uint64_t source,
                       uint32_t from, uint32_t count) {
    uint64_t *destination = object_words(target), *origin = object_words(source);
    if ((uint64_t)to + count > destination[1] || (uint64_t)from + count > origin[1])
        native_trap();
    memmove(destination + 2 + to, origin + 2 + from, (size_t)count * 8);
}

// Headerless table buffers have explicit ownership in the precise experiment.
// The collector enumerates current cells through the permanent table identity.
static uint64_t *table_allocate(uint64_t bytes) {
#ifdef SNAIL_PRECISE_GC
    return calloc(1, bytes ? bytes : 1);
#else
    return try_allocate(bytes);
#endif
}

void native_table_init(NativeTable *table, uint32_t length, uint32_t maximum) {
    if (length > maximum) native_trap();
    table->values = table_allocate((uint64_t)length * 8);
    if (!table->values) native_trap();
    table->length = length;
    table->maximum = maximum;
}

void *native_table_slot(NativeTable *table, uint32_t index) {
    if (index >= table->length) native_trap();
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
#ifdef SNAIL_PRECISE_GC
    free(table->values);
#endif
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

// ---- AWI finalization ----

extern void drop_resource(uint32_t kind, uint32_t id) __asm__("snail:drop-resource");

typedef struct Resource { uint32_t kind, id; struct Resource *next; } Resource;
static Resource *pending_resources;
static uint64_t finalized_resources;

static void finalize_resource(void *object, void *data) {
    (void)object;
    Resource *resource = data;
    resource->next = pending_resources;
    pending_resources = resource;
}

void native_register_finalizer(uint64_t reference, uint32_t kind, uint32_t id) {
    Resource *resource = malloc(sizeof(Resource)), *old = NULL;
    if (!resource) native_trap();
    *resource = (Resource){kind, id, NULL};
    // The held data contains only scalar IDs, never the watched wrapper.
    GC_register_finalizer_no_order(object_words(reference), finalize_resource,
                                   resource, NULL, (void **)&old);
    free(old);
}

void native_unregister_finalizer(uint64_t reference) {
    Resource *old = NULL;
    GC_register_finalizer_no_order(object_words(reference), NULL, NULL, NULL, (void **)&old);
    free(old);
}

// Only call this with no active translated Wasm frames. Cleanup may itself
// execute Rust; held records never contain the watched object.
void native_poll_finalizers(void) {
    GC_invoke_finalizers();
    Resource *batch = pending_resources;
    pending_resources = NULL;
    while (batch) {
        Resource *resource = batch;
        batch = resource->next;
        drop_resource(resource->kind, resource->id);
        finalized_resources++;
        free(resource);
    }
}

uint64_t native_finalizer_count(void) { return finalized_resources; }

// ---- Identity hashing ----

// BDWGC does not move live objects. Mixing the tagged reference is therefore
// stable while the key is live; unlike an AWI slot, it identifies the value.
// No registry retains hashed values, so self-referential tables remain garbage.
uint32_t native_hash_identity(uint64_t reference) {
    reference ^= reference >> 30;
    reference *= UINT64_C(0xbf58476d1ce4e5b9);
    reference ^= reference >> 27;
    reference *= UINT64_C(0x94d049bb133111eb);
    return (reference ^ (reference >> 31)) & UINT32_C(0x3fffffff);
}

// ---- Process initialization ----

extern void native_module_init(void);

void native_host_init(int argc, char **argv) {
    (void)argc;
    (void)argv;
    GC_set_all_interior_pointers(1);
    GC_set_finalize_on_demand(1);
    GC_INIT();
    const char *interval = getenv("SNAIL_NATIVE_GC_INTERVAL");
    if (interval) collection_interval = strtoull(interval, NULL, 10);
}

#ifndef SNAIL_NATIVE_LIBRARY
int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    int status = snail_cli_main();
    native_poll_finalizers();
    return status;
}
#endif
