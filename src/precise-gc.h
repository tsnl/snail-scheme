#ifndef SNAIL_PRECISE_GC_H
#define SNAIL_PRECISE_GC_H
#include <stddef.h>
#include <stdint.h>

// The collector is single-threaded, synchronous and nonmoving.
// LLVM publishes only reference-typed values; numeric i64 slots are not roots.
typedef struct NativeRoots {
    struct NativeRoots *previous;
    uint64_t capacity, count;
    uint64_t values[];
} NativeRoots;
typedef struct { uint64_t *values; uint32_t length, maximum; } NativeTable;
extern NativeRoots *volatile native_roots;
void native_roots_enter(NativeRoots *, uint64_t);
void native_roots_leave(NativeRoots *);

void native_gc_init(void);
void *native_gc_alloc(size_t);
void native_gc_collect(void);
size_t native_gc_collections(void);
typedef void (*NativeFinalizer)(void *, void *);
void native_gc_watch(void *, NativeFinalizer, void *,
                                    NativeFinalizer *, void **);
#endif
