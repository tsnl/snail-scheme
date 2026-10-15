// One supervisor owns one native instance and its process group. The guest's
// existing global collector and globals therefore belong to exactly one instance.
#define _GNU_SOURCE
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#ifndef SFIR_NATIVE_SUPERVISOR
extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void initialize(void) __asm__("wasm.main");
extern const uint64_t sfir_native_arity;
extern uint64_t sfir_native_entry(const uint64_t *);

// ---- Exact scalar messages on dedicated descriptors ----

static int read_exact(int fd, void *buffer, size_t size) {
    uint8_t *bytes = buffer;
    while (size) {
        ssize_t count = read(fd, bytes, size);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return 0;
        bytes += count;
        size -= (size_t)count;
    }
    return 1;
}

static int write_word(int fd, uint64_t word) {
    // Supported target is little-endian x86-64 Linux; there is no text float
    // conversion and no rounding of I64 through a floating representation.
    const uint8_t *bytes = (const uint8_t *)&word;
    size_t size = sizeof(word);
    while (size) {
        ssize_t count = write(fd, bytes, size);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return 0;
        bytes += count;
        size -= (size_t)count;
    }
    return 1;
}

static int guest(int request, int response, int argc, char **argv) {
    uint64_t *arguments = calloc(sfir_native_arity ? sfir_native_arity : 1, sizeof(uint64_t));
    if (!arguments) return 1;
    native_host_init(argc, argv);
    native_module_init();
    initialize();
    if (!write_word(response, UINT64_C(0x3152494653))) return native_finish(1);
    uint8_t command;
    while (read_exact(request, &command, 1) && command) {
        if (command != 1 || !read_exact(request, arguments, sfir_native_arity * 8)) break;
        if (!write_word(response, sfir_native_entry(arguments))) break;
    }
    free(arguments);
    return native_finish(0);
}

int main(int argc, char **argv) {
    if (argc != 5 || sfir_native_arity != strtoull(argv[4], NULL, 10)) return 1;
    return guest(atoi(argv[1]), atoi(argv[2]), argc, argv);
}

#else

// ---- Owned process lifetime ----

// The supervisor links no guest or provider code: constructors must execute
// only after ownership is established and the worker image is exec'd. It
// becomes a subreaper so a provider's orphaned descendants can be killed and
// reaped. Providers are
// trusted code: deliberately escaping the owned process group is unsupported.
static volatile sig_atomic_t stopped;
static void stop(int signal_number) { (void)signal_number; stopped = 1; }

static int own_lifetime(pid_t parent) {
    struct sigaction action = {.sa_handler = stop};
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGTERM, &action, NULL) || sigaction(SIGINT, &action, NULL)) return 0;
    if (signal(SIGCHLD, SIG_DFL) == SIG_ERR) return 0;
    if (prctl(PR_SET_CHILD_SUBREAPER, 1) || prctl(PR_SET_PDEATHSIG, SIGTERM)) return 0;
    // Covers host death between spawning us and installing PDEATHSIG.
    if (getppid() != parent) stopped = 1;
    return 1;
}

static int supervise(pid_t child) {
    int status = 0, grace_ticks = -1;
    siginfo_t information;
    struct timespec interval = {.tv_nsec = 10000000};
    for (;;) {
        int waited = waitid(P_PID, child, &information, WEXITED | WNOHANG | WNOWAIT);
        if (!waited && information.si_pid == child) break;
        if (waited < 0 && errno != EINTR) break;
        if (stopped && grace_ticks < 0) { kill(-child, SIGTERM); grace_ticks = 100; }
        if (grace_ticks > 0 && --grace_ticks == 0) kill(-child, SIGKILL);
        nanosleep(&interval, NULL);
    }
    // The unreaped leader reserves the group identity through the final signal.
    kill(-child, SIGKILL);
    while (waitpid(child, &status, 0) < 0 && errno == EINTR) {}
    while (waitpid(-1, NULL, 0) >= 0 || errno == EINTR) {}
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}

int main(int argc, char **argv) {
    if (argc != 6 || !own_lifetime((pid_t)strtol(argv[4], NULL, 10)) || stopped) return 1;
    int request = atoi(argv[2]), response = atoi(argv[3]);
    pid_t parent = getpid(), child = fork();
    if (child < 0) return 1;
    if (!child) {
        signal(SIGTERM, SIG_DFL); signal(SIGINT, SIG_DFL); signal(SIGPIPE, SIG_IGN);
        if (setpgid(0, 0) || prctl(PR_SET_PDEATHSIG, SIGKILL) || getppid() != parent) return 1;
        execv(argv[1], argv + 1);
        return 1;
    }
    setpgid(child, child);
    close(request);
    if (response != request) close(response);
    return supervise(child);
}
#endif
