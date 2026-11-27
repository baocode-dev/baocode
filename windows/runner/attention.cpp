#include "attention.h"

#include <flutter/standard_method_codec.h>
#include <mmsystem.h>
#include <windowsx.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <cwchar>
#include <cwctype>
#include <deque>
#include <map>
#include <utility>

#include "app_windows.h"
#include "resource.h"
#include "utils.h"

namespace {

using Microsoft::WRL::ComPtr;

// What the tray icon tells the window, and which of the app's icons it is.
constexpr UINT kTrayMessage = WM_APP + 0x41;
constexpr UINT kTrayId = 1;

// While the tray icon is asked for, how often it is looked for, and put
// back if gone (or put up, if it could not be: the taskbar not there yet,
// at sign-in). Explorer's TaskbarCreated alone was not enough (#860).
constexpr UINT_PTR kTrayTimer = 0x4244;
constexpr UINT kTrayCheckMilliseconds = 15000;

// The tray menu's commands; an agent's is kAgentCommand plus its place, a
// window's kWindowCommand plus its.
constexpr UINT kShowCommand = 1;
constexpr UINT kQuitCommand = 2;
constexpr UINT kNewWindowCommand = 3;
constexpr UINT kAgentCommand = 100;
constexpr UINT kWindowCommand = 1000;

// MCI plays files, so bundled WAV bytes need a file for each playback.
std::wstring SaveTemporaryWav(const std::vector<uint8_t>& bytes) {
  if (bytes.empty() || bytes.size() > MAXDWORD) {
    return L"";
  }
  wchar_t directory[MAX_PATH + 1] = {};
  const DWORD length = ::GetTempPathW(MAX_PATH + 1, directory);
  if (length == 0 || length >= MAX_PATH + 1) {
    return L"";
  }
  wchar_t temporary[MAX_PATH + 1] = {};
  if (::GetTempFileNameW(directory, L"Bao", 0, temporary) == 0) {
    return L"";
  }
  const HANDLE file = ::CreateFileW(temporary, GENERIC_WRITE, 0, nullptr,
                                    TRUNCATE_EXISTING, FILE_ATTRIBUTE_TEMPORARY,
                                    nullptr);
  DWORD written = 0;
  const bool saved =
      file != INVALID_HANDLE_VALUE &&
      ::WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()),
                  &written, nullptr) &&
      written == bytes.size();
  if (file != INVALID_HANDLE_VALUE) {
    ::CloseHandle(file);
  }
  if (!saved) {
    ::DeleteFileW(temporary);
    return L"";
  }
  std::wstring path(temporary);
  path.replace(path.size() - 4, 4, L".wav");
  if (!::MoveFileExW(temporary, path.c_str(), MOVEFILE_REPLACE_EXISTING)) {
    ::DeleteFileW(temporary);
    return L"";
  }
  return path;
}

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

class Attention::SoundPlayer
    : public std::enable_shared_from_this<Attention::SoundPlayer> {
 public:
  SoundPlayer() = default;
  ~SoundPlayer() {
    if (wake_event_ != nullptr) {
      ::CloseHandle(wake_event_);
    }
  }

  SoundPlayer(const SoundPlayer&) = delete;
  SoundPlayer& operator=(const SoundPlayer&) = delete;

  void PlayFile(std::wstring path) {
    if (path.empty()) {
      return;
    }
    Request request;
    request.path = std::move(path);
    Enqueue(std::move(request));
  }

  void PlayBytes(std::vector<uint8_t> bytes) {
    if (bytes.empty()) {
      return;
    }
    Request request;
    request.bytes = std::move(bytes);
    Enqueue(std::move(request));
  }

  // Tells the worker to close active sounds and exit without blocking the UI
  // thread (which would stall shutdown if an audio driver call is stuck).
  void Stop() {
    HANDLE event = nullptr;
    ::AcquireSRWLockExclusive(&lock_);
    stopping_ = true;
    queue_.clear();
    event = wake_event_;
    ::ReleaseSRWLockExclusive(&lock_);
    if (event != nullptr) {
      ::SetEvent(event);
    }
  }

 private:
  static constexpr size_t kMaxQueuedSounds = 4;
  static constexpr size_t kMaxActiveSounds = 4;
  static constexpr DWORD kReapIntervalMs = 5000;
  static constexpr ULONGLONG kMinReapAgeMs = 500;
  static constexpr ULONGLONG kMaxSoundLifetimeMs = 60000;
  static constexpr wchar_t kNotifyWindowClass[] = L"BaoCodeSoundNotify";

  struct Request {
    std::wstring path;
    std::vector<uint8_t> bytes;
  };

  struct ActiveSound {
    std::wstring alias;
    std::wstring temporary_path;
    ULONGLONG started_at = 0;
  };

  void Enqueue(Request request) {
    HANDLE event = nullptr;
    ::AcquireSRWLockExclusive(&lock_);
    if (stopping_) {
      ::ReleaseSRWLockExclusive(&lock_);
      return;
    }
    while (queue_.size() >= kMaxQueuedSounds) {
      queue_.pop_front();
    }
    queue_.push_back(std::move(request));
    if (!started_) {
      if (wake_event_ == nullptr) {
        wake_event_ = ::CreateEventW(nullptr, FALSE, FALSE, nullptr);
      }
      if (wake_event_ != nullptr) {
        auto* self = new std::shared_ptr<SoundPlayer>(shared_from_this());
        const HANDLE thread =
            ::CreateThread(nullptr, 0, &SoundPlayer::ThreadEntry, self, 0,
                           nullptr);
        if (thread != nullptr) {
          started_ = true;
          ::CloseHandle(thread);
        } else {
          delete self;
          queue_.clear();
        }
      } else {
        queue_.clear();
      }
    }
    if (started_) {
      event = wake_event_;
    }
    ::ReleaseSRWLockExclusive(&lock_);
    if (event != nullptr) {
      ::SetEvent(event);
    }
  }

  static DWORD WINAPI ThreadEntry(LPVOID param) {
    std::unique_ptr<std::shared_ptr<SoundPlayer>> holder(
        static_cast<std::shared_ptr<SoundPlayer>*>(param));
    (*holder)->Run();
    return 0;
  }

  static LRESULT CALLBACK NotifyWindowProc(HWND hwnd, UINT message,
                                           WPARAM wparam, LPARAM lparam) {
    if (message == WM_NCCREATE) {
      const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lparam);
      ::SetWindowLongPtrW(
          hwnd, GWLP_USERDATA,
          reinterpret_cast<LONG_PTR>(create->lpCreateParams));
      return TRUE;
    }
    auto* player = reinterpret_cast<SoundPlayer*>(
        ::GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (message == MM_MCINOTIFY && player != nullptr) {
      player->CloseSound(static_cast<UINT>(lparam));
      return 0;
    }
    if (message == WM_NCDESTROY) {
      ::SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
    }
    return ::DefWindowProcW(hwnd, message, wparam, lparam);
  }

  HWND CreateNotifyWindow() {
    const HINSTANCE instance = ::GetModuleHandleW(nullptr);
    WNDCLASSEXW window_class = {};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &SoundPlayer::NotifyWindowProc;
    window_class.hInstance = instance;
    window_class.lpszClassName = kNotifyWindowClass;
    if (::RegisterClassExW(&window_class) == 0 &&
        ::GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      return nullptr;
    }
    return ::CreateWindowExW(0, kNotifyWindowClass, L"", 0, 0, 0, 0, 0,
                             HWND_MESSAGE, nullptr, instance, this);
  }

  void PumpMessages() {
    MSG msg = {};
    while (::PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
      ::TranslateMessage(&msg);
      ::DispatchMessageW(&msg);
    }
  }

  bool IsStopping() {
    ::AcquireSRWLockShared(&lock_);
    const bool stopping = stopping_;
    ::ReleaseSRWLockShared(&lock_);
    return stopping;
  }

  void Run() {
    const HRESULT co = ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    notify_window_ = CreateNotifyWindow();

    for (;;) {
      PumpMessages();

      std::deque<Request> pending;
      bool stopping = false;
      ::AcquireSRWLockExclusive(&lock_);
      stopping = stopping_;
      if (!stopping) {
        pending.swap(queue_);
      }
      ::ReleaseSRWLockExclusive(&lock_);
      if (stopping) {
        break;
      }

      for (const Request& request : pending) {
        if (IsStopping()) {
          break;
        }
        PumpMessages();
        ReapFinishedSounds();
        PlayRequest(request);
      }

      if (IsStopping()) {
        break;
      }
      PumpMessages();
      ReapFinishedSounds();

      const DWORD timeout = active_.empty() ? INFINITE : kReapIntervalMs;
      const DWORD waited = ::MsgWaitForMultipleObjects(1, &wake_event_, FALSE,
                                                       timeout, QS_ALLINPUT);
      if (waited == WAIT_FAILED) {
        break;
      }
    }

    CloseAllSounds();
    if (notify_window_ != nullptr) {
      ::DestroyWindow(notify_window_);
      notify_window_ = nullptr;
    }
    if (SUCCEEDED(co)) {
      ::CoUninitialize();
    }
  }

  void PlayRequest(const Request& request) {
    std::wstring path;
    bool temporary = false;
    if (!request.bytes.empty()) {
      path = SaveTemporaryWav(request.bytes);
      temporary = true;
    } else {
      path = request.path;
    }
    if (path.empty()) {
      return;
    }
    // Cap concurrent MCI devices so broken/missing notifications can never
    // accumulate mciwave threads indefinitely.
    while (active_.size() >= kMaxActiveSounds) {
      auto oldest = active_.begin();
      for (auto it = active_.begin(); it != active_.end(); ++it) {
        if (it->second.started_at < oldest->second.started_at) {
          oldest = it;
        }
      }
      CloseSound(oldest->first);
    }

    std::wstring extension;
    const size_t dot = path.find_last_of(L'.');
    if (dot != std::wstring::npos) {
      extension = path.substr(dot);
      std::transform(extension.begin(), extension.end(), extension.begin(),
                     [](wchar_t c) {
                       return static_cast<wchar_t>(std::towlower(c));
                     });
    }
    const std::wstring alias =
        L"baocode_sound_" + std::to_wstring(::GetCurrentThreadId()) + L"_" +
        std::to_wstring(++next_id_);
    const std::wstring type =
        extension == L".wav" ? L"waveaudio" : L"mpegvideo";
    const std::wstring open =
        L"open \"" + path + L"\" type " + type + L" alias " + alias;
    if (::mciSendStringW(open.c_str(), nullptr, 0, nullptr) != 0) {
      if (temporary) {
        ::DeleteFileW(path.c_str());
      }
      return;
    }
    const UINT device = ::mciGetDeviceIDW(alias.c_str());
    if (device == 0) {
      ::mciSendStringW((L"close " + alias).c_str(), nullptr, 0, nullptr);
      if (temporary) {
        ::DeleteFileW(path.c_str());
      }
      return;
    }
    active_.emplace(
        device,
        ActiveSound{alias, temporary ? path : L"", ::GetTickCount64()});
    const std::wstring play =
        notify_window_ != nullptr ? (L"play " + alias + L" notify")
                                  : (L"play " + alias);
    if (::mciSendStringW(play.c_str(), nullptr, 0, notify_window_) != 0) {
      CloseSound(device);
    }
  }

  void CloseSound(UINT device) {
    const auto found = active_.find(device);
    if (found == active_.end()) {
      return;
    }
    ActiveSound sound = std::move(found->second);
    active_.erase(found);
    ::mciSendStringW((L"close " + sound.alias).c_str(), nullptr, 0, nullptr);
    if (!sound.temporary_path.empty()) {
      ::DeleteFileW(sound.temporary_path.c_str());
    }
  }

  void CloseAllSounds() {
    while (!active_.empty()) {
      CloseSound(active_.begin()->first);
    }
  }

  // Fallback sweep in case a stalled or disconnected audio driver never posts
  // MM_MCINOTIFY: closes stopped or overly old devices and deletes temp files.
  void ReapFinishedSounds() {
    if (active_.empty()) {
      return;
    }
    const ULONGLONG now = ::GetTickCount64();
    std::vector<UINT> finished;
    for (const auto& [device, sound] : active_) {
      const ULONGLONG age = now - sound.started_at;
      if (age >= kMaxSoundLifetimeMs) {
        finished.push_back(device);
        continue;
      }
      if (age < kMinReapAgeMs) {
        continue;
      }
      wchar_t mode[32] = {};
      const std::wstring status = L"status " + sound.alias + L" mode";
      if (::mciSendStringW(status.c_str(), mode,
                           static_cast<UINT>(sizeof(mode) / sizeof(mode[0])),
                           nullptr) != 0 ||
          _wcsicmp(mode, L"playing") != 0) {
        finished.push_back(device);
      }
    }
    for (const UINT device : finished) {
      CloseSound(device);
    }
  }

  SRWLOCK lock_ = SRWLOCK_INIT;
  HANDLE wake_event_ = nullptr;
  std::deque<Request> queue_;
  bool started_ = false;
  bool stopping_ = false;

  // Accessed on the worker thread only.
  HWND notify_window_ = nullptr;
  std::map<UINT, ActiveSound> active_;
  uint64_t next_id_ = 0;
};

Attention::Attention(flutter::BinaryMessenger* messenger, HWND window,
                     AppWindows* windows)
    : window_(window),
      windows_(windows),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "baocode/attention",
          &flutter::StandardMethodCodec::GetInstance())),
      sound_player_(std::make_shared<SoundPlayer>()),
      taskbar_created_(::RegisterWindowMessageW(L"TaskbarCreated")),
      taskbar_button_created_(
          ::RegisterWindowMessageW(L"TaskbarButtonCreated")) {
  // Let through from Explorer even with the app run as administrator: the
  // system keeps lower-integrity messages from it otherwise.
  if (taskbar_created_ != 0) {
    ::ChangeWindowMessageFilterEx(window_, taskbar_created_, MSGFLT_ALLOW,
                                  nullptr);
  }
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleMethodCall(call, std::move(result)); });
}

Attention::~Attention() {
  channel_->SetMethodCallHandler(nullptr);
  RemoveIcon();
  if (sound_player_ != nullptr) {
    sound_player_->Stop();
  }
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
      // Hidden only with the icon up to bring it back: with none (it could
      // not go up), minimized, its taskbar button left (#1107).
      if (!icon_added_ || !IconThere()) {
        icon_added_ = false;
        ShowIcon();
      }
      ::ShowWindow(window, icon_added_ ? SW_HIDE : SW_MINIMIZE);
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
    if (icon_added_ || tray_) {
      icon_added_ = false;
      ShowIcon();
    }
    return std::nullopt;
  }
  if (message == WM_TIMER && wparam == kTrayTimer) {
    if (!tray_) {
      ::KillTimer(window_, kTrayTimer);
    } else if (!icon_added_ || !IconThere()) {
      icon_added_ = false;
      ShowIcon();
    }
    return 0;
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
  bool shown = icon_added_ && ::Shell_NotifyIconW(NIM_MODIFY, &data);
  if (!shown) {
    // Not up, or gone from under it: put up anew. Up after all (a modify
    // that failed otherwise), it is changed instead.
    if (::Shell_NotifyIconW(NIM_ADD, &data)) {
      shown = true;
      data.uVersion = NOTIFYICON_VERSION_4;
      ::Shell_NotifyIconW(NIM_SETVERSION, &data);
    } else {
      const DWORD error = ::GetLastError();
      shown = ::Shell_NotifyIconW(NIM_MODIFY, &data) != FALSE;
      if (!shown && tray_ && !told_tray_failed_) {
        // In events.log, to find why (#1107).
        told_tray_failed_ = true;
        channel_->InvokeMethod(
            "trayFailed", std::make_unique<flutter::EncodableValue>(
                              static_cast<int64_t>(error)));
      }
    }
  }
  if (shown) {
    told_tray_failed_ = false;
  }
  icon_added_ = shown;
  if (tray_) {
    ::SetTimer(window_, kTrayTimer, kTrayCheckMilliseconds, nullptr);
  }
  if (icon_ != nullptr) {
    ::DestroyIcon(icon_);
  }
  icon_ = icon;
}

bool Attention::IconThere() const {
  NOTIFYICONIDENTIFIER identifier = {};
  identifier.cbSize = sizeof(identifier);
  identifier.hWnd = window_;
  identifier.uID = kTrayId;
  RECT rect = {};
  return SUCCEEDED(::Shell_NotifyIconGetRect(&identifier, &rect));
}

void Attention::RemoveIcon() {
  if (!tray_) {
    ::KillTimer(window_, kTrayTimer);
  }
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

void Attention::PlaySoundBytes(std::vector<uint8_t> bytes) {
  if (sound_player_ != nullptr) {
    sound_player_->PlayBytes(std::move(bytes));
  }
}

void Attention::PlaySoundFile(std::wstring path) {
  if (sound_player_ != nullptr) {
    sound_player_->PlayFile(std::move(path));
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
