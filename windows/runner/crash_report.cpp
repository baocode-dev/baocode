#include "crash_report.h"

// dbghelp.h needs windows.h first.
#include <windows.h>

#include <dbghelp.h>
#include <psapi.h>
#include <tlhelp32.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace crash_report {
namespace {

// The deepest a stack is followed.
constexpr int kMaxFrames = 64;

// The most reports kept in the folder, across runs: the oldest go as a new
// one is written.
constexpr size_t kKeptReports = 10;

// Leaves room in |folder| for one more report: of the reports there
// (hang-*.txt and the .dmp beside each), all but the newest
// kKeptReports - 1 are deleted. Their names (hang-YYYYMMDD-HHMMSS-pid) sort
// as their times.
void PruneReports(const std::wstring& folder, const wchar_t* kind) {
  std::vector<std::wstring> reports;
  WIN32_FIND_DATAW found = {};
  const HANDLE find = ::FindFirstFileW(
      (folder + L"\\" + kind + L"-*.txt").c_str(), &found);
  if (find == INVALID_HANDLE_VALUE) {
    return;
  }
  do {
    std::wstring name = found.cFileName;
    reports.push_back(name.substr(0, name.size() - 4));
  } while (::FindNextFileW(find, &found));
  ::FindClose(find);
  if (reports.size() < kKeptReports) {
    return;
  }
  std::sort(reports.begin(), reports.end());
  const size_t old = reports.size() - (kKeptReports - 1);
  for (size_t i = 0; i < old; ++i) {
    const std::wstring base = folder + L"\\" + reports[i];
    ::DeleteFileW((base + L".txt").c_str());
    ::DeleteFileW((base + L".dmp").c_str());
  }
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

// Where the memory |address| is in was reserved, if that is where an ELF
// file was loaded: the app's Dart code, app.so, which Dart's own loader
// puts in memory (no module Windows knows), its first byte at the start
// of the range it reserves. Offsets from there are the addresses of the
// file, which the symbols saved as it was built (tool/build_windows.dart)
// name. 0 for any other memory.
DWORD64 ElfBase(HANDLE process, DWORD64 address) {
  MEMORY_BASIC_INFORMATION memory = {};
  if (::VirtualQueryEx(process, reinterpret_cast<LPCVOID>(address), &memory,
                       sizeof(memory)) != sizeof(memory) ||
      memory.AllocationBase == nullptr) {
    return 0;
  }
  char magic[4] = {};
  SIZE_T read = 0;
  if (!::ReadProcessMemory(process, memory.AllocationBase, magic,
                           sizeof(magic), &read) ||
      read != sizeof(magic) || std::memcmp(magic, "\x7f" "ELF", 4) != 0) {
    return 0;
  }
  return reinterpret_cast<DWORD64>(memory.AllocationBase);
}

// |address| as module+offset, and the function's name where the module's
// symbols are known (its exports, at least).
std::string Describe(HANDLE process, DWORD64 address) {
  char line[600];
  IMAGEHLP_MODULE64 module = {};
  module.SizeOfStruct = sizeof(module);
  const bool known = ::SymGetModuleInfo64(process, address, &module) != FALSE;
  if (!known) {
    if (const DWORD64 base = ElfBase(process, address)) {
      std::snprintf(line, sizeof(line), "app.so+0x%llx",
                    static_cast<unsigned long long>(address - base));
      return line;
    }
  }
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

}  // namespace

std::wstring ReportFolder(const std::wstring& logs) {
  if (logs.empty()) {
    return std::wstring();
  }
  const std::wstring folder = logs + L"\\hangs";
  ::CreateDirectoryW(folder.c_str(), nullptr);
  return folder;
}

std::string Where(HANDLE process, DWORD64 address) {
  char where[400] = "?";
  HMODULE modules[1024];
  DWORD needed = 0;
  if (::K32EnumProcessModules(process, modules, sizeof(modules), &needed)) {
    const DWORD count =
        std::min<DWORD>(needed / sizeof(HMODULE), ARRAYSIZE(modules));
    for (DWORD i = 0; i < count; ++i) {
      MODULEINFO info = {};
      if (!::K32GetModuleInformation(process, modules[i], &info,
                                     sizeof(info))) {
        continue;
      }
      const DWORD64 base = reinterpret_cast<DWORD64>(info.lpBaseOfDll);
      if (address < base || address >= base + info.SizeOfImage) {
        continue;
      }
      char name[MAX_PATH] = "?";
      ::K32GetModuleBaseNameA(process, modules[i], name, MAX_PATH);
      std::snprintf(where, sizeof(where), "%s+0x%llx", name,
                    static_cast<unsigned long long>(address - base));
      return where;
    }
  }
  if (const DWORD64 base = ElfBase(process, address)) {
    std::snprintf(where, sizeof(where), "app.so+0x%llx",
                  static_cast<unsigned long long>(address - base));
  }
  return where;
}

void AppendExit(const std::wstring& logs, const char* how) {
  if (logs.empty()) {
    return;
  }
  FILE* out = nullptr;
  // Binary: a line ends in \n alone, as Flutter's do.
  if (_wfopen_s(&out, (logs + L"\\events.log").c_str(), L"ab") != 0 ||
      out == nullptr) {
    return;
  }
  SYSTEMTIME now = {};
  ::GetLocalTime(&now);
  std::fprintf(out, "%04u-%02u-%02uT%02u:%02u:%02u.%03u [exit] %s\n",
               now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute,
               now.wSecond, now.wMilliseconds, how);
  std::fclose(out);
}

void Write(const std::wstring& folder, HANDLE process, DWORD process_id,
           DWORD windows_thread, const char* reason, const wchar_t* kind,
           const Crash* crash) {
  if (folder.empty()) {
    return;
  }
  PruneReports(folder, kind);
  SYSTEMTIME now = {};
  ::GetLocalTime(&now);
  wchar_t stamp[64];
  std::swprintf(stamp, 64, L"\\%ls-%04u%02u%02u-%02u%02u%02u-%lu", kind,
                static_cast<unsigned>(now.wYear),
                static_cast<unsigned>(now.wMonth),
                static_cast<unsigned>(now.wDay),
                static_cast<unsigned>(now.wHour),
                static_cast<unsigned>(now.wMinute),
                static_cast<unsigned>(now.wSecond), process_id);
  const std::wstring base = folder + stamp;

  FILE* out = nullptr;
  if (_wfopen_s(&out, (base + L".txt").c_str(), L"w") != 0 || out == nullptr) {
    return;
  }
#ifdef FLUTTER_VERSION
  std::fprintf(out, "BaoCode %s\n", FLUTTER_VERSION);
#endif
  std::fprintf(out, "Process %lu: %s\n", process_id, reason);
  // In-process dump writing can itself block on the hung process. Keep a
  // flushed text report before entering DbgHelp, even if it never returns.
  std::fflush(out);
  // The symbols of the modules loaded, from beside them only (the
  // executable's folder first): no network, no prompts. The process's own
  // executable: this may be another's (Windows Error Reporting's, see
  // windows/wer).
  char executable[MAX_PATH] = {};
  DWORD executable_size = MAX_PATH;
  ::QueryFullProcessImageNameA(process, 0, executable, &executable_size);
  std::string search = executable;
  search = search.substr(0, search.find_last_of('\\'));
  ::SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS |
                  SYMOPT_FAIL_CRITICAL_ERRORS | SYMOPT_NO_PROMPTS);
  const bool symbols = ::SymInitialize(process, search.c_str(), TRUE) != FALSE;
  if (crash != nullptr) {
    const HANDLE thread =
        ::OpenThread(THREAD_GET_CONTEXT | THREAD_QUERY_LIMITED_INFORMATION,
                     FALSE, crash->thread);
    std::fprintf(out, "\nThread %lu %s [crashed]\n", crash->thread,
                 thread == nullptr ? "" : ThreadName(thread).c_str());
    if (thread != nullptr) {
      for (const DWORD64 address :
           Walk(process, thread, *crash->pointers->ContextRecord)) {
        std::fprintf(out, "  %s\n", Describe(process, address).c_str());
      }
      ::CloseHandle(thread);
    }
    std::fflush(out);
  }
  WriteThreads(out, process, process_id, windows_thread);
  if (symbols) {
    ::SymCleanup(process);
  }
  std::fclose(out);

  const HANDLE dump =
      ::CreateFileW((base + L".dmp").c_str(), GENERIC_WRITE, 0, nullptr,
                    CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (dump != INVALID_HANDLE_VALUE) {
    MINIDUMP_EXCEPTION_INFORMATION exception = {};
    if (crash != nullptr) {
      exception.ThreadId = crash->thread;
      exception.ExceptionPointers = crash->pointers;
      exception.ClientPointers = FALSE;
    }
    ::MiniDumpWriteDump(
        process, process_id, dump,
        static_cast<MINIDUMP_TYPE>(MiniDumpWithThreadInfo |
                                   MiniDumpWithUnloadedModules |
                                   MiniDumpWithProcessThreadData),
        crash != nullptr ? &exception : nullptr, nullptr, nullptr);
    ::CloseHandle(dump);
  }
}

}  // namespace crash_report
