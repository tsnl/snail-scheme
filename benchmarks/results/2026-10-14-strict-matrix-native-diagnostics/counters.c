// Diagnostic counters for a separate derived executor; never used for timing.
// Counters record logical lowering requests, before LLVM may remove work.

#include <assert.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


// ---- Concrete operation totals ----

enum {
    ALLOC_REQUESTS, ALLOC_BYTES, ALLOC_ALIGNED_BYTES, BUMP_FAST, HOLE_SEARCH,
    LARGE_ALLOC, GC_COLLECT, ROOT_ENTER, ROOT_ACTIVE, ROOT_CAPACITY, ROOT_LEAVE,
    REF_TEST, ARRAY_NEW, ARRAY_ELEMENTS, ARRAY_SLOT, ARRAY_COPY, COPY_ELEMENTS,
    ROOT_SLOT_STORE, ROOT_COUNT_STORE, DIRECT_CALL, INDIRECT_CALL, NULL_GUARD,
    STRUCT_FIELD_STORE, STRUCT_FIELD_BYTES, BITMAP_START, ALLOC_HEADER,
    ZERO_BYTES, ZERO_REQUESTS, ARRAY_CTOR_STORES, ARRAY_CTOR_BYTES,
    COUNTER_COUNT
};

static const char *names[] = {
    "allocation_requests", "requested_bytes", "aligned_bytes", "bump_fast",
    "hole_searches", "large_requests", "gc_collections", "root_enter_requests",
    "active_root_enters", "root_capacity_sum", "root_leave_requests", "ref_tests",
    "array_new", "array_elements", "array_slots", "array_copies", "copied_elements",
    "root_slot_store_requests", "root_count_store_requests", "direct_guest_calls",
    "indirect_guest_calls", "null_guard_requests", "struct_constructor_field_stores",
    "struct_constructor_field_bytes", "bitmap_start_updates", "allocator_header_writes",
    "zeroed_payload_bytes", "zero_payload_requests", "array_constructor_stores",
    "array_constructor_bytes"
};

typedef struct {
    uint64_t values[COUNTER_COUNT], functions[256], sizes[4096], types[4096];
} Counts;
static Counts setup, worker;

void matrix_diag_count(uint64_t index) {
    assert(index < COUNTER_COUNT);
    worker.values[index]++;
}

void matrix_diag_add(uint64_t index, uint64_t value) {
    assert(index < COUNTER_COUNT);
    worker.values[index] += value;
}

void matrix_diag_function(uint64_t index) {
    assert(index < 256);
    worker.functions[index]++;
}

void matrix_diag_type(uint64_t type) {
    assert(type < 4096);
    worker.types[type]++;
}

void matrix_diag_allocation(uint64_t bytes) {
    assert(bytes < 4096);
    worker.sizes[bytes]++;
    worker.values[ALLOC_REQUESTS]++;
    worker.values[ALLOC_BYTES] += bytes;
    worker.values[ALLOC_ALIGNED_BYTES] += (bytes + 23) & ~UINT64_C(15);
}


// ---- Setup and workload remain distinct scopes ----

void matrix_diag_reset(void) {
    setup = worker;
    memset(&worker, 0, sizeof(worker));
}

static void write_sparse(FILE *file, const uint64_t *values, size_t length) {
    int separator = 0;
    fputc('{', file);
    for (size_t index = 0; index < length; index++) {
        if (!values[index]) continue;
        fprintf(file, "%s\"%zu\":%" PRIu64, separator ? "," : "", index, values[index]);
        separator = 1;
    }
    fputc('}', file);
}

static void write_counts(FILE *file, const Counts *counts) {
    fputs("{\"operations\":{", file);
    for (size_t index = 0; index < COUNTER_COUNT; index++)
        fprintf(file, "%s\"%s\":%" PRIu64, index ? "," : "", names[index], counts->values[index]);
    fputs("},\"functions\":", file); write_sparse(file, counts->functions, 256);
    fputs(",\"sizes\":", file); write_sparse(file, counts->sizes, 4096);
    fputs(",\"types\":", file); write_sparse(file, counts->types, 4096);
    fputc('}', file);
}

void matrix_diag_report(void) {
    const char *path = getenv("SNAIL_MATRIX_DIAGNOSTICS");
    assert(path);
    FILE *file = fopen(path, "wb");
    assert(file);
    fputs("{\"setup\":", file); write_counts(file, &setup);
    fputs(",\"worker\":", file); write_counts(file, &worker);
    fputs("}\n", file);
    assert(fclose(file) == 0);
}
