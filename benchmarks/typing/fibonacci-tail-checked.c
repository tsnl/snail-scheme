#include <stdint.h>
#ifndef __wasm__
#include <stdlib.h>
#endif

/* Snail checks each tail-call argument before transferring control. */
int32_t fibonacci(int32_t n, int32_t a, int32_t b) {
    if (n < 2) return n <= 0 ? a : b;
    int64_t next = (int64_t)a + b;
    if (next < INT32_MIN || next > INT32_MAX) {
#ifdef __wasm__
        __builtin_trap();
#else
        abort();
#endif
    }
    return fibonacci(n - 1, b, (int32_t)next);
}
