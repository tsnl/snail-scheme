#define _POSIX_C_SOURCE 200809L
// The defining mark-region behavior: retain object lines, reclaim their holes.
#include "precise-gc.h"
#include <assert.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

typedef struct { uint32_t kind, count; const uint32_t *offsets; } Layout;
const Layout native_gc_layouts[] = {{1, 0, NULL}};
const uint64_t native_gc_layouts_count = 1;
uint64_t *const native_gc_globals[] = {NULL};
const uint64_t native_gc_globals_count = 0;
NativeTable *const native_gc_tables[] = {NULL};
const uint64_t native_gc_tables_count = 0;
NativeRoots *volatile native_roots;
_Noreturn void native_trap(void) { abort(); }

static uint64_t *object(uint64_t scalar) {
    uint64_t *words = native_gc_alloc(16);
    assert(words);
    words[0] = 6;
    words[1] = scalar;
    return words;
}

static void check_reclaimed_lines(void) {
    struct { NativeRoots *previous; uint64_t capacity, count, values[2]; } roots = {NULL, 2, 2, {0}};
    native_roots = (NativeRoots *)&roots;
    uint64_t *first = object(123), *last = NULL;
    roots.values[0] = (uintptr_t)first;
    for (unsigned i = 0; i < 999; i++) last = object(i);
    roots.values[1] = (uintptr_t)last;
    native_gc_collect();
    assert(first[1] == 123 && last[1] == 998);
    assert(roots.values[0] == (uintptr_t)first && roots.values[1] == (uintptr_t)last);
    uint64_t *middle = object(456);
    assert((uintptr_t)middle > (uintptr_t)first && (uintptr_t)middle < (uintptr_t)last);
    // The first object's retained 128-byte line cannot be overwritten.
    assert((uintptr_t)middle - (uintptr_t)first >= 128);
    roots.values[1] = (uintptr_t)middle;
    for (unsigned i = 0; i < 4000; i++) (void)object(i);
    native_gc_collect();
    assert(first[1] == 123 && middle[1] == 456);
}

// Allocate an object that fills a chosen number of lines or whole blocks.
static uint64_t *sized_object(size_t bytes, uint64_t scalar) {
    uint64_t *words = native_gc_alloc(bytes);
    assert(words);
    words[0] = 6;
    words[1] = scalar;
    return words;
}

static void check_wrapped_small_hole(void) {
    struct { NativeRoots *previous; uint64_t capacity, count, values[256]; } roots = {NULL, 256, 256, {0}};
    native_roots = (NativeRoots *)&roots;
    uintptr_t base = 0;
    for (unsigned line = 0; line < 256; line++) {
        uint64_t *value = sized_object(120, line);
        if (!line) base = (uintptr_t)value;
        if (line != 1 && (line < 3 || line > 10)) roots.values[line] = (uintptr_t)value;
    }
    native_gc_collect();
    size_t collected = native_gc_collections();
    // Eight lines skip the earlier one-line hole, then consume the later hole.
    uint64_t *large = sized_object(1016, 900);
    assert((uintptr_t)large == base + 3 * 128);
    roots.values[3] = (uintptr_t)large;
    uint64_t *small = object(901);
    assert((uintptr_t)small == base + 128);
    assert(native_gc_collections() == collected); // A failed search/GC retry cannot mask wrap failure.
    roots.values[1] = (uintptr_t)small;
    native_gc_collect();
    assert(large[1] == 900 && small[1] == 901);
    assert(((uint64_t *)(uintptr_t)roots.values[255])[1] == 255);
}

static void check_wrapped_large_space(void) {
    struct { NativeRoots *previous; uint64_t capacity, count, values[4]; } roots = {NULL, 4, 4, {0}};
    native_roots = (NativeRoots *)&roots;
    uint64_t *first = sized_object(2 * 32768 - 8, 1);
    uint64_t *separator = sized_object(32768 - 8, 2);
    roots.values[0] = (uintptr_t)separator;
    uint64_t *later = sized_object(3 * 32768 - 8, 3);
    uint64_t *last = sized_object(2 * 32768 - 8, 4);
    roots.values[1] = (uintptr_t)last;
    native_gc_collect();
    size_t collected = native_gc_collections();
    // A three-block request skips the first two free blocks; a later two-block
    // request must wrap past the live final reservation to recover those blocks.
    uint64_t *three = sized_object(3 * 32768 - 8, 5);
    assert(three == later);
    roots.values[2] = (uintptr_t)three;
    uint64_t *two = sized_object(2 * 32768 - 8, 6);
    assert(two == first && native_gc_collections() == collected);
    roots.values[3] = (uintptr_t)two;
    native_gc_collect();
    assert(separator[1] == 2 && last[1] == 4 && three[1] == 5 && two[1] == 6);
}

static void check_allocation_boundaries(void) {
    struct { NativeRoots *previous; uint64_t capacity, count, values[8]; } roots = {NULL, 8, 8, {0}};
    native_roots = (NativeRoots *)&roots;
    uint64_t *first = object(1);
    roots.values[0] = (uintptr_t)first;
    // The payload fits one block, but its header makes the footprint larger.
    uint64_t *large = sized_object(32768, 2);
    roots.values[1] = (uintptr_t)large;
    uint64_t *second = object(3);
    roots.values[2] = (uintptr_t)second;
    assert((uintptr_t)second == (uintptr_t)first + 32); // Large allocation preserves the bump tail.
    uint64_t *tail = sized_object(32768 - 64 - 8, 4);
    roots.values[3] = (uintptr_t)tail;
    assert((uintptr_t)tail == (uintptr_t)second + 32); // Exact remaining fit.
    uint64_t *whole = sized_object(32768 - 8, 5);
    roots.values[4] = (uintptr_t)whole;
    assert((uintptr_t)whole == (uintptr_t)first + 3 * 32768);
    uint64_t *below = sized_object(32768 - 24, 6);
    roots.values[5] = (uintptr_t)below;
    uint64_t *last = native_gc_alloc(8);
    assert(last && last[0] == 0);
    last[0] = 6;
    roots.values[6] = (uintptr_t)last;
    assert((uintptr_t)last == (uintptr_t)below + 32768 - 16);
    uint64_t *above = sized_object(32768 - 7, 7);
    roots.values[7] = (uintptr_t)above;
    assert((uintptr_t)above == (uintptr_t)first + 5 * 32768);
    // Only one block is free: a two-block failure retries collection once.
    size_t collected = native_gc_collections();
    assert(!native_gc_alloc(32768));
    assert(native_gc_collections() == collected + 1);
    assert(first[1] == 1 && large[1] == 2 && second[1] == 3 && tail[1] == 4);
    assert(whole[1] == 5 && below[1] == 6 && above[1] == 7 && last[0] == 6);
    uint64_t *remaining = object(8);
    assert((uintptr_t)remaining == (uintptr_t)first + 7 * 32768);
}

int main(int argc, char **argv) {
    bool large = argc > 1 && !strcmp(argv[1], "wrap-large");
    bool boundaries = argc > 1 && !strcmp(argv[1], "boundaries");
    setenv("SNAIL_GC_HEAP_BYTES", large || boundaries ? "262144" : "32768", 1);
    native_gc_init();
    if (boundaries) check_allocation_boundaries();
    else if (large) check_wrapped_large_space();
    else if (argc > 1) check_wrapped_small_hole();
    else check_reclaimed_lines();
    return 0;
}
