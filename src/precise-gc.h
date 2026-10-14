#ifndef SNAIL_PRECISE_GC_H
#define SNAIL_PRECISE_GC_H
#include <stddef.h>
#include <stdint.h>

// This experimental collector is single-threaded, synchronous and nonmoving.
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

#ifdef SNAIL_PRECISE_GC
void precise_init(void);
void *GC_malloc(size_t);
void GC_gcollect(void);
size_t GC_get_gc_no(void);
typedef void (*GC_finalization_proc)(void *, void *);
void GC_register_finalizer_no_order(void *, GC_finalization_proc, void *,
                                    GC_finalization_proc *, void **);
#define GC_INIT() precise_init()
#define GC_set_all_interior_pointers(x) ((void)(x))
#define GC_set_finalize_on_demand(x) ((void)(x))
#define GC_invoke_finalizers() ((void)0)
#define GC_reachable_here(x) ((void)(x))
#endif
#endif
