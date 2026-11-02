// baocode_wer.dll: a runtime exception module of Windows Error Reporting's
// (WerRegisterRuntimeExceptionModule), which the app registers as it starts
// (hang_watchdog::InstallCrashHandler). Windows loads it into its own
// process (WerFault.exe) only as the app crashes, and asks it first.
//
// A fast fail ends the app without the crash filter the app installed:
// abort() in flutter_windows.dll, which carries its own C runtime (the
// engine's fatal errors, the Dart VM's), and a broken stack cookie. Of
// those, it writes what the filter writes of the others: the event log's
// [exit] line and a crash report (crash_report.h), the app's memory read
// for where. It claims none: Windows goes on as before (its own report, its
// dialog).
//
// Its C runtime is linked in (CMakeLists.txt): WerFault.exe finds no DLLs
// beside the app's.

#include <windows.h>

#include <werapi.h>

#include <cstdio>
#include <string>

#include "../runner/crash_report.h"

namespace {

// STATUS_STACK_BUFFER_OVERRUN: what a fast fail raises, its code the first
// parameter.
constexpr DWORD kFastFail = 0xC0000409;

// FAST_FAIL_FATAL_APP_EXIT: abort()'s.
constexpr ULONG_PTR kFatalAppExit = 7;

void WriteFastFail(const crash_report::FastFailContext& app,
                   const WER_RUNTIME_EXCEPTION_INFORMATION& information) {
  const HANDLE process = information.hProcess;
  const EXCEPTION_RECORD& record = information.exceptionRecord;
  const ULONG_PTR code =
      record.NumberParameters > 0 ? record.ExceptionInformation[0] : 0;
  char how[512];
  std::snprintf(
      how, sizeof(how), "crashed: fast fail %llu (%s) at %s",
      static_cast<unsigned long long>(code),
      code == kFatalAppExit ? "abort()" : "exception 0xc0000409",
      crash_report::Where(process,
                          reinterpret_cast<DWORD64>(record.ExceptionAddress))
          .c_str());
  const std::wstring logs = app.logs;
  crash_report::AppendExit(logs, how);
  // The exception's, in this process's memory.
  EXCEPTION_RECORD exception = record;
  CONTEXT context = information.context;
  EXCEPTION_POINTERS pointers = {&exception, &context};
  const crash_report::Crash crash = {&pointers,
                                     ::GetThreadId(information.hThread)};
  crash_report::Write(crash_report::ReportFolder(logs), process,
                      ::GetProcessId(process), app.windows_thread, how,
                      L"crash", &crash);
}

}  // namespace

extern "C" __declspec(dllexport) HRESULT WINAPI
OutOfProcessExceptionEventCallback(
    PVOID context, const PWER_RUNTIME_EXCEPTION_INFORMATION information,
    BOOL* ownership_claimed, PWSTR /*event_name*/, PDWORD /*event_name_size*/,
    PDWORD /*signature_count*/) {
  *ownership_claimed = FALSE;
  // The crashes the app's filter saw are written already.
  if (information == nullptr ||
      information->exceptionRecord.ExceptionCode != kFastFail) {
    return S_OK;
  }
  crash_report::FastFailContext app = {};
  SIZE_T read = 0;
  if (!::ReadProcessMemory(information->hProcess, context, &app, sizeof(app),
                           &read) ||
      read != sizeof(app) || app.size != sizeof(app)) {
    return S_OK;
  }
  app.logs[ARRAYSIZE(app.logs) - 1] = L'\0';
  WriteFastFail(app, *information);
  return S_OK;
}

// Asked of a module that claimed the crash only.
extern "C" __declspec(dllexport) HRESULT WINAPI
OutOfProcessExceptionEventSignatureCallback(
    PVOID, const PWER_RUNTIME_EXCEPTION_INFORMATION, DWORD, PWSTR, PDWORD,
    PWSTR, PDWORD) {
  return E_NOTIMPL;
}

extern "C" __declspec(dllexport) HRESULT WINAPI
OutOfProcessExceptionEventDebuggerLaunchCallback(
    PVOID, const PWER_RUNTIME_EXCEPTION_INFORMATION, PBOOL, PWSTR, PDWORD,
    PBOOL) {
  return E_NOTIMPL;
}
