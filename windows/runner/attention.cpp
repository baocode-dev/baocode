#include "attention.h"

#include <flutter/standard_method_codec.h>
#include <mmsystem.h>
#include <windowsx.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <cwchar>
#include <cwctype>
#include <utility>

#include "app_windows.h"
#include "resource.h"
#include "utils.h"

namespace {

using Microsoft::WRL::ComPtr;

// What the tray icon tells the window, and which of the app's icons it is.
constexpr UINT kTrayMessage = WM_APP + 0x41;
constexpr UINT kTrayId = 1;

// The tray menu's commands; an agent's is kAgentCommand plus its place, a
// window's kWindowCommand plus its.
constexpr UINT kShowCommand = 1;
constexpr UINT kQuitCommand = 2;
constexpr UINT kNewWindowCommand = 3;
constexpr UINT kAgentCommand = 100;
constexpr UINT kWindowCommand = 1000;

// The alias of a sound MCI plays (a file PlaySound does not: not a WAV).
constexpr wchar_t kSoundAlias[] = L"baocode_sound";

const flutter::EncodableValue* Find(const flutter::EncodableMap& map,
                                    const char* key) {
  const auto found = map.find(flutter::EncodableValue(key));
  return found == map.end() ? nullptr : &found->second;
}

std::string String(const flutter::EncodableMap& map, const char* key) {
  const flutter::EncodableValue* value = Find(map, key);
  const auto* string =
      value == nullptr ? nullptr : std::get_if<std::string>(value);
  return string == nullptr ? std::string() : *string;
}

std::wstring WideString(const flutter::EncodableMap& map, const char* key) {
  const std::string string = String(map, key);
  return string.empty() ? std::wstring() : Utf16FromUtf8(string);
}

// |text| as a menu shows it as it is: an ampersand would underline what
// follows it.
std::wstring MenuText(const std::wstring& text) {
  std::wstring escaped;
  for (const wchar_t c : text) {
    if (c == L'&') {
      escaped += L'&';
    }
    escaped += c;
  }
  return escaped;
}

// Pixels of a square icon, top row first: 0xAARRGGBB, alpha not
// premultiplied (as an icon's are).
class Canvas {
 public:
  explicit Canvas(int size)
      : size_(size), pixels_(static_cast<size_t>(size) * size, 0) {}

  void Fill(int x0, int y0, int x1, int y1, uint32_t rgb) {
    for (int y = (std::max)(0, y0); y < (std::min)(size_, y1); y++) {
      for (int x = (std::max)(0, x0); x < (std::min)(size_, x1); x++) {
        pixels_[static_cast<size_t>(y) * size_ + x] = 0xFF000000u | rgb;
      }
    }
  }

  // A disc of |rgb| over what is there, its edge smoothed; or, |erase|, a
  // hole of that shape.
  void Disc(double cx, double cy, double radius, uint32_t rgb, bool erase) {
    constexpr int kSamples = 4;
    for (int y = 0; y < size_; y++) {
      for (int x = 0; x < size_; x++) {
        int inside = 0;
        for (int sy = 0; sy < kSamples; sy++) {
          for (int sx = 0; sx < kSamples; sx++) {
            const double px = x + (sx + 0.5) / kSamples - cx;
            const double py = y + (sy + 0.5) / kSamples - cy;
            if (px * px + py * py <= radius * radius) {
              inside++;
            }
          }
        }
        if (inside == 0) {
          continue;
        }
        const double coverage =
            static_cast<double>(inside) / (kSamples * kSamples);
        uint32_t& pixel = pixels_[static_cast<size_t>(y) * size_ + x];
        const double below = (pixel >> 24) / 255.0;
        if (erase) {
          const auto alpha =
              static_cast<uint32_t>(std::lround(below * (1 - coverage) * 255));
          pixel = (pixel & 0x00FFFFFFu) | (alpha << 24);
          continue;
        }
        const double alpha = coverage + below * (1 - coverage);
        auto channel = [&](int shift) {
          const double top = (rgb >> shift) & 0xFF;
          const double under = (pixel >> shift) & 0xFF;
          return static_cast<uint32_t>(std::lround(
              (top * coverage + under * below * (1 - coverage)) / alpha));
        };
        pixel = (static_cast<uint32_t>(std::lround(alpha * 255)) << 24) |
                (channel(16) << 16) | (channel(8) << 8) | channel(0);
      }
    }
  }

  // An icon of the pixels; the caller destroys it.
  HICON Icon() const {
    BITMAPV5HEADER header = {};
    header.bV5Size = sizeof(header);
    header.bV5Width = size_;
    header.bV5Height = -size_;  // Top row first.
    header.bV5Planes = 1;
    header.bV5BitCount = 32;
    header.bV5Compression = BI_BITFIELDS;
    header.bV5RedMask = 0x00FF0000;
    header.bV5GreenMask = 0x0000FF00;
    header.bV5BlueMask = 0x000000FF;
    header.bV5AlphaMask = 0xFF000000;
    void* bits = nullptr;
    HDC screen = ::GetDC(nullptr);
    HBITMAP color = ::CreateDIBSection(
        screen, reinterpret_cast<BITMAPINFO*>(&header), DIB_RGB_COLORS, &bits,
        nullptr, 0);
    ::ReleaseDC(nullptr, screen);
    if (color == nullptr) {
      return nullptr;
    }
    std::memcpy(bits, pixels_.data(), pixels_.size() * sizeof(uint32_t));
    // Unused where the color has alpha, but an icon has one.
    const std::vector<uint8_t> mask_bits(
        static_cast<size_t>((size_ + 15) / 16 * 2) * size_, 0);
    HBITMAP mask = ::CreateBitmap(size_, size_, 1, 1, mask_bits.data());
    ICONINFO info = {};
    info.fIcon = TRUE;
    info.hbmColor = color;
    info.hbmMask = mask;
    HICON icon = ::CreateIconIndirect(&info);
    ::DeleteObject(color);
    ::DeleteObject(mask);
    return icon;
  }

 private:
  int size_;
  std::vector<uint32_t> pixels_;
};

// The logo's cells, in its own 56×42 units (bao.svg; the same as
// Attention.swift's).
struct Cell {
  int x, y, width, height;
};
constexpr Cell kLogoCells[] = {
    {14, 0, 28, 7}, {7, 7, 7, 7},   {42, 7, 7, 7},  {0, 14, 7, 21},
    {49, 14, 7, 21}, {14, 21, 8, 7}, {35, 21, 8, 7}, {7, 35, 42, 7},
};

// Digits and a plus, 3×5 pixels each, top row first, a row's bits from the
// left: the count over the taskbar button, in the logo's pixels.
constexpr uint8_t kGlyphs[11][5] = {
    {7, 5, 5, 5, 7}, {2, 6, 2, 2, 7}, {7, 1, 7, 4, 7}, {7, 1, 7, 1, 7},
    {5, 5, 7, 1, 1}, {7, 4, 7, 1, 7}, {7, 4, 7, 5, 7}, {7, 1, 1, 1, 1},
    {7, 5, 7, 5, 7}, {7, 5, 7, 1, 7}, {0, 2, 7, 2, 0},
};
constexpr int kPlus = 10;

void DrawGlyph(Canvas& canvas, int glyph, int x, int y, int scale,
               uint32_t rgb) {
  for (int row = 0; row < 5; row++) {
    for (int column = 0; column < 3; column++) {
      if (kGlyphs[glyph][row] & (4 >> column)) {
        canvas.Fill(x + column * scale, y + row * scale,
                    x + (column + 1) * scale, y + (row + 1) * scale, rgb);
      }
    }
  }
}

// Red, as Windows's own badges.
constexpr uint32_t kBadgeRed = 0xE81123;

// The count over the taskbar button: a red disc, the number on it (9+ past
// nine).
HICON BadgeIcon(int count) {
  const int size = ::GetSystemMetrics(SM_CXSMICON);
  Canvas canvas(size);
  canvas.Disc(size / 2.0, size / 2.0, size / 2.0, kBadgeRed, false);
  std::vector<int> glyphs;
  if (count > 9) {
    glyphs = {9, kPlus};
  } else {
    glyphs = {count};
  }
  const int scale = glyphs.size() == 1
                        ? (std::max)(1, size / 8)
                        : (std::max)(1, static_cast<int>(size * 0.7) / 7);
  const int width = static_cast<int>(glyphs.size()) * 4 * scale - scale;
  int x = (size - width) / 2;
  const int y = (size - 5 * scale) / 2;
  for (const int glyph : glyphs) {
    DrawGlyph(canvas, glyph, x, y, scale, 0xFFFFFF);
    x += 4 * scale;
  }
  return canvas.Icon();
}

// Whether the taskbar is light (it follows the system's mode, not the
// apps'): the tray icon is then dark.
bool TaskbarIsLight() {
  DWORD value = 0;
  DWORD size = sizeof(value);
  if (::RegGetValueW(
          HKEY_CURRENT_USER,
          L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
          L"SystemUsesLightTheme", RRF_RT_REG_DWORD, nullptr, &value,
          &size) != ERROR_SUCCESS) {
    return false;
  }
  return value != 0;
}

const flutter::EncodableValue* Argument(
    const flutter::MethodCall<flutter::EncodableValue>& call) {
  const flutter::EncodableValue* value = call.arguments();
  if (value == nullptr || value->IsNull()) {
    return nullptr;
  }
  return value;
}

}  // namespace

Attention::Attention(flutter::BinaryMessenger* messenger, HWND window,
                     AppWindows* windows)
    : window_(window),
      windows_(windows),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "baocode/attention",
          &flutter::StandardMethodCodec::GetInstance())),
      taskbar_created_(::RegisterWindowMessageW(L"TaskbarCreated")),
      taskbar_button_created_(
          ::RegisterWindowMessageW(L"TaskbarButtonCreated")) {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleMethodCall(call, std::move(result)); });
}

Attention::~Attention() {
  channel_->SetMethodCallHandler(nullptr);
  RemoveIcon();
  StopSound();
  if (icon_ != nullptr) {
    ::DestroyIcon(icon_);
  }
}

void Attention::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  static const flutter::EncodableMap kNone;
  const flutter::EncodableValue* argument = Argument(call);
  const auto* found = argument == nullptr
                          ? nullptr
                          : std::get_if<flutter::EncodableMap>(argument);
  const flutter::EncodableMap& arguments = found == nullptr ? kNone : *found;
  const std::string& method = call.method_name();

  if (method == "notify") {
    Notify(String(arguments, "id"), WideString(arguments, "title"),
           WideString(arguments, "body"));
    result->Success();
    return;
  }
  if (method == "playSound") {
    const flutter::EncodableValue* bytes = Find(arguments, "bytes");
    const auto* data =
        bytes == nullptr ? nullptr : std::get_if<std::vector<uint8_t>>(bytes);
    if (data != nullptr) {
      PlaySoundBytes(*data);
    } else {
      PlaySoundFile(WideString(arguments, "path"));
    }
    result->Success();
    return;
  }
  if (method == "requestAttention") {
    // Until the window is in front again; nothing while it is.
    FLASHWINFO flash = {};
    flash.cbSize = sizeof(flash);
    flash.hwnd = windows_ != nullptr ? windows_->FrontWindow() : window_;
    flash.dwFlags = FLASHW_TRAY | FLASHW_TIMERNOFG;
    ::FlashWindowEx(&flash);
    result->Success();
    return;
  }
  if (method == "setBadge") {
    const auto* count =
        argument == nullptr ? nullptr : std::get_if<int32_t>(argument);
    SetBadge(count == nullptr ? 0 : *count);
    result->Success();
    return;
  }
  if (method == "setTray") {
    SetTray(argument);
    result->Success();
    return;
  }
  if (method == "quit") {
    Quit();
    result->Success();
    return;
  }
  if (method == "pickSound") {
    const std::optional<std::string> path = PickSound();
    result->Success(path ? flutter::EncodableValue(*path)
                         : flutter::EncodableValue());
    return;
  }
  result->NotImplemented();
}

std::optional<LRESULT> Attention::HandleMessage(HWND window, UINT message,
                                                WPARAM wparam, LPARAM lparam) {
  if (message == kTrayMessage) {
    // NOTIFYICON_VERSION_4: the event in the low word.
    switch (LOWORD(lparam)) {
      case NIN_SELECT:
      case NIN_KEYSELECT:
        Open(std::nullopt);
        break;
      case WM_CONTEXTMENU:
        ShowMenu();
        break;
      case NIN_BALLOONUSERCLICK:
        Open(notified_id_.empty() ? std::nullopt
                                  : std::optional<std::string>(notified_id_));
        [[fallthrough]];
      case NIN_BALLOONTIMEOUT:
        // An icon put up only for the notification goes with it.
        if (!tray_) {
          RemoveIcon();
        }
        break;
    }
    return 0;
  }
  if (message == WM_CLOSE) {
    if (quitting_) {
      // On to Flutter, which asks before it quits.
      quitting_ = false;
      return std::nullopt;
    }
    if (tray_) {
      ::ShowWindow(window, SW_HIDE);
      return 0;
    }
    return std::nullopt;
  }
  if (message == WM_COPYDATA && !::IsWindowVisible(window) &&
      !(windows_ != nullptr && windows_->started())) {
    // A second copy of the app hands this one what to open (see main.cpp):
    // the window hidden to the tray comes back for it.
    ::ShowWindow(window, SW_SHOW);
  }
  if (message == taskbar_created_ && taskbar_created_ != 0) {
    // Explorer started again: the tray is new, and empty.
    if (icon_added_) {
      icon_added_ = false;
      ShowIcon();
    }
    return std::nullopt;
  }
  if (message == taskbar_button_created_ && taskbar_button_created_ != 0) {
    // A taskbar button made anew (the window shown again) has no count.
    BadgeWindow(window);
    return std::nullopt;
  }
  if (message == WM_SETTINGCHANGE && lparam != 0 &&
      std::wcscmp(reinterpret_cast<const wchar_t*>(lparam),
                  L"ImmersiveColorSet") == 0) {
    // The taskbar may have gone light or dark.
    if (icon_added_) {
      ShowIcon();
    }
  }
  if (message == WM_DPICHANGED && icon_added_) {
    ShowIcon();
  }
  return std::nullopt;
}

void Attention::SetTray(const flutter::EncodableValue* value) {
  const auto* state =
      value == nullptr ? nullptr : std::get_if<flutter::EncodableMap>(value);
  if (state == nullptr) {
    tray_.reset();
    RemoveIcon();
    return;
  }
  TrayState tray;
  if (const flutter::EncodableValue* dot = Find(*state, "dot")) {
    if (const auto* on = std::get_if<bool>(dot)) {
      tray.dot = *on;
    }
  }
  tray.tooltip = WideString(*state, "tooltip");
  if (const flutter::EncodableValue* waiting = Find(*state, "waiting")) {
    if (const auto* list = std::get_if<flutter::EncodableList>(waiting)) {
      for (const flutter::EncodableValue& item : *list) {
        if (const auto* agent = std::get_if<flutter::EncodableMap>(&item)) {
          tray.waiting.push_back(
              Agent{String(*agent, "id"), WideString(*agent, "title")});
        }
      }
    }
  }
  if (const flutter::EncodableValue* labels = Find(*state, "labels")) {
    if (const auto* map = std::get_if<flutter::EncodableMap>(labels)) {
      tray.show = WideString(*map, "show");
      tray.waiting_label = WideString(*map, "waiting");
      tray.running = WideString(*map, "running");
      tray.quit = WideString(*map, "quit");
    }
  }
  tray_ = std::move(tray);
  ShowIcon();
}

HICON Attention::TrayIcon(bool dot) const {
  const int size = ::GetSystemMetrics(SM_CXSMICON);
  Canvas canvas(size);
  // Whole pixels for each of the logo's 8×6 cells, as large as fit.
  const int cell = (std::max)(1, size / 8);
  const double k = cell / 7.0;
  const int left = (size - 8 * cell) / 2;
  const int top = (size - 6 * cell) / 2;
  const uint32_t ink = TaskbarIsLight() ? 0x1F1F1F : 0xFFFFFF;
  for (const Cell& c : kLogoCells) {
    canvas.Fill(left + static_cast<int>(std::lround(c.x * k)),
                top + static_cast<int>(std::lround(c.y * k)),
                left + static_cast<int>(std::lround((c.x + c.width) * k)),
                top + static_cast<int>(std::lround((c.y + c.height) * k)),
                ink);
  }
  if (dot) {
    const double radius = size * 0.17;
    const double cx = size - radius;
    const double cy = radius;
    canvas.Disc(cx, cy, radius + (std::max)(1.0, size / 16.0), 0, true);
    canvas.Disc(cx, cy, radius, kBadgeRed, false);
  }
  return canvas.Icon();
}

void Attention::ShowIcon() {
  HICON icon = TrayIcon(tray_ && tray_->dot);
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = window_;
  data.uID = kTrayId;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  data.uCallbackMessage = kTrayMessage;
  data.hIcon = icon;
  const std::wstring tooltip =
      tray_ && !tray_->tooltip.empty() ? tray_->tooltip : L"BaoCode";
  wcsncpy_s(data.szTip, tooltip.c_str(), _TRUNCATE);
  if (icon_added_) {
    ::Shell_NotifyIconW(NIM_MODIFY, &data);
  } else if (::Shell_NotifyIconW(NIM_ADD, &data)) {
    icon_added_ = true;
    data.uVersion = NOTIFYICON_VERSION_4;
    ::Shell_NotifyIconW(NIM_SETVERSION, &data);
  }
  if (icon_ != nullptr) {
    ::DestroyIcon(icon_);
  }
  icon_ = icon;
}

void Attention::RemoveIcon() {
  if (!icon_added_) {
    return;
  }
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = window_;
  data.uID = kTrayId;
  ::Shell_NotifyIconW(NIM_DELETE, &data);
  icon_added_ = false;
}

void Attention::ShowMenu() {
  if (!tray_) {
    return;
  }
  const TrayState& tray = *tray_;
  HMENU menu = ::CreatePopupMenu();
  ::AppendMenuW(menu, MF_STRING, kShowCommand, MenuText(tray.show).c_str());
  ::SetMenuDefaultItem(menu, kShowCommand, FALSE);
  if (!tray.waiting.empty()) {
    ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    ::AppendMenuW(menu, MF_STRING | MF_GRAYED, 0,
                  MenuText(tray.waiting_label).c_str());
    for (size_t index = 0; index < tray.waiting.size(); index++) {
      const std::wstring title = L"    " + MenuText(tray.waiting[index].title);
      ::AppendMenuW(menu, MF_STRING, kAgentCommand + index, title.c_str());
    }
  }
  if (!tray.running.empty()) {
    ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    ::AppendMenuW(menu, MF_STRING | MF_GRAYED, 0,
                  MenuText(tray.running).c_str());
  }
  // The app's windows, the one in front checked, and a new one. A copy:
  // Flutter may list them anew before this returns.
  std::vector<AppWindows::Entry> windows;
  if (windows_ != nullptr && windows_->started()) {
    windows = windows_->entries();
    ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    const HWND foreground = ::GetForegroundWindow();
    for (size_t index = 0; index < windows.size(); index++) {
      const bool front =
          windows_->HandleOf(windows[index].view_id) == foreground;
      ::AppendMenuW(menu, MF_STRING | (front ? MF_CHECKED : MF_UNCHECKED),
                    kWindowCommand + index,
                    MenuText(windows[index].title).c_str());
    }
    ::AppendMenuW(menu, MF_STRING, kNewWindowCommand,
                  MenuText(windows_->NewWindowLabel()).c_str());
  }
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, kQuitCommand, MenuText(tray.quit).c_str());

  POINT at = {};
  ::GetCursorPos(&at);
  // In front, so that a click elsewhere closes the menu (the window may be
  // hidden; it still takes the foreground for its menu).
  ::SetForegroundWindow(window_);
  const UINT align = ::GetSystemMetrics(SM_MENUDROPALIGNMENT) != 0
                         ? TPM_RIGHTALIGN
                         : TPM_LEFTALIGN;
  const UINT command = static_cast<UINT>(::TrackPopupMenuEx(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN |
                align,
      at.x, at.y, window_, nullptr));
  ::PostMessageW(window_, WM_NULL, 0, 0);
  ::DestroyMenu(menu);

  if (command == kShowCommand) {
    Open(std::nullopt);
  } else if (command == kQuitCommand) {
    Quit();
  } else if (command == kNewWindowCommand) {
    if (windows_ != nullptr) {
      windows_->RequestNewWindow();
    }
  } else if (command >= kWindowCommand &&
             command - kWindowCommand < windows.size()) {
    if (windows_ != nullptr) {
      windows_->Focus(windows[command - kWindowCommand].view_id);
    }
  } else if (command >= kAgentCommand &&
             command - kAgentCommand < tray.waiting.size()) {
    // A copy: Flutter may set the tray anew before this returns.
    const std::string id = tray.waiting[command - kAgentCommand].id;
    Open(id);
  }
}

void Attention::Notify(const std::string& id, const std::wstring& title,
                       const std::wstring& body) {
  notified_id_ = id;
  if (!icon_added_) {
    ShowIcon();
  }
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = window_;
  data.uID = kTrayId;
  data.uFlags = NIF_INFO;
  wcsncpy_s(data.szInfoTitle, title.c_str(), _TRUNCATE);
  wcsncpy_s(data.szInfo, body.empty() ? L" " : body.c_str(), _TRUNCATE);
  // Silent: the app plays the sound the user picked itself. The app's icon,
  // large.
  data.dwInfoFlags =
      NIIF_USER | NIIF_LARGE_ICON | NIIF_NOSOUND | NIIF_RESPECT_QUIET_TIME;
  data.hBalloonIcon = static_cast<HICON>(::LoadImageW(
      ::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      ::GetSystemMetrics(SM_CXICON), ::GetSystemMetrics(SM_CYICON),
      LR_SHARED));
  ::Shell_NotifyIconW(NIM_MODIFY, &data);
}

void Attention::StopSound() {
  ::PlaySoundW(nullptr, nullptr, 0);
  if (mci_open_) {
    ::mciSendStringW((std::wstring(L"close ") + kSoundAlias).c_str(), nullptr,
                     0, nullptr);
    mci_open_ = false;
  }
}

void Attention::PlaySoundBytes(std::vector<uint8_t> bytes) {
  // Stopped first: the sound playing reads the bytes these replace.
  StopSound();
  sound_ = std::move(bytes);
  if (sound_.empty()) {
    return;
  }
  ::PlaySoundW(reinterpret_cast<LPCWSTR>(sound_.data()), nullptr,
               SND_MEMORY | SND_ASYNC | SND_NODEFAULT);
}

void Attention::PlaySoundFile(const std::wstring& path) {
  StopSound();
  if (path.empty()) {
    return;
  }
  std::wstring extension;
  const size_t dot = path.find_last_of(L'.');
  if (dot != std::wstring::npos) {
    extension = path.substr(dot);
    std::transform(extension.begin(), extension.end(), extension.begin(),
                   [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  }
  if (extension == L".wav") {
    ::PlaySoundW(path.c_str(), nullptr,
                 SND_FILENAME | SND_ASYNC | SND_NODEFAULT);
    return;
  }
  // MP3 and the like, which PlaySound does not play.
  const std::wstring open = L"open \"" + path + L"\" type mpegvideo alias " +
                            kSoundAlias;
  if (::mciSendStringW(open.c_str(), nullptr, 0, nullptr) == 0) {
    mci_open_ = true;
    ::mciSendStringW((std::wstring(L"play ") + kSoundAlias).c_str(), nullptr, 0,
                     nullptr);
  }
}

void Attention::SetBadge(int count) {
  badge_ = (std::max)(0, count);
  if (!taskbar_) {
    if (FAILED(::CoCreateInstance(CLSID_TaskbarList, nullptr,
                                  CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(&taskbar_))) ||
        FAILED(taskbar_->HrInit())) {
      taskbar_ = nullptr;
      return;
    }
  }
  HICON icon = badge_ > 0 ? BadgeIcon(badge_) : nullptr;
  const std::wstring description =
      badge_ > 0 ? std::to_wstring(badge_) : std::wstring();
  // One count for the app, over each of its windows' buttons.
  std::vector<HWND> windows = {window_};
  if (windows_ != nullptr) {
    for (const HWND shown : windows_->ShownWindows()) {
      if (shown != window_) {
        windows.push_back(shown);
      }
    }
  }
  for (const HWND window : windows) {
    taskbar_->SetOverlayIcon(window, icon, description.c_str());
  }
  // The taskbar keeps a copy of its own.
  if (icon != nullptr) {
    ::DestroyIcon(icon);
  }
}

std::optional<std::string> Attention::PickSound() {
  ComPtr<IFileOpenDialog> dialog;
  if (FAILED(::CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) {
    return std::nullopt;
  }
  DWORD options = 0;
  if (SUCCEEDED(dialog->GetOptions(&options))) {
    dialog->SetOptions(options | FOS_FORCEFILESYSTEM | FOS_FILEMUSTEXIST);
  }
  const COMDLG_FILTERSPEC types[] = {
      {L"Sounds", L"*.wav;*.mp3;*.wma;*.m4a"},
  };
  dialog->SetFileTypes(1, types);
  if (FAILED(dialog->Show(::IsWindowVisible(window_) ? window_ : nullptr))) {
    return std::nullopt;
  }
  ComPtr<IShellItem> item;
  if (FAILED(dialog->GetResult(&item))) {
    return std::nullopt;
  }
  PWSTR path = nullptr;
  if (FAILED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) {
    return std::nullopt;
  }
  std::string picked = Utf8FromUtf16(path);
  ::CoTaskMemFree(path);
  return picked;
}

void Attention::BadgeWindow(HWND window) {
  if (badge_ == 0) {
    return;
  }
  if (window == window_ || !taskbar_) {
    SetBadge(badge_);
    return;
  }
  HICON icon = BadgeIcon(badge_);
  taskbar_->SetOverlayIcon(window, icon, std::to_wstring(badge_).c_str());
  if (icon != nullptr) {
    ::DestroyIcon(icon);
  }
}

void Attention::BringBack() {
  ::ShowWindow(window_, ::IsIconic(window_) ? SW_RESTORE : SW_SHOW);
  ::SetForegroundWindow(window_);
}

void Attention::Open(const std::optional<std::string>& id) {
  // An agent's window is Flutter's to bring, once the app keeps windows of
  // its own: the IDE's it is a tab of, or this one. So is the window the
  // tray's icon brings back when none shows (an IDE's, when the app opens
  // to the IDE).
  if (windows_ == nullptr || !windows_->started()) {
    BringBack();
  } else if (!id) {
    if (windows_->ShownWindows().empty()) {
      windows_->RequestReopen();
    } else {
      BringBack();
    }
  }
  channel_->InvokeMethod(
      "open", std::make_unique<flutter::EncodableValue>(
                  id ? flutter::EncodableValue(*id) : flutter::EncodableValue()));
}

void Attention::Quit() {
  if (windows_ != nullptr && windows_->started()) {
    // The close button is the app's then (it would hide this window): the
    // app asks, in the window in front, and quits.
    windows_->RequestQuit();
    return;
  }
  BringBack();
  quitting_ = true;
  ::PostMessageW(window_, WM_CLOSE, 0, 0);
}
