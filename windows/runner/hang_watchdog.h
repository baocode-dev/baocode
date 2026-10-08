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

// From another copy of the app, started while this one runs (Explorer's
// Open with BaoCode, the `code` command): the copy running did not take
// what it was handed, or has no window left. Its threads are written down
// as above, from this copy, which is still able to.
void ReportRunningCopy();

}  // namespace hang_watchdog

#endif  // RUNNER_HANG_WATCHDOG_H_
