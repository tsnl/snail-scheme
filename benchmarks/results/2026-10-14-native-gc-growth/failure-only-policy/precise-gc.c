// Nonmoving Immix: block/line reclamation and bump allocation.
// Exact reference frames and declared heap edges provide all roots. Numeric
// slots never participate in tracing; managed references never move.
#define _GNU_SOURCE
#include "precise-gc.h"
#include <assert.h>
#include <errno.h>
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
#define CONTINUATION SIZE_MAX

typedef struct {
    uint64_t starts[START_WORDS];
    uint8_t lines[LINES];
    size_t span;
    uint32_t live_lines;
    uint16_t available_lines, next_line;
} Block;
_Static_assert(sizeof(Block) < BLOCK_SIZE, "block metadata size must fit checked region sizing");
typedef struct Region {
    uint8_t *arena;
    Block *blocks;
    size_t block_count, used_blocks, search_block, search_large;
    struct Region *next;
} Region;
typedef struct { uint32_t kind, count; const uint32_t *offsets; } Layout;
typedef struct Watch {
    void *object, *data;
    NativeFinalizer callback;
    struct Watch *next;
} Watch;
extern const Layout native_gc_layouts[];
extern const uint64_t native_gc_layouts_count;
extern uint64_t *const native_gc_globals[];
extern const uint64_t native_gc_globals_count;
extern NativeTable *const native_gc_tables[];
extern const uint64_t native_gc_tables_count;
extern _Noreturn void native_trap(void);

// Each region owns its maps and never moves. Objects cannot cross regions.
// A bump range reserves its entire line hole until GC, with its own owner:
// allocating a large object elsewhere must not change the small bump's maps.
static Region *regions, *search_region, *bump_region;
static uint8_t *cursor, *limit;
static size_t heap_bytes, heap_limit, maximum_heap_bytes, initial_heap_bytes, region_count;
static size_t since_collection, budget = 8 * 1024 * 1024, minimum_budget = 8 * 1024 * 1024;
static uint64_t **work;
static size_t work_count, work_capacity, collections, live_bytes, live_objects;
static size_t allocated_bytes, allocated_objects, peak_live, root_visits, field_visits;
static size_t reused_holes, large_objects;
static double mark_seconds, sweep_seconds;
static bool statistics;
static Watch *watches;

static double seconds(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return time.tv_sec + time.tv_nsec * 1e-9;
}

static size_t aligned_size(size_t bytes) {
    return (bytes + 8 + ALIGNMENT - 1) & ~(size_t)(ALIGNMENT - 1);
}

static void record_start(Region *region, uint64_t *header) {
    size_t offset = (uint8_t *)header - region->arena;
    size_t index = offset % BLOCK_SIZE / ALIGNMENT;
    region->blocks[offset / BLOCK_SIZE].starts[index / 64] |= UINT64_C(1) << (index % 64);
}

// ---- Region growth ----

// Prepare every resource before publication. A failed addition leaves the
// existing regions, search cursors and capacity intact. Metadata is outside
// the managed-byte cap; its size cannot overflow because sizeof(Block) < BLOCK_SIZE.
static bool add_region(size_t bytes) {
    Region *region = malloc(sizeof(*region));
    if (!region) return false;
    Block *blocks = calloc(bytes / BLOCK_SIZE, sizeof(*blocks));
    uint8_t *arena = blocks ? mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                                  MAP_PRIVATE | MAP_ANONYMOUS, -1, 0) : MAP_FAILED;
    if (arena == MAP_FAILED) { free(blocks); free(region); return false; }
    *region = (Region){.arena = arena, .blocks = blocks,
                       .block_count = bytes / BLOCK_SIZE, .next = regions};
    regions = search_region = region;
    heap_bytes += bytes;
    region_count++;
    return true;
}

// Called only after a complete collection and failed search. Double total
// capacity where possible, but obtain a larger region for a larger object.
// The final addition may consume a smaller cap remainder. If the preferred
// reservation fails, try just the complete block-rounded object extent.
static bool grow_heap(size_t bytes) {
    size_t needed = (bytes + BLOCK_SIZE - 1) / BLOCK_SIZE * BLOCK_SIZE;
    size_t remaining = maximum_heap_bytes - heap_bytes;
    if (needed > remaining) return false;
    size_t preferred = heap_bytes > needed ? heap_bytes : needed;
    if (preferred > remaining) preferred = remaining;
    return add_region(preferred) || (preferred != needed && add_region(needed));
}

// ---- Block and line allocation ----

// Search cursors reset after GC. Between collections allocation only consumes
// holes, so full blocks can be skipped without reading their line maps again.
static void claim_hole(Region *region, size_t index, size_t first, size_t end) {
    Block *block = &region->blocks[index];
    if (block->live_lines) reused_holes++;
    memset(block->lines + first, 1, end - first);
    block->span = 1;
    block->available_lines -= end - first;
    block->next_line = end;
    bump_region = region;
    cursor = region->arena + index * BLOCK_SIZE + first * LINE_SIZE;
    limit = region->arena + index * BLOCK_SIZE + end * LINE_SIZE;
    region->search_block = index;
    if (index + 1 > region->used_blocks) region->used_blocks = index + 1;
}

static bool find_hole(Region *region, size_t index, size_t first, size_t stop, size_t bytes) {
    Block *block = &region->blocks[index];
    while (first < stop) {
        while (first < stop && block->lines[first]) first++;
        size_t end = first;
        while (end < stop && !block->lines[end]) end++;
        if ((end - first) * LINE_SIZE >= bytes) {
            claim_hole(region, index, first, end);
            return true;
        }
        first = end;
    }
    return false;
}

static bool acquire_hole(Region *region, size_t bytes) {
    size_t index = region->search_block;
    for (size_t checked = 0; checked < region->block_count; checked++) {
        Block *block = &region->blocks[index];
        if (!block->span) {
            block->available_lines = LINES;
            claim_hole(region, index, 0, LINES);
            return true;
        }
        if (block->span == 1 && (size_t)block->available_lines * LINE_SIZE >= bytes) {
            // The boundary follows a consumed hole, so no free run crosses it.
            size_t next = block->next_line;
            if (find_hole(region, index, next, LINES, bytes)
                || find_hole(region, index, 0, next, bytes))
                return true;
        }
        if (++index == region->block_count) index = 0;
    }
    return false;
}

// Next-fit begins after the last reservation. A second range search includes
// all earlier holes before failure; the split follows an occupied reservation.
// Differing request sizes therefore cannot strand a free run across the split.
static uint64_t *find_large(Region *region, size_t first, size_t stop, size_t span) {
    Block *blocks = region->blocks;
    while (first + span <= stop) {
        size_t end = first;
        while (end < first + span && !blocks[end].span) end++;
        if (end == first + span) {
            blocks[first].span = span;
            for (size_t i = first + 1; i < end; i++) blocks[i].span = CONTINUATION;
            if (end > region->used_blocks) region->used_blocks = end;
            region->search_large = end;
            large_objects++;
            uint64_t *header = (uint64_t *)(region->arena + first * BLOCK_SIZE);
            record_start(region, header);
            return header;
        }
        size_t occupied = blocks[end].span;
        first = end + (occupied == CONTINUATION ? 1 : occupied);
    }
    return NULL;
}

static uint64_t *allocate_large(Region *region, size_t bytes) {
    size_t span = (bytes + BLOCK_SIZE - 1) / BLOCK_SIZE;
    uint64_t *header = find_large(region, region->search_large, region->block_count, span);
    return header ? header : find_large(region, 0, region->search_large, span);
}

static uint64_t *allocate_bump(size_t bytes) {
    uint64_t *header = (uint64_t *)cursor;
    cursor += bytes;
    record_start(bump_region, header);
    return header;
}

static __attribute__((noinline)) uint64_t *allocate_slow(size_t bytes) {
    Region *first = search_region;
    do {
        if (bytes > BLOCK_SIZE) {
            uint64_t *header = allocate_large(search_region, bytes);
            if (header) return header;
        } else if (acquire_hole(search_region, bytes)) return allocate_bump(bytes);
        search_region = search_region->next ? search_region->next : regions;
    } while (search_region != first);
    return NULL;
}

static uint64_t *allocate_header(size_t bytes) {
    // Each bump range stays inside one block, so large requests always miss.
    if (!cursor || (size_t)(limit - cursor) < bytes) return allocate_slow(bytes);
    return allocate_bump(bytes);
}

static __attribute__((noinline)) uint64_t *retry_allocation(size_t bytes, bool collected) {
    uint64_t *header = NULL;
    if (!collected) { native_gc_collect(); header = allocate_header(bytes); }
    if (!header && grow_heap(bytes)) header = allocate_header(bytes);
    return header;
}

__attribute__((always_inline)) void *native_gc_alloc(size_t bytes) {
    // Two low header bits hold flags. This bound also makes header, alignment,
    // block rounding and collection-budget arithmetic safe before any mutation.
    if (bytes > SIZE_MAX / 4 || aligned_size(bytes) > maximum_heap_bytes) return NULL;
    bool collected = since_collection >= budget;
    if (collected) native_gc_collect();
    size_t extent = aligned_size(bytes);
    uint64_t *header = allocate_header(extent);
    if (!header) header = retry_allocation(extent, collected);
    if (!header) return NULL;
    *header = ((uint64_t)bytes << 2) | ALLOCATED;
    memset(header + 1, 0, bytes);
    since_collection += extent;
    allocated_bytes += bytes;
    allocated_objects++;
    return header + 1;
}

// ---- Explicit roots and tracing ----

// Validate published reference words before following them. Null, odd i31
// immediates and static literal objects are outside the managed regions.
static Region *containing_region(uint64_t value) {
    // Mappings are page aligned; payloads start eight bytes past a 16-byte
    // aligned header. Reject null and immediate values before searching maps.
    if (value % ALIGNMENT != 8) return NULL;
    for (Region *region = regions; region; region = region->next)
        if ((uintptr_t)value - (uintptr_t)region->arena < region->used_blocks * BLOCK_SIZE)
            return region;
    return NULL;
}

static uint64_t *candidate(Region *region, uint64_t value) {
    if (!region) return NULL;
    uintptr_t offset = (uintptr_t)value - (uintptr_t)region->arena;
    size_t index = (offset - 8) % BLOCK_SIZE / ALIGNMENT;
    if (!(region->blocks[offset / BLOCK_SIZE].starts[index / 64] & (UINT64_C(1) << (index % 64)))) return NULL;
    uint64_t *header = (uint64_t *)(uintptr_t)value - 1;
    return (*header & ALLOCATED) ? header : NULL;
}

static void mark_lines(Region *region, uint64_t *header) {
    size_t offset = (uint8_t *)header - region->arena;
    size_t first = offset / LINE_SIZE;
    size_t end = (offset + aligned_size(*header >> 2) + LINE_SIZE - 1) / LINE_SIZE;
    for (size_t line = first; line < end; line++)
        region->blocks[line / LINES].lines[line % LINES] = 1;
}

static void mark(uint64_t value) {
    Region *region = containing_region(value);
    uint64_t *header = candidate(region, value);
    if (!header || (*header & MARKED)) return;
    *header |= MARKED;
    mark_lines(region, header);
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

void native_gc_watch(void *object, NativeFinalizer callback,
                                    void *data, NativeFinalizer *old_fn, void **old_data) {
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
        uint64_t value = (uintptr_t)watch->object;
        uint64_t *header = candidate(containing_region(value), value);
        if (header && !(*header & MARKED)) {
            *link = watch->next;
            // Only queues scalar IDs; it must not allocate or reenter.
            watch->callback(watch->object, watch->data);
            free(watch);
        } else link = &watch->next;
    }
}

static void sweep_starts(Region *region, size_t index) {
    Block *block = &region->blocks[index];
    for (size_t word = 0; word < START_WORDS; word++) {
        uint64_t starts = block->starts[word];
        while (starts) {
            unsigned bit = __builtin_ctzll(starts);
            uint64_t *header = (uint64_t *)(region->arena + index * BLOCK_SIZE + (word * 64 + bit) * ALIGNMENT);
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

static void sweep_region(Region *region) {
    for (size_t index = 0; index < region->used_blocks; index++) {
        Block *block = &region->blocks[index];
        sweep_starts(region, index);
        block->live_lines = 0;
        for (size_t line = 0; line < LINES; line++) block->live_lines += block->lines[line] != 0;
        if (!block->live_lines) block->span = 0;
        block->available_lines = LINES - block->live_lines;
        block->next_line = 0;
    }
    region->search_block = region->search_large = 0;
}

static void sweep(void) {
    live_bytes = live_objects = 0;
    for (Region *region = regions; region; region = region->next) sweep_region(region);
    cursor = limit = NULL;
    bump_region = NULL;
    search_region = regions;
}

void native_gc_collect(void) {
    double start = statistics ? seconds() : 0;
    for (Region *region = regions; region; region = region->next)
        for (size_t i = 0; i < region->used_blocks; i++) memset(region->blocks[i].lines, 0, LINES);
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

size_t native_gc_collections(void) { return collections; }

// ---- Initialization and opt-in measurements ----

static void report_statistics(void) {
    size_t arena_used = 0;
    for (Region *region = regions; region; region = region->next) arena_used += region->used_blocks * BLOCK_SIZE;
    fprintf(stderr, "immix-gc allocation_search=tuned evacuation=0 heap_bytes=%zu initial_heap_bytes=%zu "
            "heap_limit=%zu regions=%zu growths=%zu collections=%zu allocations=%zu bytes=%zu "
            "arena_used=%zu last_live=%zu peak_live=%zu live_objects=%zu roots=%zu fields=%zu "
            "holes_reused=%zu large_allocations=%zu mark_s=%.6f sweep_s=%.6f\n",
            heap_bytes, initial_heap_bytes, heap_limit, region_count, region_count - 1, collections, allocated_objects,
            allocated_bytes, arena_used, live_bytes, peak_live, live_objects,
            root_visits, field_visits, reused_holes, large_objects, mark_seconds, sweep_seconds);
}

static size_t configured_bytes(const char *name, size_t fallback) {
    const char *text = getenv(name);
    if (!text) return fallback;
    char *end;
    errno = 0;
    unsigned long long bytes = strtoull(text, &end, 10);
    if (!*text || *text == '-' || *end || errno || bytes > SIZE_MAX || !bytes)
        native_trap();
    return (size_t)bytes;
}

static size_t configured_heap_bytes(const char *name, size_t fallback) {
    size_t bytes = configured_bytes(name, fallback);
    if (bytes < BLOCK_SIZE || bytes > SIZE_MAX / 4) native_trap();
    return bytes / BLOCK_SIZE * BLOCK_SIZE;
}

void native_gc_init(void) {
    // Preserve the historical cap-only fixed reservation. Configured sizes
    // round down, so neither the initial mapping nor later growth exceeds it.
    heap_limit = getenv("SNAIL_GC_HEAP_BYTES") ? configured_heap_bytes("SNAIL_GC_HEAP_BYTES", 0) : 0;
    maximum_heap_bytes = heap_limit ? heap_limit : SIZE_MAX / 4 / BLOCK_SIZE * BLOCK_SIZE;
    size_t fallback = heap_limit ? heap_limit : 256 * 1024 * 1024;
    initial_heap_bytes = configured_heap_bytes("SNAIL_GC_INITIAL_BYTES", fallback);
    if (initial_heap_bytes > maximum_heap_bytes) native_trap();
    minimum_budget = budget = configured_bytes("SNAIL_GC_MIN_BYTES", minimum_budget);
    if (!add_region(initial_heap_bytes)) native_trap();
    // Mappings reserve virtual space; pages become resident as objects are used.
    statistics = getenv("SNAIL_GC_STATS") != NULL;
    if (statistics) atexit(report_statistics);
}
