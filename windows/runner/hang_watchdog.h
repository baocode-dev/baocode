#ifndef RUNNER_HANG_WATCHDOG_H_
#define RUNNER_HANG_WATCHDOG_H_

#include <windows.h>

// Watches, from a thread of its own, the thread the app's windows run on —
// Flutter's too, its platform and UI threads being one. When that thread
// stops answering for a while, or the app is still there a while after its
// windows went, what each of the app's threads was doing is written to
// the data folder's logs\hangs (see log_folder.h): a text report (each
// thread's name and the calls on its stack, as module+offset, named where
// the symbols are known) and a minidump beside it. A hang, told apart from
// a slow close, and where it is.
//
// The Dart code's frames are app.so+offset: the release's symbols (CI's
// symbols-windows artifact, see tool/build_windows.dart) name them, as
// `llvm-symbolizer --obj=app.windows-x64.symbols 0x<offset>`. The other
// lines between them are what the walk, without the Dart code's unwind
// information, took for frames. The event log (lib/diagnostics/
// frame_watch.dart) has the slow frames before the hang and its own.
//
// The folder is made as the app starts: there, it tells that the copy that
// ran watched itself.
namespace hang_watchdog {

// What the watchdog posts the window it watches, every second; answered
// (see Answer) as it is dispatched. Posted, not sent: a thread waiting in a
// call that lets sent messages through (another process's window, a COM
// call) still takes no input, and counts as hung.
constexpr UINT kPingMessage = WM_APP + 0x43;

// Starts watching |window|'s thread, the caller's.
void Start(HWND window);

// kPingMessage dispatched: the thread is there.
void Answer();

// The message loop is over: the app is to be gone shortly.
void LoopEnded();

// Writes down a crash of the app (an exception nothing handled): a line
// in the event log (log_folder::AppendExit: "crashed: exception 0x… at
// module+0x…"), and a report as a hang's, crash-<time>-<pid>.txt and .dmp,
// the thread it came on first and the exception in the minidump. Then on
// to the filter there was (Windows Error Reporting's). After the engine
// starts, which may set a filter of its own.
void InstallCrashHandler();

// From another copy of the app, started while this one runs (Explorer's
// Open with BaoCode, the `code` command): the copy running did not take
// what it was handed, or has no window left. Its threads are written down
// as above, from this copy, which is still able to.
void ReportRunningCopy();

}  // namespace hang_watchdog

#endif  // RUNNER_HANG_WATCHDOG_H_
