// baocode-browser-host: the native messaging host of BaoCode's browser
// extension (browser_extension/), which the browser starts for it. It
// passes the extension's messages to BaoCode and BaoCode's back, over a
// Unix socket of BaoCode's (lib/browser/browser_bridge.dart): waiting for
// BaoCode while it is not running, and again once it quits.
//
// Both ways a message is the browser's: its length (4 bytes, this
// machine's order), then that much JSON. The host says what goes on with
// BaoCode in messages of its own: {"type":"bridge","connected":…}. It
// quits once the browser lets it go (its input ends).
//
// Built for Linux too (linux/BrowserBridge/CMakeLists.txt): there the
// socket is in $XDG_RUNTIME_DIR, the user's alone, and BaoCode has to be
// the user's own (SO_PEERCRED), wherever the socket is.

#ifdef __linux__
#define _GNU_SOURCE  // struct ucred
#endif

#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <poll.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#ifdef __APPLE__
#include <libproc.h>
#endif

#define MAX_MESSAGE (64 * 1024 * 1024)

static pthread_mutex_t out_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t socket_lock = PTHREAD_MUTEX_INITIALIZER;
static int bao = -1;  // The socket to BaoCode, while connected.
static const char* origin = "";

static int read_all(int fd, void* buffer, size_t size) {
  char* p = buffer;
  while (size > 0) {
    ssize_t n = read(fd, p, size);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) return -1;
    p += n;
    size -= (size_t)n;
  }
  return 0;
}

static int write_all(int fd, const void* buffer, size_t size) {
  const char* p = buffer;
  while (size > 0) {
    ssize_t n = write(fd, p, size);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) return -1;
    p += n;
    size -= (size_t)n;
  }
  return 0;
}

// A whole message from [fd]: its text (freed by the caller), NULL once
// [fd] ends.
static char* read_message(int fd, uint32_t* length) {
  if (read_all(fd, length, 4) != 0 || *length > MAX_MESSAGE) return NULL;
  char* text = malloc(*length ? *length : 1);
  if (!text) return NULL;
  if (read_all(fd, text, *length) != 0) {
    free(text);
    return NULL;
  }
  return text;
}

static int write_message(int fd, const char* text, uint32_t length) {
  if (write_all(fd, &length, 4) != 0) return -1;
  return write_all(fd, text, length);
}

// To the extension, whole messages at a time.
static void to_browser(const char* text, uint32_t length) {
  pthread_mutex_lock(&out_lock);
  if (write_message(STDOUT_FILENO, text, length) != 0) exit(0);
  pthread_mutex_unlock(&out_lock);
}

static void tell_browser(int connected) {
  const char* text = connected ? "{\"type\":\"bridge\",\"connected\":true}"
                               : "{\"type\":\"bridge\",\"connected\":false}";
  to_browser(text, (uint32_t)strlen(text));
}

// The browser's executable, as the process that started this one runs it:
// the path says which browser it is (a fork's chrome is not Chrome's). ""
// when it is not to be had.
static void browser_path(char* buffer, size_t size) {
  buffer[0] = '\0';
#ifdef __APPLE__
  if (proc_pidpath(getppid(), buffer, (uint32_t)size) <= 0) buffer[0] = '\0';
#else
  char link[64];
  snprintf(link, sizeof link, "/proc/%d/exe", (int)getppid());
  const ssize_t n = readlink(link, buffer, size - 1);
  if (n <= 0) {
    buffer[0] = '\0';
    return;
  }
  buffer[n] = '\0';
#endif
}

// [text] as it goes in JSON: its quotes and backslashes escaped (a path
// has no control characters in it).
static void escape_json(const char* text, char* out, size_t size) {
  size_t j = 0;
  for (const char* p = text; *p && j + 3 < size; p++) {
    if (*p == '"' || *p == '\\') out[j++] = '\\';
    out[j++] = *p;
  }
  out[j] = '\0';
}

// As BrowserBridge.socketPath finds it.
static int socket_path(char* path, size_t size) {
  const char* dir = NULL;
#ifdef __linux__
  // The user's own; /tmp, below, is every user's.
  dir = getenv("XDG_RUNTIME_DIR");
  if (!dir || !*dir) dir = getenv("TMPDIR");
#else
  dir = getenv("TMPDIR");
#endif
#ifdef _CS_DARWIN_USER_TEMP_DIR
  char temp[PATH_MAX];
  // The browser's environment may not have it: the same folder, asked.
  if (!dir || !*dir) {
    if (confstr(_CS_DARWIN_USER_TEMP_DIR, temp, sizeof temp) > 0) dir = temp;
  }
#endif
  if (!dir || !*dir) dir = "/tmp";
  const size_t n = strlen(dir);
  const char* slash = n > 0 && dir[n - 1] == '/' ? "" : "/";
  return snprintf(path, size, "%s%sbaocode-browser.sock", dir, slash) <
                 (int)size
             ? 0
             : -1;
}

static int connect_bao(void) {
  struct sockaddr_un address = {0};
  address.sun_family = AF_UNIX;
  if (socket_path(address.sun_path, sizeof address.sun_path) != 0) return -1;
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) return -1;
  if (connect(fd, (struct sockaddr*)&address, sizeof address) != 0) {
    close(fd);
    return -1;
  }
#ifdef __linux__
  // Another user's, listening where BaoCode would: not told the browser's.
  struct ucred peer;
  socklen_t peer_size = sizeof peer;
  if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &peer, &peer_size) != 0 ||
      peer.uid != getuid()) {
    close(fd);
    return -1;
  }
#endif
  return fd;
}

// BaoCode's messages, to the browser; connecting again each time BaoCode
// comes back.
static void* from_bao(void* unused) {
  (void)unused;
  for (;;) {
    int fd = connect_bao();
    if (fd < 0) {
      sleep(1);
      continue;
    }
    // Who it is: the extension's origin, as the browser gave it; and the
    // browser's own executable, which tells one from another.
    char path[1024];
    char escaped[2048];
    browser_path(path, sizeof path);
    escape_json(path, escaped, sizeof escaped);
    char hello[4096];
    int n = snprintf(hello, sizeof hello,
                     "{\"type\":\"hello\",\"origin\":\"%s\",\"path\":\"%s\"}",
                     origin, escaped);
    if (n <= 0 || n >= (int)sizeof hello ||
        write_message(fd, hello, (uint32_t)n) != 0) {
      close(fd);
      sleep(1);
      continue;
    }
    pthread_mutex_lock(&socket_lock);
    bao = fd;
    pthread_mutex_unlock(&socket_lock);
    tell_browser(1);
    for (;;) {
      uint32_t length;
      char* text = read_message(fd, &length);
      if (!text) break;
      to_browser(text, length);
      free(text);
    }
    pthread_mutex_lock(&socket_lock);
    bao = -1;
    pthread_mutex_unlock(&socket_lock);
    close(fd);
    tell_browser(0);
    sleep(1);
  }
  return NULL;
}

int main(int argc, char** argv) {
  // The browser's: the extension's origin first (on Windows, a window's
  // handle follows).
  for (int i = 1; i < argc; i++) {
    if (strncmp(argv[i], "chrome-extension://", 19) == 0) {
      // Quotes and backslashes have no place in an origin: none is let in
      // the JSON it goes into.
      if (!strpbrk(argv[i], "\"\\")) origin = argv[i];
      break;
    }
  }
  signal(SIGPIPE, SIG_IGN);
  tell_browser(0);
  pthread_t thread;
  pthread_create(&thread, NULL, from_bao, NULL);
  // The extension's messages, to BaoCode: dropped while it is not there
  // (the extension knows, told above).
  for (;;) {
    uint32_t length;
    char* text = read_message(STDIN_FILENO, &length);
    if (!text) return 0;
    pthread_mutex_lock(&socket_lock);
    if (bao >= 0 && write_message(bao, text, length) != 0) {
      // Gone: its reader sees it too, and says so.
      shutdown(bao, SHUT_RDWR);
    }
    pthread_mutex_unlock(&socket_lock);
    free(text);
  }
}
