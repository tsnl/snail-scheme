#include <assert.h>
#include <stdint.h>

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern void initialize(void) __asm__("wasm.main");
extern int32_t invoke(int32_t) __asm__("wasm.entry");
int32_t builder_add(int32_t left, int32_t right) { return left + right; }
int snail_native_cleanup(void) { return 0; }

int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    initialize();
    const int32_t inputs[] = {-7, 0, 9, 42};
    for (unsigned index = 0; index < sizeof(inputs) / sizeof(inputs[0]); ++index)
        assert(invoke(inputs[index]) == inputs[index] * 3 + 20);
    return 0;
}
