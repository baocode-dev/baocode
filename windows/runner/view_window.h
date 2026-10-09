#ifndef RUNNER_VIEW_WINDOW_H_
#define RUNNER_VIEW_WINDOW_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <cstdint>
#include <memory>
#include <optional>
#include <string>

#include "drop_target.h"
#include "win32_window.h"
#include "window_channel.h"

// What the app's windows tell the one that keeps them (see app_windows.h).
class WindowObserver {
 public:
  virtual ~WindowObserver() = default;

  // The window of |view_id| came in front, the keyboard's.
  virtual void WindowActivated(int64_t view_id) = 0;

  // It moved, was resized, maximized or minimized (told once it settles).
  virtual void WindowFrameChanged(int64_t view_id) = 0;

  // Its close button, Alt+F4 or the taskbar's Close asks it to close:
  // whether the app takes that up (it decides, and closes it itself).
  virtual bool WindowCloseRequested(int64_t view_id) = 0;
};

// A window that hosts a view of the Flutter engine over its whole client,
// with the header Flutter draws for a caption: the main window (see
// flutter_window.h) and the IDE's (see app_windows.h).
//
// The window answers what each of its parts is (its buttons, its frame, the
// strip of the header that drags it; see WindowPart), runs the buttons, and
// carries what Flutter asks of it (see window_channel.h) and the files
// dropped on it (see drop_target.h).
class ViewWindow : public Win32Window {
 public:
  ViewWindow();
  ~ViewWindow() override;

  // Tells |observer| what happens to the window, as the window of
  // |view_id|; null for no one.
  void SetObserver(WindowObserver* observer, int64_t view_id);

 protected:
  // Hosts |view|, the Flutter view's window: its own procedure gives way to
  // ViewProc, and Flutter's channels for the window are |window_channel| and
  // |drop_channel| on |messenger|.
  void HostView(flutter::BinaryMessenger* messenger, HWND view,
                const std::string& window_channel,
                const std::string& drop_channel);

  // Lets go of the view, before it goes: its own procedure back, its
  // channels gone.
  void ReleaseView();

  // The engine's turn at the window's messages: a result when it handled
  // one.
  virtual std::optional<LRESULT> EngineMessage(HWND window, UINT message,
                                               WPARAM wparam,
                                               LPARAM lparam) = 0;

  // The system's fonts changed: the engine reads them again.
  virtual void ReloadSystemFonts() = 0;

  // Win32Window:
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

  // The Flutter view's own procedure, which takes the view's place (see
  // HostView): it hands the cursor's hit test up to this window for the
  // parts of it that are this window's, and leaves every other message as
  // the view had it.
  static LRESULT CALLBACK ViewProc(HWND window, UINT message, WPARAM wparam,
                                   LPARAM lparam) noexcept;

  // What Flutter asks of this window.
  std::unique_ptr<WindowChannel> window_channel_;

  // Takes the files other apps drag onto the view, for Flutter; a COM object,
  // released when the view goes.
  DropTarget* drop_target_ = nullptr;

  // The window button pressed, until the press is let go: the button acts
  // then, and only if the pointer is still on it, as the system's own do.
  std::optional<LRESULT> pressed_button_;

  // The Flutter view's window, and the procedure it had before ViewProc took
  // its place (put back when the view goes).
  HWND view_ = nullptr;
  WNDPROC view_proc_ = nullptr;

  // The scancode bits of the last key down the view took (see ViewProc),
  // for the character messages that follow one sent without them.
  LPARAM key_down_scancode_bits_ = 0;

  // Who is told what happens to the window, and as which.
  WindowObserver* observer_ = nullptr;
  int64_t view_id_ = 0;
};

#endif  // RUNNER_VIEW_WINDOW_H_
