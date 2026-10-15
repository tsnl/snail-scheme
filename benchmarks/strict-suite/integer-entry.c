#include <assert.h>
#include <stdint.h>
extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t bench(int64_t) __asm__("wasm.bench");
extern void observe(void) __asm__("wasm.observe");
int64_t load_input(const char *);
void free_input(void);
uint64_t barrier_count(void);

// ---- Full original count and complete observed result ----

int main(int argc, char **argv) {
    assert(argc == 2);
    native_host_init(argc, argv); native_module_init();
    int64_t count = load_input(argv[1]); guest_main();
    assert(bench(count) == 1 && barrier_count() == 3 * (uint64_t)count);
    observe(); free_input(); return native_finish(0);
}
