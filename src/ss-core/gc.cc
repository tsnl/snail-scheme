#include "ss-core/gc.hh"

#include <iostream>
#include <sstream>
#include <cassert>
#include "ss-core/config.hh"
#include "ss-core/allocator.hh"
#include "ss-core/feedback.hh"

///
// Interface:
//

namespace ss {

    Gc::Gc(APtr single_contiguous_region, size_t single_contiguous_region_size)
    :   m_gc_back_end(),
        m_gc_middle_end()
    {
        if (single_contiguous_region == nullptr) {
            std::stringstream ss;
            ss << "Insufficient system memory: could not allocate " << single_contiguous_region_size << "B";
            error(ss.str());
            throw SsiError();
        }

        // ensuring the base pointer is page-aligned
        // TODO: consider using `std::align`?
        // see: https://en.cppreference.com/w/cpp/memory/align
        size_t bytes_after_page_start = reinterpret_cast<size_t>(single_contiguous_region) % gc::PAGE_SIZE_IN_BYTES;
        if (bytes_after_page_start > 0) {
            size_t wasted_starting_byte_count = gc::PAGE_SIZE_IN_BYTES - bytes_after_page_start;
            assert(wasted_starting_byte_count % sizeof(ABlk) == 0);
            single_contiguous_region += wasted_starting_byte_count / sizeof(ABlk);
            single_contiguous_region_size -= wasted_starting_byte_count;
        }

        m_gc_back_end.init(
            single_contiguous_region_size >> CONFIG_TCMALLOC_PAGE_SHIFT,
            single_contiguous_region
        );
        m_gc_middle_end.init(&m_gc_back_end);
    }

    GcThreadFrontEnd::GcThreadFrontEnd(Gc* gc)
    :   m_impl(),
        m_tfid(s_tfid_counter++)
    {
        assert(s_tfid_counter > m_tfid && "Too many GcThreadFrontEnds spawned: maximum 255 front-ends supported.");
        m_impl.init(&gc->middle_end_impl());

        s_all_table[m_tfid] = this;
    }

    void GcThreadFrontEnd::sweep(gc::MarkedSet& marked_set) {
        m_impl.sweep(marked_set);
    }

}

///
// Implementation:
//

namespace ss::gc {

///
// Free-list:
//

using GflIterator = GenericFreeList::Iterator;

void GenericFreeList::init(size_t item_stride_in_bytes) {
    static_assert(__STDCPP_DEFAULT_NEW_ALIGNMENT__ == 16);
    static_assert(__STDCPP_DEFAULT_NEW_ALIGNMENT__ == sizeof(ABlk));
    m_item_stride_in_ablks = (item_stride_in_bytes >> 4);
}

APtr GenericFreeList::try_allocate_items(size_t item_count) {
    GflIterator pred = m_free_span_list.before_begin();
    GflIterator self = m_free_span_list.begin();
    
    while (self != m_free_span_list.end()) {
        if (self->count == item_count) {
            auto extracted_ptr = self->ptr;
            m_free_span_list.erase_after(pred);
            return extracted_ptr;
        }
        else if (self->count > item_count) {
            auto extracted_ptr = self->ptr;
            self->count -= item_count;
            self->ptr += m_item_stride_in_ablks * item_count;
            return extracted_ptr;
        }
        else {
            // keep scanning...
            pred = self;
            self++;
        }
    }

    // iff we reach the end of this free-list and could not satisfy this
    // allocation, return 'null'
    return nullptr;
}

std::pair<GflIterator,GflIterator> GenericFreeList::return_items_impl(APtr ptr, size_t item_count) {
    APtr free_beg = ptr;
    APtr free_end = ptr + item_count * m_item_stride_in_ablks;

    GflIterator pred = m_free_span_list.before_begin();
    GflIterator self = m_free_span_list.begin();

    APtr self_beg = nullptr;
    APtr self_end = nullptr;

    while (self != m_free_span_list.end()) {
        self_beg = self->ptr;
        self_end = self->ptr + item_count * m_item_stride_in_ablks;
        
        if (self_end == free_beg) {
            // extend 'self', possibly coalesce with 'next'

            // note we don't need to check for backward coalescence of
            // free-list spans if past forward coalescence fails.
            
            // acquiring 'next'
            GflIterator self_backup = self;
            GflIterator next = ++self;
            self = self_backup;
            
            // trying to coalesce first:
            bool can_coalesce = (
                next != m_free_span_list.end() &&
                // free_beg == self_end &&
                free_end == next->ptr
            );
            if (can_coalesce) {
                self->count += item_count + next->count;
                m_free_span_list.erase_after(self);
                return {pred, self};
            }

            // otherwise, just extending 'self' in +ve direction
            self->count += item_count;
            return {pred, self};
        }
        else if (free_end == self->ptr) {
            // extend 'self' backward

            // note we can never coalesce backward if past
            // forward coalescence has failed for 'pred'.

            // can still extend backward
            self->ptr -= item_count;
            self->count += item_count;
            return {pred, self};
        }
        else if (free_beg < self_beg) {
            // insert just before 'self', i.e. just after 'pred'
            assert(free_end < self_beg);
            m_free_span_list.insert_after(pred, {free_beg, item_count});
            return {pred, self};
        }
        else {
            // continue to scan...
            pred = self;
            self++;
        }
    }

    // iff we reach the end of this free-list and could not satisfy this
    // deallocation, even by extending the last free-list node, we append
    // a new node, exploiting the fact that 'pred' points at the 'back()'
    // node (since 'self' points at end())
    GflIterator back = pred;
    m_free_span_list.insert_after(back, {free_beg, item_count});
    return {pred, self};
}

///
// ObjectAllocator, CentralObjectAllocator:
//

void BaseObjectAllocator::init(SizeClassIndex sci) {
    m_sci = sci;
    m_object_free_list.init(sci);
}

void CentralObjectAllocator::init(SizeClassIndex sci) {
    BaseObjectAllocator::init(sci);
    m_page_spans.reserve(1024);
    m_page_span_refcounts.reserve(1024);
}
std::optional<ObjectSpan> CentralObjectAllocator::try_allocate_object_span() { 
    size_t const count = kSizeClasses[m_sci].num_to_move;
    APtr ptr = m_object_free_list.try_allocate_items(count);
    if (ptr) {
        retain_page_spans(ptr, ptr + ((count*kSizeClasses[m_sci].size) >> CONFIG_TCMALLOC_PAGE_SHIFT));
        return {{ptr, count}}; 
    } else {
        return {};
    }
}
std::pair<GenericFreeList::Iterator, GenericFreeList::Iterator> CentralObjectAllocator::return_object_span(ObjectSpan span) {
    release_page_spans(span.ptr, span.ptr + span.count*kSizeClasses[m_sci].size/sizeof(ABlk));
    return m_object_free_list.return_items_impl(span.ptr, span.count);
}
void CentralObjectAllocator::add_page_span_to_pool(PageSpan span) {
#if !GC_SINGLE_THREADED_MODE
    std::lock_guard lg{m_mutex};
#endif    

    // NOTE: the number of pages in each page-span is determined kSizeClasses
    assert(span.count == kSizeClasses[m_sci].pages);
    
    // adding this span into a vector, adding refcount 0 into a vector
    // Using a BFS to find the offset of the first element with ptr > this one
    // i.e. leftmost element (cf Wikipedia Binary Search)
    // Even if T is not in the array, L is the rank of T in the array
    size_t insert_index; {
#define USE_NAIVE_INSERT_INDEX_LOOKUP (0)
#if USE_NAIVE_INSERT_INDEX_LOOKUP
        for (insert_index = 0; insert_index < m_page_spans.size(); insert_index++) {
            if (m_page_spans[insert_index].ptr > span.ptr) {
                break;
            }
        }
#else
        size_t l = 0;
        size_t r = m_page_spans.size();
        while (l < r) {
            size_t m = l / 2 + r / 2;
            if (m_page_spans[m].ptr < span.ptr) {
                l = m + 1;
            }
            else {
                r = m;
            }
        }
        insert_index = l;
#endif
    }

    // insert just before this element
    m_page_spans.insert(m_page_spans.begin() + insert_index, span);
    m_page_span_refcounts.insert(m_page_span_refcounts.begin() + insert_index, 0);

    // adding objects to the free-list:
    size_t span_page_count = span.count;
    size_t span_pages_size_in_bytes = span_page_count * PAGE_SIZE_IN_BYTES;
    size_t num_objects = span_pages_size_in_bytes / kSizeClasses[m_sci].size;
    // assert(span_pages_size_in_bytes % kSizeClasses[m_sci].size == 0);
    m_object_free_list.return_items(span.ptr, num_objects);
}
void CentralObjectAllocator::retain_page_spans(APtr beg, APtr end) {
    help_map_intersecting_page_spans(
        [this] (size_t page_span_index) {
            ++this->m_page_span_refcounts[page_span_index];
        },
        beg, end
    );
}
void CentralObjectAllocator::release_page_spans(APtr beg, APtr end) {
    help_map_intersecting_page_spans(
        [this] (size_t page_span_index) {
            --this->m_page_span_refcounts[page_span_index];
        },
        beg, end
    );
}
void CentralObjectAllocator::help_map_intersecting_page_spans(std::function<void(size_t)> cb, APtr beg, APtr end) {
    // Using a binary search to locate the first page-span before 'beg'
    // According to Wikipedia, using procedure to find the right-most element: this performs 'rounding down'
    // https://en.wikipedia.org/wiki/Binary_search_algorithm#Procedure_for_finding_the_rightmost_element
    // NOTE: 'r' should be 'n' with 'l' '0' where 'n' is array length
    
    
    size_t l_page_span = 0;
    size_t r_page_span = m_page_spans.size();
    while (l_page_span < r_page_span) {
        size_t i_page_span = l_page_span/2 + r_page_span/2;
        if (m_page_spans[i_page_span].ptr > beg) {
            r_page_span = i_page_span;
        } else {
            l_page_span = i_page_span + 1;
        }
    }
    size_t i_page_span = r_page_span - 1;

    // scanning through pages to determine intersection
    while (i_page_span < m_page_spans.size()) {
        PageSpan span = m_page_spans[i_page_span];
        APtr span_beg = span.ptr;
        APtr span_end = span_beg + span.count * PAGE_SIZE_IN_ABLKS;
        bool intersect = (
            (beg <= span_beg && span_beg <= end) ||
            (span_beg <= beg && beg <= span_end) ||
            (span_beg <= beg && end <= span_end) ||
            (beg <= span_beg && span_end <= end)
        );
        if (intersect) {
            cb(i_page_span);
        }
        if (span_beg >= end) {
            break;
        } else {
            i_page_span++;
        }
    }
}
void CentralObjectAllocator::trim_unused_pages(GcMiddleEnd* middle_end) {
#if !GC_SINGLE_THREADED_MODE
    std::lock_guard lg{m_mutex};
#endif
    assert(m_page_span_refcounts.size() == m_page_spans.size());
    
    size_t page_span_index = 0;
    while (page_span_index < m_page_spans.size()) {
        PageSpan page_span = m_page_spans[page_span_index];
        if (m_page_span_refcounts[page_span_index] == 0) {
            // erasing all parallel vectors:
            m_page_spans.erase(m_page_spans.begin() + page_span_index);
            m_page_span_refcounts.erase(m_page_span_refcounts.begin() + page_span_index);
            // extract this space from the object free-list, return to back-end:
            extract_page_span_from_object_free_list(page_span, middle_end->back_end());
        } else {
            ++page_span_index;
        }
    }
}
void CentralObjectAllocator::extract_page_span_from_object_free_list(
    PageSpan extract_page_span, 
    GcBackEnd* back_end
) {
    assert(kSizeClasses[m_sci].pages == extract_page_span.count);

    GflIterator pred = m_object_free_list.before_begin();
    GflIterator self = m_object_free_list.begin();

    APtr extract_beg = extract_page_span.ptr;
    APtr extract_end = extract_page_span.ptr + extract_page_span.count * PAGE_SIZE_IN_ABLKS;

    while (self != m_object_free_list.end()) {
        APtr span_beg = self->ptr;
        APtr span_end = span_beg + self->count * m_object_free_list.object_size_in_ablks();

        if (span_beg <= extract_beg) {
            // expect the first node we find to be suitable
            assert(extract_end <= span_end);

            // calculating leftover space before and after:
            size_t bytes_before = reinterpret_cast<size_t>(extract_beg) - reinterpret_cast<size_t>(span_beg);
            size_t bytes_after = reinterpret_cast<size_t>(span_end) - reinterpret_cast<size_t>(extract_end);
            size_t object_size = kSizeClasses[m_sci].size;
            size_t objects_before = bytes_before / object_size;
            size_t objects_after = bytes_after / object_size;

            // must extract 'span' from this free-list node
            if (objects_before == 0 && objects_after == 0) {
                // delete this node
                m_object_free_list.erase_after(pred);
            }
            else if (objects_after == 0) {
                // shrink, keep 'ptr'
                self->count = objects_before;
            }
            else if (objects_before == 0) {
                // shrink
                self->ptr = extract_end;
                self->count = objects_after;
            }
            else {
                // split in two
                self->ptr = extract_beg;
                self->count = objects_before;
                m_object_free_list.insert_after(self, {extract_end, objects_after});
            }

            // returning extracted page-span directly to back-end:
            back_end->return_page_span(extract_page_span);
        }

        // next iteration
        pred = self;
        self++;
    }    
}

///
// PageMap
//

#if 0
void PageMap::init(GcBackEnd* back_end) {
    m_beg_aptr_address = reinterpret_cast<size_t>(back_end->total_pages_beg_address());
    m_end_aptr_address = reinterpret_cast<size_t>(back_end->total_pages_end_address());
    m_page_table.resize(back_end->total_page_count());
}
#endif

///
// Back-end:
//

void GcBackEnd::init(size_t single_contiguous_region_page_capacity, APtr single_contiguous_memory_region) {
    m_single_contiguous_region_beg = single_contiguous_memory_region;
    m_single_contiguous_region_end = reinterpret_cast<APtr>(
        reinterpret_cast<uint8_t*>(m_single_contiguous_region_beg) + 
        single_contiguous_region_page_capacity * PAGE_SIZE_IN_BYTES
    );
    m_single_contiguous_region_page_capacity = single_contiguous_region_page_capacity;
    
    // initializing the page free list:
    m_page_free_list.init();
    return_page_span({m_single_contiguous_region_beg, m_single_contiguous_region_page_capacity});
}
std::optional<PageSpan> GcBackEnd::try_allocate_page_span(size_t page_count) {
#if !GC_SINGLE_THREADED_MODE
    std::lock_guard lg{m_mutex};
#endif
    auto res_ptr = m_page_free_list.try_allocate_items(page_count);
    if (res_ptr) {
        return {PageSpan{res_ptr, page_count}};
    } else {
        return {};
    }
}
void GcBackEnd::return_page_span(PageSpan page_span) {
#if !GC_SINGLE_THREADED_MODE
    std::lock_guard lg{m_mutex};
#endif
    m_page_free_list.return_items(page_span.ptr, page_span.count);
}

///
// Middle-end:
//

void GcMiddleEnd::init(GcBackEnd* backend) {
    m_back_end = backend;
    for (SizeClassIndex sci = 1; sci < kSizeClassesCount; sci++) {
        m_central_object_allocators[sci].init(sci);
    }
}
std::optional<ObjectSpan> GcMiddleEnd::try_allocate_object_span(SizeClassIndex sci) {
#if !GC_SINGLE_THREADED_MODE
    std::lock_guard lg{m_central_object_allocators[sci].mutex()};
#endif

    // trying to satisfy allocation using existing page-span:
    auto opt_object_span = m_central_object_allocators[sci].try_allocate_object_span();
    if (opt_object_span.has_value()) {
        return opt_object_span;
    }

    // TODO: check all larger allocators for spare objects/page-spans (?)

    // must fetch more page-spans from the page-heap:
    auto opt_page_span = m_back_end->try_allocate_page_span(kSizeClasses[sci].pages);
    if (opt_page_span.has_value()) {
        m_central_object_allocators[sci].add_page_span_to_pool(opt_page_span.value());

        // now, allocation must succeed.
        auto opt_object_span = m_central_object_allocators[sci].try_allocate_object_span();
        assert(opt_object_span.has_value());
        return opt_object_span;
    }

    // allocation from page-heap failed => allocation failed.
    return {};
}
void GcMiddleEnd::return_object_span(SizeClassIndex sci, ObjectSpan span) {
    m_central_object_allocators[sci].return_object_span(span);
}
void GcMiddleEnd::trim_unused_pages() {
    for (SizeClassIndex sci = 1; sci < kSizeClassesCount; sci++) {
        m_central_object_allocators[sci].trim_unused_pages(this);
    }
}

///
// Front-end:
//

void GcFrontEnd::init(GcMiddleEnd* middle_end) {
    m_middle_end = middle_end;
    for (SizeClassIndex sci = 1; sci < kSizeClassesCount; sci++) {
        m_sub_allocators[sci].init(sci);
    }
}

APtr GcFrontEnd::allocate(SizeClassIndex sci) {
    if (sci == 0) {
        error("NotImplemented: support for huge allocations");
        throw SsiError();
    }
    APtr res = m_sub_allocators[sci].try_allocate_object();
    if (res) {
        // allocation from cache successful
        return res;
    } else {
        // cache depleted: try to acquire a new object-span from the global middle-end
        auto opt_object_span = m_middle_end->try_allocate_object_span(sci);
        if (opt_object_span.has_value()) {
            // adding the object-span to the free-list:
            ObjectSpan objects = opt_object_span.value();
            m_sub_allocators[sci].return_object_span({objects.ptr, objects.count});

            // now, allocation for one object must succeeed:
            APtr res = m_sub_allocators[sci].try_allocate_object();
            assert(res && "Expected allocation to succeed after adding objects from transfer-cache");
            
            // DEBUG:
            #if 0
            {
                std::cerr << "INFO: GC.F: allocated " << res << " for sci=" << (int)sci << " with size=" << kSizeClasses[sci].size << std::endl;
            }
            #endif

            return res;
        } else {
            std::stringstream ss;
            ss  << "GC: allocation failed: could not allocate " << kSizeClasses[sci].size << " bytes " << std::endl
                << "    for object with SizeClassIndex " << static_cast<int>(sci) << std::endl;
            error(ss.str());
            throw SsiError();
        }
    }
}
void GcFrontEnd::deallocate(APtr memory, SizeClassIndex sci) {
    // returning the object to the free list:
    auto fl_it_pair = m_sub_allocators[sci].return_object_span({memory, 1});
    
    // checking the modified free-list node to try to return objects to the transfer-cache:
    GflIterator fl_node_pred = fl_it_pair.first;
    GflIterator fl_node = fl_it_pair.second;
    try_return_free_list_node_to_middle_end(sci, fl_node_pred, fl_node);
}
void GcFrontEnd::sweep(MarkedSet& marked_set) {
    // clearing each free-list: we re-insert each live allocation later...
    for (SizeClassIndex sci = 1; sci < kSizeClassesCount; sci++) {
        m_sub_allocators[sci].clear();
    }

    // inserting each still-live allocation:
    while (!marked_set.empty()) {
        MarkedPtr mark = marked_set.pop_max();
        m_sub_allocators[mark.sci].return_object(mark.ptr);
    }
    
    // scan each node in each object free-list, evict free objects to middle-end
    for (SizeClassIndex sci = 1; sci < kSizeClassesCount; sci++) {
        ObjectFreeList& fl = m_sub_allocators[sci].object_free_list();
        ObjectFreeList::Iterator pred = fl.before_begin();
        ObjectFreeList::Iterator node = fl.begin();
        while (node != fl.end()) {
            // try returning objects to the middle-end:
            // - does not lock if insufficient memory.
            // - performs as many returns as possible at once.
            try_return_free_list_node_to_middle_end(sci, pred, node);

            // preparing for the next iteration or termination:
            pred = node;
            ++node;
        }
    }

    // ask middle-end to trim unused pages, returning them to back-end
    // for subsequent allocations
    m_middle_end->trim_unused_pages();
}
void GcFrontEnd::try_return_free_list_node_to_middle_end(
    SizeClassIndex sci,
    ObjectFreeList::Iterator fl_node_pred,
    ObjectFreeList::Iterator fl_node
) {
    size_t const num_to_move = kSizeClasses[sci].num_to_move;
    if (fl_node->count >= num_to_move) {
        size_t const object_size = kSizeClasses[sci].size;
    
        // returning these free objects to the transfer cache, resizing or deleting this free-list node:
        size_t const rem_objects = fl_node->count % num_to_move;
        size_t const returned_objects_count = (fl_node->count / num_to_move) * num_to_move;
        size_t const returned_objects_size_in_bytes = returned_objects_count * object_size;
        size_t const returned_objects_size_in_ablks = returned_objects_size_in_bytes / sizeof(ABlk);
        APtr const returned_objects_ptr = fl_node->ptr;
        if (rem_objects) {
            // resize the free-list node
            fl_node->count = rem_objects;
            fl_node->ptr += returned_objects_size_in_ablks;
        } else {
            // free-list node capacity becomes 0: delete it
            m_sub_allocators[sci].object_free_list().erase_after(fl_node_pred);
        }

        // locking middle-end CentralObjectAllocator for this size-class to return object span:
        m_middle_end->return_object_span(sci, {returned_objects_ptr, returned_objects_count});
    }
}

}   // namespace gc