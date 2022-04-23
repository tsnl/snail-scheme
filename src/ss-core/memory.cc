#include "ss-core/memory.hh"

namespace ss {

    StackAllocator::StackAllocator(APtr mem, size_t capacity)
    :   m_mem(mem),
        m_capacity_bytes(capacity)
    {}

    RootStackAllocator::RootStackAllocator(size_t capacity, RootAllocCb alloc, RootDeallocCb dealloc) 
    :   StackAllocator(static_cast<APtr>(alloc(capacity)), capacity),
        m_root_dealloc(dealloc)
    {}

    RootStackAllocator::~RootStackAllocator() {
        m_root_dealloc(m_mem);
    }

}   // namespace ss
