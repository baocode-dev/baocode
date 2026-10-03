#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>
#include <ole2.h>

#include <algorithm>
#include <string>
#include <utility>
#include <vector>

#include "flutter_window.h"
#include "hang_watchdog.h"
#include "open_requests.h"
#include "utils.h"

namespace {

// Matches MainFlutterWindow.swift: wider than the 720 at which the sidebar
// docks beside the chat, and tall enough for the title bar and the composer.
constexpr unsigned int kDefaultWidth = 1024;
constexpr unsigned int kDefaultHeight = 760;

// Still fits the title bar and the composer's toolbar (client area, in
// logical pixels — the same numbers as macOS's contentMinSize).
constexpr unsigned int kMinClientWidth = 400;
constexpr unsigned int kMinClientHeight = 540;

// Held by the copy of the app that runs for the user, for as long as it
// runs: a second one started (the `code` command, Explorer's Open with)
// finds it taken, and hands its paths to the first (see OpenRequests).
// Local\ is the user's session, so another user's copy is another's.
constexpr wchar_t kSingleInstanceMutex[] = L"Local\\BaoCode.SingleInstance";

// Places |size| in the centre of the monitor under |origin|, capped to that
// monitor's work area. |size| and |placed| are in logical pixels: Create
// scales them for the monitor's DPI.
void PlaceOnMonitor(const Win32Window::Point& origin,
                    Win32Window::Size* size,
                    Win32Window::Point* placed) {
  const POINT target = {static_cast<LONG>(origin.x),
                        static_cast<LONG>(origin.y)};
  HMONITOR monitor = ::MonitorFromPoint(target, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  if (!::GetMonitorInfoW(monitor, &info)) {
    *placed = origin;
    return;
  }
  const double scale =
      ::FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  const RECT& work = info.rcWork;
  const int work_width =
      static_cast<int>((work.right - work.left) / scale);
  const int work_height =
      static_cast<int>((work.bottom - work.top) / scale);
  size->width = static_cast<unsigned int>(
      (std::min)(static_cast<int>(size->width), work_width));
  size->height = static_cast<unsigned int>(
      (std::min)(static_cast<int>(size->height), work_height));
  placed->x = static_cast<unsigned int>(
      static_cast<int>(work.left / scale) +
      (work_width - static_cast<int>(size->width)) / 2);
  placed->y = static_cast<unsigned int>(
      static_cast<int>(work.top / scale) +
      (work_height - static_cast<int>(size->height)) / 2);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // The paths it was started with, from the folder it was started in: for
  // this copy to open, or for the one already running.
  std::vector<std::string> open_paths = OpenPathsFromCommandLine();
#if defined(_DEBUG)
  // A debug build — `flutter run`'s, which starts the app it just built and
  // waits for it to connect its debugger — does not join the one copy of the
  // app that runs for the user (see kSingleInstanceMutex). Were it to, a copy
  // the user already has running (an installed one, most of the time) would
  // hold the name, and the app `flutter run` just started would find it
  // taken, hand its paths over and exit without ever starting an engine: the
  // tool would fail with "The log reader stopped unexpectedly, or never
  // started". Only a release build, the one installed, claims the name.
#else
  const HANDLE single_instance =
      ::CreateMutexW(nullptr, FALSE, kSingleInstanceMutex);
  if (single_instance != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    ForwardToRunningWindow(open_paths);
    ::CloseHandle(single_instance);
    return EXIT_SUCCESS;
  }
#endif

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins, and for the folder picker and clipboard imaging; through OLE,
  // which the files dragged onto the window need as well (RegisterDragDrop).
  ::OleInitialize(nullptr);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, std::move(open_paths));
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(kDefaultWidth, kDefaultHeight);
  Win32Window::Point placed = origin;
  PlaceOnMonitor(origin, &size, &placed);
  if (!window.Create(L"BaoCode", placed, size)) {
    return EXIT_FAILURE;
  }
  window.SetMinimumSize(Win32Window::Size(kMinClientWidth, kMinClientHeight));
  window.SetQuitOnClose(true);

  // A hang (closing a window, quitting) written down where it is: see
  // hang_watchdog.h.
  hang_watchdog::Start(window.GetHandle());

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }
  hang_watchdog::LoopEnded();

  ::OleUninitialize();
  return EXIT_SUCCESS;
}
