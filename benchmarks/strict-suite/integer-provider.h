#include <stdint.h>
int64_t input_i64(int32_t index);
int64_t expected_count(void);
int64_t expected_length(int64_t index);
uint32_t expected_character(int64_t index, int64_t at);
int64_t hide_i64(int64_t value);
void emit_character(uint32_t scalar);
