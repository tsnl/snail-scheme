#include "../native-cleanup-observer.h"
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

// ---- Execute the public guest operations with actual native lowering ----

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t copy_characters(void) __asm__("wasm.copy-characters");
extern int64_t copy_standard(void) __asm__("wasm.copy-standard");
extern int32_t mixed_readers(void) __asm__("wasm.mixed-readers");
extern void cached_close(void) __asm__("wasm.cached-close");
extern void open_growing(void) __asm__("wasm.open-growing");
extern int64_t peek_growing(void) __asm__("wasm.peek-growing");
extern int64_t read_growing(void) __asm__("wasm.read-growing");
extern void close_growing(void) __asm__("wasm.close-growing");

static void observe_borrowed_input(void) {
    observe_cleanup();
    assert(fcntl(STDIN_FILENO, F_GETFD) >= 0);
}

static void append_input(char byte) {
    FILE *file = fopen("input.txt", "ab");
    assert(file && fputc(byte, file) == byte && fclose(file) == 0);
}

static void eof_growth(void) {
    open_growing();
    for (char byte = 'A'; byte <= 'B'; byte++) {
        assert(peek_growing() == -1);
        append_input(byte);
        assert(peek_growing() == -1);
        assert(read_growing() == -1);
        assert(peek_growing() == byte);
        assert(read_growing() == byte);
    }
    close_growing();
}

int main(int argc, char **argv) {
    assert(argc == 3 && atexit(observe_borrowed_input) == 0);
    if (!strcmp(argv[1], "copy-standard")) assert(freopen("input.txt", "rb", stdin));
    native_host_init(argc, argv);
    native_module_init();
    guest_main();
    if (!strcmp(argv[1], "copy-characters")) assert(copy_characters() == strtoll(argv[2], NULL, 10));
    else if (!strcmp(argv[1], "copy-standard")) assert(copy_standard() == strtoll(argv[2], NULL, 10));
    else if (!strcmp(argv[1], "mixed-readers")) assert(mixed_readers());
    else if (!strcmp(argv[1], "cached-close")) cached_close();
    else if (!strcmp(argv[1], "eof-growth")) eof_growth();
    else abort();
    return native_finish(0);
}
