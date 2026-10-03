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
  // ready; or a request (see IsRequest), which goes as it came, its flag
  // made the marker Flutter knows it by (lib/window/code_args.dart's
  // requestMarker, agentRequestMarker).
  void Deliver(std::vector<std::string> paths);

 private:
  // Kept: the paths, and the requests after them (in the order they came).
  std::vector<std::string> pending_;
  std::vector<std::vector<std::string>> pending_requests_;
  bool ready_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

// What a WM_COPYDATA carrying paths to open has as its dwData: told from
// any other app's copy data by it.
constexpr ULONG_PTR kOpenRequestData = 0x42414F43;  // "BAOC"

// The flag code.cmd starts the app with (see
// lib/platform/shell_command_io.dart): the console's folder comes next, then
// the arguments as typed (`-n`, `-r`, `-g file:line`, the paths), which
// Flutter reads as VS Code's CLI does.
constexpr char kCodeRequestFlag[] = "--baocode-cli";

// The flag Explorer's Open with BaoCode starts the app with (the context
// menu the installer adds, see tool/baocode.iss), the path next: a new agent
// in the chat's window, the file in its composer (lib/window/app_windows.dart's
// openAgent).
constexpr char kAgentRequestFlag[] = "--baocode-agent";

// Whether |paths| are a request rather than paths: kCodeRequestFlag or
// kAgentRequestFlag first.
bool IsRequest(const std::vector<std::string>& paths);

// Whether the app was started for Open with BaoCode (kAgentRequestFlag): its
// window then opens narrow, for the conversation alone.
bool StartedForAgent();

// The paths in the command line the app was started with, made absolute
// from the folder it was started in, in UTF-8; its options (from `-`) left
// out. Started by code.cmd, the request it makes instead, as it came; by
// Open with BaoCode, its flag, then the paths (see IsRequest).
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
