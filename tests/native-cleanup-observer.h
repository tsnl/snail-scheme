// A test observes the runtime's completed drops before libc exits the process.
#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
extern uint64_t native_resource_release_count(void);
static void observe_count(const char *variable, uint64_t count) {
    const char *path = getenv(variable);
    if (!path) return;
    FILE *file = fopen(path, "w");
    assert(file);
    fprintf(file, "%" PRIu64 "\n", count);
    assert(fclose(file) == 0);
}
static void observe_cleanup(void) {
    observe_count("SNAIL_NATIVE_CLEANUP_LOG", native_resource_release_count());
}
