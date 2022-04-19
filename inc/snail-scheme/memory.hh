#pragma once

#include <stdexcept>
#include <memory>
#include <cstdint>
#include <cassert>
#include <cstdlib>

constexpr inline size_t KILOBYTES(size_t num) { return num << 10; }
constexpr inline size_t MEGABYTES(size_t num) { return KILOBYTES(num) << 10; }
constexpr inline size_t GIGABYTES(size_t num) { return MEGABYTES(num) << 10; }
constexpr inline size_t TERABYTES(size_t num) { return GIGABYTES(num) << 10; }

using RootAllocCb = void*(*)(size_t size_in_bytes);
using RootDeallocCb = void(*)(void* ptr);

///
// StackAllocator: root of Reactor allocators
//

class StackAllocator {
protected:
    uint8_t* m_mem;
    size_t m_capacity_bytes;
    size_t m_occupied_bytes;
    
public:
    StackAllocator(uint8_t* mem, size_t capacity);
    
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
    uint8_t* allocate_bytes(size_t byte_count) { 
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
    uint8_t* reset_then_extract_all_bytes() {
        m_occupied_bytes = m_capacity_bytes;
        return m_mem;
    }
};

class RootStackAllocator: public StackAllocator {
private:
    RootDeallocCb m_root_dealloc;

public:
    RootStackAllocator(
        size_t capacity=MEGABYTES(64), 
        RootAllocCb alloc=malloc, 
        RootDeallocCb dealloc=free
    );
    ~RootStackAllocator();
};
