#ifndef RUNNER_APP_WINDOWS_H_
#define RUNNER_APP_WINDOWS_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <flutter_windows.h>
#include <windows.h>

#include <cstdint>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "view_window.h"

class Attention;

// One of the IDE's windows: a view of the engine the main window owns
// (FlutterDesktopEngineCreateViewController), in a window of its own with
// the main window's frame, header and channels (see ViewWindow) — those
// named for its view: `baocode/window.<id>`, `baocode/drop.<id>`.
class IdeWindow : public ViewWindow {
 public:
  IdeWindow(FlutterDesktopEngineRef engine,
            flutter::BinaryMessenger* messenger);
  ~IdeWindow() override;

  IdeWindow(const IdeWindow&) = delete;
  IdeWindow& operator=(const IdeWindow&) = delete;

  // Its view's id, once made (see Create); -1 before.
  int64_t view_id() const { return view_id_; }

  // Shows it in front, the keyboard's: maximized the first time, if it was
  // asked to be (see ShowMaximizedFirst).
  void ShowInFront();

  // Shown maximized, the first time it shows.
  void ShowMaximizedFirst() { maximize_on_show_ = true; }

  // Taskbar buttons made anew are told this (see Attention::BadgeWindow).
  void SetAttention(Attention* attention) { attention_ = attention; }

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
  FlutterDesktopEngineRef engine_;
  flutter::BinaryMessenger* messenger_;
  FlutterDesktopViewControllerRef controller_ = nullptr;
  int64_t view_id_ = -1;
  bool maximize_on_show_ = false;
  Attention* attention_ = nullptr;
  UINT taskbar_button_created_ = 0;
};

// The app's windows, for Flutter, over `baocode/windows` (the macOS app
// answers the same in AppWindows.swift; see lib/window/window_host.dart):
//
//   start                         true: the engine takes views beside the
//                                 main one
//   create {frame?, title, engineId}
//                                 an IDE window, hidden until focused: its
//                                 view's id
//   close viewId                  closes it (the main one: hides it)
//   focus viewId                  shows it in front, the keyboard's
//   hide viewId                   hides it
//   setTitle {viewId, title}      the taskbar's and Alt+Tab's title
//   setEdited {viewId, edited}    (macOS' dot; nothing here)
//   frame viewId                  {x, y, width, height, maximized,
//                                 fullscreen, screen}, in physical pixels
//                                 of the virtual screen
//   screens                       [{id, x, y, width, height}]: the
//                                 monitors' work areas
//   setWindowList {windows, labels}
//                                 what the tray's menu lists
//   setMainShownAtLaunch bool     whether the main window shows when the
//                                 app next starts
//   quit                          the app goes, Flutter having agreed (see
//                                 kQuitMessage)
//
// and tells Flutter `closeRequested viewId`, `focused viewId`,
// `frameChanged {viewId, …}`, `newWindow` (the tray's New Window) and
// `quit` (the tray's Quit: the app asks first).
class AppWindows : public WindowObserver {
 public:
  // What `quit` posts the main window: it goes then, in the message loop,
  // the engine with it (FlutterWindow::OnDestroy), and the loop after it.
  // The engine's own way out (exitApplication) ends the loop first, the
  // windows still up, and taking Flutter down outside it hangs the app.
  static constexpr UINT kQuitMessage = WM_APP + 0x42;

  // A window as the tray's menu lists it.
  struct Entry {
    int64_t view_id = 0;
    std::wstring title;
  };

  AppWindows(flutter::BinaryMessenger* messenger, HWND main);
  ~AppWindows() override;

  AppWindows(const AppWindows&) = delete;
  AppWindows& operator=(const AppWindows&) = delete;

  // Whether Flutter keeps windows of its own (it asked to start): it then
  // decides about closing them, the main one too.
  bool started() const { return started_; }

  void SetAttention(Attention* attention);

  // The windows the tray's menu lists, and its New Window's label.
  const std::vector<Entry>& entries() const { return entries_; }
  std::wstring NewWindowLabel() const;

  // The window of |view_id| (the main one's is 0), null for none.
  HWND HandleOf(int64_t view_id) const;

  // The app's windows that show: the main one (when it does), then the
  // IDE's.
  std::vector<HWND> ShownWindows() const;

  // The app's window in front, the main one if none is.
  HWND FrontWindow() const;

  // Shows |view_id|'s window in front.
  void Focus(int64_t view_id);

  // The tray's New Window and Quit, for Flutter; its icon clicked with no
  // window shown (Flutter shows one).
  void RequestNewWindow();
  void RequestQuit();
  void RequestReopen();

  // Whether the main window shows when the app starts (Flutter's last
  // word on it, setMainShownAtLaunch): the app may start in the IDE's
  // windows alone.
  static bool MainShownAtLaunch();

  // The main window, not shown at launch (see MainShownAtLaunch): shown
  // after all if Flutter has not started its windows in a while.
  void HoldMainBack();

  // WindowObserver:
  void WindowActivated(int64_t view_id) override;
  void WindowFrameChanged(int64_t view_id) override;
  bool WindowCloseRequested(int64_t view_id) override;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // A new IDE window: its view's id, or nullopt.
  std::optional<int64_t> Create(const flutter::EncodableMap& arguments);
  void Close(int64_t view_id);
  void Hide(int64_t view_id);

  // Where |window| is: its normal place and size, whether maximized, and the
  // monitor it is on.
  flutter::EncodableValue FrameOf(HWND window) const;
  static flutter::EncodableValue Screens();

  void Send(const char* method, flutter::EncodableValue arguments);

  // Shows the main window after all (see HoldMainBack).
  static void CALLBACK HoldBackTimer(HWND window, UINT message, UINT_PTR id,
                                     DWORD time);

  flutter::BinaryMessenger* messenger_;
  HWND main_;
  bool started_ = false;
  Attention* attention_ = nullptr;
  std::map<int64_t, std::unique_ptr<IdeWindow>> windows_;
  std::vector<Entry> entries_;
  std::map<std::string, std::wstring> labels_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_APP_WINDOWS_H_
