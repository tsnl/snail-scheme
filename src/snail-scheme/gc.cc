#include "snail-scheme/gc.hh"

#include <sstream>
#include "config/config.hh"
#include "snail-scheme/allocator.hh"
#include "snail-scheme/feedback.hh"

///
// Interface:
//

Gc::Gc(APtr single_contiguous_region, size_t single_contiguous_region_size)
:   m_gc_back_end(),
    m_gc_middle_end()
{
    m_gc_back_end.init(
        single_contiguous_region_size >> CONFIG_TCMALLOC_PAGE_SHIFT,
        single_contiguous_region
    );
    m_gc_middle_end.init(&m_gc_back_end);
}

GcThreadFrontEnd::GcThreadFrontEnd(Gc* gc)
:   m_impl(&gc->middle_end_impl())
{}

void Gc::global_collect() {
    // NOTE: assume the mutator has been paused before 'collect' was invoked, will not start until after return.
}


///
// Implementation:
//

namespace gc {

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
    // a new node, exploiting the fact that 'self' points at the 'back()'
    // node.
    GflIterator back = self;
    m_free_span_list.insert_after(back, {free_beg, item_count});
    return {pred, self};
}


///
// ObjectAllocator:
//

std::optional<ObjectSpan> CentralObjectAllocator::try_allocate_object_span() { 
    size_t const count = kSizeClasses[m_sci].num_to_move;
    APtr ptr = m_object_free_list.try_allocate_items(count);
    if (ptr) {
        retain_page_span(ptr);
        return {{ptr, count}}; 
    } else {
        return {};
    }
}
std::pair<GenericFreeList::Iterator, GenericFreeList::Iterator> CentralObjectAllocator::return_object_span(ObjectSpan span) {
    release_page_span(span.ptr);
    return m_object_free_list.return_items_impl(span.ptr, span.count);
}
void CentralObjectAllocator::add_page_span_to_pool(PageSpan span) {
    std::lock_guard lg{m_mutex};
    
    // NOTE: the number of pages in each page-span is determined kSizeClasses
    assert(span.count == kSizeClasses[m_sci].pages);
    
    // adding this span into a vector, adding refcount 0 into a vector
    size_t insert_index;
    for (insert_index = 0; insert_index < m_page_spans.size(); insert_index++) {
        if (m_page_spans[insert_index].ptr > span.ptr) {
            break;
        }
    }
    m_page_spans.insert(m_page_spans.begin() + insert_index, span);
    m_page_span_refcounts.insert(m_page_span_refcounts.begin() + insert_index, 0);
}
size_t CentralObjectAllocator::page_span_index(APtr ptr) {
    size_t index;
    for (index = 0; index < m_page_spans.size(); index++) {
        PageSpan span = m_page_spans[index];
        APtr span_beg = span.ptr;
        APtr span_end = span.ptr + span.count*PAGE_SIZE_IN_ABLKS;
        if (span_beg <= ptr && ptr <= span_end) {
            return index;
        }
    }
    // ERROR
    std::stringstream ss;
    ss  << "Could not locate PageSpan containing pointer: " << ptr << std::endl;
    error(ss.str());
    throw SsiError();
}
void CentralObjectAllocator::retain_page_span(APtr ptr) {
    ++m_page_span_refcounts[page_span_index(ptr)];
}
void CentralObjectAllocator::release_page_span(APtr ptr) {
    --m_page_span_refcounts[page_span_index(ptr)];
}
void CentralObjectAllocator::trim_unused_pages(GcMiddleEnd* middle_end) {
    std::lock_guard lg{m_mutex};
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
    return_page_span({m_single_contiguous_region_beg, m_single_contiguous_region_page_capacity});
}

std::optional<PageSpan> GcBackEnd::try_allocate_page_span(size_t page_count) {
    std::lock_guard lg{m_mutex};
    auto res_ptr = m_page_free_list.try_allocate_items(page_count);
    if (res_ptr) {
        // TODO: update page-map, indicating these pages now belong to the middle-end
        return {PageSpan{res_ptr, page_count}};
    } else {
        return {};
    }
}

void GcBackEnd::return_page_span(PageSpan page_span) {
    std::lock_guard lg{m_mutex};
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
std::optional<ObjectSpan> GcMiddleEnd::allocate_object_span(SizeClassIndex sci) {
    std::lock_guard lg{m_central_object_allocators[sci].mutex()};

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

///
// Front-end:
//

APtr GcFrontEnd::allocate(SizeClassIndex sci) {
    APtr res = m_sub_allocators[sci].try_allocate_object();
    if (res) {
        // allocation from cache successful
        return res;
    } else {
        // cache depleted: try to acquire a new object-span from the global middle-end
        auto opt_object_span = m_middle_end->allocate_object_span(sci);
        if (opt_object_span.has_value()) {
            // adding the object-span to the free-list:
            ObjectSpan objects = opt_object_span.value();
            m_sub_allocators[sci].return_object_span({objects.ptr, objects.count});

            // now, allocation for one object must succeeed:
            APtr res = m_sub_allocators[sci].try_allocate_object();
            assert(res && "Expected allocation to succeed after adding objects from transfer-cache");
            return res;
        } else {
            std::stringstream ss;
            ss  << "GC: allocation failed: could not allocate " << kSizeClasses[sci].size << " bytes "
                << "    for object with SizeClassIndex " << sci << std::endl;
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
    // clearing each free-list: we re-insert each live allocation
    for (SizeClassIndex sci = 1; sci < kSizeClassesCount; sci++) {
        m_sub_allocators[sci].clear();
    }

    // inserting each still-live allocation:
    while (!marked_set.empty()) {
        MarkedPtr mark = marked_set.pop_max();
        m_sub_allocators[mark.sci].return_object(mark.ptr);
    }
    
    // scan each node in object free-list, evict objects to middle-end
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
        m_middle_end->return_object_span(sci, {returned_objects_ptr, returned_objects_count});
    }
}

}   // namespace gc