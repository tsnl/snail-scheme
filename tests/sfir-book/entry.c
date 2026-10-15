#include <stdint.h>
#include <stdlib.h>

extern int32_t sfir_main(void) __asm__("wasm.main");
extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
#ifdef TEST_CONVERSION
extern int32_t sfir_convert(float) __asm__("wasm.convert");
#endif

int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    if (sfir_main() != 42) return native_finish(2);
#ifdef TEST_CONVERSION
    if (argc == 3) return native_finish(sfir_convert(strtof(argv[1], NULL)) == strtol(argv[2], NULL, 10) ? 0 : 2);
#endif
    return native_finish(argc == 1 ? 0 : 2);
}
