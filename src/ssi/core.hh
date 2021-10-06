#pragma once

#include <cstdint>
#include "config/config.hh"

#if (CONFIG_SIZEOF_VOID_P==8)
    using my_ssize_t = int64_t;
#elif (CONFIG_SIZEOF_VOID_P==4)
    using my_ssize_t = int32_t;
#else
    #error "Unknown CONFIG_SIZEOF_VOID_P value"
#endif
