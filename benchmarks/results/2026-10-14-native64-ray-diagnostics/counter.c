// Additive diagnostic counts. This file never allocates, collects or calls Rust.
#include "precise-gc.h"
#include <stdio.h>

// ---- Constructor, allocation-size and frame counts ----

static uint64_t constructors[1024], constructor_bytes[1024];
static uint64_t allocation_sizes[18], entries[1024], leaves, zero_leaves;

void native_diagnostic_constructor(uint64_t tag, uint64_t bytes) {
    if (tag >= 1024) __builtin_trap();
    constructors[tag]++;
    constructor_bytes[tag] += bytes;
}

void native_diagnostic_allocation(size_t bytes) {
    size_t index = bytes % 8 == 0 && bytes <= 128 ? bytes / 8 : 17;
    allocation_sizes[index]++;
}

void native_diagnostic_enter(uint64_t capacity) {
    if (capacity >= 1024) __builtin_trap();
    entries[capacity]++;
}

void native_diagnostic_leave(uint64_t capacity) {
    leaves++;
    if (!capacity) zero_leaves++;
}

// ---- Cumulative snapshots outside the guest workload clock ----

void native_diagnostic_report(const char *phase) {
    native_diagnostic_gc_report(phase);
    fprintf(stderr, "roots phase=%s leaves=%llu zero_leaves=%llu", phase,
            (unsigned long long)leaves, (unsigned long long)zero_leaves);
    for (size_t i = 0; i < 1024; i++)
        if (entries[i]) fprintf(stderr, " capacity_%zu=%llu", i, (unsigned long long)entries[i]);
    fprintf(stderr, "\nconstructors phase=%s", phase);
    for (size_t i = 0; i < 1024; i++)
        if (constructors[i]) fprintf(stderr, " tag_%zu=%llu:%llu", i,
                                    (unsigned long long)constructors[i], (unsigned long long)constructor_bytes[i]);
    fprintf(stderr, "\nallocation_sizes phase=%s", phase);
    for (size_t i = 0; i < 18; i++)
        if (allocation_sizes[i]) fprintf(stderr, " bytes_%zu=%llu", i == 17 ? 999 : i * 8,
                                        (unsigned long long)allocation_sizes[i]);
    fputc('\n', stderr);
}
