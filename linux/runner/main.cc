#include <sys/resource.h>

#include "my_application.h"

// The descriptors the app may hold at once, raised from the session's soft
// limit (often 1024) towards its hard one: a process started past it fails,
// and Dart leaves the child it forked then waiting forever with a copy of
// every descriptor open (see macos/Runner/AppDelegate.swift).
static void raise_open_file_limit() {
  struct rlimit limit;
  if (getrlimit(RLIMIT_NOFILE, &limit) != 0) return;
  rlim_t wanted = 10240;
  if (limit.rlim_max != RLIM_INFINITY && limit.rlim_max < wanted) {
    wanted = limit.rlim_max;
  }
  if (limit.rlim_cur != RLIM_INFINITY && limit.rlim_cur < wanted) {
    limit.rlim_cur = wanted;
    setrlimit(RLIMIT_NOFILE, &limit);
  }
}

int main(int argc, char** argv) {
  raise_open_file_limit();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
