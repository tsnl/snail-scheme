#include <assert.h>
#include <stdint.h>
#include <stdio.h>

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern int64_t guest_main(void) __asm__("wasm.main");
extern int64_t encode_scalar(int64_t) __asm__("wasm.encode-scalar");
extern int64_t decode_scalar(int64_t) __asm__("wasm.decode-scalar");

// ---- Portable little-endian oracle records, without unaligned C loads ----

static uint64_t little_endian(const unsigned char *bytes, unsigned count) {
    uint64_t value = 0;
    for (unsigned i = 0; i < count; ++i) value |= (uint64_t)bytes[i] << (8 * i);
    return value;
}

int main(int argc, char **argv) {
    assert(argc == 2);
    native_host_init(argc, argv);
    native_module_init();
    assert(guest_main() == 0);
    FILE *input = fopen(argv[1], "rb");
    assert(input);
    unsigned char record[12];
    unsigned count = 0;
    size_t size;
    while ((size = fread(record, 1, sizeof(record), input))) {
        assert(size == sizeof(record));
        int64_t scalar = (int64_t)little_endian(record, 4);
        int64_t packed = (int64_t)little_endian(record + 4, 8);
        assert(encode_scalar(scalar) == packed && decode_scalar(packed) == scalar);
        ++count;
    }
    assert(feof(input) && !ferror(input));
    assert(fclose(input) == 0);
    printf("scalars %u\n", count);
    return native_finish(0);
}
