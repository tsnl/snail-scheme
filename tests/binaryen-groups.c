// Execute identical Wasm type identities and floating values through native code.
#include <assert.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern uint32_t check(void) __asm__("wasm.check");
extern uint32_t grouped(uint32_t) __asm__("wasm.call-grouped");
extern uint32_t singleton(uint32_t) __asm__("wasm.call-singleton");
extern double negative_zero(void) __asm__("wasm.negative-zero");
extern uint32_t escaped(void) __asm__("wasm.escaped-name");
extern uint64_t nan_payload(void) __asm__("wasm.nan-payload");
extern uint64_t negative_nan_payload(void) __asm__("wasm.negative-nan-payload");
extern uint64_t wide_float(void) __asm__("wasm.wide-float");
extern uint64_t large_float(void) __asm__("wasm.large-float");
extern uint64_t signed_boundary(void) __asm__("wasm.signed-boundary");
extern uint64_t all_bits(void) __asm__("wasm.all-bits");

void snail_cli_report_failure(void) {}
void drop_resource(uint32_t, uint32_t) __asm__("snail:drop-resource");
void drop_resource(uint32_t kind, uint32_t id) { (void)kind; (void)id; abort(); }

int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    if (argc > 1) { singleton(41); return 2; }
    assert(check() == 0 && grouped(41) == 42);
    assert(negative_zero() == 0 && signbit(negative_zero()));
    assert(escaped() == 19);
    assert(nan_payload() == UINT64_C(0x7ff8000000000005));
    assert(negative_nan_payload() == UINT64_C(0xfff8000000000005));
    assert(wide_float() == UINT64_C(0x43e0000000000000));
    assert(large_float() == UINT64_C(0x4415af1d78b58c40));
    assert(signed_boundary() == UINT64_C(0x8000000000000000));
    assert(all_bits() == UINT64_MAX);
    return 0;
}
