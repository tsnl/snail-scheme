#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "../native-cleanup-observer.h"

extern void native_host_init(int argc, char **argv);
extern void native_module_init(void);
extern int native_finish(int status);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t copy_output(void) __asm__("wasm.copy-output");
extern int32_t roundtrip(void) __asm__("wasm.roundtrip");
extern void graphs(void) __asm__("wasm.graphs");
extern void deep_output(void) __asm__("wasm.deep-output");
extern void stdout_check(void) __asm__("wasm.stdout-check");
extern void closed_empty(void) __asm__("wasm.closed-empty");
extern void callback_trap(void) __asm__("wasm.callback-trap");
extern void invalid_character(void) __asm__("wasm.invalid-character");
extern void invalid_handle(void) __asm__("wasm.invalid-handle");
extern void read_stdout(void) __asm__("wasm.read-stdout");
extern void stdout_failure(void) __asm__("wasm.stdout-failure");

// ---- The native host executes the same named Scheme exports as Node ----

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    assert(atexit(observe_cleanup) == 0);
    native_host_init(argc, argv);
    native_module_init();
    guest_main();
    if (!strcmp(argv[1], "stream")) {
        if (copy_output() <= 0 || !roundtrip()) return native_finish(2);
    } else if (!strcmp(argv[1], "graphs")) graphs();
    else if (!strcmp(argv[1], "deep")) deep_output();
    else if (!strcmp(argv[1], "stdout")) stdout_check();
    else if (!strcmp(argv[1], "closed")) closed_empty();
    else if (!strcmp(argv[1], "trap")) callback_trap();
    else if (!strcmp(argv[1], "character")) invalid_character();
    else if (!strcmp(argv[1], "handle")) invalid_handle();
    else if (!strcmp(argv[1], "read-stdout")) read_stdout();
    else if (!strcmp(argv[1], "stdout-failure")) {
        if (!freopen("/dev/full", "w", stdout)) return native_finish(2);
        stdout_failure();
    } else return native_finish(2);
    return native_finish(0);
}
