// What the app's UI thread (the Dart code's) was doing, for a few seconds,
// on Windows and Linux: its stack taken every so often from a thread of the
// sampler's own, and written down as a text report, the stacks the same
// counted together. macOS has its own `sample` for this
// (lib/diagnostics/jank_sample.dart).
//
// Each sample holds the thread only while its registers and the top of its
// stack are copied (Windows: suspended; Linux: in a signal handler of its
// own), then lets it go: the stack is walked from the copy, on the
// sampler's thread. Nothing that could wait on a lock the thread holds (the
// heap's, the loader's) is done while it is held.
//
// The walk follows the frame pointers. The Dart code keeps them always;
// code built without them (Flutter's engine on Linux and Windows x64)
// breaks the chain, and the walk then looks up the copied stack for the
// next Dart frame (a saved frame pointer above it, then a return address
// into the Dart code) and goes on from there, a `...` line marking the
// frames it could not see. So the Dart code that was running is there
// whole, what it called in the engine by its innermost frame.
//
// Frames are written module+offset: the Dart code's `app.so+0x…` (Windows)
// or `libapp.so+0x…` (Linux), offsets in the ELF file the release's symbols
// name (tool/symbolize_jank_sample.dart).

#if !defined(_WIN32) && !defined(_GNU_SOURCE)
// dladdr.
#define _GNU_SOURCE
#endif

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <intrin.h>
#include <tlhelp32.h>
#define BAO_EXPORT __declspec(dllexport)
#define BAO_RETURN_ADDRESS() ((uintptr_t)_ReturnAddress())
#else
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <semaphore.h>
#include <signal.h>
#include <stdatomic.h>
#include <sys/syscall.h>
#include <time.h>
#include <ucontext.h>
#include <unistd.h>
#define BAO_EXPORT __attribute__((visibility("default")))
#define BAO_RETURN_ADDRESS() ((uintptr_t)__builtin_return_address(0))
#endif

#if defined(_M_ARM64) || defined(__aarch64__)
#define BAO_ARM64 1
#endif

enum {
  kMaxFrames = 64,
  // The top of the stack copied: the deepest Dart frames are what a jank
  // is about, and further up the copy only takes longer.
  kStackCopy = 128 * 1024,
  kMaxSamples = 400,
};

// A frame the walk could not see: written `...`.
#define BAO_GAP ((uintptr_t)1)

typedef struct {
  uintptr_t pcs[kMaxFrames];
  int count;
} Stack;

typedef struct {
  uintptr_t pc, sp, fp, lr;
} Registers;

// Where the Dart code is: the ELF file of it, as loaded.
static uintptr_t g_dart_start, g_dart_end;
static char g_dart_name[64] = "app.so";

static uint8_t g_copy[kStackCopy];

static char* g_path;
static int g_millis, g_interval;
static Stack* g_samples;

static int IsDart(uintptr_t pc) {
  return pc >= g_dart_start && pc < g_dart_end;
}

// A return address as a code address: arm64's pointer authentication, if
// any, in its top bits.
static uintptr_t Strip(uintptr_t address) {
#if defined(BAO_ARM64)
  return address & (uintptr_t)0x0000FFFFFFFFFFFFull;
#else
  return address;
#endif
}

// ---------------------------------------------------------------------------
// The platform's part: the UI thread held and copied, modules named.

#if defined(_WIN32)

static DWORD g_ui_thread;
static volatile LONG g_busy;

// The ELF file (app.so) whose memory |address| is in, as Dart's own loader
// reserved it (no module Windows knows): its range.
static int FindDart(uintptr_t address) {
  MEMORY_BASIC_INFORMATION memory;
  if (VirtualQuery((LPCVOID)address, &memory, sizeof(memory)) == 0 ||
      memory.AllocationBase == NULL) {
    return 0;
  }
  const uint8_t* base = (const uint8_t*)memory.AllocationBase;
  if (memcmp(base, "\x7f" "ELF", 4) != 0) return 0;
  uintptr_t end = (uintptr_t)base;
  for (;;) {
    if (VirtualQuery((LPCVOID)end, &memory, sizeof(memory)) == 0 ||
        memory.AllocationBase != base) {
      break;
    }
    end = (uintptr_t)memory.BaseAddress + memory.RegionSize;
  }
  g_dart_start = (uintptr_t)base;
  g_dart_end = end;
  return 1;
}

static int IsCode(uintptr_t address) {
  if (IsDart(address)) return 1;
  HMODULE module = NULL;
  return GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                                GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            (LPCWSTR)address, &module) != 0;
}

static void Describe(uintptr_t address, char* out, size_t size) {
  if (IsDart(address)) {
    snprintf(out, size, "%s+0x%llx", g_dart_name,
             (unsigned long long)(address - g_dart_start));
    return;
  }
  HMODULE module = NULL;
  wchar_t path[MAX_PATH];
  if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                             GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                         (LPCWSTR)address, &module) &&
      GetModuleFileNameW(module, path, MAX_PATH) > 0) {
    const wchar_t* name = wcsrchr(path, L'\\');
    name = name ? name + 1 : path;
    char utf8[MAX_PATH * 3];
    WideCharToMultiByte(CP_UTF8, 0, name, -1, utf8, sizeof(utf8), NULL, NULL);
    snprintf(out, size, "%s+0x%llx", utf8,
             (unsigned long long)(address - (uintptr_t)module));
    return;
  }
  snprintf(out, size, "?+0x%llx", (unsigned long long)address);
}

// Holds the thread, copies its registers and the top of its stack (into
// g_copy, |*copied| bytes from regs->sp), lets it go.
static int Take(HANDLE thread, Registers* regs, size_t* copied) {
  if (SuspendThread(thread) == (DWORD)-1) return 0;
  CONTEXT context;
  memset(&context, 0, sizeof(context));
  context.ContextFlags = CONTEXT_CONTROL | CONTEXT_INTEGER;
  int taken = GetThreadContext(thread, &context) != 0;
  if (taken) {
#if defined(BAO_ARM64)
    regs->pc = context.Pc;
    regs->sp = context.Sp;
    regs->fp = context.Fp;
    regs->lr = context.Lr;
#else
    regs->pc = context.Rip;
    regs->sp = context.Rsp;
    regs->fp = context.Rbp;
    regs->lr = 0;
#endif
    // The stack's committed part, from its pointer up to its base.
    MEMORY_BASIC_INFORMATION memory;
    size_t length = 0;
    if (VirtualQuery((LPCVOID)regs->sp, &memory, sizeof(memory)) != 0 &&
        memory.State == MEM_COMMIT) {
      length = (uintptr_t)memory.BaseAddress + memory.RegionSize - regs->sp;
    }
    if (length > kStackCopy) length = kStackCopy;
    memcpy(g_copy, (const void*)regs->sp, length);
    *copied = length;
  }
  ResumeThread(thread);
  return taken;
}

#else  // Linux

static pid_t g_ui_thread;
static atomic_int g_busy;

static int g_signal;
static sem_t g_taken;

// The request to the handler, and its answer: idle, asked, being written
// (the handler has it), written.
enum { kIdle, kAsked, kWriting, kWritten };
static atomic_int g_state;
static pid_t g_asked_thread;
static uintptr_t g_stack_end;
static Registers g_regs;
static size_t g_copied;

static void Handler(int signal, siginfo_t* info, void* context) {
  (void)signal;
  (void)info;
  const int saved = errno;
  if ((pid_t)syscall(SYS_gettid) != g_asked_thread) {
    errno = saved;
    return;
  }
  int asked = kAsked;
  if (!atomic_compare_exchange_strong(&g_state, &asked, kWriting)) {
    errno = saved;
    return;
  }
  const ucontext_t* uc = (const ucontext_t*)context;
#if defined(BAO_ARM64)
  g_regs.pc = uc->uc_mcontext.pc;
  g_regs.sp = uc->uc_mcontext.sp;
  g_regs.fp = uc->uc_mcontext.regs[29];
  g_regs.lr = uc->uc_mcontext.regs[30];
#else
  g_regs.pc = uc->uc_mcontext.gregs[REG_RIP];
  g_regs.sp = uc->uc_mcontext.gregs[REG_RSP];
  g_regs.fp = uc->uc_mcontext.gregs[REG_RBP];
  g_regs.lr = 0;
#endif
  size_t length = 0;
  if (g_stack_end > g_regs.sp) {
    length = g_stack_end - g_regs.sp;
    if (length > kStackCopy) length = kStackCopy;
    memcpy(g_copy, (const void*)g_regs.sp, length);
  }
  g_copied = length;
  atomic_store(&g_state, kWritten);
  sem_post(&g_taken);
  errno = saved;
}

// The mapping |address| is in, from /proc/self/maps: its range and file.
static int Mapping(uintptr_t address, uintptr_t* start, uintptr_t* end,
                   char* path, size_t path_size) {
  FILE* maps = fopen("/proc/self/maps", "r");
  if (maps == NULL) return 0;
  char line[1024];
  int found = 0;
  while (fgets(line, sizeof(line), maps) != NULL) {
    unsigned long long from = 0, to = 0;
    int name_at = 0;
    if (sscanf(line, "%llx-%llx %*s %*s %*s %*s %n", &from, &to, &name_at) <
        2) {
      continue;
    }
    if (address < from || address >= to) continue;
    *start = (uintptr_t)from;
    *end = (uintptr_t)to;
    if (path != NULL) {
      snprintf(path, path_size, "%s", name_at > 0 ? line + name_at : "");
      path[strcspn(path, "\n")] = '\0';
    }
    found = 1;
    break;
  }
  fclose(maps);
  return found;
}

// The Dart code's ELF file (libapp.so), all its mappings: its range.
static int FindDart(uintptr_t address) {
  uintptr_t start, end;
  char path[512];
  if (!Mapping(address, &start, &end, path, sizeof(path))) return 0;
  g_dart_start = start;
  g_dart_end = end;
  if (path[0] == '/') {
    FILE* maps = fopen("/proc/self/maps", "r");
    char line[1024];
    while (maps != NULL && fgets(line, sizeof(line), maps) != NULL) {
      unsigned long long from = 0, to = 0;
      int name_at = 0;
      if (sscanf(line, "%llx-%llx %*s %*s %*s %*s %n", &from, &to,
                 &name_at) < 2 ||
          name_at == 0) {
        continue;
      }
      line[strcspn(line, "\n")] = '\0';
      if (strcmp(line + name_at, path) != 0) continue;
      if (from < g_dart_start) g_dart_start = (uintptr_t)from;
      if (to > g_dart_end) g_dart_end = (uintptr_t)to;
    }
    if (maps != NULL) fclose(maps);
    const char* name = strrchr(path, '/');
    snprintf(g_dart_name, sizeof(g_dart_name), "%s", name + 1);
  }
  return 1;
}

static int IsCode(uintptr_t address) {
  if (IsDart(address)) return 1;
  Dl_info info;
  return dladdr((const void*)address, &info) != 0 && info.dli_fbase != NULL;
}

static void Describe(uintptr_t address, char* out, size_t size) {
  if (IsDart(address)) {
    snprintf(out, size, "%s+0x%llx", g_dart_name,
             (unsigned long long)(address - g_dart_start));
    return;
  }
  Dl_info info;
  if (dladdr((const void*)address, &info) != 0 && info.dli_fname != NULL) {
    const char* name = strrchr(info.dli_fname, '/');
    name = name ? name + 1 : info.dli_fname;
    snprintf(out, size, "%s+0x%llx", name,
             (unsigned long long)(address - (uintptr_t)info.dli_fbase));
    return;
  }
  snprintf(out, size, "?+0x%llx", (unsigned long long)address);
}

// Asks |thread|'s handler for its registers and the top of its stack (none
// with |stack_end| 0), and waits for them a while.
static int Ask(pid_t thread, uintptr_t stack_end) {
  g_asked_thread = thread;
  g_stack_end = stack_end;
  atomic_store(&g_state, kAsked);
  if (syscall(SYS_tgkill, getpid(), thread, g_signal) != 0) {
    atomic_store(&g_state, kIdle);
    return 0;
  }
  struct timespec until;
  clock_gettime(CLOCK_REALTIME, &until);
  until.tv_nsec += 100 * 1000 * 1000;
  if (until.tv_nsec >= 1000000000) {
    until.tv_sec++;
    until.tv_nsec -= 1000000000;
  }
  while (sem_timedwait(&g_taken, &until) != 0) {
    if (errno == EINTR) continue;
    // Not there in time: taken back, unless the handler has it already
    // (then it is soon written).
    int asked = kAsked;
    if (atomic_compare_exchange_strong(&g_state, &asked, kIdle)) return 0;
    while (sem_wait(&g_taken) != 0) {
    }
    break;
  }
  atomic_store(&g_state, kIdle);
  return 1;
}

#endif

// ---------------------------------------------------------------------------
// The walk, from the copy.

typedef struct {
  const uint8_t* copy;
  uintptr_t sp;
  size_t length;
} Copy;

static int InCopy(const Copy* c, uintptr_t address) {
  return (address & (sizeof(uintptr_t) - 1)) == 0 && address >= c->sp &&
         address - c->sp + 2 * sizeof(uintptr_t) <= c->length;
}

static uintptr_t Read(const Copy* c, uintptr_t address) {
  uintptr_t value;
  memcpy(&value, c->copy + (address - c->sp), sizeof(value));
  return value;
}

static void Add(Stack* stack, uintptr_t pc) {
  if (stack->count < kMaxFrames) stack->pcs[stack->count++] = pc;
}

// From |from| up the copy, the next frame record of the Dart code: a saved
// frame pointer further up, then a return address into the Dart code. 0
// for none.
static uintptr_t NextDartFrame(const Copy* c, uintptr_t from) {
  for (uintptr_t at = (from + sizeof(uintptr_t) - 1) & ~(sizeof(uintptr_t) - 1);
       InCopy(c, at); at += sizeof(uintptr_t)) {
    const uintptr_t next = Read(c, at);
    if (next > at && InCopy(c, next) &&
        IsDart(Strip(Read(c, at + sizeof(uintptr_t))))) {
      return at;
    }
  }
  return 0;
}

#if !defined(BAO_ARM64)
// Whether |ret|, in the Dart code, is just after a call: `call rel32`
// (E8), or `call r/m` (FF /2) two to seven bytes long.
static int FollowsCall(uintptr_t ret) {
  if (!IsDart(ret) || ret - g_dart_start < 8) return 0;
  const uint8_t* code = (const uint8_t*)ret;
  if (code[-5] == 0xE8) return 1;
  for (int length = 2; length <= 7; ++length) {
    if (code[-length] == 0xFF && ((code[1 - length] >> 3) & 7) == 2) {
      return 1;
    }
  }
  return 0;
}
#endif

static void Walk(const Copy* c, const Registers* regs, Stack* stack) {
  stack->count = 0;
  Add(stack, regs->pc);
  uintptr_t fp = regs->fp;
#if defined(BAO_ARM64)
  // A function that keeps no frame record (a leaf), or has not made it
  // yet: its caller is in the link register alone.
  const uintptr_t lr = Strip(regs->lr);
  if (lr != 0 && IsCode(lr) &&
      !(InCopy(c, fp) && Strip(Read(c, fp + sizeof(uintptr_t))) == lr)) {
    Add(stack, lr);
  }
#else
  // A Dart function that calls nothing keeps no frame (it starts with its
  // stack check, not `push rbp`): its caller is in the return address on
  // top of the stack, which a call instruction is just before.
  if (IsDart(regs->pc) && InCopy(c, c->sp)) {
    const uintptr_t ret = Read(c, c->sp);
    if (FollowsCall(ret) &&
        !(InCopy(c, fp) && Read(c, fp + sizeof(uintptr_t)) == ret)) {
      Add(stack, ret);
    }
  }
#endif
  uintptr_t scanned = c->sp;
  while (stack->count < kMaxFrames) {
    if (InCopy(c, fp)) {
      const uintptr_t next = Read(c, fp);
      const uintptr_t ret = Strip(Read(c, fp + sizeof(uintptr_t)));
      if (ret != 0 && IsCode(ret)) {
        Add(stack, ret);
        scanned = fp + 2 * sizeof(uintptr_t);
        if (next <= fp) break;
        fp = next;
        continue;
      }
    }
    // The chain broke, in code that keeps no frame pointer: on from the
    // next Dart frame up the stack.
    const uintptr_t found = NextDartFrame(c, scanned);
    if (found == 0) break;
    Add(stack, BAO_GAP);
    // The Dart function that called that code has its return address just
    // under its own frame record, kept by its callee alone: the last into
    // the Dart code below |found|.
    for (uintptr_t at = found - sizeof(uintptr_t); at >= scanned;
         at -= sizeof(uintptr_t)) {
      const uintptr_t ret = Strip(Read(c, at));
      if (IsDart(ret)) {
        if (ret != Strip(Read(c, found + sizeof(uintptr_t)))) Add(stack, ret);
        break;
      }
    }
    fp = found;
  }
}

// ---------------------------------------------------------------------------
// The report.

static int SameStack(const Stack* a, const Stack* b) {
  return a->count == b->count &&
         memcmp(a->pcs, b->pcs, a->count * sizeof(uintptr_t)) == 0;
}

static int CompareCounts(const void* a, const void* b) {
  const int* x = (const int*)a;
  const int* y = (const int*)b;
  return y[1] - x[1];
}

static FILE* OpenReport(const char* path) {
#if defined(_WIN32)
  wchar_t wide[MAX_PATH * 2];
  if (MultiByteToWideChar(CP_UTF8, 0, path, -1, wide, MAX_PATH * 2) == 0) {
    return NULL;
  }
  FILE* out = NULL;
  return _wfopen_s(&out, wide, L"w") == 0 ? out : NULL;
#else
  return fopen(path, "w");
#endif
}

static void WriteReport(int taken, int missed, int millis) {
  FILE* out = OpenReport(g_path);
  if (out == NULL) return;
#if defined(BAO_ARM64)
  const char* arch = "arm64";
#else
  const char* arch = "x64";
#endif
#if defined(_WIN32)
  const char* os = "windows";
#else
  const char* os = "linux";
#endif
  fprintf(out, "BaoCode jank sample (%s-%s): the UI thread, %d ms, every %d ms\n",
          os, arch, millis, g_interval);
  fprintf(out, "%d samples, %d not taken\n", taken, missed);
  fprintf(out, "Dart code: %s, at 0x%llx\n", g_dart_name,
          (unsigned long long)g_dart_start);

  // Each stack once, with how many samples had it: the most first.
  int* counts = (int*)calloc((size_t)taken * 2, sizeof(int));
  int distinct = 0;
  for (int i = 0; counts != NULL && i < taken; ++i) {
    int j = 0;
    while (j < distinct && !SameStack(&g_samples[counts[j * 2]], &g_samples[i])) {
      ++j;
    }
    if (j == distinct) {
      counts[distinct * 2] = i;
      counts[distinct * 2 + 1] = 0;
      ++distinct;
    }
    counts[j * 2 + 1]++;
  }
  if (counts != NULL) {
    qsort(counts, (size_t)distinct, 2 * sizeof(int), CompareCounts);
  }
  char line[600];
  for (int k = 0; counts != NULL && k < distinct; ++k) {
    const Stack* stack = &g_samples[counts[k * 2]];
    fprintf(out, "\n%d samples:\n", counts[k * 2 + 1]);
    for (int f = 0; f < stack->count; ++f) {
      if (stack->pcs[f] == BAO_GAP) {
        fprintf(out, "    ...\n");
        continue;
      }
      Describe(stack->pcs[f], line, sizeof(line));
      fprintf(out, "    %s\n", line);
    }
  }
  free(counts);
  fclose(out);
}

// Milliseconds on a clock that only goes forward.
static int64_t Now(void) {
#if defined(_WIN32)
  return (int64_t)GetTickCount64();
#else
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
#endif
}

static void Run(void) {
  int taken = 0, missed = 0;
  Registers regs;
#if defined(_WIN32)
  HANDLE thread = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT |
                                 THREAD_QUERY_INFORMATION,
                             FALSE, g_ui_thread);
  if (thread == NULL) return;
#else
  // Where the thread's stack ends: the mapping its stack pointer is in.
  uintptr_t stack_end = 0;
  if (Ask(g_ui_thread, 0)) {
    uintptr_t start, end;
    if (Mapping(g_regs.sp, &start, &end, NULL, 0)) stack_end = end;
  }
  if (stack_end == 0) return;
#endif
  // Sleeps on Windows are a tick (15.6 ms) at the least, so the samples are
  // counted by the clock, not by the sleeps.
  const int64_t until = Now() + g_millis;
  while (Now() < until && taken < kMaxSamples) {
    size_t copied = 0;
#if defined(_WIN32)
    int got = Take(thread, &regs, &copied);
#else
    int got = Ask(g_ui_thread, stack_end);
    if (got) {
      regs = g_regs;
      copied = g_copied;
    }
#endif
    if (got) {
      const Copy copy = {g_copy, regs.sp, copied};
      Walk(&copy, &regs, &g_samples[taken++]);
    } else {
      ++missed;
    }
#if defined(_WIN32)
    Sleep((DWORD)g_interval);
#else
    struct timespec pause = {0, (long)g_interval * 1000 * 1000};
    while (nanosleep(&pause, &pause) != 0 && errno == EINTR) {
    }
#endif
  }
#if defined(_WIN32)
  CloseHandle(thread);
#endif
  WriteReport(taken, missed, g_millis);
}

#if defined(_WIN32)
static DWORD WINAPI Sampler(LPVOID unused) {
  (void)unused;
  Run();
  free(g_samples);
  free(g_path);
  InterlockedExchange(&g_busy, 0);
  return 0;
}
#else
static void* Sampler(void* unused) {
  (void)unused;
  Run();
  free(g_samples);
  free(g_path);
  atomic_store(&g_busy, 0);
  return NULL;
}
#endif

// ---------------------------------------------------------------------------
// The calls.

// Called on the UI thread, from the Dart code: that thread is the one
// sampled, and where the Dart code is is told by where this returns to.
// 0 where it cannot sample.
BAO_EXPORT int bao_sampler_init(void) {
  if (!FindDart(BAO_RETURN_ADDRESS())) return 0;
#if defined(_WIN32)
  g_ui_thread = GetCurrentThreadId();
  return 1;
#else
  g_ui_thread = (pid_t)syscall(SYS_gettid);
  if (g_signal != 0) return 1;
  // A real-time signal no one handles yet.
  for (int candidate = SIGRTMIN + 4; candidate <= SIGRTMAX; ++candidate) {
    struct sigaction old;
    if (sigaction(candidate, NULL, &old) != 0 || old.sa_handler != SIG_DFL ||
        (old.sa_flags & SA_SIGINFO) != 0) {
      continue;
    }
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_sigaction = Handler;
    action.sa_flags = SA_SIGINFO | SA_RESTART;
    sigemptyset(&action.sa_mask);
    if (sem_init(&g_taken, 0, 0) != 0) return 0;
    if (sigaction(candidate, &action, NULL) != 0) return 0;
    g_signal = candidate;
    return 1;
  }
  return 0;
#endif
}

// Samples the UI thread for |millis|, each |interval| ms, on a thread of its
// own, into the file at |path| (UTF-8), written once done. 0 if under way
// already, or not set up (bao_sampler_init).
BAO_EXPORT int bao_sampler_start(const char* path, int millis, int interval) {
  if (g_ui_thread == 0 || path == NULL || millis <= 0 || interval <= 0) {
    return 0;
  }
#if defined(_WIN32)
  if (InterlockedCompareExchange(&g_busy, 1, 0) != 0) return 0;
#else
  int idle = 0;
  if (!atomic_compare_exchange_strong(&g_busy, &idle, 1)) return 0;
#endif
  g_millis = millis;
  g_interval = interval;
  g_path = (char*)malloc(strlen(path) + 1);
  g_samples = (Stack*)calloc(kMaxSamples, sizeof(Stack));
  if (g_path != NULL) strcpy(g_path, path);
  int started = 0;
  if (g_path != NULL && g_samples != NULL) {
#if defined(_WIN32)
    HANDLE thread = CreateThread(NULL, 0, Sampler, NULL, 0, NULL);
    if (thread != NULL) {
      CloseHandle(thread);
      started = 1;
    }
#else
    pthread_t thread;
    if (pthread_create(&thread, NULL, Sampler, NULL) == 0) {
      pthread_detach(thread);
      started = 1;
    }
#endif
  }
  if (!started) {
    free(g_samples);
    free(g_path);
#if defined(_WIN32)
    InterlockedExchange(&g_busy, 0);
#else
    atomic_store(&g_busy, 0);
#endif
  }
  return started;
}
