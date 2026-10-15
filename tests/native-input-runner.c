// Each process makes the same typed calls as the Node/WASI input fixture.
#include "native-cleanup-observer.h"
#include <string.h>

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void main_entry(void) __asm__("wasm.main");
extern int64_t copy_lines(void) __asm__("wasm.copy-lines");
extern int32_t line_storage(void) __asm__("wasm.line-storage");
extern void close_alias(void) __asm__("wasm.close-input-alias");
extern int64_t callback_close(void) __asm__("wasm.input-callback-close");
extern void escaped_alias(void) __asm__("wasm.input-escaped-alias");
extern void missing(void) __asm__("wasm.input-missing");
extern void callback_trap(void) __asm__("wasm.input-callback-trap");
extern void read_invalid(void) __asm__("wasm.read-invalid");
extern void raw_output(void) __asm__("wasm.input-raw-output");
extern void stale_handle(void) __asm__("wasm.input-stale-handle");
extern void invalid_handle(void) __asm__("wasm.input-invalid-handle");
extern void invalid_peek(void) __asm__("wasm.input-invalid-peek");

int main(int argc, char **argv) {
    assert(argc > 1 && atexit(observe_cleanup) == 0);
    native_host_init(argc, argv);
    native_module_init();
    main_entry();
    if (!strcmp(argv[1], "copy")) assert(argc == 3 && copy_lines() == strtoll(argv[2], NULL, 10));
    else if (!strcmp(argv[1], "ownership")) {
        assert(line_storage());
        close_alias();
        assert(callback_close() == 19);
    } else if (!strcmp(argv[1], "alias")) escaped_alias();
    else if (!strcmp(argv[1], "missing")) missing();
    else if (!strcmp(argv[1], "trap")) callback_trap();
    else if (!strcmp(argv[1], "invalid")) read_invalid();
    else if (!strcmp(argv[1], "output")) raw_output();
    else if (!strcmp(argv[1], "stale")) stale_handle();
    else if (!strcmp(argv[1], "handle")) invalid_handle();
    else if (!strcmp(argv[1], "peek")) invalid_peek();
    else abort();
    return native_finish(0);
}
