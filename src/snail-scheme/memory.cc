#include "snail-scheme/memory.hh"

StackAllocator::StackAllocator(uint8_t* mem, size_t capacity)
:   m_mem(mem),
    m_capacity_bytes(capacity)
{}

RootStackAllocator::RootStackAllocator(size_t capacity, RootAllocCb alloc, RootDeallocCb dealloc) 
:   StackAllocator(static_cast<uint8_t*>(alloc(capacity)), capacity),
    m_root_dealloc(dealloc)
{}

RootStackAllocator::~RootStackAllocator() {
    m_root_dealloc(m_mem);
}
