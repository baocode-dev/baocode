// A crash of the app on Linux, written down where the diagnostics go:
// Linux keeps no report of it the app can read (macOS has its .ips,
// Windows Windows Error Reporting and windows/runner/hang_watchdog.h's).
//
// On SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT or SIGTRAP, from the thread
// it came on:
//   - the logs folder's hangs/crash-<time>-<pid>.txt: the signal, where
//     (module+offset), and the stack, both as the unwinder sees it (the
//     engine's code; it stops at the Dart code, which has no unwind
//     information) and by the frame pointers (the Dart code keeps them);
//     frames as `libapp.so+0x…`, named by the release's symbols
//     (tool/symbolize_jank_sample.dart);
//   - a line in events.log: `<time> [exit] crashed: SIGSEGV at …`, as
//     lib/platform/event_log.dart writes its own.
// Then the signal goes on as it would have: the handler there was before,
// or the system's (a core dump, apport).
//
// What runs in the handler keeps to calls safe there (open, write, read,
// clock_gettime), but for backtrace(), called once beforehand so that it
// has loaded what it needs. Where code is comes from /proc/self/maps,
// read into a buffer of its own: dladdr may wait on a lock the thread
// crashed holding.

#if !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#include <errno.h>
#include <execinfo.h>
#include <fcntl.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <ucontext.h>
#include <unistd.h>

#define BAO_EXPORT __attribute__((visibility("default")))

#if defined(__aarch64__)
#define BAO_ARM64 1
#endif

enum {
  kMaxFrames = 64,
  kPathSize = 4096,
  kMapsSize = 512 * 1024,
  kLineSize = 1024,
  kAltStackSize = 64 * 1024,
};

static const int kSignals[] = {SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT,
                               SIGTRAP};
#define kSignalCount ((int)(sizeof(kSignals) / sizeof(kSignals[0])))

static struct sigaction g_previous[kSignalCount];
static char g_events[kPathSize];
static char g_reports[kPathSize];
static char g_header[256];
static long g_utc_offset;
static atomic_int g_crashing;
// The last fault handed to the handler there was before: the same again
// is a crash it did not handle.
static uintptr_t g_handed_pc;
static int g_handed_signal;

static char g_maps[kMapsSize];
static size_t g_maps_length;
static char g_alt_stack[kAltStackSize];

// --- Writing, with no buffer and no allocation ---------------------------

typedef struct {
  char text[kLineSize];
  size_t length;
} Line;

static void Put(Line* line, const char* text) {
  while (*text != '\0' && line->length + 1 < sizeof(line->text)) {
    line->text[line->length++] = *text++;
  }
  line->text[line->length] = '\0';
}

static void PutNumber(Line* line, unsigned long long value, int base,
                      int digits) {
  char reversed[32];
  int count = 0;
  do {
    const int digit = (int)(value % (unsigned)base);
    reversed[count++] = (char)(digit < 10 ? '0' + digit : 'a' + digit - 10);
    value /= (unsigned)base;
  } while (value != 0 && count < (int)sizeof(reversed));
  while (count < digits && count < (int)sizeof(reversed)) {
    reversed[count++] = '0';
  }
  char forward[33];
  for (int i = 0; i < count; ++i) forward[i] = reversed[count - 1 - i];
  forward[count] = '\0';
  Put(line, forward);
}

static void PutHex(Line* line, uintptr_t value) {
  Put(line, "0x");
  PutNumber(line, value, 16, 1);
}

static void WriteAll(int fd, const char* text, size_t length) {
  while (length > 0) {
    const ssize_t written = write(fd, text, length);
    if (written < 0 && errno == EINTR) continue;
    if (written <= 0) return;
    text += written;
    length -= (size_t)written;
  }
}

static void WriteLine(int fd, Line* line) {
  Put(line, "\n");
  WriteAll(fd, line->text, line->length);
  line->length = 0;
  line->text[0] = '\0';
}

// --- The time, local, as Dart's DateTime.toIso8601String has it ----------

// The civil date of |days| since 1970-01-01 (Howard Hinnant's algorithm).
static void CivilFromDays(long days, int* year, int* month, int* day) {
  days += 719468;
  const long era = (days >= 0 ? days : days - 146096) / 146097;
  const long of_era = days - era * 146097;
  const long year_of_era =
      (of_era - of_era / 1460 + of_era / 36524 - of_era / 146096) / 365;
  const long of_year = of_era - (365 * year_of_era + year_of_era / 4 -
                                 year_of_era / 100);
  const long m = (5 * of_year + 2) / 153;
  *day = (int)(of_year - (153 * m + 2) / 5 + 1);
  *month = (int)(m < 10 ? m + 3 : m - 9);
  *year = (int)(year_of_era + era * 400 + (*month <= 2));
}

// `2026-10-28T12:46:36.981` (|stamp|: `20261028-124636`, for a file name).
static void PutTime(Line* line, Line* stamp) {
  struct timespec now;
  clock_gettime(CLOCK_REALTIME, &now);
  const long local = (long)now.tv_sec + g_utc_offset;
  long days = local / 86400;
  long seconds = local % 86400;
  if (seconds < 0) {
    seconds += 86400;
    days -= 1;
  }
  int year, month, day;
  CivilFromDays(days, &year, &month, &day);
  const int fields[] = {year, month, day, (int)(seconds / 3600),
                        (int)(seconds / 60 % 60), (int)(seconds % 60)};
  const char* const separators[] = {"", "-", "-", "T", ":", ":"};
  for (int i = 0; i < 6; ++i) {
    Put(line, separators[i]);
    PutNumber(line, (unsigned long long)fields[i], 10, i == 0 ? 4 : 2);
    if (stamp != NULL) {
      if (i == 3) Put(stamp, "-");
      PutNumber(stamp, (unsigned long long)fields[i], 10, i == 0 ? 4 : 2);
    }
  }
  Put(line, ".");
  PutNumber(line, (unsigned long long)(now.tv_nsec / 1000000), 10, 3);
}

// --- Where code is, from /proc/self/maps ---------------------------------

static void ReadMaps(void) {
  g_maps_length = 0;
  const int fd = open("/proc/self/maps", O_RDONLY | O_CLOEXEC);
  if (fd < 0) return;
  while (g_maps_length + 1 < sizeof(g_maps)) {
    const ssize_t read_now =
        read(fd, g_maps + g_maps_length, sizeof(g_maps) - 1 - g_maps_length);
    if (read_now < 0 && errno == EINTR) continue;
    if (read_now <= 0) break;
    g_maps_length += (size_t)read_now;
  }
  g_maps[g_maps_length] = '\0';
  close(fd);
}

static uintptr_t ParseHex(const char** at) {
  uintptr_t value = 0;
  for (;;) {
    const char c = **at;
    int digit;
    if (c >= '0' && c <= '9') {
      digit = c - '0';
    } else if (c >= 'a' && c <= 'f') {
      digit = c - 'a' + 10;
    } else {
      return value;
    }
    value = value * 16 + (uintptr_t)digit;
    ++*at;
  }
}

typedef struct {
  uintptr_t start, end, offset;
  int executable;
  const char* path;  // Into g_maps, to the end of the line.
  size_t path_length;
} Mapping;

// The next line of the maps read, from |cursor|: 0 past the last.
static int MappingAt(const char** cursor, Mapping* mapping) {
  const char* at = *cursor;
  if (at == NULL || *at == '\0') return 0;
  const char* end = strchr(at, '\n');
  if (end == NULL) end = at + strlen(at);
  mapping->start = ParseHex(&at);
  if (*at == '-') ++at;
  mapping->end = ParseHex(&at);
  while (*at == ' ') ++at;
  mapping->executable = at + 2 < end && at[2] == 'x';
  while (at < end && *at != ' ') ++at;  // Permissions.
  while (*at == ' ') ++at;
  mapping->offset = ParseHex(&at);
  for (int field = 0; field < 2; ++field) {  // Device, inode.
    while (at < end && *at == ' ') ++at;
    while (at < end && *at != ' ') ++at;
  }
  while (at < end && *at == ' ') ++at;
  mapping->path = at;
  mapping->path_length = (size_t)(end - at);
  *cursor = *end == '\n' ? end + 1 : end;
  return 1;
}

static int FindMapping(uintptr_t address, Mapping* found) {
  const char* cursor = g_maps;
  Mapping mapping;
  while (MappingAt(&cursor, &mapping)) {
    if (address >= mapping.start && address < mapping.end) {
      *found = mapping;
      return 1;
    }
  }
  return 0;
}

static int IsCode(uintptr_t address) {
  Mapping mapping;
  return FindMapping(address, &mapping) && mapping.executable;
}

// |address| as module+offset: from where the module was loaded (its
// mapping at file offset 0), the address the module's symbols name.
static void PutWhere(Line* line, uintptr_t address) {
  Mapping mapping;
  if (!FindMapping(address, &mapping) || mapping.path_length == 0) {
    Put(line, "?+");
    PutHex(line, address);
    return;
  }
  uintptr_t base = mapping.start - mapping.offset;
  const char* cursor = g_maps;
  Mapping other;
  while (MappingAt(&cursor, &other)) {
    if (other.offset == 0 && other.path_length == mapping.path_length &&
        memcmp(other.path, mapping.path, mapping.path_length) == 0) {
      base = other.start;
      break;
    }
  }
  const char* name = mapping.path;
  for (size_t i = 0; i < mapping.path_length; ++i) {
    if (mapping.path[i] == '/') name = mapping.path + i + 1;
  }
  char module[256];
  size_t length = (size_t)(mapping.path + mapping.path_length - name);
  if (length >= sizeof(module)) length = sizeof(module) - 1;
  memcpy(module, name, length);
  module[length] = '\0';
  Put(line, module);
  Put(line, "+");
  PutHex(line, address - base);
}

// --- The handler ---------------------------------------------------------

static const char* SignalName(int signal) {
  switch (signal) {
    case SIGSEGV: return "SIGSEGV";
    case SIGBUS: return "SIGBUS";
    case SIGILL: return "SIGILL";
    case SIGFPE: return "SIGFPE";
    case SIGABRT: return "SIGABRT";
    case SIGTRAP: return "SIGTRAP";
    default: return "signal";
  }
}

static int IndexOf(int signal) {
  for (int i = 0; i < kSignalCount; ++i) {
    if (kSignals[i] == signal) return i;
  }
  return -1;
}

// The frames by the frame pointers, from |fp|: [fp] the caller's, [fp+8]
// the return address (x64 and arm64 alike), each above the last, within
// the stack's mapping.
static void WriteFramePointers(int fd, uintptr_t sp, uintptr_t fp) {
  Mapping stack;
  if (!FindMapping(sp, &stack)) return;
  Line line = {{0}, 0};
  for (int i = 0; i < kMaxFrames; ++i) {
    if (fp < sp || fp % sizeof(uintptr_t) != 0 || fp < stack.start ||
        fp + 2 * sizeof(uintptr_t) > stack.end) {
      return;
    }
    const uintptr_t next = ((const uintptr_t*)fp)[0];
    const uintptr_t ret = ((const uintptr_t*)fp)[1];
    if (ret == 0 || !IsCode(ret)) return;
    Put(&line, "  ");
    PutWhere(&line, ret);
    WriteLine(fd, &line);
    if (next <= fp) return;
    sp = fp;
    fp = next;
  }
}

static void Report(int signal, const siginfo_t* info,
                   const ucontext_t* context) {
  ReadMaps();
  uintptr_t pc = 0, sp = 0, fp = 0, lr = 0;
  if (context != NULL) {
#if defined(BAO_ARM64)
    pc = context->uc_mcontext.pc;
    sp = context->uc_mcontext.sp;
    fp = context->uc_mcontext.regs[29];
    lr = context->uc_mcontext.regs[30];
#else
    pc = (uintptr_t)context->uc_mcontext.gregs[REG_RIP];
    sp = (uintptr_t)context->uc_mcontext.gregs[REG_RSP];
    fp = (uintptr_t)context->uc_mcontext.gregs[REG_RBP];
#endif
  }

  Line time = {{0}, 0};
  Line stamp = {{0}, 0};
  PutTime(&time, &stamp);

  // What happened, in a line: the report's and the event log's.
  Line what = {{0}, 0};
  Put(&what, SignalName(signal));
  if (pc != 0) {
    Put(&what, " at ");
    PutWhere(&what, pc);
  }
  // A fault's address; not of one sent (kill's, raise's).
  if ((signal == SIGSEGV || signal == SIGBUS) && info->si_code > 0) {
    Put(&what, ", address ");
    PutHex(&what, (uintptr_t)info->si_addr);
  }

  Line path = {{0}, 0};
  Put(&path, g_reports);
  Put(&path, "/crash-");
  Put(&path, stamp.text);
  Put(&path, "-");
  PutNumber(&path, (unsigned long long)getpid(), 10, 1);
  Put(&path, ".txt");

  Line line = {{0}, 0};
  const int report =
      g_reports[0] == '\0'
          ? -1
          : open(path.text, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
  if (report >= 0) {
    Put(&line, g_header);
    WriteLine(report, &line);
    Put(&line, "Process ");
    PutNumber(&line, (unsigned long long)getpid(), 10, 1);
    Put(&line, ": ");
    Put(&line, what.text);
    Put(&line, " (code ");
    if (info->si_code < 0) Put(&line, "-");
    PutNumber(&line,
              (unsigned long long)(info->si_code < 0 ? -info->si_code
                                                     : info->si_code),
              10, 1);
    Put(&line, ")");
    WriteLine(report, &line);
    Put(&line, "\nThread ");
    PutNumber(&line, (unsigned long long)syscall(SYS_gettid), 10, 1);
    Put(&line, " [crashed], by the unwinder:");
    WriteLine(report, &line);
    void* frames[kMaxFrames];
    const int count = backtrace(frames, kMaxFrames);
    for (int i = 0; i < count; ++i) {
      Put(&line, "  ");
      PutWhere(&line, (uintptr_t)frames[i]);
      WriteLine(report, &line);
    }
    Put(&line, "\nBy the frame pointers:");
    WriteLine(report, &line);
    Put(&line, "  ");
    PutWhere(&line, pc);
    WriteLine(report, &line);
    if (lr != 0 && IsCode(lr)) {
      Put(&line, "  ");
      PutWhere(&line, lr);
      WriteLine(report, &line);
    }
    WriteFramePointers(report, sp, fp);
    close(report);
  }

  if (g_events[0] != '\0') {
    const int events =
        open(g_events, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    if (events >= 0) {
      Put(&line, time.text);
      Put(&line, " [exit] crashed: ");
      Put(&line, what.text);
      if (report >= 0) {
        Put(&line, " (hangs/");
        Put(&line, path.text + strlen(g_reports) + 1);
        Put(&line, ")");
      }
      WriteLine(events, &line);
      close(events);
    }
  }
}

static void Handler(int signal, siginfo_t* info, void* context) {
  const int saved = errno;
  const int index = IndexOf(signal);
  const struct sigaction* previous = index < 0 ? NULL : &g_previous[index];
  const ucontext_t* uc = (const ucontext_t*)context;
#if defined(BAO_ARM64)
  const uintptr_t pc = uc == NULL ? 0 : uc->uc_mcontext.pc;
#else
  const uintptr_t pc =
      uc == NULL ? 0 : (uintptr_t)uc->uc_mcontext.gregs[REG_RIP];
#endif
  // A handler there before (a runtime's own use of faults) has it first;
  // only what it hands back again, unhandled, is a crash.
  if (previous != NULL && (previous->sa_flags & SA_SIGINFO) != 0 &&
      previous->sa_sigaction != NULL &&
      !(g_handed_signal == signal && g_handed_pc == pc)) {
    g_handed_signal = signal;
    g_handed_pc = pc;
    previous->sa_sigaction(signal, info, context);
    errno = saved;
    return;
  }
  if (previous != NULL && (previous->sa_flags & SA_SIGINFO) == 0 &&
      previous->sa_handler != SIG_DFL && previous->sa_handler != SIG_IGN &&
      !(g_handed_signal == signal && g_handed_pc == pc)) {
    g_handed_signal = signal;
    g_handed_pc = pc;
    previous->sa_handler(signal);
    errno = saved;
    return;
  }
  if (atomic_exchange(&g_crashing, 1) == 0) {
    Report(signal, info, uc);
  }
  // On as it would have gone: the system's way, now that it is told.
  struct sigaction fallback;
  memset(&fallback, 0, sizeof(fallback));
  fallback.sa_handler = SIG_DFL;
  sigemptyset(&fallback.sa_mask);
  sigaction(signal, &fallback, NULL);
  errno = saved;
  // Sent again, held till the handler returns, and then the end: not left
  // to the instruction faulting again as it runs again, which one sent
  // (abort's, kill's) would not.
  raise(signal);
}

static void Copy(char* to, size_t size, const char* from) {
  if (from == NULL) {
    to[0] = '\0';
    return;
  }
  size_t length = strlen(from);
  if (length >= size) length = size - 1;
  memcpy(to, from, length);
  to[length] = '\0';
}

// Writes the app's crashes down (see above): the event log at |events|,
// the reports in the folder |reports| (UTF-8 paths), each report's first
// line |header| (the app's version). Again: the paths anew. 1 once set.
BAO_EXPORT int bao_crash_install(const char* events, const char* reports,
                                 const char* header) {
  Copy(g_events, sizeof(g_events), events);
  Copy(g_reports, sizeof(g_reports), reports);
  Copy(g_header, sizeof(g_header), header);
  // Daylight saving's change in the run's time is not followed.
  const time_t now = time(NULL);
  struct tm local;
  localtime_r(&now, &local);
  g_utc_offset = local.tm_gmtoff;
  static int installed = 0;
  if (installed) return 1;
  // Loads what the unwinder needs (libgcc_s), not to in the handler.
  void* warm[2];
  backtrace(warm, 2);
  // A stack of its own on this thread (the UI thread), for an overflow.
  stack_t alt;
  memset(&alt, 0, sizeof(alt));
  alt.ss_sp = g_alt_stack;
  alt.ss_size = sizeof(g_alt_stack);
  sigaltstack(&alt, NULL);
  for (int i = 0; i < kSignalCount; ++i) {
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_sigaction = Handler;
    action.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&action.sa_mask);
    sigaction(kSignals[i], &action, &g_previous[i]);
  }
  installed = 1;
  return 1;
}
