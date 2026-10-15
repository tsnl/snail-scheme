#include "probe.h"
#include <inttypes.h>
#include <stdio.h>

// ---- Effects escape the guest before a terminal initialization failure ----

void record(int64_t value) {
    printf("effect:%" PRId64 "\n", value);
}
