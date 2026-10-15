#define _GNU_SOURCE
// Growth keeps exact object identities, line reuse and weak cleanup intact.
#include "precise-gc.h"
#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

#define BLOCK_SIZE 32768u
typedef struct { uint32_t kind, count; const uint32_t *offsets; } Layout;
static const uint32_t reference_field[] = {1};
const Layout native_gc_layouts[] = {{1, 1, reference_field}, {1, 0, NULL}, {2, 0, NULL}};
const uint64_t native_gc_layouts_count = 3;
uint64_t *const native_gc_globals[] = {NULL};
const uint64_t native_gc_globals_count = 0;
NativeTable *const native_gc_tables[] = {NULL};
const uint64_t native_gc_tables_count = 0;
NativeRoots *volatile native_roots;
_Noreturn void native_trap(void) { abort(); }
static struct { NativeRoots *previous; uint64_t capacity, count, values[16]; } roots = {NULL, 16, 16, {0}};
static unsigned finalized[16];

// ---- OS and metadata failures at the real allocation boundary ----

// Linker wrappers leave the collector unchanged. Only provisional region
// allocations are failed; already published maps remain ordinary OS mappings.
void *__real_malloc(size_t);
void *__real_calloc(size_t, size_t);
void __real_free(void *);
void *__real_mmap(void *, size_t, int, int, int, off_t);
static bool fail_descriptor, fail_blocks, fail_mapping;
static size_t mapping_limit = SIZE_MAX, mapped_bytes, mapping_count, mapping_attempts;
static size_t freed_metadata;

void *__wrap_malloc(size_t bytes) {
    return fail_descriptor ? NULL : __real_malloc(bytes);
}

void *__wrap_calloc(size_t count, size_t bytes) {
    return fail_blocks ? NULL : __real_calloc(count, bytes);
}

void __wrap_free(void *memory) {
    if (memory) freed_metadata++;
    __real_free(memory);
}

void *__wrap_mmap(void *address, size_t bytes, int protection, int flags, int fd, off_t offset) {
    mapping_attempts++;
    if (fail_mapping || bytes > mapping_limit) { errno = ENOMEM; return MAP_FAILED; }
    void *result = __real_mmap(address, bytes, protection, flags, fd, offset);
    if (result != MAP_FAILED) { mapped_bytes += bytes; mapping_count++; }
    return result;
}

static uint64_t *object(size_t bytes, uint64_t tag, uint64_t value) {
    uint64_t *words = native_gc_alloc(bytes);
    assert(words);
    for (size_t i = 0; i < bytes / 8; i++) assert(words[i] == 0);
    words[0] = tag;
    words[1] = value;
    return words;
}

static void finalizer(void *object, void *data) {
    (void)object;
    size_t index = (uintptr_t)data;
    assert(index < 16 && finalized[index] == 0);
    finalized[index]++;
}

static void watch(uint64_t *value, size_t index) {
    native_gc_watch(value, finalizer, (void *)(uintptr_t)index, NULL, NULL);
}

// ---- Repeated growth and references between regions ----

static void check_growth(void) {
    uint64_t *oldest = NULL;
    for (size_t i = 0; i < 12; i++) {
        uint64_t *value = object(BLOCK_SIZE - 8, 6, roots.values[0]);
        value[2] = i;
        roots.values[0] = (uintptr_t)value;
        if (!i) oldest = value;
        watch(value, i);
    }
    assert(mapping_count == 5 && mapped_bytes == 16 * BLOCK_SIZE);
    // One contiguous object larger than the entire existing heap. Its final
    // reference lies in the last block; the cycle crosses both old and new maps.
    size_t count = 131072, bytes = 16 + count * 8;
    uint64_t *array = object(bytes, 15, count);
    array[count + 1] = roots.values[0];
    oldest[1] = (uintptr_t)array;
    watch(array, 12);
    native_gc_collect();
    assert(mapping_count == 6 && mapped_bytes == 49 * BLOCK_SIZE);
    uint64_t *value = (uint64_t *)(uintptr_t)roots.values[0];
    for (size_t i = 12; i--;) {
        assert(value[2] == i && finalized[i] == 0);
        value = (uint64_t *)(uintptr_t)value[1];
    }
    assert(value == array && array[count + 1] == roots.values[0] && finalized[12] == 0);
    roots.values[0] = 0;
    native_gc_collect();
    for (size_t i = 0; i < 13; i++) assert(finalized[i] == 1);
    assert(object(bytes, 15, count) == array); // Whole spanning extent is reusable.
    native_gc_collect(); // The reused address cannot inherit the old watch.
}

static void check_bump_owner(void) {
    uint64_t *first = object(24, 10, 123);
    roots.values[0] = (uintptr_t)first;
    roots.values[1] = (uintptr_t)object(3 * BLOCK_SIZE - 8, 10, 456);
    roots.values[2] = (uintptr_t)object(4 * BLOCK_SIZE - 8, 10, 789);
    assert(mapping_count == 2 && mapped_bytes == 8 * BLOCK_SIZE);
    // Both regions now have a three-block hole. Place a large object and a
    // small bump in the new one, then another large object in the old one.
    roots.values[1] = roots.values[2] = 0;
    native_gc_collect();
    roots.values[2] = (uintptr_t)object(3 * BLOCK_SIZE - 8, 10, 456);
    uint64_t *small = object(24, 10, 987);
    roots.values[1] = (uintptr_t)small;
    size_t collected = native_gc_collections();
    uint64_t *large = object(3 * BLOCK_SIZE - 8, 10, 654);
    roots.values[3] = (uintptr_t)large;
    uint64_t *tail = object(24, 10, 321);
    roots.values[4] = (uintptr_t)tail;
    assert(tail == small + 4); // Large reservation preserved the active bump.
    assert(native_gc_collections() == collected && mapping_count == 2);
    native_gc_collect();
    assert(first[1] == 123 && small[1] == 987);
    assert(large[1] == 654 && tail[1] == 321);
}

static void check_exact_starts(void) {
    // Numeric payloads, fake aligned interior headers, unpublished slots,
    // tagged immediates and static addresses must not become reference edges.
    uint64_t *owner = object(48, 10, (16 << 2) | 1);
    roots.values[0] = (uintptr_t)owner;
    owner[2] = UINT64_MAX; // Tracing this fake interior object would trap.
    roots.values[1] = (uintptr_t)(owner + 2);
    watch(owner, 13);
    native_gc_collect();
    roots.values[0] = 1;
    roots.values[2] = (uintptr_t)owner;
    roots.count = 2;
    native_gc_collect();
    assert(finalized[13] == 1);
    roots.values[1] = (uintptr_t)(owner + 2); // Dead start, with stale payload bytes.
    uint64_t *child = object(24, 10, 111);
    watch(child, 14);
    uint64_t *numeric = object(24, 10, (uintptr_t)child);
    roots.values[0] = (uintptr_t)numeric;
    native_gc_collect();
    assert(finalized[14] == 1 && numeric[1] == (uintptr_t)child);
}

// ---- Bounded growth, failure recovery and size arithmetic ----

static void check_cap(void) {
    for (size_t i = 0; i < 10; i++)
        roots.values[i] = (uintptr_t)object(BLOCK_SIZE - 8, 10, i);
    assert(mapping_count == 5 && mapped_bytes == 10 * BLOCK_SIZE);
    size_t collected = native_gc_collections(), attempts = mapping_attempts;
    assert(!native_gc_alloc(24));
    assert(native_gc_collections() == collected + 1 && mapping_attempts == attempts);
    for (size_t i = 0; i < 10; i++) assert(((uint64_t *)(uintptr_t)roots.values[i])[1] == i);
    roots.values[3] = 0;
    roots.values[3] = (uintptr_t)object(BLOCK_SIZE - 8, 10, 42);
    assert(mapped_bytes == 10 * BLOCK_SIZE); // Collect/reuse before growing.
}

static void check_failed_growth(void) {
    roots.values[0] = (uintptr_t)object(BLOCK_SIZE - 8, 10, 123);
    size_t freed = freed_metadata;
    fail_descriptor = true;
    assert(!native_gc_alloc(24));
    assert(freed_metadata == freed);
    fail_descriptor = false;
    fail_blocks = true;
    assert(!native_gc_alloc(24));
    assert(freed_metadata == freed + 1);
    fail_blocks = false;
    fail_mapping = true;
    assert(!native_gc_alloc(24));
    assert(freed_metadata == freed + 3);
    fail_mapping = false;
    assert(mapping_count == 1 && mapped_bytes == BLOCK_SIZE);
    roots.values[1] = (uintptr_t)object(BLOCK_SIZE - 8, 10, 456);
    // Preferred doubling fails but a single-block addition can still succeed.
    mapping_limit = BLOCK_SIZE;
    size_t attempts = mapping_attempts;
    roots.values[2] = (uintptr_t)object(BLOCK_SIZE - 8, 10, 789);
    assert(mapping_attempts == attempts + 2 && mapped_bytes == 3 * BLOCK_SIZE);
    native_gc_collect();
    assert(((uint64_t *)(uintptr_t)roots.values[0])[1] == 123);
    assert(((uint64_t *)(uintptr_t)roots.values[1])[1] == 456);
    assert(((uint64_t *)(uintptr_t)roots.values[2])[1] == 789);
}

static void check_sizes(void) {
    size_t collected = native_gc_collections(), attempts = mapping_attempts;
    assert(!native_gc_alloc(SIZE_MAX));
    assert(!native_gc_alloc(SIZE_MAX / 4));
    assert(!native_gc_alloc(SIZE_MAX / 4 + 1));
    assert(native_gc_collections() == collected && mapping_attempts == attempts);
    roots.values[0] = (uintptr_t)object(BLOCK_SIZE - 8, 10, 123);
    collected = native_gc_collections();
    // Budget collection satisfies reclaim-before-growth within this call.
    roots.values[1] = (uintptr_t)object(BLOCK_SIZE - 8, 10, 456);
    assert(native_gc_collections() == collected + 1 && mapping_count == 2);
}

// ---- Headroom after a capacity miss ----

static void fill_lines(size_t retained) {
    for (size_t i = 0; i < 1024; i++) {
        uint64_t *value = object(120, 6, roots.values[0]);
        if (i < retained) roots.values[0] = (uintptr_t)value;
    }
    assert(mapping_count == 1 && mapped_bytes == 4 * BLOCK_SIZE);
}

static void check_headroom(size_t retained, size_t mappings, bool fail) {
    fill_lines(retained);
    fail_mapping = fail;
    uint64_t *value = object(24, 6, roots.values[0]);
    roots.values[0] = (uintptr_t)value;
    fail_mapping = false;
    assert(native_gc_collections() == 1 && mapping_count == mappings);
    native_gc_collect();
    for (size_t i = 0; i < retained; i++) {
        value = (uint64_t *)(uintptr_t)value[1];
        assert(value && value[0] == 6);
    }
    assert(value[1] == 0);
}

static void check_large_headroom(void) {
    // The header pushes this object into a third block. Its reserved tail is
    // unavailable even though it contains only one marked line.
    roots.values[0] = (uintptr_t)object(2 * BLOCK_SIZE, 10, 123);
    roots.values[1] = (uintptr_t)object(120, 10, 456);
    for (size_t i = 1; i < 256; i++) object(120, 10, i);
    assert(mapping_count == 1);
    roots.values[2] = (uintptr_t)object(24, 10, 789);
    assert(native_gc_collections() == 1 && mapping_count == 2);
    native_gc_collect();
    assert(((uint64_t *)(uintptr_t)roots.values[0])[1] == 123);
    assert(((uint64_t *)(uintptr_t)roots.values[1])[1] == 456);
}

int main(int argc, char **argv) {
    assert(argc == 2);
    native_gc_init();
    native_roots = (NativeRoots *)&roots;
    if (!strcmp(argv[1], "growth")) { check_growth(); check_exact_starts(); }
    else if (!strcmp(argv[1], "bump")) check_bump_owner();
    else if (!strcmp(argv[1], "cap")) check_cap();
    else if (!strcmp(argv[1], "failure")) check_failed_growth();
    else if (!strcmp(argv[1], "sizes")) check_sizes();
    else if (!strcmp(argv[1], "headroom")) check_headroom(896, 2, false);
    else if (!strcmp(argv[1], "headroom-low")) check_headroom(768, 1, false);
    else if (!strcmp(argv[1], "headroom-failure")) check_headroom(896, 1, true);
    else if (!strcmp(argv[1], "headroom-cap")) check_headroom(896, 1, false);
    else if (!strcmp(argv[1], "headroom-large")) check_large_headroom();
    else assert(!strcmp(argv[1], "init"));
    return 0;
}
