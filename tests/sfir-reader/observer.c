#include <inttypes.h>
#include <stdio.h>
#include <string.h>
#include "observer.h"

// ---- Scalar observations preserve integer precision and binary64 bits ----

void emit_i64(int64_t value) { printf("i:%" PRId64 "\n", value); }
void emit_char(uint32_t value) { printf("c:%" PRIu32 "\n", value); }
void emit_f64(double value) {
    uint64_t bits;
    memcpy(&bits, &value, sizeof bits);
    if ((bits & UINT64_C(0x7fffffffffffffff)) > UINT64_C(0x7ff0000000000000))
        puts("f:nan");
    else printf("f:%" PRIu64 "\n", bits);
}
