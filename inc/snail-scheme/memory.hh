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

class StackAllocator {
private:
    uint8_t* m_mem;
    size_t m_capacity_bytes;
    size_t m_occupied_bytes;
    RootAllocCb m_root_alloc;
    RootDeallocCb m_root_dealloc;
    
public:
    StackAllocator(size_t capacity=MEGABYTES(64), RootAllocCb alloc=malloc, RootDeallocCb dealloc=free);
    ~StackAllocator();

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
};
