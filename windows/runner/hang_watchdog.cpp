#include "hang_watchdog.h"

#include <windows.h>

#include <tlhelp32.h>
#include <werapi.h>

#include <atomic>
#include <cstdio>
#include <cwchar>
#include <string>

#include "crash_report.h"
#include "log_folder.h"

namespace hang_watchdog {
namespace {

// How long the windows' thread may not answer before it counts as hung, and
// how long the app may still be there once its message loop is over.
constexpr ULONGLONG kHangMilliseconds = 6000;
constexpr ULONGLONG kExitMilliseconds = 10000;

// The longest a crash's report is waited for before the app goes.
constexpr DWORD kCrashMilliseconds = 15000;

// The most reports a run writes: a hang that comes and goes is written a
// few times, not on and on.
constexpr int kMaxReports = 3;

// Longer than this between two of the watch's 1 s rounds, the watch itself
// was not running (the computer asleep, the process suspended): the windows'
// thread was not either, so it is given a fresh start.
constexpr ULONGLONG kWatchGapMilliseconds = 3000;

// Milliseconds the computer has been running, its sleep and hibernation left
// out (GetTickCount64 counts them): waking up is no hang.
ULONGLONG Now() {
  ULONGLONG hundreds_of_nanoseconds = 0;
  ::QueryUnbiasedInterruptTime(&hundreds_of_nanoseconds);
  return hundreds_of_nanoseconds / 10000;
}

std::atomic<HWND> g_window{nullptr};
std::atomic<ULONGLONG> g_answered{0};
std::atomic<ULONGLONG> g_loop_ended{0};
DWORD g_windows_thread = 0;

// The data folder's logs\hangs (see log_folder.h), made if need be; empty
// if there is none.
std::wstring ReportFolder() {
  return crash_report::ReportFolder(log_folder::Path());
}

// What baocode_wer.dll is told of the app (see RegisterFastFailModule).
crash_report::FastFailContext g_fast_fail = {};

// |logs| as g_fast_fail's, cut short if need be.
void SetFastFailLogs(const std::wstring& logs) {
  ::wcsncpy_s(g_fast_fail.logs, logs.c_str(), _TRUNCATE);
}

// baocode_wer.dll (windows/wer), beside the executable, registered with
// Windows Error Reporting for this process: a fast fail (abort() in a
// module with its own C runtime, flutter_windows.dll's) ends the process
// without the crash filter, and Windows Error Reporting's process has the
// module write it down instead. Listed for the user as such a module
// (RuntimeExceptionHelperModules) first, as Windows requires; the
// installer removes the value as it uninstalls (tool/baocode.iss).
void RegisterFastFailModule() {
  wchar_t executable[MAX_PATH] = {};
  const DWORD length = ::GetModuleFileNameW(nullptr, executable, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return;
  }
  std::wstring module = executable;
  module = module.substr(0, module.find_last_of(L'\\') + 1) +
           L"baocode_wer.dll";
  if (::GetFileAttributesW(module.c_str()) == INVALID_FILE_ATTRIBUTES) {
    return;
  }
  const DWORD listed = 0;
  if (::RegSetKeyValueW(HKEY_CURRENT_USER,
                        L"Software\\Microsoft\\Windows\\Windows Error "
                        L"Reporting\\RuntimeExceptionHelperModules",
                        module.c_str(), REG_DWORD, &listed,
                        sizeof(listed)) != ERROR_SUCCESS) {
    return;
  }
  g_fast_fail.size = sizeof(g_fast_fail);
  g_fast_fail.windows_thread = g_windows_thread;
  SetFastFailLogs(log_folder::Path());
  ::WerRegisterRuntimeExceptionModule(module.c_str(), &g_fast_fail);
}


void WriteOwnReport(const char* reason) {
  crash_report::Write(ReportFolder(), ::GetCurrentProcess(),
                      ::GetCurrentProcessId(), g_windows_thread, reason);
}

DWORD WINAPI Watch(LPVOID) {
  int reports = 0;
  // Whether the hang under way was written: once until the thread answers
  // again.
  bool written = false;
  ULONGLONG last_round = Now();
  while (reports < kMaxReports) {
    ::Sleep(1000);
    const ULONGLONG now = Now();
    const bool resumed = now - last_round > kWatchGapMilliseconds;
    last_round = now;
    const ULONGLONG ended = g_loop_ended.load();
    if (ended != 0) {
      if (now - ended >= kExitMilliseconds) {
        WriteOwnReport("Still running 10 s after the message loop ended.");
        return 0;
      }
      continue;
    }
    const HWND window = g_window.load();
    // WM_DESTROY can invalidate the HWND before engine teardown finishes.
    // Keep watching until the message loop ends, not just while it exists.
    if (window == nullptr) {
      continue;
    }
    // Paused in a debugger, the thread answers no one; back from a pause of
    // the watch's own, it has had no turn to.
    if (resumed || ::IsDebuggerPresent()) {
      g_answered.store(now);
      continue;
    }
    ::PostMessageW(window, kPingMessage, 0, 0);
    // The thread, idle, can take the ping before this reads the time it
    // did: that time is then after |now|, and taken from it, wraps round to
    // a hang of centuries.
    const ULONGLONG answered = g_answered.load();
    if (answered >= now || now - answered < kHangMilliseconds) {
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

// The filter the app's crash handler came after (Flutter's, if any).
LPTOP_LEVEL_EXCEPTION_FILTER g_previous_filter = nullptr;
std::atomic<bool> g_crashed{false};

// Writes down |param|'s crash (a Crash), from a thread of its own: the
// one it came on may have no stack left (a stack overflow), or hold a lock.
DWORD WINAPI WriteCrash(LPVOID param) {
  const auto* crash = static_cast<const crash_report::Crash*>(param);
  const HANDLE process = ::GetCurrentProcess();
  const EXCEPTION_RECORD* record = crash->pointers->ExceptionRecord;
  // Where, for the event log's line: module+offset (app.so's for the Dart
  // code), no symbols (DbgHelp loads them in crash_report::Write).
  char how[512];
  std::snprintf(
      how, sizeof(how), "crashed: exception 0x%08lx at %s",
      record->ExceptionCode,
      crash_report::Where(process,
                          reinterpret_cast<DWORD64>(record->ExceptionAddress))
          .c_str());
  log_folder::AppendExit(how);
  crash_report::Write(ReportFolder(), process, ::GetCurrentProcessId(),
                      g_windows_thread, how, L"crash", crash);
  return 0;
}

LONG WINAPI OnCrash(EXCEPTION_POINTERS* pointers) {
  if (!g_crashed.exchange(true)) {
    crash_report::Crash crash = {pointers, ::GetCurrentThreadId()};
    const HANDLE thread =
        ::CreateThread(nullptr, 0, WriteCrash, &crash, 0, nullptr);
    if (thread != nullptr) {
      ::WaitForSingleObject(thread, kCrashMilliseconds);
      ::CloseHandle(thread);
    }
  }
  // On to Windows Error Reporting, as before.
  return g_previous_filter != nullptr ? g_previous_filter(pointers)
                                      : EXCEPTION_CONTINUE_SEARCH;
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
  g_answered.store(Now());
  // There from the start: this copy watches itself.
  ReportFolder();
  const HANDLE thread = ::CreateThread(nullptr, 0, Watch, nullptr, 0, nullptr);
  if (thread != nullptr) {
    ::CloseHandle(thread);
  }
}

void Answer() {
  g_answered.store(Now());
}

void LoopEnded() {
  g_loop_ended.store(Now());
}

void InstallCrashHandler() {
  g_previous_filter = ::SetUnhandledExceptionFilter(OnCrash);
  RegisterFastFailModule();
}

void LogsFolderNamed(const std::wstring& logs) {
  SetFastFailLogs(logs);
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
  crash_report::Write(ReportFolder(), process, running, windows_thread,
                      "Another copy, started to open paths, found this one "
                      "not taking them (or without a window).");
  ::CloseHandle(process);
}

}  // namespace hang_watchdog
