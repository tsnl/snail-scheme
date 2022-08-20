#pragma once

#include <cstdint>
#include "ss-core/config.hh"
#include "robin_hood.h"

namespace ss {

    template <typename T>
    using UnstableHashSet = robin_hood::unordered_flat_set<T>;
    template <typename T>
    using StableHashSet = robin_hood::unordered_set<T>;

    template <typename K, typename V>
    using UnstableHashMap = robin_hood::unordered_flat_map<K, V>;
    template <typename K, typename V>
    using StableHashMap = robin_hood::unordered_map<K, V>;

    #if (CONFIG_SIZEOF_VOID_P==8)
        using ssize_t = int64_t;
        using float_t = double;
    // #elif (CONFIG_SIZEOF_VOID_P==4)
    //     using ssize_t = int32_t;
    //     using float_t = float;
    #else
        #error "Unknown CONFIG_SIZEOF_VOID_P value: expected 64-bit only"
    #endif

    template <typename T>
    inline void SUPPRESS_UNUSED_VARIABLE_WARNING(T x) {
        // see: https://stackoverflow.com/questions/1486904/how-do-i-best-silence-a-warning-about-unused-variables
        (void)x;
    }

}   // namespace ss
