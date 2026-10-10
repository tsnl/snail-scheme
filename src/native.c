// Native host for translated Wasm: BDWGC objects, wasm32 memory and WASIp1.
// The Scheme and Rust runtimes both come from the same linked Wasm module.
// This host knows no Scheme representation beyond AWI's finalizer import.

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <gc/gc.h>
#include <inttypes.h>
#include <limits.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#if !defined(__linux__) || !defined(__x86_64__)
#error "The native Wasm backend currently supports x86-64 Linux"
#endif

// ---- Traps and collection ----

_Noreturn void native_trap(void) {
    fputs("WebAssembly trap\n", stderr);
    exit(1);
}

static uint64_t allocations, collection_interval;

static void *try_allocate(uint64_t size) {
    if (collection_interval && ++allocations % collection_interval == 0) GC_gcollect();
    void *object = GC_malloc(size);
    // Collector callbacks only queue scalar IDs. Calling translated Rust here
    // could reenter a borrowed RefCell, so cleanup waits for a host safepoint.
    GC_invoke_finalizers();
    GC_reachable_here(object);
    return object;
}

uint64_t native_alloc(uint64_t size) {
    void *object = try_allocate(size);
    if (!object) native_trap();
    return (uintptr_t)object;
}

static uint64_t *object_words(uint64_t reference) {
    if (!reference || (reference & 1)) native_trap();
    return (uint64_t *)(uintptr_t)reference;
}

uint32_t native_ref_test(uint64_t reference, int64_t type, uint32_t nullable) {
    if (!reference) return nullable;
    if (type == -1) return (reference & 1) || ((object_words(reference)[0] & 3) != 0);
    if (type == -2) return reference & 1;
    if ((reference & 1) || type == -6) return 0;
    uint64_t actual = object_words(reference)[0];
    if (type >= 0) return actual == (uint64_t)type;
    return (actual & 3) == (type == -3 ? 2 : type == -4 ? 3 : 0);
}

// ---- GC arrays and rooted tables ----

// Every array element has an eight-byte slot. Lengths remain unsigned wasm32.
// Reference slots contain raw BDWGC pointers or odd immediate words; linear
// memory is deliberately not scanned because Rust stores AWI handles there.

uint64_t native_array_new(uint64_t type, uint32_t length, uint64_t initial) {
    uint64_t reference = native_alloc(16 + (uint64_t)length * 8);
    uint64_t *words = object_words(reference);
    words[0] = type;
    words[1] = length;
    for (uint32_t i = 0; i < length; i++) words[i + 2] = initial;
    return reference;
}

uint32_t native_array_length(uint64_t reference) {
    return (uint32_t)object_words(reference)[1];
}

void *native_array_slot(uint64_t reference, uint32_t index) {
    uint64_t *words = object_words(reference);
    if (index >= words[1]) native_trap();
    return &words[2 + (uint64_t)index];
}

void native_array_copy(uint64_t target, uint32_t to, uint64_t source,
                       uint32_t from, uint32_t count) {
    uint64_t *destination = object_words(target), *origin = object_words(source);
    if ((uint64_t)to + count > destination[1] || (uint64_t)from + count > origin[1])
        native_trap();
    memmove(destination + 2 + to, origin + 2 + from, (size_t)count * 8);
}

typedef struct {
    uint64_t *values;
    uint32_t length, maximum;
} NativeTable;

void native_table_init(NativeTable *table, uint32_t length, uint32_t maximum) {
    if (length > maximum) native_trap();
    table->values = (void *)(uintptr_t)native_alloc((uint64_t)length * 8);
    table->length = length;
    table->maximum = maximum;
}

void *native_table_slot(NativeTable *table, uint32_t index) {
    if (index >= table->length) native_trap();
    return &table->values[index];
}

uint32_t native_table_size(NativeTable *table) { return table->length; }

uint32_t native_table_grow(NativeTable *table, uint64_t initial, uint32_t delta) {
    uint32_t old = table->length;
    if (!delta) return old;
    if ((uint64_t)old + delta > table->maximum) return UINT32_MAX;
    uint64_t *values = try_allocate(((uint64_t)old + delta) * 8);
    if (!values) return UINT32_MAX;
    memcpy(values, table->values, (size_t)old * 8);
    for (uint64_t i = old; i < (uint64_t)old + delta; i++) values[i] = initial;
    table->values = values;
    table->length = old + delta;
    return old;
}

// ---- Linear memory ----

// Reserve the complete wasm32 address range once. Growth commits zeroed pages
// without moving addresses held by an active WASI call. Explicit bounds checks
// use the current size; inaccessible reserve pages are an additional backstop.

static uint8_t *memory;
static uint64_t memory_size;
static uint32_t memory_maximum;

void native_memory_init(uint32_t pages, uint32_t maximum) {
    if (memory || maximum > 65536 || pages > maximum) native_trap();
    memory = mmap(NULL, UINT64_C(1) << 32, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (memory == MAP_FAILED) native_trap();
    memory_maximum = maximum;
    memory_size = (uint64_t)pages << 16;
    if (mprotect(memory, memory_size, PROT_READ | PROT_WRITE)) native_trap();
}

void *native_memory_address(uint64_t address, uint64_t size) {
    if (address > memory_size || size > memory_size - address) native_trap();
    return memory + address;
}

uint32_t native_memory_pages(void) { return memory_size >> 16; }

uint32_t native_memory_grow(uint32_t delta) {
    uint32_t old = native_memory_pages();
    if ((uint64_t)old + delta > memory_maximum) return UINT32_MAX;
    uint64_t added = (uint64_t)delta << 16;
    if (added && mprotect(memory + memory_size, added, PROT_READ | PROT_WRITE)) return UINT32_MAX;
    memory_size += added;
    return old;
}

void native_memory_copy(uint32_t target, uint32_t source, uint32_t count) {
    void *to = native_memory_address(target, count);
    void *from = native_memory_address(source, count);
    memmove(to, from, count);
}

void native_memory_fill(uint32_t target, uint32_t value, uint32_t count) {
    memset(native_memory_address(target, count), value, count);
}

// ---- Defined numeric boundaries ----

// LLVM division and float-to-integer conversion are undefined at boundaries
// where Wasm requires a trap. Guard in C before executing the native operation.
#define SIGNED_DIVISION(TYPE, NAME, MINIMUM)                                   \
    TYPE native_##NAME##_div_s(TYPE a, TYPE b) {                              \
        if (!b || (a == MINIMUM && b == -1)) native_trap();                    \
        return a / b;                                                        \
    }                                                                        \
    TYPE native_##NAME##_rem_s(TYPE a, TYPE b) {                              \
        if (!b) native_trap();                                                \
        return (a == MINIMUM && b == -1) ? 0 : a % b;                         \
    }
SIGNED_DIVISION(int32_t, i32, INT32_MIN)
SIGNED_DIVISION(int64_t, i64, INT64_MIN)

#define TRUNCATIONS(FLOAT, SOURCE)                                            \
    int32_t native_i32_trunc_##SOURCE##_s(FLOAT x) {                           \
        double y = trunc((double)x);                                         \
        if (!(y >= -0x1p31 && y < 0x1p31)) native_trap();                     \
        return (int32_t)y;                                                    \
    }                                                                        \
    uint32_t native_i32_trunc_##SOURCE##_u(FLOAT x) {                          \
        double y = trunc((double)x);                                         \
        if (!(y >= 0 && y < 0x1p32)) native_trap();                           \
        return (uint32_t)y;                                                   \
    }                                                                        \
    int64_t native_i64_trunc_##SOURCE##_s(FLOAT x) {                           \
        double y = trunc((double)x);                                         \
        if (!(y >= -0x1p63 && y < 0x1p63)) native_trap();                     \
        return (int64_t)y;                                                    \
    }                                                                        \
    uint64_t native_i64_trunc_##SOURCE##_u(FLOAT x) {                          \
        double y = trunc((double)x);                                         \
        if (!(y >= 0 && y < 0x1p64)) native_trap();                           \
        return (uint64_t)y;                                                   \
    }
TRUNCATIONS(float, f32)
TRUNCATIONS(double, f64)

// ---- AWI finalization ----

extern void drop_resource(uint32_t kind, uint32_t id)
    __asm__("wasm.snail:drop-resource") __attribute__((weak));

typedef struct Resource { uint32_t kind, id; struct Resource *next; } Resource;
static Resource *pending_resources;
static uint64_t finalized_resources;

static void finalize_resource(void *object, void *data) {
    (void)object;
    Resource *resource = data;
    resource->next = pending_resources;
    pending_resources = resource;
}

void native_register_finalizer(uint64_t reference, uint32_t kind, uint32_t id) {
    Resource *resource = malloc(sizeof(Resource)), *old = NULL;
    if (!resource || !drop_resource) native_trap();
    *resource = (Resource){kind, id, NULL};
    // The held data contains only scalar IDs, never the watched wrapper.
    GC_register_finalizer_no_order(object_words(reference), finalize_resource,
                                   resource, NULL, (void **)&old);
    free(old);
}

void native_unregister_finalizer(uint64_t reference) {
    Resource *old = NULL;
    GC_register_finalizer_no_order(object_words(reference), NULL, NULL, NULL, (void **)&old);
    free(old);
}

// Only call this with no active translated Wasm frames. Cleanup may itself
// execute translated Rust; held records never contain the watched object.
void native_poll_finalizers(void) {
    GC_invoke_finalizers();
    Resource *batch = pending_resources;
    pending_resources = NULL;
    while (batch) {
        Resource *resource = batch;
        batch = resource->next;
        drop_resource(resource->kind, resource->id);
        finalized_resources++;
        free(resource);
    }
}

uint64_t native_finalizer_count(void) { return finalized_resources; }

// ---- WASIp1 scalar layouts and errors ----

static void put32(uint32_t address, uint32_t value) {
    memcpy(native_memory_address(address, 4), &value, 4);
}

static void put64(uint32_t address, uint64_t value) {
    memcpy(native_memory_address(address, 8), &value, 8);
}

static uint32_t get32(uint32_t address) {
    uint32_t value;
    memcpy(&value, native_memory_address(address, 4), 4);
    return value;
}

static uint32_t wasi_error(void) {
    switch (errno) {
    case 0: return 0; case EACCES: return 2; case EAGAIN: return 6;
    case EBADF: return 8; case EEXIST: return 20; case EFAULT: return 21;
    case EFBIG: return 22; case EINTR: return 27; case EINVAL: return 28;
    case EIO: return 29; case EISDIR: return 31; case ELOOP: return 32;
    case EMFILE: return 33; case ENAMETOOLONG: return 37; case ENFILE: return 41;
    case ENOENT: return 44; case ENOMEM: return 48; case ENOSPC: return 51;
    case ENOTDIR: return 54; case ENOTEMPTY: return 55; case ENOTSUP: return 58;
    case EOVERFLOW: return 61; case EPERM: return 63; case EPIPE: return 64;
    case EROFS: return 69; case ESPIPE: return 70; default: return 29;
    }
}

static uint8_t wasi_filetype(mode_t mode) {
    if (S_ISDIR(mode)) return 3;
    if (S_ISREG(mode)) return 4;
    if (S_ISCHR(mode)) return 2;
    if (S_ISBLK(mode)) return 1;
    if (S_ISLNK(mode)) return 7;
    if (S_ISSOCK(mode)) return 6;
    return 0;
}

// ---- WASIp1 arguments, environment and clocks ----

extern char **environ;
static char **argument_values;

static uint32_t strings_sizes(char **strings, uint32_t count_at, uint32_t bytes_at) {
    uint64_t count = 0, bytes = 0;
    for (; strings[count]; count++) bytes += strlen(strings[count]) + 1;
    if (count > UINT32_MAX || bytes > UINT32_MAX) return 61;
    put32(count_at, count);
    put32(bytes_at, bytes);
    return 0;
}

static uint32_t strings_copy(char **strings, uint32_t pointers, uint32_t buffer) {
    uint64_t count = 0, bytes = 0;
    for (; strings[count]; count++) bytes += strlen(strings[count]) + 1;
    native_memory_address(pointers, count * 4);
    native_memory_address(buffer, bytes);
    for (uint64_t i = 0; strings[i]; i++) {
        size_t length = strlen(strings[i]) + 1;
        put32(pointers + i * 4, buffer);
        memcpy(native_memory_address(buffer, length), strings[i], length);
        buffer += length;
    }
    return 0;
}

uint32_t wasi_args_sizes_get(uint32_t count, uint32_t bytes) {
    return strings_sizes(argument_values, count, bytes);
}
uint32_t wasi_args_get(uint32_t pointers, uint32_t buffer) {
    return strings_copy(argument_values, pointers, buffer);
}
uint32_t wasi_environ_sizes_get(uint32_t count, uint32_t bytes) {
    return strings_sizes(environ, count, bytes);
}
uint32_t wasi_environ_get(uint32_t pointers, uint32_t buffer) {
    return strings_copy(environ, pointers, buffer);
}

uint32_t wasi_clock_time_get(uint32_t clock, uint64_t precision, uint32_t result) {
    (void)precision;
    clockid_t clocks[] = {CLOCK_REALTIME, CLOCK_MONOTONIC, CLOCK_PROCESS_CPUTIME_ID, CLOCK_THREAD_CPUTIME_ID};
    struct timespec now;
    if (clock >= 4) return 28;
    if (clock_gettime(clocks[clock], &now)) return wasi_error();
    put64(result, (uint64_t)now.tv_sec * 1000000000 + now.tv_nsec);
    return 0;
}

_Noreturn void wasi_proc_exit(uint32_t code) { exit(code & 255); }

// ---- WASIp1 descriptors and preopened directories ----

typedef struct { int host; char *preopen; } Descriptor;
static Descriptor descriptors[4096];
static const uint32_t descriptor_count = sizeof(descriptors) / sizeof(*descriptors);

static int host_fd(uint32_t fd) {
    if (fd >= descriptor_count || descriptors[fd].host < 0) { errno = EBADF; return -1; }
    return descriptors[fd].host;
}

static uint32_t save_fd(int host, char *preopen) {
    for (uint32_t i = 0; i < descriptor_count; i++) {
        if (descriptors[i].host < 0) {
            descriptors[i] = (Descriptor){host, preopen};
            return i;
        }
    }
    close(host);
    return UINT32_MAX;
}

static void preopen(const char *path, const char *name) {
    int fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (fd >= 0) save_fd(fd, strdup(name));
}

static void initialize_descriptors(void) {
    for (uint32_t i = 0; i < descriptor_count; i++) descriptors[i].host = -1;
    for (uint32_t i = 0; i < 3; i++) descriptors[i].host = i;
    char *cwd = getcwd(NULL, 0);
    if (!cwd) native_trap();
    preopen(cwd, ".");
    preopen(cwd, cwd);
    const char *trace = getenv("SNAIL_TRACE_DIR");
    if (trace && *trace) { preopen(trace, trace); }
    free(cwd);
}

uint32_t wasi_fd_close(uint32_t fd) {
    int host = host_fd(fd);
    if (host < 0) return 8;
    if (close(host)) return wasi_error();
    free(descriptors[fd].preopen);
    descriptors[fd] = (Descriptor){-1, NULL};
    return 0;
}

uint32_t wasi_fd_prestat_get(uint32_t fd, uint32_t address) {
    if (host_fd(fd) < 0 || !descriptors[fd].preopen) return 8;
    native_memory_address(address, 8);
    put32(address, 0);
    put32(address + 4, strlen(descriptors[fd].preopen));
    return 0;
}

uint32_t wasi_fd_prestat_dir_name(uint32_t fd, uint32_t address, uint32_t length) {
    if (host_fd(fd) < 0 || !descriptors[fd].preopen) return 8;
    size_t needed = strlen(descriptors[fd].preopen);
    if (length < needed) return 37;
    memcpy(native_memory_address(address, needed), descriptors[fd].preopen, needed);
    return 0;
}

uint32_t wasi_fd_fdstat_get(uint32_t fd, uint32_t address) {
    int host = host_fd(fd), flags;
    struct stat status;
    if (host < 0 || fstat(host, &status)) return wasi_error();
    if ((flags = fcntl(host, F_GETFL)) < 0) return wasi_error();
    memset(native_memory_address(address, 24), 0, 24);
    *(uint8_t *)native_memory_address(address, 1) = wasi_filetype(status.st_mode);
    uint16_t wasi_flags = ((flags & O_APPEND) ? 1 : 0) | ((flags & O_NONBLOCK) ? 4 : 0);
    memcpy(native_memory_address(address + 2, 2), &wasi_flags, 2);
    put64(address + 8, UINT64_C(0x3fffffff));
    put64(address + 16, UINT64_C(0x3fffffff));
    return 0;
}

static void write_filestat(uint32_t address, const struct stat *status) {
    memset(native_memory_address(address, 64), 0, 64);
    put64(address, status->st_dev);
    put64(address + 8, status->st_ino);
    *(uint8_t *)native_memory_address(address + 16, 1) = wasi_filetype(status->st_mode);
    put64(address + 24, status->st_nlink);
    put64(address + 32, status->st_size);
    put64(address + 40, (uint64_t)status->st_atim.tv_sec * 1000000000 + status->st_atim.tv_nsec);
    put64(address + 48, (uint64_t)status->st_mtim.tv_sec * 1000000000 + status->st_mtim.tv_nsec);
    put64(address + 56, (uint64_t)status->st_ctim.tv_sec * 1000000000 + status->st_ctim.tv_nsec);
}

uint32_t wasi_fd_filestat_get(uint32_t fd, uint32_t address) {
    struct stat status;
    int host = host_fd(fd);
    if (host < 0 || fstat(host, &status)) return wasi_error();
    write_filestat(address, &status);
    return 0;
}

uint32_t wasi_fd_seek(uint32_t fd, int64_t offset, uint32_t whence, uint32_t result) {
    if (whence > 2) return 28;
    int host = host_fd(fd);
    if (host < 0) return 8;
    off_t position = lseek(host, offset, whence);
    if (position < 0) return wasi_error();
    put64(result, position);
    return 0;
}

static uint32_t descriptor_io(uint32_t fd, uint32_t vectors, uint32_t count,
                               uint32_t result, bool writing) {
    int host = host_fd(fd);
    uint64_t total = 0;
    if (host < 0) return 8;
    native_memory_address(vectors, (uint64_t)count * 8);
    for (uint32_t i = 0; i < count; i++) {
        uint32_t address = get32(vectors + i * 8), length = get32(vectors + i * 8 + 4);
        void *buffer = native_memory_address(address, length);
        ssize_t done = writing ? write(host, buffer, length) : read(host, buffer, length);
        if (done < 0) { if (!total) return wasi_error(); break; }
        total += done;
        if ((uint64_t)done < length) break;
    }
    put32(result, total);
    return 0;
}

uint32_t wasi_fd_write(uint32_t fd, uint32_t vectors, uint32_t count, uint32_t result) {
    return descriptor_io(fd, vectors, count, result, true);
}
uint32_t wasi_fd_read(uint32_t fd, uint32_t vectors, uint32_t count, uint32_t result) {
    return descriptor_io(fd, vectors, count, result, false);
}

// ---- WASIp1 paths ----

static char *path_string(uint32_t address, uint32_t length) {
    const char *bytes = native_memory_address(address, length);
    if (memchr(bytes, 0, length)) { errno = EINVAL; return NULL; }
    char *path = malloc((size_t)length + 1);
    if (!path) return NULL;
    memcpy(path, bytes, length);
    path[length] = 0;
    return path;
}

static int open_flags(uint32_t lookup, uint32_t oflags, uint64_t rights, uint32_t fdflags) {
    int flags = (rights & 64) ? ((rights & 2) ? O_RDWR : O_WRONLY) : O_RDONLY;
    flags |= ((oflags & 1) ? O_CREAT : 0) | ((oflags & 2) ? O_DIRECTORY : 0);
    flags |= ((oflags & 4) ? O_EXCL : 0) | ((oflags & 8) ? O_TRUNC : 0);
    flags |= ((fdflags & 1) ? O_APPEND : 0) | ((fdflags & 4) ? O_NONBLOCK : 0);
    flags |= ((fdflags & 2) ? O_DSYNC : 0) | ((fdflags & 16) ? O_SYNC : 0);
    return flags | ((lookup & 1) ? 0 : O_NOFOLLOW) | O_CLOEXEC;
}

uint32_t wasi_path_open(uint32_t fd, uint32_t lookup, uint32_t address, uint32_t length,
                        uint32_t oflags, uint64_t rights, uint64_t inheriting,
                        uint32_t fdflags, uint32_t result) {
    (void)inheriting;
    int directory = host_fd(fd);
    if (directory < 0) return 8;
    char *path = path_string(address, length);
    if (!path) return wasi_error();
    int opened = openat(directory, path, open_flags(lookup, oflags, rights, fdflags), 0666);
    free(path);
    if (opened < 0) return wasi_error();
    uint32_t saved = save_fd(opened, NULL);
    if (saved == UINT32_MAX) return 33;
    put32(result, saved);
    return 0;
}

uint32_t wasi_path_create_directory(uint32_t fd, uint32_t address, uint32_t length) {
    int directory = host_fd(fd);
    if (directory < 0) return 8;
    char *path = path_string(address, length);
    if (!path) return wasi_error();
    int status = mkdirat(directory, path, 0777);
    free(path);
    return status ? wasi_error() : 0;
}

uint32_t wasi_path_filestat_get(uint32_t fd, uint32_t flags, uint32_t address,
                                uint32_t length, uint32_t result) {
    int directory = host_fd(fd);
    if (directory < 0) return 8;
    char *path = path_string(address, length);
    struct stat status;
    if (!path) return wasi_error();
    int code = fstatat(directory, path, &status, (flags & 1) ? 0 : AT_SYMLINK_NOFOLLOW);
    free(path);
    if (code) return wasi_error();
    write_filestat(result, &status);
    return 0;
}

// ---- Process initialization ----

extern void native_module_init(void);
extern void module_start(void) __asm__("wasm._start");

void native_host_init(int argc, char **argv) {
    (void)argc;
    argument_values = argv;
    GC_set_all_interior_pointers(1);
    GC_set_finalize_on_demand(1);
    GC_INIT();
    const char *interval = getenv("SNAIL_NATIVE_GC_INTERVAL");
    if (interval) collection_interval = strtoull(interval, NULL, 10);
    initialize_descriptors();
}

#ifndef SNAIL_NATIVE_LIBRARY
int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    module_start();
    native_poll_finalizers();
    return 0;
}
#endif
