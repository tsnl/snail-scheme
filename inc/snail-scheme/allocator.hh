#pragma once

#include <functional>

// APointer = Aligned Pointer
// ABlk = Aligned Block <=> sizeof(Aligned Block) == default alignment
struct Blk { size_t _0; size_t _1; };
static_assert(__STDCPP_DEFAULT_NEW_ALIGNMENT__ == sizeof(Blk));
typedef Blk* APointer;

constexpr inline size_t KILOBYTES(size_t num) { return num << 10; }
constexpr inline size_t MEGABYTES(size_t num) { return KILOBYTES(num) << 10; }
constexpr inline size_t GIGABYTES(size_t num) { return MEGABYTES(num) << 10; }
constexpr inline size_t TERABYTES(size_t num) { return GIGABYTES(num) << 10; }

using RootAllocCb = std::function<void*(size_t size_in_bytes)>;
using RootDeallocCb = std::function<void(void* ptr)>;