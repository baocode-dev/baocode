#include "window_channel.h"

#include <flutter/method_codec.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <windows.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "clipboard_images.h"
#include "context_menu.h"
#include "utils.h"

namespace {

using Microsoft::WRL::ComPtr;

// The arguments of a call, as a map: an empty one when it sent none.
const flutter::EncodableMap& Arguments(const flutter::EncodableValue* value) {
  static const flutter::EncodableMap kNone;
  if (value == nullptr) {
    return kNone;
  }
  const auto* map = std::get_if<flutter::EncodableMap>(value);
  return map == nullptr ? kNone : *map;
}

std::string String(const flutter::EncodableMap& arguments, const char* key) {
  const auto found = arguments.find(flutter::EncodableValue(key));
  if (found == arguments.end()) {
    return std::string();
  }
  const auto* value = std::get_if<std::string>(&found->second);
  return value == nullptr ? std::string() : *value;
}

double Number(const flutter::EncodableMap& arguments, const char* key) {
  const auto found = arguments.find(flutter::EncodableValue(key));
  if (found == arguments.end()) {
    return 0.0;
  }
  if (const auto* value = std::get_if<double>(&found->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int32_t>(&found->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&found->second)) {
    return static_cast<double>(*value);
  }
  return 0.0;
}

bool Boolean(const flutter::EncodableValue* value, bool fallback) {
  if (value == nullptr) {
    return fallback;
  }
  const auto* boolean = std::get_if<bool>(value);
  return boolean == nullptr ? fallback : *boolean;
}

bool Boolean(const flutter::EncodableMap& arguments, const char* key,
             bool fallback) {
  const auto found = arguments.find(flutter::EncodableValue(key));
  if (found == arguments.end()) {
    return fallback;
  }
  return Boolean(&found->second, fallback);
}

std::vector<std::string> Strings(const flutter::EncodableMap& arguments,
                                 const char* key) {
  std::vector<std::string> strings;
  const auto found = arguments.find(flutter::EncodableValue(key));
  if (found == arguments.end()) {
    return strings;
  }
  const auto* list = std::get_if<flutter::EncodableList>(&found->second);
  if (list == nullptr) {
    return strings;
  }
  for (const flutter::EncodableValue& value : *list) {
    if (const auto* string = std::get_if<std::string>(&value)) {
      strings.push_back(*string);
    }
  }
  return strings;
}

// One of the rectangles Flutter reports: its left, top, width and height.
CaptionAreas::Rect RectFrom(const flutter::EncodableMap& map) {
  CaptionAreas::Rect rect;
  rect.left = Number(map, "left");
  rect.top = Number(map, "top");
  rect.width = Number(map, "width");
  rect.height = Number(map, "height");
  return rect;
}

std::vector<CaptionAreas::Rect> Rects(const flutter::EncodableMap& arguments,
                                      const char* key) {
  std::vector<CaptionAreas::Rect> rects;
  const auto found = arguments.find(flutter::EncodableValue(key));
  if (found == arguments.end()) {
    return rects;
  }
  const auto* list = std::get_if<flutter::EncodableList>(&found->second);
  if (list == nullptr) {
    return rects;
  }
  for (const flutter::EncodableValue& value : *list) {
    if (const auto* map = std::get_if<flutter::EncodableMap>(&value)) {
      rects.push_back(RectFrom(*map));
    }
  }
  return rects;
}

// One of the three window buttons, under |key| of the map Flutter reports.
CaptionAreas::Rect ButtonRect(const flutter::EncodableMap& arguments,
                              const char* key) {
  const auto found = arguments.find(flutter::EncodableValue("buttons"));
  if (found == arguments.end()) {
    return CaptionAreas::Rect();
  }
  const auto* buttons = std::get_if<flutter::EncodableMap>(&found->second);
  if (buttons == nullptr) {
    return CaptionAreas::Rect();
  }
  const auto rect = buttons->find(flutter::EncodableValue(key));
  if (rect == buttons->end()) {
    return CaptionAreas::Rect();
  }
  const auto* map = std::get_if<flutter::EncodableMap>(&rect->second);
  return map == nullptr ? CaptionAreas::Rect() : RectFrom(*map);
}

// A command line argument: quoted, so that a path with spaces in it stays
// one argument, and escaped as the program reads its command line back
// (CommandLineToArgvW): backslashes are only literal where no quote follows
// them, which the closing one does — a drive's root, `C:\`, would otherwise
// run on into what comes after it.
std::wstring Quoted(const std::string& argument) {
  const std::wstring text = Utf16FromUtf8(argument);
  std::wstring quoted = L"\"";
  size_t backslashes = 0;
  for (const wchar_t c : text) {
    if (c == L'\\') {
      ++backslashes;
      continue;
    }
    // Before a quote, each backslash doubled and the quote escaped.
    quoted.append(c == L'"' ? backslashes * 2 + 1 : backslashes, L'\\');
    backslashes = 0;
    quoted += c;
  }
  // Before the closing quote, each doubled.
  quoted.append(backslashes * 2, L'\\');
  return quoted + L"\"";
}

// The project folder the user picked through the system's own panel; null
// when they cancel, or it cannot be shown.
std::optional<std::string> PickDirectory(HWND window) {
  ComPtr<IFileOpenDialog> dialog;
  if (FAILED(::CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) {
    return std::nullopt;
  }
  DWORD options = 0;
  if (SUCCEEDED(dialog->GetOptions(&options))) {
    dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM |
                       FOS_PATHMUSTEXIST);
  }
  dialog->SetTitle(L"Choose a project folder");
  dialog->SetOkButtonLabel(L"Open");
  // The panel runs its own message loop, which keeps Flutter drawing while
  // it is up.
  if (FAILED(dialog->Show(window))) {
    return std::nullopt;
  }
  ComPtr<IShellItem> folder;
  if (FAILED(dialog->GetResult(&folder))) {
    return std::nullopt;
  }
  PWSTR path = nullptr;
  if (FAILED(folder->GetDisplayName(SIGDN_FILESYSPATH, &path))) {
    return std::nullopt;
  }
  std::optional<std::string> picked = Utf8FromUtf16(path);
  ::CoTaskMemFree(path);
  return picked;
}

}  // namespace

WindowChannel::WindowChannel(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "monad/window",
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleMethodCall(call, std::move(result)); });
}

WindowChannel::~WindowChannel() = default;

void WindowChannel::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  const flutter::EncodableMap& arguments = Arguments(call.arguments());

  if (method == "setAlwaysOnTop") {
    // Pinned: above other apps' windows, as a floating window should be.
    const bool on_top = Boolean(call.arguments(), false);
    ::SetWindowPos(window_, on_top ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    result->Success();
    return;
  }

  if (method == "pickDirectory") {
    const std::optional<std::string> path = PickDirectory(window_);
    if (path.has_value()) {
      result->Success(flutter::EncodableValue(*path));
    } else {
      result->Success();
    }
    return;
  }

  if (method == "canPaste") {
    result->Success(flutter::EncodableValue(ClipboardHasContent()));
    return;
  }

  if (method == "readPasteboardImages") {
    flutter::EncodableList images;
    for (const ClipboardImage& image : ClipboardImages()) {
      flutter::EncodableMap encoded;
      encoded[flutter::EncodableValue("bytes")] =
          flutter::EncodableValue(image.bytes);
      encoded[flutter::EncodableValue("type")] =
          flutter::EncodableValue(image.media_type);
      if (!image.name.empty()) {
        encoded[flutter::EncodableValue("name")] =
            flutter::EncodableValue(image.name);
      }
      images.push_back(flutter::EncodableValue(std::move(encoded)));
    }
    result->Success(flutter::EncodableValue(std::move(images)));
    return;
  }

  if (method == "showContextMenu") {
    std::vector<ContextMenuItem> items;
    const auto found = arguments.find(flutter::EncodableValue("items"));
    if (found != arguments.end()) {
      if (const auto* list = std::get_if<flutter::EncodableList>(&found->second)) {
        for (const flutter::EncodableValue& value : *list) {
          const auto* map = std::get_if<flutter::EncodableMap>(&value);
          if (map == nullptr) {
            continue;
          }
          ContextMenuItem item;
          item.separator = Boolean(*map, "separator", false);
          item.id = String(*map, "id");
          item.label = String(*map, "label");
          item.key = String(*map, "key");
          item.enabled = Boolean(*map, "enabled", true);
          items.push_back(std::move(item));
        }
      }
    }
    // The position is in Flutter's own pixels, from the top left of the
    // client area; the menu opens at the screen point under it.
    const double scale = Scale();
    POINT at = {static_cast<LONG>(Number(arguments, "x") * scale),
                static_cast<LONG>(Number(arguments, "y") * scale)};
    ::ClientToScreen(window_, &at);
    const std::optional<std::string> chosen = ShowContextMenu(window_, at, items);
    if (chosen.has_value()) {
      result->Success(flutter::EncodableValue(*chosen));
    } else {
      result->Success();
    }
    return;
  }

  if (method == "open") {
    Open(arguments, std::move(result));
    return;
  }

  if (method == "setHitTestAreas") {
    // Flutter drew its header: this is where its pieces are, in the app's
    // own pixels. The window scales them to its own as it hit-tests them
    // (see CaptionAreas).
    areas_.Set(Number(arguments, "height"), Rects(arguments, "controls"),
               ButtonRect(arguments, "minimize"),
               ButtonRect(arguments, "maximize"),
               ButtonRect(arguments, "close"));
    result->Success();
    return;
  }

  if (method == "windowCommand") {
    const auto* name = call.arguments() == nullptr
                           ? nullptr
                           : std::get_if<std::string>(call.arguments());
    const std::string command = name == nullptr ? std::string() : *name;
    if (command == "minimize") {
      ::ShowWindow(window_, SW_MINIMIZE);
    } else if (command == "maximize") {
      // Either way round, as the button itself does: the system's own click
      // on it goes through DefWindowProc and lands in the same place.
      ::ShowWindow(window_, ::IsZoomed(window_) ? SW_RESTORE : SW_MAXIMIZE);
    } else if (command == "close") {
      ::PostMessageW(window_, WM_CLOSE, 0, 0);
    }
    result->Success();
    return;
  }

  result->NotImplemented();
}

double WindowChannel::Scale() const {
  return ::FlutterDesktopGetDpiForHWND(window_) / 96.0;
}

void WindowChannel::ReportHover(LRESULT hit) {
  std::optional<std::string> hovered;
  switch (hit) {
    case HTMINBUTTON:
      hovered = "minimize";
      break;
    case HTMAXBUTTON:
      hovered = "maximize";
      break;
    case HTCLOSE:
      hovered = "close";
      break;
    default:
      break;
  }
  if (hovered == hovered_) {
    return;
  }
  hovered_ = hovered;
  channel_->InvokeMethod(
      "captionHover",
      std::make_unique<flutter::EncodableValue>(hovered.value_or(std::string())));
}

void WindowChannel::ReportMaximized(bool maximized) {
  if (maximized == maximized_) {
    return;
  }
  maximized_ = maximized;
  channel_->InvokeMethod(
      "maximized", std::make_unique<flutter::EncodableValue>(maximized));
}

void WindowChannel::Open(
    const flutter::EncodableMap& arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string target = String(arguments, "target");
  if (target.empty()) {
    result->Success(flutter::EncodableValue(false));
    return;
  }
  // Named an app: the shell finds it by the command the Flutter side uses
  // (`code`, `wt`…), the way the PATH does for a terminal. When the Flutter
  // side also passes arguments, those are the whole of what the app is
  // given (e.g. `wt -d folder`); otherwise the target is what it opens.
  // Without an app, the target itself is what opens, in whatever the system
  // opens it with (a URL, a folder, a file).
  const std::string app = String(arguments, "app");
  const std::wstring file = Utf16FromUtf8(app.empty() ? target : app);
  const std::vector<std::string> extras = Strings(arguments, "arguments");
  std::wstring parameters;
  if (!app.empty()) {
    if (extras.empty()) {
      parameters = Quoted(target);
    } else {
      for (const std::string& extra : extras) {
        if (!parameters.empty()) {
          parameters += L' ';
        }
        parameters += Quoted(extra);
      }
    }
  }

  const HINSTANCE opened =
      ::ShellExecuteW(nullptr, L"open", file.c_str(),
                      parameters.empty() ? nullptr : parameters.c_str(),
                      nullptr, SW_SHOWNORMAL);
  // ShellExecute answers a value above 32 when it worked, or an error code
  // under it (33 and up are the codes it means).
  const bool worked = reinterpret_cast<INT_PTR>(opened) > 32;
  result->Success(flutter::EncodableValue(worked));
}
