#include "snail-scheme/gc.hh"

#include "config/config.hh"
#include "allocator.hh"

///
// Interface:
//

Gc::Gc(APointer single_contiguous_region, size_t single_contiguous_region_size)
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

///
// Implementation:
//

namespace gc {

///
// Free-list:
//

using GflIterator = GenericFreeList::Iterator;

APointer GenericFreeList::try_allocate_items(size_t item_count) {
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

std::pair<GflIterator,GflIterator> GenericFreeList::return_items_impl(APointer ptr, size_t item_count) {
    APointer free_beg = ptr;
    APointer free_end = ptr + item_count * m_item_stride_in_ablks;

    GflIterator pred = m_free_span_list.before_begin();
    GflIterator self = m_free_span_list.begin();

    APointer self_beg = nullptr;
    APointer self_end = nullptr;

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

void GenericFreeList::clear() {
    m_free_span_list.clear();
};

///
// Middle-end:
//

void GlobalObjectAllocator::return_items(APointer ptr, size_t item_count) {
    // invoking super 'impl' 
    auto obj_fl_node_pair = m_object_free_list.return_items_impl(ptr, item_count);
    GflIterator obj_fl_node_pred = obj_fl_node_pair.first;
    GflIterator obj_fl_node_self = obj_fl_node_pair.second;

    // TODO: check if this object free-list node contains a large enough contiguous
    //       span to extract one or more page-spans for return to the page-free-list.
}

///
// Back-end:
//

void GcBackEnd::init(size_t single_contiguous_memory_region_page_capacity, APointer single_contiguous_memory_region) {
    m_single_contiguous_region = single_contiguous_memory_region;
    m_single_contiguous_region_page_capacity = single_contiguous_memory_region_page_capacity;
}

std::optional<PageSpan> GcBackEnd::try_allocate_page_span(size_t page_count) {
    auto res_ptr = m_page_free_list.try_allocate_items(page_count);
    if (res_ptr) {
        return {PageSpan{res_ptr, page_count}};
    } else {
        return {};
    }
}

void GcBackEnd::return_page_span(PageSpan page_span) {
    m_page_free_list.return_memory(page_span.ptr, page_span.count);
}

///
// Middle-end:
//

}   // namespace gc