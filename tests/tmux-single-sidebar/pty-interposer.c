#define _GNU_SOURCE

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/uio.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

static int log_fd = -1;
static ssize_t (*next_read)(int, void *, size_t);
static ssize_t (*next_write)(int, const void *, size_t);
static ssize_t (*next_readv)(int, const struct iovec *, int);
static ssize_t (*next_writev)(int, const struct iovec *, int);
static ssize_t (*next_recv)(int, void *, size_t, int);
static ssize_t (*next_send)(int, const void *, size_t, int);
static ssize_t (*next_recvmsg)(int, struct msghdr *, int);
static ssize_t (*next_sendmsg)(int, const struct msghdr *, int);
static int (*next_poll)(struct pollfd *, nfds_t, int);
static int (*next_ioctl)(int, unsigned long, void *);
static int (*next_fcntl)(int, int, ...);
static int (*next_tcgetattr)(int, struct termios *);
static int (*next_tcsetattr)(int, int, const struct termios *);

static void resolve_symbols(void)
{
    next_read = dlsym(RTLD_NEXT, "read");
    next_write = dlsym(RTLD_NEXT, "write");
    next_readv = dlsym(RTLD_NEXT, "readv");
    next_writev = dlsym(RTLD_NEXT, "writev");
    next_recv = dlsym(RTLD_NEXT, "recv");
    next_send = dlsym(RTLD_NEXT, "send");
    next_recvmsg = dlsym(RTLD_NEXT, "recvmsg");
    next_sendmsg = dlsym(RTLD_NEXT, "sendmsg");
    next_poll = dlsym(RTLD_NEXT, "poll");
    next_ioctl = dlsym(RTLD_NEXT, "ioctl");
    next_fcntl = dlsym(RTLD_NEXT, "fcntl");
    next_tcgetattr = dlsym(RTLD_NEXT, "tcgetattr");
    next_tcsetattr = dlsym(RTLD_NEXT, "tcsetattr");
}

static void trace_line(const char *format, ...)
{
    char body[1024];
    char line[1200];
    struct timespec now;
    va_list args;
    int length;

    if (log_fd < 0)
        return;
    clock_gettime(CLOCK_MONOTONIC, &now);
    va_start(args, format);
    length = vsnprintf(body, sizeof(body), format, args);
    va_end(args);
    if (length < 0)
        return;
    length = snprintf(line, sizeof(line), "%lld.%09ld pid=%ld %s\n",
        (long long)now.tv_sec, now.tv_nsec, (long)getpid(), body);
    if (length > 0)
        (void)syscall(SYS_write, log_fd, line, (size_t)length);
}

static void trace_fd_identity(int fd)
{
    char path[64];
    char target[256];
    int length;
    ssize_t result;

    length = snprintf(path, sizeof(path), "/proc/self/fd/%d", fd);
    if (length < 0 || (size_t)length >= sizeof(path))
        return;
    result = syscall(SYS_readlinkat, AT_FDCWD, path, target, sizeof(target) - 1);
    if (result < 0)
        return;
    target[result] = '\0';
    trace_line("fd.identity fd=%d target=%s", fd, target);
}

static void trace_bytes(const char *event, int fd, ssize_t result,
    const unsigned char *bytes)
{
    char hex[129];
    size_t index;
    size_t limit = result > 0 && result < 64 ? (size_t)result : 0;

    for (index = 0; index < limit; index++)
        snprintf(hex + index * 2, sizeof(hex) - index * 2, "%02x", bytes[index]);
    hex[limit * 2] = '\0';
    trace_line("%s fd=%d result=%zd hex=%s", event, fd, result, hex);
}

__attribute__((constructor)) static void interposer_init(void)
{
    const char *path = getenv("TMUX_KEYBOARD_INTERPOSER_LOG");

    resolve_symbols();
    if (path)
        log_fd = (int)syscall(SYS_openat, AT_FDCWD, path,
            O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0600);
    trace_line("process.start stdin_tty=%d stdout_tty=%d stderr_tty=%d",
        isatty(STDIN_FILENO), isatty(STDOUT_FILENO), isatty(STDERR_FILENO));
}

ssize_t read(int fd, void *buffer, size_t length)
{
    ssize_t result = next_read(fd, buffer, length);

    if (result <= 0 || result <= 64)
        trace_bytes("read", fd, result, buffer);
    else
        trace_line("read fd=%d result=%zd requested=%zu", fd, result, length);
    return result;
}

ssize_t write(int fd, const void *buffer, size_t length)
{
    ssize_t result = next_write(fd, buffer, length);

    if (length <= 64 || result < 0)
        trace_bytes("write", fd, result, buffer);
    else
        trace_line("write fd=%d result=%zd requested=%zu", fd, result, length);
    return result;
}

ssize_t readv(int fd, const struct iovec *iov, int count)
{
    ssize_t result = next_readv(fd, iov, count);

    trace_line("readv fd=%d iovcnt=%d result=%zd errno=%d", fd, count, result,
        result < 0 ? errno : 0);
    return result;
}

ssize_t writev(int fd, const struct iovec *iov, int count)
{
    ssize_t result = next_writev(fd, iov, count);

    trace_line("writev fd=%d iovcnt=%d result=%zd errno=%d", fd, count, result,
        result < 0 ? errno : 0);
    return result;
}

ssize_t recv(int fd, void *buffer, size_t length, int flags)
{
    ssize_t result = next_recv(fd, buffer, length, flags);

    if (result <= 64)
        trace_bytes("recv", fd, result, buffer);
    else
        trace_line("recv fd=%d result=%zd requested=%zu flags=0x%x", fd, result,
            length, flags);
    return result;
}

ssize_t send(int fd, const void *buffer, size_t length, int flags)
{
    ssize_t result = next_send(fd, buffer, length, flags);

    if (length <= 64 || result < 0)
        trace_bytes("send", fd, result, buffer);
    else
        trace_line("send fd=%d result=%zd requested=%zu flags=0x%x", fd, result,
            length, flags);
    return result;
}

ssize_t recvmsg(int fd, struct msghdr *message, int flags)
{
    ssize_t result = next_recvmsg(fd, message, flags);

    trace_line("recvmsg fd=%d result=%zd flags=0x%x errno=%d", fd, result,
        flags, result < 0 ? errno : 0);
    return result;
}

ssize_t sendmsg(int fd, const struct msghdr *message, int flags)
{
    ssize_t result = next_sendmsg(fd, message, flags);

    trace_line("sendmsg fd=%d result=%zd flags=0x%x errno=%d", fd, result,
        flags, result < 0 ? errno : 0);
    return result;
}

int poll(struct pollfd *fds, nfds_t count, int timeout)
{
    int result = next_poll(fds, count, timeout);
    nfds_t index;

    trace_line("poll count=%lu timeout=%d result=%d", (unsigned long)count,
        timeout, result);
    for (index = 0; index < count && index < 8; index++)
        trace_line("poll.fd index=%lu fd=%d events=0x%x revents=0x%x",
            (unsigned long)index, fds[index].fd, fds[index].events,
            fds[index].revents);
    for (index = 0; index < count && index < 8; index++)
        trace_fd_identity(fds[index].fd);
    return result;
}

int ioctl(int fd, unsigned long request, ...)
{
    va_list args;
    void *argument;
    int result;

    va_start(args, request);
    argument = va_arg(args, void *);
    va_end(args);
    result = next_ioctl(fd, request, argument);
    trace_line("ioctl fd=%d request=0x%lx result=%d errno=%d", fd, request,
        result, result < 0 ? errno : 0);
    return result;
}

int fcntl(int fd, int command, ...)
{
    va_list args;
    long argument = 0;
    int result;

    va_start(args, command);
    if (command != F_GETFD && command != F_GETFL)
        argument = va_arg(args, long);
    va_end(args);
    result = next_fcntl(fd, command, argument);
    if (command == F_GETFD || command == F_GETFL || result < 0)
        trace_line("fcntl fd=%d command=%d argument=%ld result=%d errno=%d",
            fd, command, argument, result, result < 0 ? errno : 0);
    return result;
}

int tcgetattr(int fd, struct termios *term)
{
    int result = next_tcgetattr(fd, term);

    trace_line("tcgetattr fd=%d result=%d errno=%d", fd, result,
        result < 0 ? errno : 0);
    if (result == 0)
        trace_line("termios fd=%d iflag=0x%lx oflag=0x%lx cflag=0x%lx lflag=0x%lx vmin=%d vtime=%d",
            fd, (unsigned long)term->c_iflag, (unsigned long)term->c_oflag,
            (unsigned long)term->c_cflag, (unsigned long)term->c_lflag,
            term->c_cc[VMIN], term->c_cc[VTIME]);
    return result;
}

int tcsetattr(int fd, int action, const struct termios *term)
{
    int result = next_tcsetattr(fd, action, term);

    trace_line("tcsetattr fd=%d action=%d result=%d errno=%d iflag=0x%lx oflag=0x%lx cflag=0x%lx lflag=0x%lx vmin=%d vtime=%d",
        fd, action, result, result < 0 ? errno : 0,
        (unsigned long)term->c_iflag, (unsigned long)term->c_oflag,
        (unsigned long)term->c_cflag, (unsigned long)term->c_lflag,
        term->c_cc[VMIN], term->c_cc[VTIME]);
    return result;
}
