// Behavioral tests for exact roots, typed heap edges, weak cleanup and reuse.
#include "precise-gc.h"
#include <assert.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

typedef struct { uint32_t kind, count; const uint32_t *offsets; } Layout;
static const uint32_t reference_field[] = {1};
const Layout native_gc_layouts[] = {{1, 1, reference_field}, {1, 0, NULL}, {2, 0, NULL}};
const uint64_t native_gc_layouts_count = 3;
static uint64_t permanent;
uint64_t *const native_gc_globals[] = {&permanent};
const uint64_t native_gc_globals_count = 1;
static NativeTable table;
NativeTable *const native_gc_tables[] = {&table};
const uint64_t native_gc_tables_count = 1;
NativeRoots *volatile native_roots;
_Noreturn void native_trap(void) { abort(); }
static unsigned finalized;

static uint64_t *object(uint64_t tag) {
    uint64_t *value = GC_malloc(16);
    assert(value);
    value[0] = tag;
    return value;
}

static void finalizer(void *object, void *data) {
    (void)object;
    assert(data == &finalized);
    finalized++;
}

static void watch(uint64_t *value) {
    GC_register_finalizer_no_order(value, finalizer, &finalized, NULL, NULL);
}

int main(void) {
    precise_init();
    struct { NativeRoots *previous; uint64_t capacity, count, values[2]; } roots = {NULL, 2, 2, {0}};
    native_roots = (NativeRoots *)&roots;
    uint64_t *parent = object(6); // Struct with a declared reference field.
    roots.values[0] = (uintptr_t)parent;
    uint64_t *child = object(10); // Struct containing only an ordinary i64.
    parent[1] = (uintptr_t)child;
    watch(child);
    GC_gcollect();
    assert(finalized == 0 && parent[1] == (uintptr_t)child);
    child[1] = (uintptr_t)parent; // Pointer-shaped numeric field is not an edge.
    roots.values[0] = (uintptr_t)child;
    watch(parent);
    GC_gcollect();
    assert(finalized == (getenv("SNAIL_GC_SCAN_ALL") ? 0 : 1));
    roots.values[0] = 0;
    GC_gcollect();
    assert(finalized == 2);

    // A reference cycle is reclaimed; a table root keeps it until released.
    uint64_t *cycle = object(6);
    cycle[1] = (uintptr_t)cycle;
    uint64_t cells[] = {(uintptr_t)cycle};
    table = (NativeTable){cells, 1, 1};
    watch(cycle);
    GC_gcollect();
    assert(finalized == 2);
    permanent = cells[0];
    cells[0] = 0;
    GC_gcollect();
    assert(finalized == 2);
    permanent = 0;
    GC_gcollect();
    assert(finalized == 3);

    // Declared reference arrays include all elements; stale frame slots don't.
    uint64_t *array = GC_malloc(16 + 20000 * 8);
    array[0] = 15;
    array[1] = 20000;
    roots.values[0] = (uintptr_t)array;
    child = object(10);
    array[20001] = (uintptr_t)child;
    watch(child);
    GC_gcollect();
    assert(finalized == 3);
    roots.values[1] = roots.values[0];
    roots.count = 0;
    GC_gcollect();
    assert(finalized == 4);
    uint64_t *reused = GC_malloc(16 + 20000 * 8);
    assert(reused == array); // Stable slab can be reused after collection.
    for (size_t i = 0; i < 20002; i++) assert(reused[i] == 0);
    roots.count = 1;
    roots.values[0] = (uintptr_t)reused;
    reused[0] = 15;
    reused[1] = 20000;
    GC_gcollect();
    static uint64_t immortal[] = {10, 0};
    watch(immortal);
    GC_gcollect();
    assert(finalized == 4);
    GC_register_finalizer_no_order(immortal, NULL, NULL, NULL, NULL);
    return 0;
}
