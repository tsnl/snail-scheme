#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../native-cleanup-observer.h"

extern void native_host_init(int argc, char **argv);
extern void native_module_init(void);
extern int native_finish(int status);
extern void guest_main(void) __asm__("wasm.main");
extern uint32_t lower(uint32_t) __asm__("wasm.lower");
extern int32_t alphabetic(uint32_t) __asm__("wasm.alphabetic");
extern int32_t numeric(uint32_t) __asm__("wasm.numeric");
extern int32_t whitespace(uint32_t) __asm__("wasm.whitespace");
extern void fresh_strings(int64_t, int64_t) __asm__("wasm.fresh-strings");
extern void fill_left(int64_t, uint32_t) __asm__("wasm.fill-left");
extern void fill_right(int64_t, uint32_t) __asm__("wasm.fill-right");
extern int32_t ordered(void) __asm__("wasm.ordered");
extern int32_t self_ordered(void) __asm__("wasm.self-ordered");
extern void fold_left(void) __asm__("wasm.fold-left");
extern uint32_t read_left(int64_t) __asm__("wasm.read-left");
extern uint32_t read_right(int64_t) __asm__("wasm.read-right");
extern int64_t right_length(void) __asm__("wasm.right-length");
extern int32_t same_strings(void) __asm__("wasm.same-strings");
extern int32_t fold_literal(void) __asm__("wasm.fold-literal");
extern uint32_t fold_count(uint32_t) __asm__("wasm.fold-count");
extern uint32_t fold_component(uint32_t, uint32_t) __asm__("wasm.fold-component");
extern void malformed(int64_t, int32_t) __asm__("wasm.malformed");

// ---- Consume the same scalar corpus and mutable strings as Node ----

static void scalars(void) {
    FILE *input = fopen("scalars.txt", "r");
    assert(input);
    unsigned value;
    int a, b, c, d;
    while (fscanf(input, "%u %d %d %d %d", &value, &a, &b, &c, &d) == 5)
        printf("%u %u %d %d %d\n", value, lower(value), alphabetic(value), numeric(value), whitespace(value));
    assert(feof(input) && fclose(input) == 0);
}

static void strings(void) {
    FILE *input = fopen("strings.txt", "r");
    assert(input);
    unsigned a, b, expected, character;
    while (fscanf(input, "%u %u %u", &a, &b, &expected) == 3) {
        fresh_strings(a, b);
        for (unsigned index = 0; index < a; index++) {
            assert(fscanf(input, "%u", &character) == 1); fill_left(index, character);
        }
        for (unsigned index = 0; index < b; index++) {
            assert(fscanf(input, "%u", &character) == 1); fill_right(index, character);
        }
        printf("%d\n", ordered());
        assert(!self_ordered() && ordered() == (int32_t)expected);
    }
    assert(feof(input) && fclose(input) == 0);
    fresh_strings(1, 1); fill_left(0, 97); fill_right(0, 98); assert(ordered());
    fill_left(0, 99); assert(!ordered()); fill_left(0, 98); assert(!ordered());
    fill_right(0, 99); assert(ordered());
}

// ---- Full Unicode folding and independently mutable output storage ----

static void fold_scalars(void) {
    FILE *input = fopen("fold-scalars.txt", "r");
    unsigned code, length, expected[3], count = 0;
    assert(input);
    while (fscanf(input, "%u %u %u %u %u", &code, &length, &expected[0], &expected[1], &expected[2]) == 5) {
        assert(fold_count(code) == length);
        for (unsigned index = 0; index < length; index++) assert(fold_component(code, index) == expected[index]);
        count++;
    }
    assert(feof(input) && fclose(input) == 0); printf("%u\n", count);
}

static void check_folded_storage(unsigned size, unsigned length, const unsigned *source, const unsigned *expected) {
    fold_left(); assert(right_length() == length && !same_strings());
    for (unsigned index = 0; index < size; index++) assert(read_left(index) == source[index]);
    for (unsigned index = 0; index < length; index++) assert(read_right(index) == expected[index]);
    if (size) {
        fill_left(0, 33); assert(read_right(0) == expected[0]);
        fill_right(0, 63); assert(read_left(0) == 33);
    }
}

static void fold_strings(void) {
    FILE *input = fopen("fold-strings.txt", "r");
    unsigned size, length, count = 0;
    assert(input);
    while (fscanf(input, "%u %u", &size, &length) == 2) {
        unsigned *source = malloc((size + 1) * sizeof(unsigned)), *expected = malloc((length + 1) * sizeof(unsigned));
        assert(source && expected); fresh_strings(size, 0);
        for (unsigned index = 0; index < size; index++) {
            assert(fscanf(input, "%u", &source[index]) == 1); fill_left(index, source[index]);
        }
        for (unsigned index = 0; index < length; index++) assert(fscanf(input, "%u", &expected[index]) == 1);
        check_folded_storage(size, length, source, expected);
        free(source); free(expected); count++;
    }
    assert(feof(input) && fclose(input) == 0 && fold_literal()); printf("%u\n", count);
}

// ---- One invocation, including deliberate terminal raw-scalar failures ----

int main(int argc, char **argv) {
    assert(argc >= 2 && atexit(observe_cleanup) == 0);
    native_host_init(argc, argv); native_module_init(); guest_main();
    if (!strcmp(argv[1], "scalars")) scalars();
    else if (!strcmp(argv[1], "strings")) strings();
    else if (!strcmp(argv[1], "fold-scalars")) fold_scalars();
    else if (!strcmp(argv[1], "fold-strings")) fold_strings();
    else { assert(argc == 4); malformed(strtoll(argv[2], NULL, 10), (int32_t)strtoul(argv[3], NULL, 10)); }
    return native_finish(0);
}
