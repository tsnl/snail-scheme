// Decoded from the retained original input before timing.
// Kind, row count, then each row length and its eleven Boolean marks.
#include <stdint.h>

static const int64_t expected_grid[] = {
    2, 11,
    11, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    11, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0,
    11, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1,
    11, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1,
    11, 1, 0, 1, 1, 1, 0, 1, 0, 1, 0, 1,
    11, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1,
    11, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1,
    11, 1, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0,
    11, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1,
    11, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0,
    11, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1,
};
