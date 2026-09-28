#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"
#include "window_channel.h"

// A window that hosts a Flutter view, and answers the window commands
// Flutter asks for over `monad/window` (see window_channel.h).
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // What the pointer at |point| (client pixels) is over, when it is the
  // window's own: one of its buttons, its frame, the header Flutter draws.
  // nullopt where it is Flutter's (its controls in the header, and
  // everything under it) — this is the one answer both the window
  // (WM_NCHITTEST, and what it runs when such a part is pressed) and the
  // view (see ViewProc) go by.
  std::optional<LRESULT> WindowPart(POINT point) const;

  // The Flutter view's own procedure, which takes the view's place on create
  // (see OnCreate): it hands the cursor's hit test up to this window for the
  // parts of it that are this window's, and leaves every other message as the
  // view had it.
  static LRESULT CALLBACK ViewProc(HWND window, UINT message, WPARAM wparam,
                                   LPARAM lparam) noexcept;

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // What Flutter asks of this window.
  std::unique_ptr<WindowChannel> window_channel_;

  // The Flutter view's window, and the procedure it had before ViewProc took
  // its place (put back when the window goes).
  HWND view_ = nullptr;
  WNDPROC view_proc_ = nullptr;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
