#include <stdint.h>
extern uint64_t native_alloc(uint64_t bytes);
struct array3 { uint64_t type, length, values[3]; };
struct array3 *construct(uint64_t a, uint64_t b, uint64_t c) {
    struct array3 *result = (void *)(uintptr_t)native_alloc(sizeof(struct array3));
    *result = (struct array3){7, 3, {a, b, c}};
    return result;
}
uint64_t roundtrip(uint64_t a, uint64_t b, uint64_t c) {
    return construct(a, b, c)->values[1];
}
uint64_t local_roundtrip(uint64_t a, uint64_t b, uint64_t c) {
    struct array3 result = {7, 3, {a, b, c}};
    return result.values[1];
}
