// Direct native runner for the bounded WasmGC-to-LLVM experiment.
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <gc/gc.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

extern void wasm_init(void);
extern int32_t wasm_export_fibonacci(int32_t) __attribute__((weak));
extern int32_t wasm_export_gc_probe(void) __attribute__((weak));
static unsigned observed, finalized, forced_collections, watched;
static GC_hidden_pointer identities[32];
static unsigned reclaimed[32];

// ---- Errors and arguments ----

static void fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  exit(1);
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

// ---- Collector test imports ----

static void object_finalized(void *object, void *data) {
  (void)object;
  reclaimed[(uintptr_t)data - 1] = 1;
  finalized++;
}

void native_observe(uintptr_t word) {
  void *object = (void *)word;
  if (!word || (word & 7) || GC_base(object) != object)
    fail("translated struct is not an aligned BDWGC allocation");
  observed++;
  GC_hidden_pointer identity = GC_HIDE_POINTER(object);
  unsigned index = 0;
  while (index < watched && identities[index] != identity)
    index++;
  if (index < watched) {
    if (reclaimed[index])
      fail("a live translated reference was finalized");
    return;
  }
  if (watched == 32)
    fail("too many watched fixture objects");
  identities[watched++] = identity;
  GC_register_finalizer_no_order(object, object_finalized,
                                 (void *)(uintptr_t)(index + 1), NULL, NULL);
}

// Allocation pressure is deliberately confined to the semantic fixture, never
// the Fibonacci timing loop. Scheme pointers remain in native caller frames.
void native_collect(void) {
  for (unsigned index = 0; index < 512; index++)
    if (!GC_malloc(4096))
      fail("GC allocation failed");
  forced_collections++;
  GC_gcollect();
  GC_invoke_finalizers();
}

// Overwrite obsolete fixture frames before testing finalization. Conservative
// collectors may retain stale words, so allow several collections afterward.
__attribute__((noinline)) static void clear_old_stack(unsigned depth) {
  volatile uintptr_t words[512];
  for (unsigned index = 0; index < 512; index++)
    words[index] = index;
  if (depth)
    clear_old_stack(depth - 1);
  if (words[0] != 0)
    fail("stack overwrite failed");
}

static void gc_test(size_t before_bytes, GC_word before_collections) {
  if (!wasm_export_gc_probe)
    fail("module does not export gc_probe");
  if (wasm_export_gc_probe() != 1083)
    fail("GC fixture result mismatch");
  for (unsigned attempt = 0; attempt < 8 && !finalized; attempt++) {
    clear_old_stack(16);
    native_collect();
  }
  size_t allocated = GC_get_total_bytes() - before_bytes;
  GC_word collections = GC_get_gc_no() - before_collections;
  if (observed < 21 || !finalized || !allocated || !collections ||
      forced_collections < 2)
    fail("missing allocation, collection, root, or reclamation evidence");
  printf("gc probe: result 1083; observed %u; finalized %u; allocated %zu "
         "bytes; collections %lu; forced %u\n",
         observed, finalized, allocated, (unsigned long)collections,
         forced_collections);
}

// ---- Fibonacci workload ----

static void warmup(void) {
  if (!wasm_export_fibonacci)
    fail("module does not export fibonacci");
  const int32_t small[] = {0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144};
  const int32_t large[] = {17711, 28657, 46368, 75025};
  for (int32_t n = 0; n < 13; n++)
    if (wasm_export_fibonacci(n) != small[n])
      fail("small fibonacci check failed");
  for (int32_t n = 22; n <= 25; n++)
    if (wasm_export_fibonacci(n) != large[n - 22])
      fail("benchmark fibonacci check failed");
}

static double seconds_since(struct timespec started) {
  struct timespec ended;
  if (clock_gettime(CLOCK_MONOTONIC, &ended))
    fail("clock_gettime failed");
  return (double)(ended.tv_sec - started.tv_sec) +
         1e-9 * (double)(ended.tv_nsec - started.tv_nsec);
}

static void benchmark(uint64_t count) {
  uint64_t checksum = 0;
  struct timespec started;
  if (clock_gettime(CLOCK_MONOTONIC, &started))
    fail("clock_gettime failed");
  for (uint64_t iteration = 0; iteration < count; iteration++)
    for (int32_t n = 22; n <= 25; n++)
      checksum += (uint64_t)(n + 1) * (uint32_t)wasm_export_fibonacci(n);
  double elapsed = seconds_since(started);
  if (checksum != count * 4204971)
    fail("benchmark checksum mismatch");
  printf("checksum: %" PRIu64 "\nelapsed: %.9f s; repetitions: %" PRIu64 "\n",
         checksum, elapsed, count);
}

// ---- Program entry ----

int main(int argc, char **argv) {
  if (argc != 2)
    fail("usage: native-run REPETITIONS | --gc-test");
  GC_INIT();
  GC_set_finalize_on_demand(1);
  size_t before_bytes = GC_get_total_bytes();
  GC_word before_collections = GC_get_gc_no();
  wasm_init();
  if (!strcmp(argv[1], "--gc-test"))
    gc_test(before_bytes, before_collections);
  else {
    uint64_t count = repetitions(argv[1]);
    warmup();
    benchmark(count);
  }
  return 0;
}
