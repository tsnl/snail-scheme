#define _POSIX_C_SOURCE 200809L
#include "oracle.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern char *arguments[2], *output;
extern size_t output_size;

// ---- Every valid case compares its entire decimal result ----

extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t integer_probe(int64_t) __asm__("wasm.integer-probe");
int main(int argc, char **argv) {
    assert(argc == 2);
    native_host_init(argc, argv); native_module_init(); guest_main();
    FILE *input = fopen(argv[1], "r"); assert(input);
    char *line = NULL; size_t capacity = 0, count = 0;
    while (getline(&line, &capacity, input) != -1) {
        char *field[4]; field[0] = line;
        for (int index = 1; index < 4; index++) {
            char *tab = strchr(field[index - 1], '\t'); assert(tab); *tab = 0; field[index] = tab + 1;
        }
        field[3][strcspn(field[3], "\n")] = 0;
        arguments[0] = field[1]; arguments[1] = field[2]; output_size = 0;
        assert(integer_probe(strtoll(field[0], NULL, 10)) == 1);
        if (strcmp(output, field[3]) != 0) {
            fprintf(stderr, "case %zu differs: %s != %s\n", count, output, field[3]); abort();
        }
        count++;
    }
    assert(!ferror(input)); fclose(input); free(line); free(output);
    printf("cases %zu passed\n", count);
    return native_finish(0);
}
