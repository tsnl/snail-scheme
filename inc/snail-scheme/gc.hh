#pragma once

#define GC_SINGLE_THREADED_MODE (1)

#include <vector>
#include <queue>
#include <forward_list>
#include <functional>
#include <algorithm>
#include <optional>
#include <cstdint>

#if !GC_SINGLE_THREADED_MODE
#include <mutex>
#endif

#include "gc.d.hh"
#include "config/config.hh"
#include "memory.hh"
#include "object.hh"

// see `/doc/gc-design.md`
// Largely based on TCMalloc, with mark-and-sweep support for the front-end
// and transfer-cache.
// See: https://github.com/google/tcmalloc/blob/master/docs/design.md
// Only 64-bit portions are used (alignment 16-bytes)

namespace gc {

class GcBackEnd;
class GcMiddleEnd;
class GcFrontEnd;

struct SizeClassInfo;

struct GenericSpan;
struct ObjectSpan;
struct PageSpan;

class GenericFreeList;
class ObjectFreeList;
class PageFreeList;

class ObjectAllocator;
class CentralObjectAllocator;

class MarkedSet;
struct MarkedPtr;

///
//
// Config:
//
//

inline constexpr size_t PAGE_SIZE_IN_BYTES = (1 << CONFIG_TCMALLOC_PAGE_SHIFT);
inline constexpr size_t PAGE_SIZE_IN_ABLKS = PAGE_SIZE_IN_BYTES / sizeof(ABlk);

///
//
// Size classes:
//
//

using SizeClassIndex = int8_t;

struct SizeClassInfo {
    // Size of each element in this size-class, in bytes.
    size_t size;
    
    // Number of pages to allocate at a time
    size_t pages;

    // Number of objects to move between transfer-cache and per-thread frontend.
    // Must be not-too-small to amortize lock-access-time.
    size_t num_to_move;
};

#include "gc.size_class.inl"

inline bool is_oversized_sci(SizeClassIndex sci) {
    return sci == kSizeClassesCount;
}

const int OVERSIZED_SCI = kSizeClassesCount;

constexpr SizeClassIndex sci(size_t size_in_bytes) {
#define USE_NAIVE_LOOKUP 0
#if USE_NAIVE_LOOKUP
    for (int i = 1; i < kSizeClassesCount; i++) {
        if (size_in_bytes <= kSizeClasses[i].size) {
            return i;
        }
    }
    return 0;   // unknown size-class
#else
    if (size_in_bytes > kMaxSize) {
        return 0;
    }
    // According to Wikipedia, using procedure to find the
    // left-most element: this performs 'rounding up'
    // https://en.wikipedia.org/wiki/Binary_search_algorithm#Procedure_for_finding_the_leftmost_element
    // NOTE: 'r' should be 'n' with 'l' '0' where 'n' is array length
    int l = 1;
    int r = kSizeClassesCount;
    while (l < r) {
        int m = (l + r) / 2;    // overflow-safe since size-classes are small
        if (kSizeClasses[m].size < size_in_bytes) {
            l = m + 1;
        } else {
            r = m;
        }
    }
    return l;
#endif
#undef USE_NAIVE_LOOKUP
}

///
//
// MarkedSet
//
//

template <typename T, size_t reserved_size=512>
struct reserved_vector: public std::vector<T> {
    reserved_vector()
    :   std::vector<T>() 
    {
        std::vector<T>::reserve(reserved_size);
    }
};

struct MarkedPtr {
    APtr ptr;
    SizeClassIndex sci;
};
inline bool operator>(MarkedPtr const& lt, MarkedPtr const& rt) {
    return lt.ptr > rt.ptr;
}

class MarkedSet {
private:
    std::priority_queue< MarkedPtr, reserved_vector<MarkedPtr>, std::greater<MarkedPtr> > m_ptr_max_heap;
public:
    void mark(SizeClassIndex sci, APtr ptr) {
        m_ptr_max_heap.emplace(ptr, sci);
    }
    bool empty() {
        return m_ptr_max_heap.empty();
    }
    MarkedPtr pop_max() {
        MarkedPtr top = m_ptr_max_heap.top();
        m_ptr_max_heap.pop();
        return top;
    }
};

///
//
// Span
//
//

struct GenericSpan {
    APtr ptr;
    size_t count;   // measures available bytes in multiple of free-list 'stride'
};
struct PageSpan: public GenericSpan {};
struct ObjectSpan: public GenericSpan {};

///
//
// FreeList
//
//

class ObjectAllocator;

// Each FreeList manages 'items' of fixed size.
class GenericFreeList {
public:
    using Iterator = std::forward_list<GenericSpan>::iterator;
protected:
    std::forward_list<GenericSpan> m_free_span_list;
    size_t m_item_stride_in_ablks;
protected:
    GenericFreeList() = default;
    void init(size_t item_stride_in_bytes);
public:
    APtr try_allocate_items(size_t item_count);
    std::pair<Iterator,Iterator> return_items_impl(APtr ptr, size_t item_count);
public:
    void return_items(APtr ptr, size_t item_count) { return_items_impl(ptr, item_count); }
public:
    void clear() { m_free_span_list.clear(); }
    Iterator before_begin() { return m_free_span_list.before_begin(); }
    Iterator begin() { return m_free_span_list.begin(); }
    Iterator end() { return m_free_span_list.end(); }
    void erase_after(GenericFreeList::Iterator it) {
        m_free_span_list.erase_after(it);
    }
    void insert_after(GenericFreeList::Iterator it, GenericSpan span) {
        m_free_span_list.insert_after(it, span);
    }
};
class PageFreeList: public GenericFreeList {
public:
    PageFreeList() = default;
public:
    void init() {
        GenericFreeList::init(PAGE_SIZE_IN_BYTES);
    }
};
class ObjectFreeList: public GenericFreeList {
public:
    ObjectFreeList() = default;   
public:
    void init(SizeClassIndex sci) {
        GenericFreeList::init(gc::kSizeClasses[sci].size);
    }
    size_t object_size_in_ablks() const { 
        return m_item_stride_in_ablks;
    }
};

///
// ObjectAllocator:
// - used by TransferCache
// - used by ThreadCache
//

class BaseObjectAllocator {
protected:
    ObjectFreeList m_object_free_list;
    SizeClassIndex m_sci;
protected:
    BaseObjectAllocator() = default;
public:
    void init(SizeClassIndex sci);
public:
    void clear() { m_object_free_list.clear(); }
    ObjectFreeList& object_free_list() { return m_object_free_list; }
};

class FrontEndObjectAllocator: public BaseObjectAllocator {
public:
    APtr try_allocate_object() {
        return m_object_free_list.try_allocate_items(1);
    }
    void return_object(APtr ptr) { 
        m_object_free_list.return_items(ptr, 1);
    }
    std::pair<
        ObjectFreeList::Iterator, 
        ObjectFreeList::Iterator
    > return_object_span(ObjectSpan span) {
        return m_object_free_list.return_items_impl(span.ptr, span.count);
    }
};

class CentralObjectAllocator: public BaseObjectAllocator {
protected:
    size_t const MAX_PAGESPANS_PER_SIZE_CLASS = 8192;

protected:
    std::vector<PageSpan> m_page_spans;
    std::vector<size_t> m_page_span_refcounts;
#if !GC_SINGLE_THREADED_MODE
    std::mutex m_mutex;
#endif
public:
    CentralObjectAllocator() = default;
public:
    std::optional<ObjectSpan> try_allocate_object_span();
    std::pair<GenericFreeList::Iterator, GenericFreeList::Iterator> return_object_span(ObjectSpan span);
    void add_page_span_to_pool(PageSpan span);
#if !GC_SINGLE_THREADED_MODE
public:
    std::mutex& mutex() { return m_mutex; }
#endif
private:
    size_t page_span_index(APtr ptr);
    void retain_single_page_span(APtr ptr);
    void release_single_page_span(APtr ptr);
    void retain_page_spans(APtr beg, APtr end);
    void release_page_spans(APtr beg, APtr end);
    void help_map_intersecting_page_spans(std::function<void(size_t)> cb, APtr beg, APtr end);
public:
    void trim_unused_pages(GcMiddleEnd* middle_end);
private:
    void extract_page_span_from_object_free_list(PageSpan extract_page_span, GcBackEnd* back_end);
};

///
// PageMap
// - maps pointers to page-index
// - maps page-index to...
//   - which front-end currently holds this page (0..N-1), else middle-end (-1) or back-end (-2)
//   - current size-class (else 0)
//   - index into a span [of pages], else -ve value
// - allows us to query the page => size-class, span, and owner (back-end, middle-end, front-end(i)) of any pointer
//

#if 0       // not in use
using PageIndex = int64_t;

struct PageInfo {
    int32_t owner;
    int16_t size_class;
    int16_t span_index;
};

class PageMap {
private:
    size_t m_beg_aptr_address;
    size_t m_end_aptr_address;
    std::vector<PageInfo> m_page_table;
public:
    explicit PageMap();
    void init(GcBackEnd* back_end);
private:
    PageIndex page_index(APtr ptr) {
        size_t ptr_address = reinterpret_cast<size_t>(ptr);
        assert(m_beg_aptr_address <= ptr_address && ptr_address <= m_end_aptr_address);
        size_t ablk_offset = ptr_address - m_beg_aptr_address;
        size_t byte_offset = ablk_offset * sizeof(ABlk);
        assert(byte_offset % PAGE_SIZE_IN_BYTES == 0);
        size_t page_offset = byte_offset >> CONFIG_TCMALLOC_PAGE_SHIFT;
        return page_offset;
    }
public:
    PageInfo& page_info(PageIndex index) {
        return m_page_table[index];
    }
    PageInfo& page_info(APtr ptr) {
        return page_info(page_index(ptr));
    }
};
#endif

///
// GC Back-end: pageheap: free-list of page-spans
// - Subdivides a single contiguous region into the required number of
//   page-spans lazily.
//   Single contiguous region is of fixed-size.
//   Allocations in this manner are prone to fragmentation, but at this
//   size (page-size), this is rarely an issue.
// - maintains page-map
//

class GcBackEnd {
private:
    // pointer to and page-capacity of single contiguous region
    APtr m_single_contiguous_region_beg;
    APtr m_single_contiguous_region_end;
    size_t m_single_contiguous_region_page_capacity;
    PageFreeList m_page_free_list;
#if !GC_SINGLE_THREADED_MODE
    std::mutex m_mutex;
#endif
    // PageMap m_page_map;
public:
    GcBackEnd() = default;
public:
    void init(size_t single_contiguous_region_page_capacity, APtr single_contiguous_region);
public:
    std::optional<PageSpan> try_allocate_page_span(size_t page_count);
    void return_page_span(PageSpan page_span);
public:
    size_t total_page_count() { return m_single_contiguous_region_page_capacity; }
    // PageMap& page_map() { return m_page_map; }
    APtr total_pages_beg_address() { return m_single_contiguous_region_beg; }
    APtr total_pages_end_address() { return m_single_contiguous_region_end; }
};

///
// GC Middle-end: transfer-cache at PageSpan-level granularity
// - maintains a pool of objects with a pool of backing PageSpans
// - maintains one lock per-size-class
//

class GcMiddleEnd {
private:
    CentralObjectAllocator m_central_object_allocators[kSizeClassesCount];
    GcBackEnd* m_back_end;
public:
    GcMiddleEnd() = default;
public:
    void init(GcBackEnd* backend);
public:
    std::optional<ObjectSpan> try_allocate_object_span(SizeClassIndex sci);
    void return_object_span(SizeClassIndex sci, ObjectSpan span);
public:
    GcBackEnd* back_end() { return m_back_end; }
public:
    void trim_unused_pages();
};

///
// GC Front-end: pool of objects acquired from transfer-cache.
//

class GcFrontEnd {
private:
    FrontEndObjectAllocator m_sub_allocators[kSizeClassesCount];
    GcMiddleEnd* m_middle_end;
public:
    GcFrontEnd() = default;
    void init(GcMiddleEnd* middle_end);
public:
    APtr allocate(SizeClassIndex sci);
    void deallocate(APtr memory, SizeClassIndex sci);
public:
    void sweep(MarkedSet& marked_set);
private:
    void try_return_free_list_node_to_middle_end(
        SizeClassIndex fl_sci,
        ObjectFreeList::Iterator fl_node_pred, ObjectFreeList::Iterator fl_node
    );
};

}   // namespace gc

///
//
// Interface:
//
//

class Gc {
private:
    gc::GcBackEnd m_gc_back_end;
    gc::GcMiddleEnd m_gc_middle_end;
public:
    explicit Gc(APtr single_contiguous_region, size_t single_contiguous_region_size);
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
    APtr allocate_size_class(gc::SizeClassIndex sci) {
        return m_impl.allocate(sci);
    }
    void deallocate_size_class(APtr ptr, gc::SizeClassIndex sci) {
        m_impl.deallocate(ptr, sci);
    }
public:
    APtr allocate_bytes(size_t byte_count) { 
        return allocate_size_class(gc::sci(byte_count)); 
    }
    void deallocate_bytes(APtr ptr, size_t byte_count) { 
        deallocate_size_class(ptr, gc::sci(byte_count)); 
    }
public:
    void sweep(gc::MarkedSet& marked_set);
};
