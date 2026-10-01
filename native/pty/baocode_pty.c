// The native half of the pseudo terminal on macOS and Linux, bound by
// lib/ide/terminal/pty_native.dart and built by hook/build.dart.
//
// Dart cannot fork: only the forking thread goes on in the child, where no
// Dart may run. So the fork is here, and the child makes only
// async-signal-safe calls up to execve. The rest takes structs or errno,
// which Dart's FFI does not reach well.

#if defined(__linux__)
#define _GNU_SOURCE
#endif

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <sys/event.h>
#else
#include <sys/syscall.h>
#endif

#define EXPORT __attribute__((visibility("default"))) __attribute__((used))

// What baocode_pty_poll found ready.
enum { kOutput = 1, kExited = 2, kWoken = 4 };

// Where baocode_pty_spawn failed.
enum { kStageSetup = 0, kStageDirectory = 1, kStageExec = 2 };

// Closing every descriptor the app might have open is a loop up to here at
// most.
enum { kMaxDescriptors = 65536 };

static int cloexec_pipe(int fds[2]) {
#if defined(__linux__)
  return pipe2(fds, O_CLOEXEC);
#else
  // macOS has no pipe2: flagged right after, which leaves a moment for a
  // fork elsewhere in the app to inherit them.
  if (pipe(fds) == -1) return -1;
  for (int i = 0; i < 2; i++) {
    int flags = fcntl(fds[i], F_GETFD);
    if (flags != -1) fcntl(fds[i], F_SETFD, flags | FD_CLOEXEC);
  }
  return 0;
#endif
}

static int slave_name(int master, char *name, size_t size) {
#if defined(__APPLE__)
  char buffer[128];  // TIOCPTYGNAME's size.
  if (ioctl(master, TIOCPTYGNAME, buffer) == -1) return -1;
  size_t length = strnlen(buffer, sizeof buffer);
  if (length >= size) {
    errno = ENAMETOOLONG;
    return -1;
  }
  memcpy(name, buffer, length + 1);
  return 0;
#else
  int error = ptsname_r(master, name, size);
  if (error != 0) {
    errno = error;
    return -1;
  }
  return 0;
#endif
}

// The terminal settings node-pty starts with (BSD's ttydefaults), in UTF-8.
static void terminal_defaults(struct termios *t) {
  memset(t, 0, sizeof *t);
  t->c_iflag = ICRNL | IXON | IXANY | IMAXBEL | BRKINT;
#if defined(IUTF8)
  t->c_iflag |= IUTF8;
#endif
  t->c_oflag = OPOST | ONLCR;
  t->c_cflag = CREAD | CS8 | HUPCL;
  t->c_lflag = ICANON | ISIG | IEXTEN | ECHO | ECHOE | ECHOK | ECHOKE | ECHOCTL;
  t->c_cc[VEOF] = 4;
  t->c_cc[VEOL] = _POSIX_VDISABLE;
  t->c_cc[VEOL2] = _POSIX_VDISABLE;
  t->c_cc[VERASE] = 0x7f;
  t->c_cc[VWERASE] = 23;
  t->c_cc[VKILL] = 21;
  t->c_cc[VREPRINT] = 18;
  t->c_cc[VINTR] = 3;
  t->c_cc[VQUIT] = 0x1c;
  t->c_cc[VSUSP] = 26;
  t->c_cc[VSTART] = 17;
  t->c_cc[VSTOP] = 19;
  t->c_cc[VLNEXT] = 22;
  t->c_cc[VDISCARD] = 15;
  t->c_cc[VMIN] = 1;
  t->c_cc[VTIME] = 0;
#if defined(__APPLE__)
  t->c_cc[VDSUSP] = 25;
  t->c_cc[VSTATUS] = 20;
#endif
  cfsetispeed(t, B38400);
  cfsetospeed(t, B38400);
}

static int descriptor_limit(void) {
  struct rlimit limit;
  if (getrlimit(RLIMIT_NOFILE, &limit) == 0 && limit.rlim_cur != RLIM_INFINITY &&
      limit.rlim_cur < kMaxDescriptors) {
    return (int)limit.rlim_cur;
  }
  return kMaxDescriptors;
}

// A descriptor that turns readable once `pid` exits, or -1: a kqueue on
// macOS, a pidfd on Linux.
static int watch_exit(pid_t pid) {
#if defined(__APPLE__)
  int queue = kqueue();
  if (queue == -1) return -1;
  struct kevent change;
  EV_SET(&change, pid, EVFILT_PROC, EV_ADD | EV_ONESHOT,
         NOTE_EXIT | NOTE_EXITSTATUS, 0, NULL);
  if (kevent(queue, &change, 1, NULL, 0, NULL) == -1) {
    close(queue);
    return -1;
  }
  return queue;
#elif defined(SYS_pidfd_open)
  return (int)syscall(SYS_pidfd_open, pid, 0);
#else
  (void)pid;
  return -1;
#endif
}

static int decode_status(int status) {
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  if (WIFSIGNALED(status)) return -WTERMSIG(status);
  return 0;
}

// In the child, from here on: async-signal-safe calls only.

static void __attribute__((noreturn)) child_fail(int report, int stage) {
  int message[2] = {stage, errno};
  ssize_t ignored = write(report, message, sizeof message);
  (void)ignored;
  _exit(127);
}

static void close_descriptors(int keep, int limit) {
#if defined(__linux__) && defined(SYS_close_range)
  if ((keep == 3 || syscall(SYS_close_range, 3, keep - 1, 0) == 0) &&
      syscall(SYS_close_range, keep + 1, ~0U, 0) == 0) {
    return;
  }
#endif
  for (int fd = 3; fd < limit; fd++) {
    if (fd != keep) close(fd);
  }
}

static void __attribute__((noreturn)) run_child(
    int slave, const int go[2], int report, int limit, const char *path,
    char *const argv[], char *const envp[], const char *cwd) {
  // The app's signal handling is not the shell's: Dart ignores SIGPIPE, and
  // an ignored signal stays ignored across execve.
  struct sigaction action;
  memset(&action, 0, sizeof action);
  action.sa_handler = SIG_DFL;
  sigemptyset(&action.sa_mask);
  for (int number = 1; number < NSIG; number++) sigaction(number, &action, NULL);
  sigset_t none;
  sigemptyset(&none);
  sigprocmask(SIG_SETMASK, &none, NULL);

  // Held until the parent watches for this process's exit: its closing
  // the pipe, once this copy of the write end is closed too.
  close(go[1]);
  char byte;
  while (read(go[0], &byte, 1) == -1 && errno == EINTR) {
  }

  if (setsid() == -1 || ioctl(slave, TIOCSCTTY, 0) == -1) {
    child_fail(report, kStageSetup);
  }
  for (int fd = 0; fd <= 2; fd++) {
    int result = slave == fd ? fcntl(fd, F_SETFD, 0) : dup2(slave, fd);
    if (result == -1) child_fail(report, kStageSetup);
  }
  if (cwd != NULL && cwd[0] != '\0' && chdir(cwd) == -1) {
    child_fail(report, kStageDirectory);
  }
  // Only the terminal goes to the child: any of the app's descriptors
  // without close-on-exec (another terminal's master side among them) would
  // otherwise stay open in it.
  close_descriptors(report, limit);
  execve(path, argv, envp);
  child_fail(report, kStageExec);
}

// Starts `path` with `argv` and `envp` (both NULL-terminated) in `cwd`, on
// a new pseudo terminal of `columns` by `rows`, as a session leader with the
// terminal as its controlling one.
//
// Returns the child's pid, and sets `*master` (non-blocking) and
// `*exit_fd` (see watch_exit). On failure returns -errno and sets `*stage`.
EXPORT int baocode_pty_spawn(const char *path, char *const argv[],
                           char *const envp[], const char *cwd, int columns,
                           int rows, int *master, int *exit_fd, int *stage) {
  int pty = -1, slave = -1, watcher = -1;
  int go[2] = {-1, -1}, report[2] = {-1, -1};
  char name[128];
  struct termios settings;
  struct winsize size;
  sigset_t all, previous;
  pid_t pid;
  int message[2];
  ssize_t got;
  int error, limit;

  *stage = kStageSetup;
  pty = open("/dev/ptmx", O_RDWR | O_NOCTTY | O_CLOEXEC);
  if (pty == -1 || grantpt(pty) == -1 || unlockpt(pty) == -1 ||
      slave_name(pty, name, sizeof name) == -1) {
    goto fail;
  }
  slave = open(name, O_RDWR | O_NOCTTY | O_CLOEXEC);
  if (slave == -1) goto fail;
  terminal_defaults(&settings);
  memset(&size, 0, sizeof size);
  size.ws_col = (unsigned short)columns;
  size.ws_row = (unsigned short)rows;
  if (tcsetattr(slave, TCSANOW, &settings) == -1 ||
      ioctl(slave, TIOCSWINSZ, &size) == -1) {
    goto fail;
  }
  if (cloexec_pipe(go) == -1 || cloexec_pipe(report) == -1) goto fail;
  limit = descriptor_limit();

  // No signal handler of the app's may run in the child.
  sigfillset(&all);
  pthread_sigmask(SIG_SETMASK, &all, &previous);
  pid = fork();
  if (pid == 0) {
    run_child(slave, go, report[1], limit, path, argv, envp, cwd);
  }
  error = errno;
  pthread_sigmask(SIG_SETMASK, &previous, NULL);
  if (pid == -1) {
    errno = error;
    goto fail;
  }

  close(slave);
  close(go[0]);
  close(report[1]);
  slave = go[0] = report[1] = -1;
  // Watched before it may run (and end): Dart reaps any child while it has
  // processes of its own running, and the kqueue still has the status then.
  watcher = watch_exit(pid);
  close(go[1]);
  go[1] = -1;

  // The report pipe closes on a successful execve; a failure writes to it.
  got = 0;
  while (got < (ssize_t)sizeof message) {
    ssize_t count = read(report[0], (char *)message + got, sizeof message - got);
    if (count == -1 && errno == EINTR) continue;
    if (count <= 0) break;
    got += count;
  }
  close(report[0]);
  report[0] = -1;
  if (got == (ssize_t)sizeof message) {
    int status;
    while (waitpid(pid, &status, 0) == -1 && errno == EINTR) {
    }
    if (watcher != -1) close(watcher);
    close(pty);
    *stage = message[0];
    return -message[1];
  }

  fcntl(pty, F_SETFL, fcntl(pty, F_GETFL) | O_NONBLOCK);
  *master = pty;
  *exit_fd = watcher;
  return pid;

fail:
  error = errno;
  if (pty != -1) close(pty);
  if (slave != -1) close(slave);
  for (int i = 0; i < 2; i++) {
    if (go[i] != -1) close(go[i]);
    if (report[i] != -1) close(report[i]);
  }
  return -error;
}

// Waits up to `timeout` ms (-1: no limit) for output on `master`, the exit
// of the child (`exit_fd`), or a byte on `wake`; a negative descriptor is
// not waited for. Returns what is ready (kOutput, kExited, kWoken), or
// -errno.
EXPORT int baocode_pty_poll(int master, int exit_fd, int wake, int timeout) {
  struct pollfd fds[3] = {
      {.fd = master, .events = POLLIN},
      {.fd = exit_fd, .events = POLLIN},
      {.fd = wake, .events = POLLIN},
  };
  int count;
  while ((count = poll(fds, 3, timeout)) == -1 && errno == EINTR) {
  }
  if (count == -1) return -errno;
  int ready = 0;
  if (fds[0].revents != 0) ready |= kOutput;
  if (fds[1].revents != 0) ready |= kExited;
  if (fds[2].revents != 0) ready |= kWoken;
  return ready;
}

// Reads what `master` has: the count; 0 when there is nothing yet; -1 once
// the child's side is closed (0 on macOS, EIO on Linux) or reading fails.
EXPORT int baocode_pty_read(int master, uint8_t *buffer, int length) {
  for (;;) {
    ssize_t count = read(master, buffer, (size_t)length);
    if (count > 0) return (int)count;
    if (count == 0) return -1;
    if (errno == EINTR) continue;
    return errno == EAGAIN || errno == EWOULDBLOCK ? 0 : -1;
  }
}

// Writes what `master` takes now: the count, 0 when it is full, -1 when the
// terminal is gone.
EXPORT int baocode_pty_write(int master, const uint8_t *data, int length) {
  for (;;) {
    ssize_t count = write(master, data, (size_t)length);
    if (count >= 0) return (int)count;
    if (errno == EINTR) continue;
    return errno == EAGAIN || errno == EWOULDBLOCK ? 0 : -1;
  }
}

// Whether the child has exited: 1 with `*code` its exit code, or minus the
// signal that ended it (0 when another waiter took the status); 0 while it
// runs.
EXPORT int baocode_pty_exit_status(int pid, int exit_fd, int *code) {
  int status = 0;
#if defined(__APPLE__)
  if (exit_fd != -1) {
    struct kevent event;
    struct timespec now = {0, 0};
    int count = kevent(exit_fd, NULL, 0, &event, 1, &now);
    if (count == 0) return 0;
    if (count == 1) {
      // Reaped here, unless Dart's own reaper came first: it has exited, so
      // this does not block.
      while (waitpid(pid, &status, 0) == -1 && errno == EINTR) {
      }
      *code = decode_status((int)event.data);
      return 1;
    }
  }
#else
  (void)exit_fd;
#endif
  pid_t reaped;
  while ((reaped = waitpid(pid, &status, WNOHANG)) == -1 && errno == EINTR) {
  }
  if (reaped == 0) return 0;
  *code = reaped == pid ? decode_status(status) : 0;
  return 1;
}

// Sets the terminal's size; its foreground job gets SIGWINCH.
EXPORT int baocode_pty_resize(int master, int columns, int rows) {
  struct winsize size;
  memset(&size, 0, sizeof size);
  size.ws_col = (unsigned short)columns;
  size.ws_row = (unsigned short)rows;
  return ioctl(master, TIOCSWINSZ, &size) == -1 ? -errno : 0;
}

// Sends `number` to the child, then its process group, then the job in the
// terminal's foreground (which an interactive shell puts in a group of its
// own). Returns 0, or -errno from the first.
EXPORT int baocode_pty_kill(int pid, int master, int number) {
  int result = kill(pid, number) == -1 ? -errno : 0;
  kill(-pid, number);
  pid_t foreground = tcgetpgrp(master);
  if (foreground > 0 && foreground != pid) kill(-foreground, number);
  return result;
}

// A pipe, close-on-exec at both ends, into `fds`.
EXPORT int baocode_pty_pipe(int *fds) {
  return cloexec_pipe(fds) == -1 ? -errno : 0;
}

// Writes a byte to `fd`, the write end of a pipe from baocode_pty_pipe.
EXPORT void baocode_pty_wake(int fd) {
  char byte = 1;
  while (write(fd, &byte, 1) == -1 && errno == EINTR) {
  }
}

EXPORT void baocode_pty_close(int fd) { close(fd); }

// What errno `error` means, in the C library's words.
EXPORT const char *baocode_pty_describe(int error) { return strerror(error); }

EXPORT void *baocode_pty_alloc(size_t size) { return calloc(1, size); }

EXPORT void baocode_pty_free(void *pointer) { free(pointer); }
