#include <stdint.h>
#include "case-config.h"

int64_t input_i64(int32_t index);
double input_f64(int32_t index);
int64_t vector_length(int32_t index);
int64_t vector_i64(int32_t index, int64_t element);
double vector_f64(int32_t index, int64_t element);
int64_t expected_length(void);
int64_t expected_i64(int64_t index);
double expected_f64(int64_t index);
double tolerance(void);
int64_t count(void);
int64_t hide_i64(int64_t value);
double hide_f64(double value);
int32_t barrier(void);
void write_character(uint32_t value);
void write_char(uint32_t value);
void print_text(int64_t index);
void print_size(int64_t index, int64_t value);
void print_construction(int64_t iterations, int64_t depth);
#if PATH_ARGUMENTS == 1
int64_t path_length(int32_t which);
uint32_t path_character(int32_t which, int64_t index);
#elif PATH_ARGUMENTS == 0
int64_t path_length(void);
uint32_t path_character(int64_t index);
#endif
