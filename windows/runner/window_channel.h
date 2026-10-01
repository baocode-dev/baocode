#ifndef RUNNER_WINDOW_CHANNEL_H_
#define RUNNER_WINDOW_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <windows.h>

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "caption_areas.h"

// What Flutter asks of the window, over the `baocode/window` channel: the
// methods the macOS app answers in MainFlutterWindow.swift, which are asked
// for in lib/workspace/window_controls.dart.
//
//   setAlwaysOnTop (bool)         keep the window above other apps' windows
//   pickDirectory                 the folder the user chose, or null
//   canPaste                      whether the clipboard holds anything
//   readPasteboardImages          the images on the clipboard
//   writePasteboardImage (…)      put an image on the clipboard
//   readPasteboardFiles           the files copied to the clipboard
//   writePasteboardFiles (paths)  copy files to the clipboard, as Explorer
//   readImageFile (path)          an image file as the composer takes one
//   pickFiles                     the files the user chose, or none
//   showContextMenu (x, y, items) the item chosen from the system's menu
//   open (target, app?, …)        the system opens it, in the app's own way
//   setHitTestAreas (…)           where the header Flutter draws is, so the
//                                 window can drag it and run its buttons
//   windowCommand (name)          minimize, maximize or close the window
//   windowRoom                    how much larger the window can get on its
//                                 monitor, in Flutter's pixels
//   growWindow (width, height)    makes it that much larger, on the monitor
//
// The Edit menu's commands are not here: Windows draws no menu bar for the
// app (see hasEditMenu), so Flutter handles those shortcuts itself.
class WindowChannel {
 public:
  WindowChannel(flutter::BinaryMessenger* messenger, HWND window);
  ~WindowChannel();

  WindowChannel(const WindowChannel&) = delete;
  WindowChannel& operator=(const WindowChannel&) = delete;

  // What the window hit-tests its header with (see CaptionAreas), at the
  // dpi it has now.
  std::optional<LRESULT> ButtonAt(POINT point) const {
    return areas_.ButtonAt(point, Scale());
  }
  bool IsHeaderControl(POINT point) const {
    return areas_.IsControl(point, Scale());
  }
  bool IsInHeader(POINT point) const {
    return areas_.Contains(point, Scale());
  }

  // Tells Flutter which of the window's buttons the pointer is over (the
  // system is the one hit-testing them, so this is how the header paints
  // them), and whether the window is maximized; only what changed.
  void ReportHover(LRESULT hit);
  void ReportMaximized(bool maximized);

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // The `open` method: |arguments| holds the target, and, when the Flutter
  // side named one, the app to open it with and what to pass it.
  void Open(const flutter::EncodableMap& arguments,
            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                result);

  // The `growWindow` method: |width| and |height| more, in Flutter's pixels,
  // as far as the monitor's work area goes.
  void Grow(double width, double height);

  // The window's dpi over 96: its physical pixels to one of Flutter's.
  double Scale() const;

  // The window the commands act on: the runner's own, not the Flutter view
  // it holds.
  HWND window_;

  // Where Flutter's header is (see setHitTestAreas).
  CaptionAreas areas_;

  // What was last reported to Flutter, so it is told once.
  std::optional<std::string> hovered_;
  bool maximized_ = false;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_WINDOW_CHANNEL_H_
