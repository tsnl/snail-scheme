#pragma once

#include <stdexcept>
#include <memory>
#include <cstdint>
#include <cassert>
#include <cstdlib>

#include "allocator.hh"

///
// StackAllocator: root of Reactor allocators
//

class StackAllocator {
protected:
    APtr m_mem;
    size_t m_capacity_bytes;
    size_t m_occupied_bytes;
    
public:
    StackAllocator(APtr mem, size_t capacity_in_bytes);
    
public:
    size_t capacity_byte_count() const { 
        return m_capacity_bytes; 
    }
    size_t occupied_byte_count() const {
        return m_occupied_bytes;
    }
    size_t remaining_byte_count() const {
        auto capacity = capacity_byte_count();
        auto occupied = occupied_byte_count();
        assert(occupied < capacity);
        return capacity - occupied;
    }
    APtr allocate_bytes(size_t byte_count) { 
        // Rounding allocation up to the next aligned address:
        byte_count = (
            (byte_count % sizeof(APtr)) == 0 ?
            byte_count :
            ((byte_count / sizeof(APtr)) + 1) * sizeof(APtr)
        );

        // Allocating: if we only perform aligned allocations, then all
        // returned pointers are aligned by default.
        if (byte_count <= remaining_byte_count()) {
            auto offset = m_occupied_bytes;
            auto res = m_mem + offset;
            m_occupied_bytes += byte_count;
            return res;
        } else {
            throw std::runtime_error("Stack overflow");
        }
    }

public:
    void reset() {
        m_occupied_bytes = 0;
    }
    APtr reset_then_extract_all_bytes() {
        m_occupied_bytes = m_capacity_bytes;
        return m_mem;
    }
};

class RootStackAllocator: public StackAllocator {
private:
    RootDeallocCb m_root_dealloc;

public:
    RootStackAllocator(
        size_t capacity=MIBIBYTES(64), 
        RootAllocCb alloc=malloc, 
        RootDeallocCb dealloc=free
    );
    ~RootStackAllocator();
};
