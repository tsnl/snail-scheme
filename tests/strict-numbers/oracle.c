#define _POSIX_C_SOURCE 200809L
#include "../strict-integer/oracle.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern char *arguments[2], *output;
extern size_t output_size;
extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void guest_main(void) __asm__("wasm.main");
extern double probe(int64_t, double) __asm__("wasm.probe");

// ---- Compare full exact strings and every binary64 result bit ----

int main(int argc, char **argv) {
    assert(argc == 2);
    native_host_init(argc, argv); native_module_init(); guest_main();
    FILE *input = fopen(argv[1], "r"); assert(input);
    char *line = NULL; size_t capacity = 0, count = 0;
    while (getline(&line, &capacity, input) != -1) {
        char *field[6]; field[0] = line;
        for (int index = 1; index < 6; index++) {
            char *tab = strchr(field[index - 1], '\t'); assert(tab); *tab = 0; field[index] = tab + 1;
        }
        field[5][strcspn(field[5], "\n")] = 0;
        arguments[0] = field[1]; arguments[1] = field[2]; output_size = 0;
        if (output) output[0] = 0;
        uint64_t input_bits = strtoull(field[3], NULL, 10), actual_bits;
        double value; memcpy(&value, &input_bits, 8);
        value = probe(strtoll(field[0], NULL, 10), value);
        memcpy(&actual_bits, &value, 8);
        if (actual_bits != strtoull(field[4], NULL, 10) || strcmp(output ? output : "", field[5])) {
            fprintf(stderr, "case %zu differs: bits %llu, text %s\n", count,
                    (unsigned long long)actual_bits, output ? output : ""); abort();
        }
        count++;
    }
    assert(!ferror(input)); fclose(input); free(line); free(output);
    printf("cases %zu passed\n", count);
    return native_finish(0);
}
