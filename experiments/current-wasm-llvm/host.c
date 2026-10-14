// Benchmark imports remain opaque: compile this file without LTO, separately
// from the guest and collector. Inputs are read at runtime before initialization.
#define _POSIX_C_SOURCE 200809L
#include "precise-gc.h"
#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// ---- Runtime specification and opaque imports ----

typedef struct { size_t length; int64_t *integers; double *floats; } Values;
static Values *inputs, expected_values;
static size_t input_count;
static int64_t count, expected, per_iteration, setup_expected;
static double tolerance;
static uint64_t barriers;
static int validate;

static Values read_values(FILE *file) {
    Values values;
    assert(fscanf(file, "%zu", &values.length) == 1);
    values.integers = calloc(values.length, sizeof(*values.integers));
    values.floats = calloc(values.length, sizeof(*values.floats));
    assert(!values.length || (values.integers && values.floats));
    for (size_t i = 0; i < values.length; i++)
        assert(fscanf(file, "%" SCNd64 " %lf", &values.integers[i], &values.floats[i]) == 2);
    return values;
}

static void read_specification(const char *path) {
    FILE *file = fopen(path, "r");
    assert(file);
    assert(fscanf(file, "%" SCNd64 " %" SCNd64 " %" SCNd64 " %" SCNd64 " %zu %lf",
                  &count, &expected, &per_iteration, &setup_expected, &input_count, &tolerance) == 6);
    inputs = calloc(input_count, sizeof(*inputs));
    assert(!input_count || inputs);
    for (size_t i = 0; i < input_count; i++) inputs[i] = read_values(file);
    expected_values = read_values(file);
    assert(fclose(file) == 0);
}

int64_t benchmark_hide_i64(int64_t value) { if (validate) barriers++; return value; }
int64_t benchmark_count(void) { return count; }
double benchmark_hide_f64(double value) { if (validate) barriers++; return value; }
int32_t benchmark_barrier(void) { if (validate) barriers++; return 1; }
int64_t benchmark_input_i64(uint32_t index) {
    assert(index < input_count && inputs[index].length == 1);
    return inputs[index].integers[0];
}
double benchmark_input_f64(uint32_t index) {
    assert(index < input_count && inputs[index].length == 1);
    return inputs[index].floats[0];
}
int64_t benchmark_vector_length(uint32_t index) {
    assert(index < input_count);
    return inputs[index].length;
}
int64_t benchmark_vector_i64(uint32_t index, uint64_t element) {
    assert(index < input_count && element < inputs[index].length);
    return inputs[index].integers[element];
}
double benchmark_vector_f64(uint32_t index, uint64_t element) {
    assert(index < input_count && element < inputs[index].length);
    return inputs[index].floats[element];
}
int64_t benchmark_expected_length(void) { return expected_values.length; }
int64_t benchmark_expected_i64(uint64_t index) {
    assert(index < expected_values.length);
    return expected_values.integers[index];
}
double benchmark_expected_f64(uint64_t index) {
    assert(index < expected_values.length);
    return expected_values.floats[index];
}
double benchmark_tolerance(void) { return tolerance; }

// ---- Guest execution and matching timing boundary ----

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t guest_bench(int64_t) __asm__("wasm.bench");
void snail_cli_report_failure(void) {}
void drop_resource(uint32_t, uint32_t) __asm__("snail:drop-resource");
void drop_resource(uint32_t kind, uint32_t id) { (void)kind; (void)id; abort(); }

static double seconds(void) {
    struct timespec time;
    assert(clock_gettime(CLOCK_MONOTONIC, &time) == 0);
    return time.tv_sec + time.tv_nsec * 1e-9;
}

typedef struct {
    double seconds, setup_seconds;
    int64_t result;
    uint64_t setup_barriers;
    size_t setup_collections, collections;
} Measurement;

static void initialize_guest(int argc, char **argv, Measurement *measurement) {
    double start = seconds();
    native_host_init(argc, argv);
    native_module_init();
    guest_main();
    measurement->setup_seconds = seconds() - start;
    measurement->setup_barriers = barriers;
    measurement->setup_collections = GC_get_gc_no();
    if (validate && setup_expected >= 0) assert(barriers == (uint64_t)setup_expected);
    barriers = 0;
}

static void measure_workload(Measurement *measurement) {
    double start = seconds();
    measurement->result = guest_bench(count);
    assert(measurement->result == expected);
    measurement->seconds = seconds() - start;
    measurement->collections = GC_get_gc_no() - measurement->setup_collections;
    if (validate) assert(barriers == (uint64_t)(per_iteration * (count > 0 ? count : 0)));
}

static void write_measurement(Measurement measurement) {
    printf("{\"seconds\":%.9f,\"result\":\"%" PRId64 "\",\"barriers\":", measurement.seconds, measurement.result);
    if (validate) printf("%" PRIu64, barriers); else fputs("null", stdout);
    fputs(",\"setup_barriers\":", stdout);
    if (validate) printf("%" PRIu64, measurement.setup_barriers); else fputs("null", stdout);
    printf(",\"setup_seconds\":%.9f,\"setup_collections\":%zu,\"collections\":%zu}\n",
           measurement.setup_seconds, measurement.setup_collections, measurement.collections);
}

int main(int argc, char **argv) {
    assert(argc == 2 || (argc == 3 && !strcmp(argv[2], "--validate")));
    validate = argc == 3;
    read_specification(argv[1]);
    Measurement measurement = {0};
    initialize_guest(argc, argv, &measurement);
    measure_workload(&measurement);
    write_measurement(measurement);
    return 0;
}
