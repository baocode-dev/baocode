#ifndef RUNNER_ATTENTION_H_
#define RUNNER_ATTENTION_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <windows.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>

class AppWindows;

// What tells the user an agent wants them while they look elsewhere, over the
// `baocode/attention` channel (lib/notifications/; the macOS app answers the
// same in Attention.swift):
//
//   notify (id, title, body)  a notification: the tray icon's balloon, which
//                             Windows 10 and 11 show as a toast
//   playSound (path | bytes)  a sound file, or a WAV file's bytes
//   requestAttention          the taskbar button flashes
//   setBadge (count)          a count over the taskbar button; 0 for none
//   setTray (state | null)    the system tray icon and its menu, or none
//   pickSound                 a sound file the user picked, or null
//   quit                      quits as the tray's Quit: the app asks first
//
// and tells Flutter `open (id | null)` when a notification or the tray's menu
// is clicked, the window brought back first (once the app keeps windows of
// its own, an agent's is for Flutter to bring: the IDE's window it is a tab
// of, or the main one).
//
// The tray's menu lists the app's windows too, and New Window, and the
// count goes over every window's taskbar button (see AppWindows).
class Attention {
 public:
  Attention(flutter::BinaryMessenger* messenger, HWND window,
            AppWindows* windows);
  ~Attention();

  Attention(const Attention&) = delete;
  Attention& operator=(const Attention&) = delete;

  // The window's messages that are this's: the tray icon's, the taskbar's
  // coming back, a change of the system's theme, and the close button, which
  // hides the window while there is a tray icon to bring it back. A result
  // when it handled the message.
  std::optional<LRESULT> HandleMessage(HWND window, UINT message,
                                       WPARAM wparam, LPARAM lparam);

  // The count, over |window|'s taskbar button just made.
  void BadgeWindow(HWND window);

  // The app's windows are going: none to ask about from now on.
  void DetachWindows() { windows_ = nullptr; }

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // An agent waiting on the user, as the tray's menu lists it.
  struct Agent {
    std::string id;
    std::wstring title;
  };

  // The tray icon as Flutter last described it.
  struct TrayState {
    bool dot = false;
    std::wstring tooltip;
    std::vector<Agent> waiting;
    std::wstring show;
    std::wstring waiting_label;
    std::wstring running;
    std::wstring quit;
  };

  void SetTray(const flutter::EncodableValue* state);
  void Notify(const std::string& id, const std::wstring& title,
              const std::wstring& body);
  void PlaySoundFile(const std::wstring& path);
  void PlaySoundBytes(std::vector<uint8_t> bytes);
  void StopSound();
  void SetBadge(int count);
  std::optional<std::string> PickSound();

  // Adds the icon to the tray, or updates it (its picture and tooltip).
  void ShowIcon();
  void RemoveIcon();
  void ShowMenu();

  // Brings the window back, hidden or minimized, in front.
  void BringBack();

  // The window brought back, on the agent |id| names (none: as it was).
  void Open(const std::optional<std::string>& id);

  // Quits as the close button would without a tray: the app asks first, in
  // the window.
  void Quit();

  // The tray icon's picture, for the taskbar's theme now.
  HICON TrayIcon(bool dot) const;

  HWND window_;
  AppWindows* windows_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  // Whether the tray icon is up, and whether Flutter asked for it (it is up
  // without, for a notification's sake, until the notification goes).
  bool icon_added_ = false;
  std::optional<TrayState> tray_;
  HICON icon_ = nullptr;

  // The agent the notification shown last is about.
  std::string notified_id_;

  // A WAV file's bytes being played: PlaySound reads them as it plays.
  std::vector<uint8_t> sound_;
  bool mci_open_ = false;

  // The count over the taskbar button, put back when the button is made
  // again (the window hidden and shown).
  int badge_ = 0;
  Microsoft::WRL::ComPtr<ITaskbarList3> taskbar_;

  // The close button goes on to Flutter (and quits) once: Quit chosen.
  bool quitting_ = false;

  // Sent to every window when Explorer starts again (the tray is new), and
  // when the window's taskbar button is made.
  UINT taskbar_created_ = 0;
  UINT taskbar_button_created_ = 0;
};

#endif  // RUNNER_ATTENTION_H_
