#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "app_windows.h"
#include "attention.h"
#include "open_requests.h"
#include "view_window.h"

// The main window: the chat's, the one the app starts with, which hosts the
// engine's first view (the implicit one) and owns the engine; it answers the
// window commands Flutter asks for over `baocode/window` (see
// window_channel.h), and keeps the IDE's windows (see app_windows.h), the
// paths the app is asked to open and the tray.
class FlutterWindow : public ViewWindow {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|,
  // asked to open |open_paths| (UTF-8, absolute, or a request of the `code`
  // command; see OpenRequests) once Flutter is ready for them.
  explicit FlutterWindow(const flutter::DartProject& project,
                         std::vector<std::string> open_paths = {});
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

  // ViewWindow:
  std::optional<LRESULT> EngineMessage(HWND window, UINT message,
                                       WPARAM wparam, LPARAM lparam) override;
  void ReloadSystemFonts() override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // The paths the app is asked to open, for Flutter; until it is made (see
  // OnCreate), those kept for it, as they came.
  std::unique_ptr<OpenRequests> open_requests_;
  std::vector<std::vector<std::string>> open_paths_;

  // The IDE's windows (see app_windows.h).
  std::unique_ptr<AppWindows> app_windows_;

  // Notifications, the taskbar button's count and the tray icon, which the
  // close button hides the window to (see attention.h).
  std::unique_ptr<Attention> attention_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
