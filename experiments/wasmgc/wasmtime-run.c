// Wasmtime C API runner; compilation, instantiation, and warmup are not timed.
// Build with cc -O3 -std=c11 wasmtime-run.c -I<wasmtime/include>
//   -L<wasmtime/lib> -Wl,-rpath,<wasmtime/lib> -lwasmtime -o wasmtime-run
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <wasmtime.h>

// ---- Errors and input ----

static void fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  exit(1);
}

static void check(wasmtime_error_t *error, wasm_trap_t *trap) {
  if (!error && !trap)
    return;
  wasm_byte_vec_t message;
  if (error)
    wasmtime_error_message(error, &message);
  else
    wasm_trap_message(trap, &message);
  fwrite(message.data, 1, message.size, stderr);
  fputc('\n', stderr);
  wasm_byte_vec_delete(&message);
  if (error)
    wasmtime_error_delete(error);
  if (trap)
    wasm_trap_delete(trap);
  exit(1);
}

static wasm_byte_vec_t read_module(const char *path) {
  FILE *file = fopen(path, "rb");
  if (!file || fseek(file, 0, SEEK_END))
    fail("cannot read module");
  long length = ftell(file);
  if (length < 0 || fseek(file, 0, SEEK_SET))
    fail("cannot size module");
  wasm_byte_vec_t bytes;
  wasm_byte_vec_new_uninitialized(&bytes, (size_t)length);
  if (bytes.size != (size_t)length)
    fail("cannot allocate module bytes");
  if (fread(bytes.data, 1, bytes.size, file) != bytes.size)
    fail("cannot read module bytes");
  if (fclose(file))
    fail("cannot close module");
  return bytes;
}

static uint64_t repetitions(const char *text) {
  char *end;
  errno = 0;
  unsigned long long count = strtoull(text, &end, 10);
  if (errno || text[0] < '0' || text[0] > '9' || *end || !count ||
      count > UINT64_MAX / 4204971)
    fail("repetitions must be positive and the checksum must fit uint64");
  return count;
}

// ---- Engine and calls ----

static wasm_engine_t *engine(void) {
  wasm_config_t *config = wasm_config_new();
  wasmtime_config_wasm_gc_set(config, true);
  wasmtime_config_wasm_tail_call_set(config, true);
  wasmtime_config_strategy_set(config, WASMTIME_STRATEGY_CRANELIFT);
  wasmtime_config_cranelift_opt_level_set(config, WASMTIME_OPT_LEVEL_SPEED);
#ifdef WASMTIME_FEATURE_PARALLEL_COMPILATION
  wasmtime_config_parallel_compilation_set(config, false);
#endif
  wasm_engine_t *engine = wasm_engine_new_with_config(config);
  if (!engine)
    fail("cannot create engine");
  return engine;
}

static int32_t fibonacci(wasmtime_context_t *context,
                         const wasmtime_func_t *function, int32_t n) {
  wasmtime_val_t argument = {.kind = WASMTIME_I32, .of.i32 = n};
  wasmtime_val_t result;
  wasm_trap_t *trap = NULL;
  wasmtime_error_t *error =
      wasmtime_func_call(context, function, &argument, 1, &result, 1, &trap);
  check(error, trap);
  if (result.kind != WASMTIME_I32)
    fail("fibonacci did not return i32");
  return result.of.i32;
}

static void warmup(wasmtime_context_t *context,
                   const wasmtime_func_t *function) {
  const int32_t small[] = {0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144};
  const int32_t large[] = {17711, 28657, 46368, 75025};
  for (int32_t n = 0; n < 13; n++)
    if (fibonacci(context, function, n) != small[n])
      fail("small fibonacci check failed");
  for (int32_t n = 22; n <= 25; n++)
    if (fibonacci(context, function, n) != large[n - 22])
      fail("benchmark fibonacci check failed");
}

// ---- Timed workload ----

static double seconds_since(struct timespec started) {
  struct timespec ended;
  if (clock_gettime(CLOCK_MONOTONIC, &ended))
    fail("clock_gettime failed");
  return (double)(ended.tv_sec - started.tv_sec) +
         1e-9 * (double)(ended.tv_nsec - started.tv_nsec);
}

static void benchmark(wasmtime_context_t *context,
                      const wasmtime_func_t *function, uint64_t count) {
  struct timespec started;
  uint64_t checksum = 0;
  if (clock_gettime(CLOCK_MONOTONIC, &started))
    fail("clock_gettime failed");
  for (uint64_t iteration = 0; iteration < count; iteration++)
    for (int32_t n = 22; n <= 25; n++)
      checksum += (uint64_t)(n + 1) * (uint32_t)fibonacci(context, function, n);
  double elapsed = seconds_since(started);
  if (checksum != count * 4204971)
    fail("benchmark checksum mismatch");
  printf("checksum: %" PRIu64 "\nelapsed: %.9f s; repetitions: %" PRIu64 "\n",
         checksum, elapsed, count);
}

// ---- Program entry ----

int main(int argc, char **argv) {
  if (argc != 3)
    fail("usage: wasmtime-run MODULE.wasm REPETITIONS");
  uint64_t count = repetitions(argv[2]);
  wasm_engine_t *runtime = engine();
  wasm_byte_vec_t bytes = read_module(argv[1]);
  wasmtime_module_t *module = NULL;
  check(wasmtime_module_new(runtime, (const uint8_t *)bytes.data, bytes.size,
                            &module),
        NULL);
  wasm_byte_vec_delete(&bytes);
  wasmtime_store_t *store = wasmtime_store_new(runtime, NULL, NULL);
  wasmtime_context_t *context = wasmtime_store_context(store);
  wasmtime_instance_t instance;
  wasm_trap_t *trap = NULL;
  wasmtime_error_t *error =
      wasmtime_instance_new(context, module, NULL, 0, &instance, &trap);
  check(error, trap);
  wasmtime_extern_t function;
  if (!wasmtime_instance_export_get(context, &instance, "fibonacci", 9,
                                    &function) ||
      function.kind != WASMTIME_EXTERN_FUNC)
    fail("module does not export function fibonacci");
  warmup(context, &function.of.func);
  benchmark(context, &function.of.func, count);
  wasmtime_extern_delete(&function);
  wasmtime_store_delete(store);
  wasmtime_module_delete(module);
  wasm_engine_delete(runtime);
  return 0;
}
