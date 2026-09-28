#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include <algorithm>
#include <vector>

#include "flutter_window.h"
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

int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

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

// The outer-frame size that holds a client area of |client_width| by
// |client_height| under |style| and |ex_style|, in the same units as those
// sizes (logical, when they are).
Win32Window::Size FrameForClient(unsigned int client_width,
                                 unsigned int client_height,
                                 DWORD style,
                                 DWORD ex_style) {
  RECT rect = {0, 0, static_cast<LONG>(client_width),
               static_cast<LONG>(client_height)};
  ::AdjustWindowRectEx(&rect, style, FALSE, ex_style);
  return Win32Window::Size(
      static_cast<unsigned int>(rect.right - rect.left),
      static_cast<unsigned int>(rect.bottom - rect.top));
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins, and for the folder picker and clipboard imaging.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(kDefaultWidth, kDefaultHeight);
  Win32Window::Point placed = origin;
  PlaceOnMonitor(origin, &size, &placed);
  if (!window.Create(L"Monad", placed, size)) {
    return EXIT_FAILURE;
  }
  // WM_GETMINMAXINFO is in physical pixels; Create took logical ones.
  const double scale =
      ::FlutterDesktopGetDpiForHWND(window.GetHandle()) / 96.0;
  const Win32Window::Size logical_min = FrameForClient(
      kMinClientWidth, kMinClientHeight, Win32Window::kStyle, 0);
  window.SetMinimumSize(Win32Window::Size(
      static_cast<unsigned int>(Scale(static_cast<int>(logical_min.width), scale)),
      static_cast<unsigned int>(
          Scale(static_cast<int>(logical_min.height), scale))));
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
