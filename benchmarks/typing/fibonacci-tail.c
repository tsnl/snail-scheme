#include <stdint.h>

/* All three arguments carry algorithm state. Returning b at n=1 avoids an
   unused, overflowing F(47) intermediate when computing the valid F(46). */
int32_t fibonacci(int32_t n, int32_t a, int32_t b) {
    if (n < 2) return n <= 0 ? a : b;
    return fibonacci(n - 1, b, a + b);
}
