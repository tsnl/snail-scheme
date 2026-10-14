// Experimental nonmoving Immix: block/line reclamation and bump allocation.
// This prototype deliberately omits opportunistic evacuation. Exact reference
// frames and declared heap edges are unchanged from the precise experiment.
#define _GNU_SOURCE
#include "precise-gc.h"
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>

// ---- Heap representation ----

#define BLOCK_SIZE 32768u
#define LINE_SIZE 128u
#define LINES (BLOCK_SIZE / LINE_SIZE)
#define ALIGNMENT 16u
#define START_WORDS (BLOCK_SIZE / ALIGNMENT / 64)
#define ALLOCATED 1u
#define MARKED 2u
#define CONTINUATION UINT32_MAX

typedef struct {
    uint64_t starts[START_WORDS];
    uint8_t lines[LINES];
    uint32_t span, live_lines;
    uint16_t available_lines, next_line;
} Block;
typedef struct { uint32_t kind, count; const uint32_t *offsets; } Layout;
typedef struct Watch {
    void *object, *data;
    GC_finalization_proc callback;
    struct Watch *next;
} Watch;
extern const Layout native_gc_layouts[];
extern const uint64_t native_gc_layouts_count;
extern uint64_t *const native_gc_globals[];
extern const uint64_t native_gc_globals_count;
extern NativeTable *const native_gc_tables[];
extern const uint64_t native_gc_tables_count;
extern _Noreturn void native_trap(void);

// A bump range reserves its entire line hole. If a larger request abandons
// the remaining tail, that reserved space becomes reusable only after GC.
static uint8_t *arena, *cursor, *limit;
static Block *blocks;
static size_t heap_bytes = 300 * 1024 * 1024, block_count, used_blocks, search_block, search_large;
static size_t since_collection, budget = 8 * 1024 * 1024, minimum_budget = 8 * 1024 * 1024;
static uint64_t **work;
static size_t work_count, work_capacity, collections, live_bytes, live_objects;
static size_t allocated_bytes, allocated_objects, peak_live, root_visits, field_visits;
static size_t reused_holes, large_objects;
static double mark_seconds, sweep_seconds, prefault_seconds;
static bool scan_all, statistics;
static Watch *watches;

static double seconds(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return time.tv_sec + time.tv_nsec * 1e-9;
}

static size_t aligned_size(size_t bytes) {
    return (bytes + 8 + ALIGNMENT - 1) & ~(size_t)(ALIGNMENT - 1);
}

static void record_start(uint64_t *header) {
    size_t offset = (uint8_t *)header - arena;
    size_t index = offset % BLOCK_SIZE / ALIGNMENT;
    blocks[offset / BLOCK_SIZE].starts[index / 64] |= UINT64_C(1) << (index % 64);
}

// Search cursors reset after GC. Between collections allocation only consumes
// holes, so full blocks can be skipped without reading their line maps again.
static void claim_hole(size_t index, size_t first, size_t end) {
    Block *block = &blocks[index];
    if (block->live_lines) reused_holes++;
    memset(block->lines + first, 1, end - first);
    block->span = 1;
    block->available_lines -= end - first;
    block->next_line = end;
    cursor = arena + index * BLOCK_SIZE + first * LINE_SIZE;
    limit = arena + index * BLOCK_SIZE + end * LINE_SIZE;
    search_block = index;
    if (index + 1 > used_blocks) used_blocks = index + 1;
}

static bool find_hole(size_t index, size_t first, size_t stop, size_t bytes) {
    Block *block = &blocks[index];
    while (first < stop) {
        while (first < stop && block->lines[first]) first++;
        size_t end = first;
        while (end < stop && !block->lines[end]) end++;
        if ((end - first) * LINE_SIZE >= bytes) {
            claim_hole(index, first, end);
            return true;
        }
        first = end;
    }
    return false;
}

static bool acquire_hole(size_t bytes) {
    size_t index = search_block;
    for (size_t checked = 0; checked < block_count; checked++) {
        Block *block = &blocks[index];
        if (!block->span) {
            block->available_lines = LINES;
            claim_hole(index, 0, LINES);
            return true;
        }
        if (block->span == 1 && (size_t)block->available_lines * LINE_SIZE >= bytes) {
            // The boundary follows a consumed hole, so no free run crosses it.
            size_t next = block->next_line;
            if (find_hole(index, next, LINES, bytes) || find_hole(index, 0, next, bytes))
                return true;
        }
        if (++index == block_count) index = 0;
    }
    return false;
}

// Next-fit begins after the last reservation. A second range search includes
// all earlier holes before failure; the split follows an occupied reservation.
// Differing request sizes therefore cannot strand a free run across the split.
static uint64_t *find_large(size_t first, size_t stop, size_t span) {
    while (first + span <= stop) {
        size_t end = first;
        while (end < first + span && !blocks[end].span) end++;
        if (end == first + span) {
            blocks[first].span = span;
            for (size_t i = first + 1; i < end; i++) blocks[i].span = CONTINUATION;
            if (end > used_blocks) used_blocks = end;
            search_large = end;
            large_objects++;
            return (uint64_t *)(arena + first * BLOCK_SIZE);
        }
        size_t occupied = blocks[end].span;
        first = end + (occupied == CONTINUATION ? 1 : occupied);
    }
    return NULL;
}

static uint64_t *allocate_large(size_t bytes) {
    size_t span = (bytes + BLOCK_SIZE - 1) / BLOCK_SIZE;
    uint64_t *header = find_large(search_large, block_count, span);
    return header ? header : find_large(0, search_large, span);
}

static uint64_t *allocate_header(size_t bytes) {
    if (bytes > BLOCK_SIZE) return allocate_large(bytes);
    if (!cursor || (size_t)(limit - cursor) < bytes)
        if (!acquire_hole(bytes)) return NULL;
    uint64_t *header = (uint64_t *)cursor;
    cursor += bytes;
    return header;
}

void *GC_malloc(size_t bytes) {
    if (bytes > heap_bytes - 8 - ALIGNMENT) return NULL;
    if (since_collection >= budget) GC_gcollect();
    uint64_t *header = allocate_header(aligned_size(bytes));
    if (!header) { GC_gcollect(); header = allocate_header(aligned_size(bytes)); }
    if (!header) return NULL;
    record_start(header);
    *header = ((uint64_t)bytes << 2) | ALLOCATED;
    memset(header + 1, 0, bytes);
    since_collection += aligned_size(bytes);
    allocated_bytes += bytes;
    allocated_objects++;
    return header + 1;
}

// ---- Explicit roots and tracing ----

// The object-start bitmap validates pointer-shaped numeric values in scan-all.
// Interior pointers are never roots in this exact-frame experiment.
static uint64_t *candidate(uint64_t value) {
    uintptr_t offset = (uintptr_t)value - (uintptr_t)arena;
    if (offset >= used_blocks * BLOCK_SIZE || offset % ALIGNMENT != 8) return NULL;
    size_t index = (offset - 8) % BLOCK_SIZE / ALIGNMENT;
    if (!(blocks[offset / BLOCK_SIZE].starts[index / 64] & (UINT64_C(1) << (index % 64)))) return NULL;
    uint64_t *header = (uint64_t *)(uintptr_t)value - 1;
    return (*header & ALLOCATED) ? header : NULL;
}

static void mark_lines(uint64_t *header) {
    size_t first = ((uint8_t *)header - arena) / LINE_SIZE;
    size_t end = (((uint8_t *)header - arena) + aligned_size(*header >> 2) + LINE_SIZE - 1) / LINE_SIZE;
    for (size_t line = first; line < end; line++)
        blocks[line / LINES].lines[line % LINES] = 1;
}

static void mark(uint64_t value) {
    uint64_t *header = candidate(value);
    if (!header || (*header & MARKED)) return;
    *header |= MARKED;
    mark_lines(header);
    if (work_count == work_capacity) {
        work_capacity = work_capacity ? work_capacity * 2 : 1024;
        void *grown = realloc(work, work_capacity * sizeof(*work));
        if (!grown) native_trap();
        work = grown;
    }
    work[work_count++] = header + 1;
}

static void mark_roots(void) {
    for (NativeRoots *frame = native_roots; frame; frame = frame->previous) {
        assert(frame->count <= frame->capacity);
        root_visits += frame->count;
        for (size_t i = 0; i < frame->count; i++) mark(frame->values[i]);
    }
    root_visits += native_gc_globals_count;
    for (size_t i = 0; i < native_gc_globals_count; i++) mark(*native_gc_globals[i]);
    for (size_t i = 0; i < native_gc_tables_count; i++) {
        NativeTable *table = native_gc_tables[i];
        root_visits += table->length;
        for (size_t j = 0; j < table->length; j++) mark(table->values[j]);
    }
}

static void trace_object(uint64_t *words) {
    size_t count = words[-1] >> 5;
    if (scan_all) {
        field_visits += count;
        for (size_t i = 0; i < count; i++) mark(words[i]);
        return;
    }
    uint64_t type = words[0] >> 2;
    if (!type || type > native_gc_layouts_count) native_trap();
    Layout layout = native_gc_layouts[type - 1];
    if (layout.kind == 2) {
        assert(words[1] <= count - 2);
        field_visits += words[1];
        for (size_t i = 0; i < words[1]; i++) mark(words[i + 2]);
    } else {
        field_visits += layout.count;
        for (size_t i = 0; i < layout.count; i++) {
            assert(layout.offsets[i] < count);
            mark(words[layout.offsets[i]]);
        }
    }
}

// ---- Weak cleanup and line reclamation ----

void GC_register_finalizer_no_order(void *object, GC_finalization_proc callback,
                                    void *data, GC_finalization_proc *old_fn, void **old_data) {
    Watch **link = &watches;
    while (*link && (*link)->object != object) link = &(*link)->next;
    Watch *old = *link;
    if (old_fn) *old_fn = old ? old->callback : NULL;
    if (old_data) *old_data = old ? old->data : NULL;
    if (old) { *link = old->next; free(old); }
    if (!callback) return;
    Watch *watch = malloc(sizeof(*watch));
    if (!watch) native_trap();
    *watch = (Watch){object, data, callback, watches};
    watches = watch;
}

static void queue_finalizers(void) {
    Watch **link = &watches;
    while (*link) {
        Watch *watch = *link;
        uint64_t *header = candidate((uintptr_t)watch->object);
        if (header && !(*header & MARKED)) {
            *link = watch->next;
            // Only queues scalar IDs; it must not allocate or reenter.
            watch->callback(watch->object, watch->data);
            free(watch);
        } else link = &watch->next;
    }
}

static void sweep_starts(size_t index) {
    Block *block = &blocks[index];
    for (size_t word = 0; word < START_WORDS; word++) {
        uint64_t starts = block->starts[word];
        while (starts) {
            unsigned bit = __builtin_ctzll(starts);
            uint64_t *header = (uint64_t *)(arena + index * BLOCK_SIZE + (word * 64 + bit) * ALIGNMENT);
            if (*header & MARKED) {
                *header &= ~MARKED;
                live_bytes += *header >> 2;
                live_objects++;
            } else {
                block->starts[word] &= ~(UINT64_C(1) << bit);
                *header = 0;
            }
            starts &= starts - 1;
        }
    }
}

static void sweep(void) {
    live_bytes = live_objects = 0;
    for (size_t index = 0; index < used_blocks; index++) {
        Block *block = &blocks[index];
        sweep_starts(index);
        block->live_lines = 0;
        for (size_t line = 0; line < LINES; line++) block->live_lines += block->lines[line] != 0;
        if (!block->live_lines) block->span = 0;
        block->available_lines = LINES - block->live_lines;
        block->next_line = 0;
    }
    cursor = limit = NULL;
    search_block = search_large = 0;
}

void GC_gcollect(void) {
    double start = statistics ? seconds() : 0;
    for (size_t i = 0; i < used_blocks; i++) memset(blocks[i].lines, 0, LINES);
    mark_roots();
    while (work_count) trace_object(work[--work_count]);
    double marked = statistics ? seconds() : 0;
    queue_finalizers();
    sweep();
    if (statistics) { mark_seconds += marked - start; sweep_seconds += seconds() - marked; }
    collections++;
    if (live_bytes > peak_live) peak_live = live_bytes;
    budget = live_bytes * 2 > minimum_budget ? live_bytes * 2 : minimum_budget;
    since_collection = 0;
}

size_t GC_get_gc_no(void) { return collections; }

// ---- Initialization and opt-in measurements ----

static void report_statistics(void) {
    fprintf(stderr, "immix-gc allocation_search=tuned evacuation=0 scan_all=%d heap_bytes=%zu prefault_s=%.6f collections=%zu allocations=%zu bytes=%zu "
            "arena_used=%zu last_live=%zu peak_live=%zu live_objects=%zu roots=%zu fields=%zu "
            "holes_reused=%zu large_allocations=%zu mark_s=%.6f sweep_s=%.6f\n",
            scan_all, heap_bytes, prefault_seconds, collections, allocated_objects,
            allocated_bytes, used_blocks * BLOCK_SIZE, live_bytes, peak_live, live_objects,
            root_visits, field_visits, reused_holes, large_objects, mark_seconds, sweep_seconds);
}

void precise_init(void) {
    const char *heap = getenv("SNAIL_GC_HEAP_BYTES");
    if (heap) heap_bytes = strtoull(heap, NULL, 10) / BLOCK_SIZE * BLOCK_SIZE;
    if (heap_bytes < BLOCK_SIZE) native_trap();
    block_count = heap_bytes / BLOCK_SIZE;
    arena = mmap(NULL, heap_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    blocks = calloc(block_count, sizeof(*blocks));
    if (arena == MAP_FAILED || !blocks) native_trap();
    double start = seconds();
    // Touch every page before native_module_init and any internal benchmark timer.
    memset(arena, 0, heap_bytes);
    prefault_seconds = seconds() - start;
    scan_all = getenv("SNAIL_GC_SCAN_ALL") != NULL;
    statistics = getenv("SNAIL_GC_STATS") != NULL;
    const char *minimum = getenv("SNAIL_GC_MIN_BYTES");
    if (minimum) minimum_budget = budget = strtoull(minimum, NULL, 10);
    if (statistics) atexit(report_statistics);
}
