#include <stdint.h>

/* Same two-argument recursion as the generated Scheme fixture. Offset stays
   a runtime argument. The tested inputs never overflow signed 32-bit integers. */
int32_t fibonacci(int32_t n, int32_t offset) {
    if (n < 2) return n + offset;
    return fibonacci(n - 1, offset) + fibonacci(n - 2, offset);
}
