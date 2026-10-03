#ifndef RUNNER_HANG_WATCHDOG_H_
#define RUNNER_HANG_WATCHDOG_H_

#include <windows.h>

// Watches, from a thread of its own, the thread the app's windows run on —
// Flutter's too, its platform and UI threads being one. When that thread
// stops answering for a while, or the app is still there a while after its
// windows went, what each of the app's threads was doing is written to
// %APPDATA%\baocode\hangs: a text report (each thread's name and the calls
// on its stack, as module+offset, named where the symbols are known) and a
// minidump beside it. A hang, told apart from a slow close, and where it is.
namespace hang_watchdog {

// Starts watching |window|'s thread, the caller's.
void Start(HWND window);

// The message loop is over: the app is to be gone shortly.
void LoopEnded();

}  // namespace hang_watchdog

#endif  // RUNNER_HANG_WATCHDOG_H_
