#include <assert.h>
#include <math.h>
extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void guest_main(void) __asm__("wasm.main");
extern double rounded(double) __asm__("wasm.worker");
extern float rounded32(float) __asm__("wasm.round32");
extern double concrete(double) __asm__("wasm.view64");
extern float concrete32(float) __asm__("wasm.view32");
int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    guest_main();
    const double inputs[] = {-INFINITY, -3.5, -2.5, -1.5, -0.5, -0.0, 0.0, 0.5, 1.5, 2.5, 3.5, INFINITY};
    const double outputs[] = {-INFINITY, -4, -2, -2, -0.0, -0.0, 0.0, 0.0, 2, 2, 4, INFINITY};
    for (unsigned i = 0; i < sizeof(inputs) / sizeof(inputs[0]); i++) {
        assert(rounded(inputs[i]) == outputs[i] && concrete(inputs[i]) == outputs[i]);
        assert(rounded32(inputs[i]) == outputs[i] && concrete32(inputs[i]) == outputs[i]);
        assert(!!signbit(rounded(inputs[i])) == !!signbit(outputs[i]));
        assert(!!signbit(rounded32(inputs[i])) == !!signbit(outputs[i]));
    }
    assert(isnan(rounded(NAN)) && isnan(rounded32(NAN)));
    return native_finish(0);
}
