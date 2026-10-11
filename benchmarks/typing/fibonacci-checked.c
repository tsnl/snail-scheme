#include <stdint.h>
#ifndef __wasm__
#include <stdlib.h>
#endif

/* Same checked i32 return policy as Snail's specialized worker. */
int32_t fibonacci(int32_t n, int32_t offset) {
    int64_t result;
    if (n < 2) result = (int64_t)n + offset;
    else result = (int64_t)fibonacci(n - 1, offset) + fibonacci(n - 2, offset);
    if (result < INT32_MIN || result > INT32_MAX) {
#ifdef __wasm__
        __builtin_trap();
#else
        abort();
#endif
    }
    return (int32_t)result;
}
