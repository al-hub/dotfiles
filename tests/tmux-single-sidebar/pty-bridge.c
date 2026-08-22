#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pty.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

static pid_t child_pid = -1;
static int trace_fd = -1;
static volatile sig_atomic_t pending_signal = 0;

static void trace_line(const char *format, ...)
{
    char buffer[4096];
    char line[4608];
    struct timespec now;
    va_list args;
    int length;

    if (trace_fd < 0)
        return;
    clock_gettime(CLOCK_MONOTONIC, &now);
    va_start(args, format);
    length = vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    if (length < 0)
        return;
    length = snprintf(line, sizeof(line), "%lld.%09ld %s\n",
        (long long)now.tv_sec, now.tv_nsec, buffer);
    if (length > 0)
        (void)!write(trace_fd, line, (size_t)length);
}

static void trace_bytes(const char *event, const unsigned char *bytes, size_t length)
{
    char hex[4096];
    size_t offset = 0;
    size_t index;

    for (index = 0; index < length && offset + 3 < sizeof(hex); index++) {
        int written = snprintf(hex + offset, sizeof(hex) - offset, "%02x", bytes[index]);
        if (written < 0)
            return;
        offset += (size_t)written;
    }
    hex[offset] = '\0';
    trace_line("%s length=%zu hex=%s", event, length, hex);
}

static void trace_fd_state(const char *label, int fd)
{
    int flags;
    struct termios term;

    flags = fcntl(fd, F_GETFL);
    if (flags < 0)
        trace_line("fd.state label=%s fd=%d flags=error errno=%d", label, fd, errno);
    else
        trace_line("fd.state label=%s fd=%d flags=0x%x nonblock=%d", label, fd,
            flags, !!(flags & O_NONBLOCK));

    if (tcgetattr(fd, &term) < 0) {
        trace_line("termios label=%s fd=%d result=error errno=%d", label, fd, errno);
        return;
    }
    trace_line("termios label=%s fd=%d iflag=0x%lx oflag=0x%lx cflag=0x%lx lflag=0x%lx vmin=%d vtime=%d",
        label, fd, (unsigned long)term.c_iflag, (unsigned long)term.c_oflag,
        (unsigned long)term.c_cflag, (unsigned long)term.c_lflag,
        term.c_cc[VMIN], term.c_cc[VTIME]);
}

static void trace_window(const char *label, int fd)
{
    struct winsize window;

    if (ioctl(fd, TIOCGWINSZ, &window) < 0) {
        trace_line("window label=%s fd=%d result=error errno=%d", label, fd, errno);
        return;
    }
    trace_line("window label=%s fd=%d rows=%d cols=%d xpixel=%d ypixel=%d",
        label, fd, window.ws_row, window.ws_col, window.ws_xpixel, window.ws_ypixel);
}

static int write_all(int fd, const unsigned char *bytes, size_t length)
{
    size_t written = 0;
    while (written < length) {
        ssize_t result = write(fd, bytes + written, length - written);
        if (result < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        written += (size_t)result;
    }
    return 0;
}

static void stop_child(int signal_number)
{
    pending_signal = signal_number;
    if (child_pid > 0)
        kill(child_pid, SIGHUP);
}

static void note_only_signal(int signal_number)
{
    pending_signal = signal_number;
}

static void note_signal(void)
{
    if (pending_signal != 0) {
        trace_line("signal.pending number=%d", pending_signal);
        pending_signal = 0;
    }
}

static void usage(const char *program)
{
    fprintf(stderr, "usage: %s --log FILE --output FILE -- COMMAND [ARGS...]\n", program);
}

int main(int argc, char **argv)
{
    const char *log_path = NULL;
    const char *output_path = NULL;
    int command_index = -1;
    int master_fd = -1;
    int output_fd = -1;
    struct winsize window = { .ws_row = 24, .ws_col = 80 };
    unsigned char bytes[4096];
    int index;

    for (index = 1; index < argc; index++) {
        if (!strcmp(argv[index], "--log") && index + 1 < argc)
            log_path = argv[++index];
        else if (!strcmp(argv[index], "--output") && index + 1 < argc)
            output_path = argv[++index];
        else if (!strcmp(argv[index], "--")) {
            command_index = index + 1;
            break;
        } else {
            usage(argv[0]);
            return 2;
        }
    }
    if (!log_path || !output_path || command_index < 0 || command_index >= argc) {
        usage(argv[0]);
        return 2;
    }

    trace_fd = open(log_path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0600);
    output_fd = open(output_path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0600);
    if (trace_fd < 0 || output_fd < 0) {
        perror("pty-bridge open");
        return 1;
    }

    child_pid = forkpty(&master_fd, NULL, NULL, &window);
    if (child_pid < 0) {
        perror("pty-bridge forkpty");
        return 1;
    }
    if (child_pid == 0) {
        execvp(argv[command_index], &argv[command_index]);
        perror("pty-bridge exec");
        _exit(127);
    }

    signal(SIGTERM, stop_child);
    signal(SIGINT, stop_child);
    signal(SIGHUP, stop_child);
    signal(SIGWINCH, note_only_signal);
    trace_line("child.start pid=%ld master_fd=%d", (long)child_pid, master_fd);
    trace_fd_state("stdin.initial", STDIN_FILENO);
    trace_fd_state("pty.initial", master_fd);
    trace_window("stdin.initial", STDIN_FILENO);
    trace_window("pty.initial", master_fd);

    for (;;) {
        struct pollfd fds[2];
        int poll_result;

        fds[0].fd = STDIN_FILENO;
        fds[0].events = POLLIN;
        fds[1].fd = master_fd;
        fds[1].events = POLLIN;
        poll_result = poll(fds, 2, 1000);
        note_signal();
        if (poll_result < 0) {
            if (errno == EINTR)
                continue;
            trace_line("poll.error errno=%d", errno);
            break;
        }
        if (poll_result == 0) {
            trace_line("poll.timeout");
            int status;
            if (waitpid(child_pid, &status, WNOHANG) == child_pid)
                break;
            continue;
        }
        trace_line("poll.result count=%d stdin_revents=0x%x pty_revents=0x%x",
            poll_result, fds[0].revents, fds[1].revents);

        if (fds[0].revents & (POLLIN | POLLHUP)) {
            ssize_t length = read(STDIN_FILENO, bytes, sizeof(bytes));
            if (length > 0) {
                trace_fd_state("stdin.before-read", STDIN_FILENO);
                trace_bytes("stdin.read", bytes, (size_t)length);
                if (write_all(master_fd, bytes, (size_t)length) < 0)
                    trace_line("pty.write.error errno=%d", errno);
                else
                    trace_bytes("pty.write", bytes, (size_t)length);
            } else if (length == 0) {
                trace_line("stdin.eof");
                break;
            } else
                trace_line("stdin.read.error errno=%d", errno);
        }

        if (fds[1].revents & (POLLIN | POLLHUP | POLLERR)) {
            ssize_t length = read(master_fd, bytes, sizeof(bytes));
            if (length > 0) {
                trace_bytes("pty.read", bytes, (size_t)length);
                if (write_all(output_fd, bytes, (size_t)length) < 0)
                    trace_line("stdout.write.error errno=%d", errno);
            } else {
                trace_line("pty.read.end result=%s errno=%d",
                    length == 0 ? "eof" : "error", errno);
                break;
            }
        }
    }

    close(master_fd);
    close(output_fd);
    if (child_pid > 0) {
        int status;
        if (waitpid(child_pid, &status, 0) == child_pid) {
            if (WIFEXITED(status))
                trace_line("child.exit status=%d", WEXITSTATUS(status));
            else if (WIFSIGNALED(status))
                trace_line("child.signal signal=%d", WTERMSIG(status));
        }
    }
    close(trace_fd);
    return 0;
}
