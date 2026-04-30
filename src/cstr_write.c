#define _GNU_SOURCE
#include <unistd.h>
#include <string.h>
#include <time.h>
#include <pthread.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/wait.h>

int cstr_write(int fd, const char *s) {
    return (int)write(fd, s, strlen(s));
}

const char *cstr_timestamp() {
    static char buf[64];
    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", tm_info);
    return buf;
}

/*
 * spawn_child: fork + exec a shell command with stdout/stderr redirected
 * to a pipe. All fd setup happens in C using ONLY async-signal-safe
 * functions (no malloc, no opendir, no snprintf, etc.).
 *
 * This avoids deadlock in multi-threaded Chez processes, where forked
 * children inherit locked mutexes from other threads.
 *
 * Args:
 *   cmd     - the full command string passed to sh -c (including timeout)
 *   fds_out - int[2] output: [readFd, childPid]
 *   flags   - pipe flags (e.g., O_CLOEXEC)
 *
 * Returns 0 on success, -1 on error.
 */
int spawn_child(const char *cmd, int *fds_out, int flags) {
    int pipefd[2];
    if (pipe2(pipefd, flags) < 0) {
        return -1;
    }

    pid_t pid = fork();
    if (pid < 0) {
        close(pipefd[0]);
        close(pipefd[1]);
        return -1;
    }

    if (pid == 0) {
        /* Child: ONLY async-signal-safe functions here! */
        close(pipefd[0]);

        if (dup2(pipefd[1], 1) < 0) _exit(126);
        if (dup2(pipefd[1], 2) < 0) _exit(126);
        close(pipefd[1]);

        /* Close all fds >= 3 using only close() - async-signal-safe */
        for (int fd = 3; fd < 1024; fd++) {
            close(fd);
        }

        /* Redirect stdin from /dev/null */
        int devnull = open("/dev/null", O_RDONLY);
        if (devnull >= 0) {
            if (devnull != 0) {
                dup2(devnull, 0);
                close(devnull);
            }
        }

        execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
        _exit(127);
    }

    /* Parent */
    close(pipefd[1]);
    fds_out[0] = pipefd[0];
    fds_out[1] = (int)pid;
    return 0;
}

/*
 * Legacy wrappers for pipe/close operations.
 */

int pipe_track(void *fds) {
    int *fd_arr = (int *)fds;
    return pipe(fd_arr);
}

int pipe2_track(void *fds, int flags) {
    int *fd_arr = (int *)fds;
    return pipe2(fd_arr, flags);
}

int close_track(int fd) {
    return close(fd);
}
