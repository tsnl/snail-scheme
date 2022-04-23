#pragma once

#include <functional>

namespace ss {

    // APointer = Aligned Pointer
    // ABlk = Aligned Block <=> sizeof(Aligned Block) == default alignment
    struct ABlk { size_t _0; size_t _1; };
    static_assert(__STDCPP_DEFAULT_NEW_ALIGNMENT__ == sizeof(ABlk));
    typedef ABlk* APtr;

    constexpr inline size_t KIBIBYTES(size_t num) { return num << 10; }
    constexpr inline size_t MIBIBYTES(size_t num) { return KIBIBYTES(num) << 10; }
    constexpr inline size_t GIBIBYTES(size_t num) { return MIBIBYTES(num) << 10; }
    constexpr inline size_t TIBIBYTES(size_t num) { return GIBIBYTES(num) << 10; }

    using RootAllocCb = std::function<void*(size_t size_in_bytes)>;
    using RootDeallocCb = std::function<void(void* ptr)>;

}   // namespace ss