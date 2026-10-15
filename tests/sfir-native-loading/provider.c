#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int32_t counter;
int32_t tick(void) { return ++counter; }
int32_t bad_bool(void) { return 7; }
int32_t bad_char(void) { return 0xd800; }
int32_t hang(void) { for (;;) pause(); }

void mark(int32_t value) {
    FILE *file = fopen(getenv("SNAIL_TEST_EFFECTS"), "a");
    if (!file) abort();
    fprintf(file, "%d %d\n", (int)getpid(), value);
    fclose(file);
    puts("provider output is separate from scalar transport");
}

void spawn_child(void) {
    // The descendant inherits the worker's group and deliberately ignores TERM.
    pid_t child = fork();
    if (child < 0) abort();
    if (!child) { signal(SIGTERM, SIG_IGN); for (;;) pause(); }
    FILE *file = fopen(getenv("SNAIL_TEST_CHILD"), "w");
    if (!file) abort();
    fprintf(file, "%d\n", (int)child);
    fclose(file);
}

__attribute__((constructor)) static void construct_provider(void) {
    if (getenv("SNAIL_TEST_CONSTRUCTOR")) spawn_child();
    if (getenv("SNAIL_TEST_CONSTRUCTOR_HANG")) hang();
}

extern void pathname_start(void) __asm__("snail:io/path-begin");
extern void pathname_character(uint32_t) __asm__("snail:io/path-character");
extern int32_t open_output(void) __asm__("snail:io/open-output-file");
extern void write_character(int32_t, uint32_t) __asm__("snail:io/write-character");

void open_resource(void) {
    const char *path = getenv("SNAIL_TEST_RESOURCE");
    pathname_start();
    while (*path) pathname_character((unsigned char)*path++);
    write_character(open_output(), 'x');
    // Terminal native_finish must flush and close this real Rust-owned resource.
}
