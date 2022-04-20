#pragma once

#include <vector>
#include <mutex>
#include <forward_list>
#include <cstdint>

#include "config/config.hh"

// see `/doc/gc-design.md`
// Largely based on TCMalloc, with mark-and-sweep support for the front-end.
// See: https://github.com/google/tcmalloc/blob/master/docs/design.md
// Only 64-bit portions are used (alignment 16-bytes)

namespace gc {

///
// Config:
//

inline constexpr size_t PAGE_SIZE_IN_BYTES = (1 << CONFIG_TCMALLOC_PAGE_SHIFT);

///
// Size classes:
//

using SizeClassIndex = int8_t;

struct SizeClassInfo {
    // Size of each element in this size-class, in bytes.
    size_t size;
    
    // Number of pages to allocate at a time
    size_t pages;

    // Number of objects to move between a thread-cache and the transfer-cache
    // in one shot. We want this to be not too small so we can aortize the lock 
    // overhead for accessing the transfer cache.
    size_t num_to_move;
};

#include "gc.size_class.inl"

inline bool is_oversized_sci(SizeClassIndex sci) {
    return sci == kSizeClassesCount;
}

const int OVERSIZED_SCI = kSizeClassesCount;

constexpr SizeClassIndex sci(size_t size_in_bytes) {
    // TODO: optimize this!
    for (int i = 1; i <= kSizeClassesCount; i++) {
        if (size_in_bytes <= kSizeClasses[i].size) {
            return i;
        }
    }
    return 0;
}

///
// MarkedSet
//

class SingleSizeClassMarkedVector {
private:
    std::vector<uint8_t*> m_marked_ptrs;

public:
    SingleSizeClassMarkedVector()
    :   m_marked_ptrs()
    {
        m_marked_ptrs.reserve(1024);
    }

    void mark(uint8_t* ptr) {
        m_marked_ptrs.push_back(ptr);
    }

    std::vector<uint8_t*>& ptrs() { return m_marked_ptrs; };
};

class MarkedSet {
private:
    SingleSizeClassMarkedVector* m_per_sci_marked_table;

public:
    void mark(SizeClassIndex sci, uint8_t* ptr) {
        m_per_sci_marked_table[sci].mark(ptr);
    }
};


///
// Span
//

struct GenericSpan {
    uint8_t* ptr;
    size_t count;
};
struct PageSpan: public GenericSpan {};
struct ObjectSpan: public GenericSpan {};

///
// FreeList
//

class FreeList {
private:
    std::forward_list<GenericSpan> m_free_span_list;
    size_t m_object_size_in_bytes;

public:
    FreeList(SizeClassIndex sci);

public:
    uint8_t* try_allocate_object();
    void free_object(uint8_t* ptr);

public:
    void reset(std::vector<PageSpan>& pages);
    uint8_t* force_allocate_object(uint8_t* ptr);
};

///
// GC Back-end: pageheap: free-list of page-spans
// Subdivides a single contiguous region into the required number of
// page-spans lazily.
// Single contiguous region is of fixed-size.
// Allocations in this manner are prone to fragmentation, but at this
// size (page-size), this is rarely an issue.
//

class GcBackEnd {
private:
    // pointer to and page-capacity of single contiguous region
    uint8_t* m_single_contiguous_region;
    size_t m_single_contiguous_region_page_capacity;
    FreeList m_page_free_list;
public:
    std::optional<PageSpan> try_allocate_page_span();
    void deallocate_page_span(PageSpan page_span);
};

///
// GC Middle-end: transfer-cache at PageSpan-level granularity
// - maintains a pool of 'PageSpan's 
// - maintains one lock per-size-class
//

class SizeClassPageSpanPool {
private:
    std::forward_list<PageSpan> m_page_spans;
    FreeList m_free_page_list;
    std::mutex m_mutex;

public:
    SizeClassPageSpanPool();
};

class GcMiddleEnd {
private:
    SizeClassPageSpanPool m_size_class_page_span_pools[kSizeClassesCount];
    GcBackEnd* m_backend;
    
public:
    explicit GcMiddleEnd(GcBackEnd* backend);
};

///
// GC Front-end:
//

class SizeClassAllocator {
private:
    FreeList m_free_list;
    std::vector<PageSpan> m_pages;

public:
    SizeClassAllocator(SizeClassIndex sci);

public:
    uint8_t* try_allocate_object() { return m_free_list.try_allocate_object(); }
    void free_object(uint8_t* ptr) { m_free_list.free_object(ptr); }

public:
    void sweep(SingleSizeClassMarkedVector* marked_vector) {
        m_free_list.reset(m_pages);
        for (auto marked_ptr: marked_vector->ptrs()) {
            m_free_list.force_allocate_object(marked_ptr);
        }
    }
};

class GcFrontend {
private:
    SizeClassAllocator m_sub_allocators[kSizeClassesCount];
    GcMiddleEnd* m_middle_end;

public:
    uint8_t* allocate(SizeClassIndex sci);
    void deallocate(uint8_t* memory, SizeClassIndex sci);

public:
    void mark_and_sweep();
};

}   // namespace gc
