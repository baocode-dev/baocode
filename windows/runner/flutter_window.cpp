#include "flutter_window.h"

#include <flutter_windows.h>
#include <windows.h>
#include <optional>
#include <utility>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             std::vector<std::string> open_paths)
    : project_(project) {
  if (!open_paths.empty()) {
    open_paths_.push_back(std::move(open_paths));
  }
}

FlutterWindow::~FlutterWindow() {
  // Here, where OnDestroy is still this window's (Win32Window's destructor
  // would only call its own): the IDE's windows and the view go while the
  // engine is there.
  Destroy();
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  flutter::BinaryMessenger* messenger =
      flutter_controller_->engine()->messenger();
  HostView(messenger, flutter_controller_->view()->GetNativeWindow(),
           "baocode/window", "baocode/drop");

  // Paths the app is asked to open (see open_requests.dart): those it was
  // started with first, then those a second copy of it hands this window
  // (see main.cpp), which is marked for it to find.
  open_requests_ = std::make_unique<OpenRequests>(messenger,
                                                  std::vector<std::string>());
  for (std::vector<std::string>& paths : open_paths_) {
    open_requests_->Deliver(std::move(paths));
  }
  open_paths_.clear();
  MarkOpenRequestWindow(GetHandle(), true);

  // The IDE's windows, views of this engine beside this one (see
  // lib/window/window_host.dart).
  app_windows_ = std::make_unique<AppWindows>(messenger, GetHandle());
  SetObserver(app_windows_.get(), 0);

  // Notifications, the taskbar button's count and the tray icon (see
  // lib/notifications/).
  attention_ = std::make_unique<Attention>(messenger, GetHandle(),
                                           app_windows_.get());
  app_windows_->SetAttention(attention_.get());

  // Shown with its first frame — unless the app starts in the IDE's windows
  // alone (see AppWindows::MainShownAtLaunch), which show themselves.
  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    if (AppWindows::MainShownAtLaunch()) {
      this->Show();
    } else if (app_windows_ != nullptr) {
      app_windows_->HoldMainBack();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // The IDE's windows first: their views are this engine's, which goes with
  // the controller below.
  SetObserver(nullptr, 0);
  if (attention_ != nullptr) {
    attention_->DetachWindows();
  }
  app_windows_ = nullptr;
  ReleaseView();

  if (const HWND window = GetHandle()) {
    MarkOpenRequestWindow(window, false);
  }
  open_requests_ = nullptr;
  attention_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

std::optional<LRESULT> FlutterWindow::EngineMessage(HWND hwnd, UINT message,
                                                   WPARAM wparam,
                                                   LPARAM lparam) {
  if (!flutter_controller_) {
    return std::nullopt;
  }
  return flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                       lparam);
}

void FlutterWindow::ReloadSystemFonts() {
  if (flutter_controller_) {
    flutter_controller_->engine()->ReloadSystemFonts();
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // The app quits (see AppWindows::kQuitMessage): this window goes, and the
  // engine and the IDE's windows with it, in OnDestroy.
  if (message == AppWindows::kQuitMessage) {
    // Out of sight at once: what is left of the going takes a moment.
    ::ShowWindow(hwnd, SW_HIDE);
    ::DestroyWindow(hwnd);
    return 0;
  }

  // The session ends, or an installer closes the app for the files it
  // replaces (the Restart Manager: ENDSESSION_CLOSEAPP). It goes the same
  // way, unasked: no one is there to answer, and the engine does nothing
  // with it, which left the app running and the installer unable to close
  // it. What it ran (agents, terminals) is ended at the next launch.
  if (message == WM_ENDSESSION && wparam) {
    ::DestroyWindow(hwnd);
    return 0;
  }

  // Once the app keeps windows of its own, the close button is the app's to
  // decide about (see AppWindows): the tray, if any, is what keeps it.
  const bool app_closes =
      message == WM_CLOSE && app_windows_ != nullptr && app_windows_->started();

  // The tray icon's messages, and the close button while there is a tray
  // icon to hide the window to: before the engine, which would quit.
  if (attention_ != nullptr && !app_closes) {
    if (const std::optional<LRESULT> handled =
            attention_->HandleMessage(hwnd, message, wparam, lparam)) {
      return *handled;
    }
  }

  // Paths a second copy of the app hands over (see ForwardToRunningWindow),
  // for Flutter to open. Before the app keeps windows of its own, this
  // window comes to the front for them, as the user just asked for it;
  // after, the app brings the one it opens them in.
  if (message == WM_COPYDATA) {
    const auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
    if (data != nullptr && data->dwData == kOpenRequestData) {
      std::vector<std::string> paths = OpenRequestPaths(*data);
      if (open_requests_ != nullptr) {
        open_requests_->Deliver(std::move(paths));
      } else {
        open_paths_.push_back(std::move(paths));
      }
      if (app_windows_ == nullptr || !app_windows_->started()) {
        if (::IsIconic(hwnd)) {
          ::ShowWindow(hwnd, SW_RESTORE);
        }
        ::SetForegroundWindow(hwnd);
      }
      return TRUE;
    }
  }

  // The app asks before it quits (see quit_confirmation.dart), in this
  // window: brought back for it when closed from the taskbar minimized.
  if (message == WM_CLOSE && ::IsIconic(hwnd) && !app_closes) {
    ::ShowWindow(hwnd, SW_RESTORE);
  }

  return ViewWindow::MessageHandler(hwnd, message, wparam, lparam);
}
