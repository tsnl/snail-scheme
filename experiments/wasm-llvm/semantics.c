#include <assert.h>
#include <stdint.h>
#include <unistd.h>

extern void wasm_init(void);
extern int32_t wasm_export_equivalent(void);
extern int32_t wasm_export_i31_signed_min(void);
extern int32_t wasm_export_i31_unsigned_max(void);
extern void wasm_export_store_order(void);

void native_observe(uint64_t reference) {
  assert(reference == 75);
  assert(write(1, "RHS evaluated\n", 14) == 14);
}

int main(int argc, char **argv) {
  (void)argv;
  wasm_init();
  assert(wasm_export_equivalent() == 72);
  assert(wasm_export_i31_signed_min() == -1073741824);
  assert(wasm_export_i31_unsigned_max() == 2147483647);
  if (argc == 2)
    wasm_export_store_order();
  return 0;
}
