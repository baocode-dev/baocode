#ifndef RUNNER_OPEN_REQUESTS_H_
#define RUNNER_OPEN_REQUESTS_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <string>
#include <vector>

// The paths the app is asked to open from outside it — what it is started
// with (the `code` command, see lib/platform/shell_command_io.dart; Explorer's
// Open with), and what another copy started later hands it — for Flutter,
// over the `baocode/open` channel (as AppDelegate.swift's OpenRequests does;
// see lib/platform/open_requests.dart):
//
//   takePending   the paths kept so far; Flutter is ready for each as it
//                 comes from then on
//   stop          Flutter stopped listening: kept again until it next asks
//   open (paths)  sent to Flutter, once it is ready
//
// One copy of the app runs for the user (see main.cpp): a second one hands
// its paths to the first's window (WM_COPYDATA, see ForwardToRunningWindow)
// and goes.
class OpenRequests {
 public:
  OpenRequests(flutter::BinaryMessenger* messenger,
               std::vector<std::string> pending);
  ~OpenRequests();

  OpenRequests(const OpenRequests&) = delete;
  OpenRequests& operator=(const OpenRequests&) = delete;

  // Hands |paths| (UTF-8, absolute) to Flutter, or keeps them until it is
  // ready.
  void Deliver(std::vector<std::string> paths);

 private:
  std::vector<std::string> pending_;
  bool ready_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

// What a WM_COPYDATA carrying paths to open has as its dwData: told from
// any other app's copy data by it.
constexpr ULONG_PTR kOpenRequestData = 0x42414F43;  // "BAOC"

// The paths in the command line the app was started with, made absolute
// from the folder it was started in, in UTF-8; its options (from `-`) left
// out.
std::vector<std::string> OpenPathsFromCommandLine();

// Marks |window| as the one that takes the paths a second copy of the app
// hands over (see ForwardToRunningWindow), or, as it goes, no longer.
void MarkOpenRequestWindow(HWND window, bool marked);

// Hands |paths| to the window of the copy of the app already running, which
// comes to the front (none: it does only that). Waits a little for its
// window while it is still starting; false when there is none by then.
bool ForwardToRunningWindow(const std::vector<std::string>& paths);

// The paths in |data|, when it is a WM_COPYDATA of ForwardToRunningWindow's
// (see kOpenRequestData); none otherwise.
std::vector<std::string> OpenRequestPaths(const COPYDATASTRUCT& data);

#endif  // RUNNER_OPEN_REQUESTS_H_
