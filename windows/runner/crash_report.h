#ifndef RUNNER_CRASH_REPORT_H_
#define RUNNER_CRASH_REPORT_H_

#include <windows.h>

#include <string>

// The reports in the logs folder's hangs\ (see hang_watchdog.h), written of
// a process from any process: the app's of itself (a hang, a crash its
// filter sees) and of the copy running, and baocode_wer.dll's (windows/wer)
// from Windows Error Reporting's of an app that ended without its filter
// seeing (a fast fail, abort()'s). A text report (each thread's name and
// the calls on its stack, as module+offset) and a minidump beside it.
namespace crash_report {

// What a crash report is of: the exception, and the thread it came on.
struct Crash {
  EXCEPTION_POINTERS* pointers;
  DWORD thread;
};

// What the app tells baocode_wer.dll (windows/wer) of itself, as Windows
// Error Reporting's context for it: read from the app's memory as it ends.
struct FastFailContext {
  // sizeof(FastFailContext), the same build's.
  DWORD size;
  // The thread the app's windows run on.
  DWORD windows_thread;
  // The logs folder (see log_folder.h); empty if there is none.
  wchar_t logs[1024];
};

// |logs|' hangs\, made if need be; empty if |logs| is.
std::wstring ReportFolder(const std::wstring& logs);

// Where |address| is in |process|: module+0x… (app.so+0x… for the Dart
// code), "?" outside them. No symbols.
std::string Where(HANDLE process, DWORD64 address);

// Writes how the app is ending to |logs|' event log (lib/platform/
// event_log.dart's events.log), as Flutter's lines: "<time> [exit] |how|".
void AppendExit(const std::wstring& logs, const char* how);

// The report of |process| in |folder| (ReportFolder's), for |reason|: a
// minidump and a text report, named |kind|-<time>-<pid> (hang, crash), the
// oldest of its kind deleted past ten. With |crash|, the thread it came on
// first, from where it came, and the exception in the minidump.
void Write(const std::wstring& folder, HANDLE process, DWORD process_id,
           DWORD windows_thread, const char* reason,
           const wchar_t* kind = L"hang", const Crash* crash = nullptr);

}  // namespace crash_report

#endif  // RUNNER_CRASH_REPORT_H_
