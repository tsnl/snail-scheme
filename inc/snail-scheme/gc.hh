#pragma once

#include <vector>
#include <mutex>
#include <forward_list>
#include <cstdint>

// see `/doc/gc-design.md`
// Largely based on TCMalloc, with mark-and-sweep support for the front-end.
// See: https://github.com/google/tcmalloc/blob/master/docs/design.md
// Only 64-bit portions are used (alignment 16-bytes)

namespace gc {

class SizeClassAllocator;

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

extern const int kMaxSize;
extern const int kSizeClassesCount;
extern const SizeClassInfo kSizeClasses[];

inline bool is_oversized_sci(SizeClassIndex sci) {
    return sci == kSizeClassesCount;
}

const int OVERSIZED_SCI = kSizeClassesCount;

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
// GC Back-end:
//

class GcBackEnd {
public:
    void allocate_page();
};

///
// GC Middle-end:
//

class GcMiddleEnd {
private:
    FreeList m_free_page_list;
    std::vector<PageSpan> m_page_spans;
    std::mutex m_mutex;
    GcBackEnd* m_backend;
    
public:

};

///
// GC Front-end:
//

class GcFrontend {
private:
    SizeClassAllocator* m_sub_allocators;
    GcMiddleEnd* m_middle_end;

public:
    uint8_t* allocate(SizeClassIndex sci);
    void deallocate(uint8_t* memory, SizeClassIndex sci);

public:
    void mark_and_sweep();
};

///
// GC Front-end: individual size-class allocator:
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

}   // namespace gc
