// Throwaway native allocator diagnostic: bounded, zeroed mmap arena; never reclaimed.
// Rust links natively and retains Scheme values through owned AWI handles.
// This host knows no Scheme representation beyond AWI's finalizer import.

#define _GNU_SOURCE
#include <sys/mman.h>
#include <sys/resource.h>
#include <time.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "measurement.h"

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

// Anonymous mmap pages begin zeroed. Each range is handed out once; no memset,
// reclamation, tracing, collection, or per-allocation finalizer polling occurs.
// A minimum eight-byte reservation gives zero-length allocations distinct identity.
static unsigned char *arena;
static uint64_t arena_used, arena_capacity;
static struct timespec process_started;

static void *try_allocate(uint64_t size) {
    if (size > UINT64_MAX - 7) return NULL;
    uint64_t aligned = size ? (size + 7) & ~UINT64_C(7) : 8;
    if (aligned > arena_capacity - arena_used) return NULL;
    void *object = arena + arena_used;
    arena_used += aligned;
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
// Reference slots contain fixed arena pointers or odd immediate words. Rust
// keeps its unchanged AWI handle table; table storage uses this same arena.

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

typedef struct {
    uint64_t *values;
    uint32_t length, maximum;
} NativeTable;

void native_table_init(NativeTable *table, uint32_t length, uint32_t maximum) {
    if (length > maximum) native_trap();
    table->values = (void *)(uintptr_t)native_alloc((uint64_t)length * 8);
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
    uint64_t *values = try_allocate(((uint64_t)old + delta) * 8);
    if (!values) return UINT32_MAX;
    memcpy(values, table->values, (size_t)old * 8);
    for (uint64_t i = old; i < (uint64_t)old + delta; i++) values[i] = initial;
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

// Diagnostic only: unreachable Rust resources are never released. This changes
// resource semantics and makes this allocator unsuitable as a production runtime.
// Explicit resource-close behavior still comes from the unchanged Rust runtime.
void native_register_finalizer(uint64_t reference, uint32_t kind, uint32_t id) {
    (void)object_words(reference);
    (void)kind;
    (void)id;
}

void native_unregister_finalizer(uint64_t reference) {
    (void)object_words(reference);
}

void native_poll_finalizers(void) {}
uint64_t native_finalizer_count(void) { return 0; }

// ---- Identity hashing ----

// Arena objects never move. Mixing the tagged reference is therefore
// stable while the key is live; unlike an AWI slot, it identifies the value.
// Identity hashing remains unchanged; this experiment never reclaims any object.
uint32_t native_hash_identity(uint64_t reference) {
    reference ^= reference >> 30;
    reference *= UINT64_C(0xbf58476d1ce4e5b9);
    reference ^= reference >> 27;
    reference *= UINT64_C(0x94d049bb133111eb);
    return (reference ^ (reference >> 31)) & UINT32_C(0x3fffffff);
}

// ---- Process initialization ----

extern void native_module_init(void);

static void report_bump(void) {
    struct rusage usage;
    struct timespec ended;
    getrusage(RUSAGE_SELF, &usage);
    clock_gettime(CLOCK_MONOTONIC, &ended);
    double elapsed = ended.tv_sec - process_started.tv_sec;
    elapsed += (ended.tv_nsec - process_started.tv_nsec) * 1e-9;
    fprintf(stderr, "BUMP used=%lu capacity=%lu rss_kib=%ld wall_s=%.6f\n",
            arena_used, arena_capacity, usage.ru_maxrss, elapsed);
}

void native_host_init(int argc, char **argv) {
    (void)argc;
    (void)argv;
    double setup_started = heap_clock();
    clock_gettime(CLOCK_MONOTONIC, &process_started);
    const char *capacity = getenv("SNAIL_BUMP_BYTES");
    arena_capacity = capacity ? strtoull(capacity, NULL, 10) : UINT64_C(2) << 30;
    if (!arena_capacity || arena_capacity > (UINT64_C(24) << 30)) native_trap();
    arena = mmap(NULL, arena_capacity, PROT_READ | PROT_WRITE,
                 MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (arena == MAP_FAILED) native_trap();
    if (getenv("SNAIL_PREFAULT_HEAP")) prefault_memory(arena, arena_capacity);
    if (getenv("SNAIL_BUMP_REPORT")) atexit(report_bump);
    record_heap_setup(setup_started);
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
