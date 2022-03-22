#include "snail-scheme/memory.hh"

StackAllocator::StackAllocator(size_t capacity, RootAllocCb alloc, RootDeallocCb dealloc) 
:   m_mem(alloc(capacity)),
    m_capacity(capacity),
    m_root_alloc(alloc),
    m_root_dealloc(dealloc)
{}

StackAllocator::~StackAllocator() {
    m_root_dealloc(m_mem);
}
