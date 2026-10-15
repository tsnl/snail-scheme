// Observe resource release before process exit, including terminal failures.
#include <assert.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern uint64_t native_resource_release_count(void);
extern int64_t format_number(int64_t) __asm__("wasm.format-number");
extern int64_t unicode(void) __asm__("wasm.unicode");
extern double callback_result(void) __asm__("wasm.callback-result");
extern int32_t exists(void) __asm__("wasm.exists");
extern void remove_file(void) __asm__("wasm.remove");
extern void callback_trap(void) __asm__("wasm.callback-trap");
extern void close_failure(void) __asm__("wasm.close-failure");
extern void missing_directory(void) __asm__("wasm.missing-directory");
extern void invalid_character(void) __asm__("wasm.invalid-character");
extern void invalid_handle(void) __asm__("wasm.invalid-handle");
extern void escaped_alias(void) __asm__("wasm.escaped-alias");
extern void close_alias(void) __asm__("wasm.close-alias");
extern void main_entry(void) __asm__("wasm.main");

#include "native-cleanup-observer.h"

int main(int argc, char **argv) {
    assert(atexit(observe_cleanup) == 0);
    native_host_init(argc, argv);
    native_module_init();
    main_entry();
    if (argc > 1 && !strcmp(argv[1], "unicode")) assert(unicode() == 42);
    else if (argc > 1 && !strcmp(argv[1], "trap")) callback_trap();
    else if (argc > 1 && !strcmp(argv[1], "io-error")) close_failure();
    else if (argc > 1 && !strcmp(argv[1], "missing")) missing_directory();
    else if (argc > 1 && !strcmp(argv[1], "character")) invalid_character();
    else if (argc > 1 && !strcmp(argv[1], "handle")) invalid_handle();
    else if (argc > 1 && !strcmp(argv[1], "alias")) escaped_alias();
    else if (argc > 2 && !strcmp(argv[1], "number")) {
        int64_t number = strtoll(argv[2], NULL, 10);
        assert(format_number(number) == number);
    } else {
        assert(unicode() == 42 && exists());
        assert(callback_result() == 1.25);
        close_alias();
        remove_file();
        assert(!exists());
    }
    return native_finish(0);
}
