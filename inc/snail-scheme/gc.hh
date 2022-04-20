#pragma once

#include <vector>
#include <mutex>
#include <forward_list>
#include <algorithm>
#include <cstdint>

#include "config/config.hh"
#include "memory.hh"

// see `/doc/gc-design.md`
// Largely based on TCMalloc, with mark-and-sweep support for the front-end
// and transfer-cache.
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
    std::vector<APointer> m_marked_ptrs;

public:
    SingleSizeClassMarkedVector()
    :   m_marked_ptrs()
    {
        m_marked_ptrs.reserve(1024);
    }

    void mark(APointer ptr) {
        m_marked_ptrs.push_back(ptr);
    }

    std::vector<APointer>& ptrs() { return m_marked_ptrs; };
};

class MarkedSet {
private:
    SingleSizeClassMarkedVector* m_per_sci_marked_table;

public:
    void mark(SizeClassIndex sci, APointer ptr) {
        m_per_sci_marked_table[sci].mark(ptr);
    }
};


///
// Span
//

struct GenericSpan {
    APointer ptr;
    size_t count;   // measures available bytes in multiple of free-list 'stride'
};
struct PageSpan: public GenericSpan {};
struct ObjectSpan: public GenericSpan {};

///
// FreeList
//

class ObjectAllocator;

// Each FreeList manages 'items' of fixed size.
class GenericFreeList {
    friend ObjectAllocator;

public:
    using Iterator = std::forward_list<GenericSpan>::iterator;

private:
    std::forward_list<GenericSpan> m_free_span_list;
    size_t m_item_stride_in_ablks;

protected:
    GenericFreeList(size_t item_stride_in_bytes)
    :   m_item_stride_in_ablks(item_stride_in_bytes >> 4) 
    {
        static_assert(__STDCPP_DEFAULT_NEW_ALIGNMENT__ == 16);
    }

public:
    APointer try_allocate_items(size_t item_count);
    std::pair<Iterator,Iterator> return_items_impl(APointer ptr, size_t item_count);
    void clear();

    void return_items(APointer ptr, size_t item_count) {
        return_items_impl(ptr, item_count);
    }
};
class PageFreeList: public GenericFreeList {
public:
    PageFreeList()
    :   GenericFreeList(PAGE_SIZE_IN_BYTES)
    {}
};
class ObjectFreeList: public GenericFreeList {
public:
    ObjectFreeList(gc::SizeClassIndex sci)
    :   GenericFreeList(gc::kSizeClasses[sci].size)
    {}
};

///
// ObjectAllocator:
// - used by TransferCache
// - used by ThreadCache
//

class ObjectAllocator {
protected:
    ObjectFreeList m_object_free_list;
    SizeClassIndex m_sci;

public:
    ObjectAllocator(SizeClassIndex sci)
    :   m_object_free_list(sci),
        m_sci(sci)
    {}

public:
    APointer try_allocate_object() { return m_object_free_list.try_allocate_items(1); }
    void deallocate(APointer ptr) { m_object_free_list.return_items(ptr, 1); }

public:
    void sweep(SingleSizeClassMarkedVector* marked_vector) {
        m_object_free_list.clear();
        for (auto marked_ptr: marked_vector->ptrs()) {
            m_object_free_list.return_items(marked_ptr, 1);
        }
    }
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
    APointer m_single_contiguous_region;
    size_t m_single_contiguous_region_page_capacity;
    PageFreeList m_page_free_list;
public:
    GcBackEnd() = default;
public:
    void init(size_t single_contiguous_region_page_capacity, APointer single_contiguous_region);
public:
    std::optional<PageSpan> try_allocate_page_span(size_t page_count);
    void return_page_span(PageSpan page_span);
};

///
// GC Middle-end: transfer-cache at PageSpan-level granularity
// - maintains a pool of 'PageSpan's 
// - maintains one lock per-size-class
//

size_t const MAX_PAGESPANS_PER_SIZE_CLASS = 8192;

class GlobalObjectAllocator: public ObjectAllocator {
protected:
    PageFreeList m_free_page_list;
    std::mutex m_mutex;

public:
    SizeClassPagesPool(SizeClassIndex sci);

public:
    // NOTE: the number of pages in each page-span is determined by 
    // gc::kSizeClasses[m_sci].pages
    void add_page_span_to_pool(PageSpan span) {
        std::lock_guard lg{m_mutex};
        assert(span.count == kSizeClasses[m_sci].pages);
        m_free_page_list.return_items(span.ptr, span.count);
    }
    
    void collect_free_pages();

public:
    void return_items(APointer ptr, size_t item_count);
};

class GcMiddleEnd {
private:
    GlobalObjectAllocator m_object_allocators[kSizeClassesCount];
    GcBackEnd* m_backend;
    
public:
    GcMiddleEnd();

public:
    void init(GcBackEnd* backend);
};

///
// GC Front-end:
//

class GcFrontEnd {
private:
    ObjectAllocator m_sub_allocators[kSizeClassesCount];
    GcMiddleEnd* m_middle_end;

public:
    GcFrontEnd(GcMiddleEnd* middle_end);

public:
    APointer allocate(SizeClassIndex sci);
    void deallocate(APointer memory, SizeClassIndex sci);

public:
    void mark_and_sweep();
};

}   // namespace gc


///
// Interface:
//

class Gc {
private:
    gc::GcBackEnd m_gc_back_end;
    gc::GcMiddleEnd m_gc_middle_end;

public:
    explicit Gc(APointer single_contiguous_region, size_t single_contiguous_region_size);

public:
    gc::GcBackEnd& back_end_impl() { return m_gc_back_end; }
    gc::GcMiddleEnd& middle_end_impl() { return m_gc_middle_end; }
};


class GcThreadFrontEnd {
private:
    gc::GcFrontEnd m_impl;

public:
    GcThreadFrontEnd(Gc* gc);

public:
    APointer allocate_size_class(gc::SizeClassIndex sci) {
        return m_impl.allocate(sci);
    }
    void deallocate_size_class(APointer ptr, gc::SizeClassIndex sci) {
        m_impl.deallocate(ptr, sci);
    }
    
public:
    APointer allocate_bytes(size_t byte_count) { 
        return allocate_size_class(gc::sci(byte_count)); 
    }
    void deallocate_bytes(APointer ptr, size_t byte_count) { 
        deallocate_size_class(ptr, gc::sci(byte_count)); 
    }
};
