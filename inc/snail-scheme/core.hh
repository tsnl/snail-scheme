#pragma once

#include <cstdint>
#include "ss-config/config.hh"

#if (CONFIG_SIZEOF_VOID_P==8)
    using my_ssize_t = int64_t;
    using my_float_t = double;
#elif (CONFIG_SIZEOF_VOID_P==4)
    using my_ssize_t = int32_t;
    using my_float_t = float;
#else
    #error "Unknown CONFIG_SIZEOF_VOID_P value"
#endif
