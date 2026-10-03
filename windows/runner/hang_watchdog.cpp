#include "hang_watchdog.h"

// dbghelp.h needs windows.h first.
#include <windows.h>

#include <dbghelp.h>
#include <tlhelp32.h>

#include <atomic>
#include <cstdio>
#include <cwchar>
#include <string>
#include <vector>

namespace hang_watchdog {
namespace {

// How long the windows' thread may not answer before it counts as hung, and
// how long the app may still be there once its message loop is over.
constexpr ULONGLONG kHangMilliseconds = 6000;
constexpr ULONGLONG kExitMilliseconds = 10000;

// The most reports a run writes: a hang that comes and goes is written a
// few times, not on and on.
constexpr int kMaxReports = 3;

// The deepest a stack is followed.
constexpr int kMaxFrames = 64;

std::atomic<HWND> g_window{nullptr};
std::atomic<ULONGLONG> g_answered{0};
std::atomic<ULONGLONG> g_loop_ended{0};
DWORD g_windows_thread = 0;

// %APPDATA%\baocode\hangs (the data folder's default place), made if need
// be; empty if there is none.
std::wstring ReportFolder() {
  wchar_t app_data[MAX_PATH];
  const DWORD length =
      ::GetEnvironmentVariableW(L"APPDATA", app_data, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return std::wstring();
  }
  std::wstring folder = std::wstring(app_data) + L"\\baocode";
  ::CreateDirectoryW(folder.c_str(), nullptr);
  folder += L"\\hangs";
  ::CreateDirectoryW(folder.c_str(), nullptr);
  return folder;
}

// The name a thread was given (Flutter names its own: io.flutter.raster…),
// in UTF-8; empty for none, or before Windows 10 1607.
std::string ThreadName(HANDLE thread) {
  using GetThreadDescriptionProc = HRESULT(WINAPI*)(HANDLE, PWSTR*);
  static const auto get_description = reinterpret_cast<GetThreadDescriptionProc>(
      ::GetProcAddress(::GetModuleHandleW(L"kernel32.dll"),
                       "GetThreadDescription"));
  if (get_description == nullptr) {
    return std::string();
  }
  PWSTR description = nullptr;
  if (FAILED(get_description(thread, &description)) ||
      description == nullptr) {
    return std::string();
  }
  char name[256] = {};
  ::WideCharToMultiByte(CP_UTF8, 0, description, -1, name, sizeof(name) - 1,
                        nullptr, nullptr);
  ::LocalFree(description);
  return name;
}

// The return addresses on the stack |context| was taken at, innermost
// first. Taken after the thread runs again (see WriteThreads): a thread
// that hangs is still where it was.
std::vector<DWORD64> Walk(HANDLE process, HANDLE thread, CONTEXT context) {
  std::vector<DWORD64> frames;
  STACKFRAME64 frame = {};
#if defined(_M_ARM64) || defined(__aarch64__)
  const DWORD machine = IMAGE_FILE_MACHINE_ARM64;
  frame.AddrPC.Offset = context.Pc;
  frame.AddrFrame.Offset = context.Fp;
  frame.AddrStack.Offset = context.Sp;
#else
  const DWORD machine = IMAGE_FILE_MACHINE_AMD64;
  frame.AddrPC.Offset = context.Rip;
  frame.AddrFrame.Offset = context.Rbp;
  frame.AddrStack.Offset = context.Rsp;
#endif
  frame.AddrPC.Mode = AddrModeFlat;
  frame.AddrFrame.Mode = AddrModeFlat;
  frame.AddrStack.Mode = AddrModeFlat;
  for (int i = 0; i < kMaxFrames; ++i) {
    if (!::StackWalk64(machine, process, thread, &frame, &context, nullptr,
                       ::SymFunctionTableAccess64, ::SymGetModuleBase64,
                       nullptr) ||
        frame.AddrPC.Offset == 0) {
      break;
    }
    frames.push_back(frame.AddrPC.Offset);
  }
  return frames;
}

// |address| as module+offset, and the function's name where the module's
// symbols are known (its exports, at least).
std::string Describe(HANDLE process, DWORD64 address) {
  char line[600];
  IMAGEHLP_MODULE64 module = {};
  module.SizeOfStruct = sizeof(module);
  const bool known = ::SymGetModuleInfo64(process, address, &module) != FALSE;
  const char* module_name = known ? module.ModuleName : "?";
  const DWORD64 offset = known ? address - module.BaseOfImage : address;

  alignas(SYMBOL_INFO) char buffer[sizeof(SYMBOL_INFO) + 256] = {};
  auto* symbol = reinterpret_cast<SYMBOL_INFO*>(buffer);
  symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
  symbol->MaxNameLen = 255;
  DWORD64 displacement = 0;
  if (::SymFromAddr(process, address, &displacement, symbol)) {
    std::snprintf(line, sizeof(line), "%s+0x%llx  %s+0x%llx", module_name,
                  static_cast<unsigned long long>(offset), symbol->Name,
                  static_cast<unsigned long long>(displacement));
  } else {
    std::snprintf(line, sizeof(line), "%s+0x%llx", module_name,
                  static_cast<unsigned long long>(offset));
  }
  return line;
}

// Each thread of |process_id| (but the caller), its name and stack, to
// |out|; |windows_thread| marked as the one the windows run on.
void WriteThreads(FILE* out, HANDLE process, DWORD process_id,
                  DWORD windows_thread) {
  const DWORD self = ::GetCurrentThreadId();
  const HANDLE snapshot = ::CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  if (snapshot == INVALID_HANDLE_VALUE) {
    std::fprintf(out, "(the threads could not be listed)\n");
    return;
  }
  THREADENTRY32 entry = {};
  entry.dwSize = sizeof(entry);
  for (BOOL more = ::Thread32First(snapshot, &entry); more;
       more = ::Thread32Next(snapshot, &entry)) {
    if (entry.th32OwnerProcessID != process_id ||
        entry.th32ThreadID == self) {
      continue;
    }
    const HANDLE thread = ::OpenThread(
        THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT |
            THREAD_QUERY_LIMITED_INFORMATION,
        FALSE, entry.th32ThreadID);
    if (thread == nullptr) {
      continue;
    }
    std::fprintf(out, "\nThread %lu %s%s\n", entry.th32ThreadID,
                 ThreadName(thread).c_str(),
                 entry.th32ThreadID == windows_thread
                     ? " [the windows' thread: Flutter's platform and UI]"
                     : "");
    // Only the context while it is held: nothing that could wait on a
    // lock the thread has (the heap's) is done before it runs again.
    CONTEXT context = {};
    context.ContextFlags = CONTEXT_FULL;
    bool taken = false;
    if (::SuspendThread(thread) != static_cast<DWORD>(-1)) {
      taken = ::GetThreadContext(thread, &context) != FALSE;
      ::ResumeThread(thread);
    }
    if (taken) {
      for (const DWORD64 address : Walk(process, thread, context)) {
        std::fprintf(out, "  %s\n", Describe(process, address).c_str());
      }
    } else {
      std::fprintf(out, "  (its stack could not be read)\n");
    }
    ::CloseHandle(thread);
  }
  ::CloseHandle(snapshot);
}

// The report of |process| (this one, or the copy running: see
// ReportRunningCopy), for |reason|: a minidump and a text report.
void WriteReport(HANDLE process, DWORD process_id, DWORD windows_thread,
                 const char* reason) {
  const std::wstring folder = ReportFolder();
  if (folder.empty()) {
    return;
  }
  SYSTEMTIME now = {};
  ::GetLocalTime(&now);
  wchar_t stamp[64];
  std::swprintf(stamp, 64, L"\\hang-%04u%02u%02u-%02u%02u%02u-%lu",
                static_cast<unsigned>(now.wYear),
                static_cast<unsigned>(now.wMonth),
                static_cast<unsigned>(now.wDay),
                static_cast<unsigned>(now.wHour),
                static_cast<unsigned>(now.wMinute),
                static_cast<unsigned>(now.wSecond), process_id);
  const std::wstring base = folder + stamp;

  // The minidump first: it stands on its own, for a debugger.
  const HANDLE dump =
      ::CreateFileW((base + L".dmp").c_str(), GENERIC_WRITE, 0, nullptr,
                    CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (dump != INVALID_HANDLE_VALUE) {
    ::MiniDumpWriteDump(
        process, process_id, dump,
        static_cast<MINIDUMP_TYPE>(MiniDumpWithThreadInfo |
                                   MiniDumpWithUnloadedModules |
                                   MiniDumpWithProcessThreadData),
        nullptr, nullptr, nullptr);
    ::CloseHandle(dump);
  }

  FILE* out = nullptr;
  if (_wfopen_s(&out, (base + L".txt").c_str(), L"w") != 0 || out == nullptr) {
    return;
  }
#ifdef FLUTTER_VERSION
  std::fprintf(out, "BaoCode %s\n", FLUTTER_VERSION);
#endif
  std::fprintf(out, "Process %lu: %s\n", process_id, reason);
  // The symbols of the modules loaded, from beside them only (the
  // executable's folder first): no network, no prompts.
  char executable[MAX_PATH] = {};
  ::GetModuleFileNameA(nullptr, executable, MAX_PATH);
  std::string search = executable;
  search = search.substr(0, search.find_last_of('\\'));
  ::SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS |
                  SYMOPT_FAIL_CRITICAL_ERRORS | SYMOPT_NO_PROMPTS);
  const bool symbols = ::SymInitialize(process, search.c_str(), TRUE) != FALSE;
  WriteThreads(out, process, process_id, windows_thread);
  if (symbols) {
    ::SymCleanup(process);
  }
  std::fclose(out);
}

void WriteOwnReport(const char* reason) {
  WriteReport(::GetCurrentProcess(), ::GetCurrentProcessId(),
              g_windows_thread, reason);
}

DWORD WINAPI Watch(LPVOID) {
  int reports = 0;
  // Whether the hang under way was written: once until the thread answers
  // again.
  bool written = false;
  while (reports < kMaxReports) {
    ::Sleep(1000);
    const ULONGLONG now = ::GetTickCount64();
    const ULONGLONG ended = g_loop_ended.load();
    if (ended != 0) {
      if (now - ended >= kExitMilliseconds) {
        WriteOwnReport("Still running 10 s after the message loop ended.");
        return 0;
      }
      continue;
    }
    const HWND window = g_window.load();
    if (window == nullptr || !::IsWindow(window)) {
      continue;
    }
    // Paused in a debugger, the thread answers no one.
    if (::IsDebuggerPresent()) {
      g_answered.store(now);
      continue;
    }
    ::PostMessageW(window, kPingMessage, 0, 0);
    if (now - g_answered.load() < kHangMilliseconds) {
      written = false;
      continue;
    }
    if (written) {
      continue;
    }
    written = true;
    ++reports;
    WriteOwnReport("The windows' thread took no message for 6 s.");
  }
  return 0;
}

// The file name |path| ends in.
const wchar_t* FileName(const wchar_t* path) {
  const wchar_t* slash = std::wcsrchr(path, L'\\');
  return slash == nullptr ? path : slash + 1;
}

}  // namespace

void Start(HWND window) {
  if (g_window.exchange(window) != nullptr) {
    return;
  }
  g_windows_thread = ::GetCurrentThreadId();
  g_answered.store(::GetTickCount64());
  // There from the start: this copy watches itself.
  ReportFolder();
  const HANDLE thread = ::CreateThread(nullptr, 0, Watch, nullptr, 0, nullptr);
  if (thread != nullptr) {
    ::CloseHandle(thread);
  }
}

void Answer() {
  g_answered.store(::GetTickCount64());
}

void LoopEnded() {
  g_loop_ended.store(::GetTickCount64());
}

void ReportRunningCopy() {
  // The other process of this executable's name: the copy running.
  wchar_t executable[MAX_PATH] = {};
  ::GetModuleFileNameW(nullptr, executable, MAX_PATH);
  const wchar_t* name = FileName(executable);
  const DWORD self = ::GetCurrentProcessId();
  DWORD running = 0;
  const HANDLE snapshot = ::CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) {
    return;
  }
  PROCESSENTRY32W entry = {};
  entry.dwSize = sizeof(entry);
  for (BOOL more = ::Process32FirstW(snapshot, &entry); more;
       more = ::Process32NextW(snapshot, &entry)) {
    if (entry.th32ProcessID != self && _wcsicmp(entry.szExeFile, name) == 0) {
      running = entry.th32ProcessID;
      break;
    }
  }
  ::CloseHandle(snapshot);
  if (running == 0) {
    return;
  }
  const HANDLE process =
      ::OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ |
                        PROCESS_DUP_HANDLE,
                    FALSE, running);
  if (process == nullptr) {
    return;
  }
  // Its windows' thread: the one that made its first thread's windows, its
  // main thread (the first the snapshot lists of it).
  DWORD windows_thread = 0;
  const HANDLE threads = ::CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  if (threads != INVALID_HANDLE_VALUE) {
    THREADENTRY32 thread = {};
    thread.dwSize = sizeof(thread);
    for (BOOL more = ::Thread32First(threads, &thread); more;
         more = ::Thread32Next(threads, &thread)) {
      if (thread.th32OwnerProcessID == running) {
        windows_thread = thread.th32ThreadID;
        break;
      }
    }
    ::CloseHandle(threads);
  }
  WriteReport(process, running, windows_thread,
              "Another copy, started to open paths, found this one not "
              "taking them (or without a window).");
  ::CloseHandle(process);
}

}  // namespace hang_watchdog
