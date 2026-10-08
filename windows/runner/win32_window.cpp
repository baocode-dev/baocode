#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include <algorithm>
#include <chrono>
#include <cstdarg>
#include <cstdio>
#include <string>

#include "log_folder.h"
#include "resource.h"

namespace {

// The longest the engine blocks waiting for a frame of the content's new
// size (kWindowResizeTimeout in flutter_windows_view.cc): a move of the
// content that takes as long gave up on it (see Win32Window::SizeContent).
constexpr std::chrono::milliseconds kEngineResizeWait{100};

// The timer of Win32Window::ResyncContent, and when it runs: soon after
// the window settles, then less and less often while the engine presents
// nothing (the display asleep); after kMaxResyncAttempts, only as the
// window is shown or activated again.
constexpr UINT_PTR kResyncTimer = 0x4243;
constexpr UINT kResyncDelayMilliseconds = 300;
constexpr UINT kMaxResyncDelayMilliseconds = 8000;
constexpr int kMaxResyncAttempts = 8;

// The most lines a run writes to window.log, and the size past which the
// next run starts it anew (the old one kept as window.1.log).
constexpr int kMaxLogLines = 300;
constexpr ULONGLONG kMaxLogBytes = 1024 * 1024;

// A line in the data folder's logs\window.log (see log_folder.h), for a
// user to send: how the windows' content was kept in step with the engine
// (see Win32Window::SizeContent).
void LogContent(const char* format, ...) {
  static int lines = 0;
  static bool started = false;
  if (lines >= kMaxLogLines) {
    return;
  }
  const std::wstring folder = log_folder::Path();
  if (folder.empty()) {
    return;
  }
  const std::wstring path = folder + L"\\window.log";
  if (!started) {
    started = true;
    WIN32_FILE_ATTRIBUTE_DATA data = {};
    if (::GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data) &&
        ((static_cast<ULONGLONG>(data.nFileSizeHigh) << 32) |
         data.nFileSizeLow) > kMaxLogBytes) {
      ::MoveFileExW(path.c_str(), (folder + L"\\window.1.log").c_str(),
                    MOVEFILE_REPLACE_EXISTING);
    }
  }
  FILE* out = nullptr;
  if (_wfopen_s(&out, path.c_str(), L"a") != 0 || out == nullptr) {
    return;
  }
  SYSTEMTIME now = {};
  ::GetLocalTime(&now);
  std::fprintf(out, "%04u-%02u-%02u %02u:%02u:%02u.%03u ", now.wYear,
               now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond,
               now.wMilliseconds);
  va_list arguments;
  va_start(arguments, format);
  std::vfprintf(out, format, arguments);
  va_end(arguments);
  std::fputc('\n', out);
  std::fclose(out);
  lines++;
}

LONG WidthOf(const RECT& rect) {
  return rect.right - rect.left;
}

LONG HeightOf(const RECT& rect) {
  return rect.bottom - rect.top;
}

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

/// What DWM should do with the window's corners.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0, which is where Windows 11 rounding comes in.
#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWCP_ROUND
#define DWMWCP_ROUND 2
#endif

/// The window's border and caption colors, and "no color". Windows 11.
///
/// Redefined in case the SDK is older than 10.0.22000.0.
#ifndef DWMWA_BORDER_COLOR
#define DWMWA_BORDER_COLOR 34
#endif
#ifndef DWMWA_CAPTION_COLOR
#define DWMWA_CAPTION_COLOR 35
#endif
#ifndef DWMWA_COLOR_NONE
#define DWMWA_COLOR_NONE 0xFFFFFFFE
#endif

/// Which system backdrop DWM draws in the frame extended into the client.
/// Windows 11 build 22523. Acrylic blurs what is behind the window, which
/// is the material the sidebar tints (see AppColors.sidebarSurface).
#ifndef DWMWA_SYSTEMBACKDROP_TYPE
#define DWMWA_SYSTEMBACKDROP_TYPE 38
#endif
#ifndef DWMSBT_TRANSIENTWINDOW
#define DWMSBT_TRANSIENTWINDOW 3
#endif

/// First Windows 11 build, and the first that takes the backdrop attribute.
constexpr DWORD kWindows11Build = 22000;
constexpr DWORD kSystemBackdropBuild = 22523;

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;
static std::optional<bool> g_dark_appearance;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

// The OS build, from ntdll. GetVersionEx lies once the manifest names
// Windows 10, and Windows 11 still reports itself as 10.0.
DWORD WindowsBuild() {
  using RtlGetVersionPtr = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
  const HMODULE ntdll = ::GetModuleHandleW(L"ntdll.dll");
  if (ntdll == nullptr) {
    return 0;
  }
  const auto rtl_get_version = reinterpret_cast<RtlGetVersionPtr>(
      ::GetProcAddress(ntdll, "RtlGetVersion"));
  if (rtl_get_version == nullptr) {
    return 0;
  }
  RTL_OSVERSIONINFOW info = {};
  info.dwOSVersionInfoSize = sizeof(info);
  if (rtl_get_version(&info) != 0) {
    return 0;
  }
  return info.dwBuildNumber;
}

// Acrylic, on the Windows 11 builds that have no backdrop attribute yet:
// the undocumented composition policy. The tint is the app's own dark, in
// the policy's AABBGGRR.
void AskForAccentAcrylic(HWND window) {
  using SetWindowCompositionAttributePtr =
      BOOL(WINAPI*)(HWND, void*);
  struct AccentPolicy {
    int state;
    DWORD flags;
    DWORD color;
    DWORD animation;
  };
  struct CompositionAttribute {
    int attribute;
    void* data;
    SIZE_T size;
  };
  const HMODULE user32 = ::GetModuleHandleW(L"user32.dll");
  if (user32 == nullptr) {
    return;
  }
  const auto set_attribute = reinterpret_cast<SetWindowCompositionAttributePtr>(
      ::GetProcAddress(user32, "SetWindowCompositionAttribute"));
  if (set_attribute == nullptr) {
    return;
  }
  // ACCENT_ENABLE_ACRYLICBLURBEHIND, and the flag that tints it.
  AccentPolicy policy = {4, 2, 0xCC181818, 0};
  CompositionAttribute data = {19, &policy, sizeof(policy)};
  set_attribute(window, &data);
}

// Asks DWM for the frame a window of this system has around it: its shadow,
// its rounded corners and the line along its edge. The window's non-client
// area is empty (see WM_NCCALCSIZE) — the app draws the header itself — and
// that is what takes all of those with it: what DWM has to draw around is
// named here instead.
//
// On Windows 11 the frame is the whole client, a sheet of glass, and the
// backdrop behind it is acrylic: what the sidebar and the conversation tint
// (see AppColors). Elsewhere it is one pixel of each side, the window's
// own edge and nothing the app paints under.
void AskForSystemFrame(HWND window) {
  const DWORD build = WindowsBuild();
  const bool acrylic = build >= kWindows11Build;
  const MARGINS margins = acrylic ? MARGINS{-1, -1, -1, -1}
                                  : MARGINS{1, 1, 1, 1};
  ::DwmExtendFrameIntoClientArea(window, &margins);
  // Windows rounds the corners of a window whose frame it draws, of its own
  // accord only while the frame is the whole of the window's edge (see
  // above), so it is asked for them.
  const int corners = DWMWCP_ROUND;
  ::DwmSetWindowAttribute(window, DWMWA_WINDOW_CORNER_PREFERENCE, &corners,
                          sizeof(corners));
  if (!acrylic) {
    return;
  }
  // No caption bar of its own over the glass: the app draws the header.
  // Keep the DWM border in step with the system app theme. Without this,
  // Windows 11 keeps the hard-coded dark border even in light mode.
  const COLORREF caption = DWMWA_COLOR_NONE;
  ::DwmSetWindowAttribute(window, DWMWA_CAPTION_COLOR, &caption,
                          sizeof(caption));
  DWORD apps_use_light_theme = 1;
  DWORD value_size = sizeof(apps_use_light_theme);
  const bool has_theme =
      RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                  kGetPreferredBrightnessRegValue, RRF_RT_REG_DWORD, nullptr,
                  &apps_use_light_theme, &value_size) == ERROR_SUCCESS;
  const bool dark = g_dark_appearance.value_or(
      has_theme ? apps_use_light_theme == 0 : false);
  const COLORREF border = dark ? 0x002C2C2C : 0x00D6D6D6;
  ::DwmSetWindowAttribute(window, DWMWA_BORDER_COLOR, &border, sizeof(border));
  if (build >= kSystemBackdropBuild) {
    const int backdrop = DWMSBT_TRANSIENTWINDOW;
    ::DwmSetWindowAttribute(window, DWMWA_SYSTEMBACKDROP_TYPE, &backdrop,
                            sizeof(backdrop));
  } else {
    AskForAccentAcrylic(window);
  }
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), kStyle,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);
  AskForSystemFrame(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE:
      SizeContent();
      return 0;

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      // Back in front: a resync that gave up tries again.
      if (LOWORD(wparam) != WA_INACTIVE && resync_pending_) {
        resync_attempts_ = 0;
        ScheduleResync(kResyncDelayMilliseconds);
      }
      return 0;

    case WM_SHOWWINDOW:
      if (wparam && resync_pending_) {
        resync_attempts_ = 0;
        ScheduleResync(kResyncDelayMilliseconds);
      }
      break;

    case WM_ENTERSIZEMOVE:
      sizing_ = true;
      break;

    case WM_EXITSIZEMOVE:
      sizing_ = false;
      if (resync_pending_) {
        ScheduleResync(kResyncDelayMilliseconds);
      }
      break;

    case WM_TIMER:
      if (wparam == kResyncTimer) {
        ::KillTimer(hwnd, kResyncTimer);
        ResyncContent();
        return 0;
      }
      break;

    case WM_GETMINMAXINFO: {
      // At the dpi the window has now, with the frame it has (see
      // NonClientSize): the sides and the bottom, no top.
      if (minimum_size_.width > 0 && minimum_size_.height > 0) {
        const double scale = FlutterDesktopGetDpiForHWND(hwnd) / 96.0;
        const SIZE border = ResizeBorder();
        auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
        info->ptMinTrackSize.x =
            static_cast<LONG>(minimum_size_.width * scale) + 2 * border.cx;
        info->ptMinTrackSize.y =
            static_cast<LONG>(minimum_size_.height * scale) + border.cy;
      }
      return 0;
    }

    case WM_NCCALCSIZE:
      if (const std::optional<LRESULT> size = NonClientSize(wparam, lparam)) {
        return *size;
      }
      break;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      AskForSystemFrame(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  // The view covers the client. The backdrop is asked for again once it
  // does: parenting the view is what would otherwise paint over the glass
  // before the first frame.
  AskForSystemFrame(window_handle_);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

void Win32Window::SizeContent() {
  if (child_content_ == nullptr) {
    return;
  }
  const RECT client = GetClientArea();
  const long long waited = MoveContent(client);
  if (waited >= kEngineResizeWait.count() && !resync_pending_) {
    LogContent("%p: content %ldx%ld waited %lldms for a frame: resync pending",
               window_handle_, WidthOf(client), HeightOf(client), waited);
    resync_pending_ = true;
  }
  // Pending, a quick move clears nothing: back to the size of the engine's
  // surface, the engine does not wait at all.
  if (resync_pending_) {
    resync_attempts_ = 0;
    ScheduleResync(kResyncDelayMilliseconds);
  }
}

long long Win32Window::MoveContent(const RECT& rect) {
  const auto start = std::chrono::steady_clock::now();
  ::MoveWindow(child_content_, rect.left, rect.top, WidthOf(rect),
               HeightOf(rect), TRUE);
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::steady_clock::now() - start)
      .count();
}

void Win32Window::ScheduleResync(UINT milliseconds) {
  if (window_handle_ != nullptr) {
    ::SetTimer(window_handle_, kResyncTimer, milliseconds, nullptr);
  }
}

void Win32Window::ResyncContent() {
  if (!resync_pending_ || child_content_ == nullptr ||
      window_handle_ == nullptr) {
    return;
  }
  // Only where the engine can present: shown, not minimized, not being
  // sized. Each schedules this again as it ends.
  if (sizing_ || !::IsWindowVisible(window_handle_) ||
      ::IsIconic(window_handle_)) {
    return;
  }
  const RECT client = GetClientArea();
  if (HeightOf(client) <= 2) {
    resync_pending_ = false;
    return;
  }
  // A pixel shorter, or two when the content is a pixel short already (a
  // try that timed out left it there): a size other than the content's, so
  // one the engine waits for.
  RECT content = {};
  ::GetClientRect(child_content_, &content);
  RECT shorter = client;
  shorter.bottom -= HeightOf(content) == HeightOf(client) - 1 ? 2 : 1;
  const long long waited = MoveContent(shorter);
  if (waited >= kEngineResizeWait.count()) {
    // No frame of it presented in time: the content stays short (a size the
    // engine still waits for, and presents once it can) until a later try.
    resync_attempts_++;
    const bool again = resync_attempts_ < kMaxResyncAttempts;
    LogContent("%p: resync %d: content %ldx%ld waited %lldms for a frame: %s",
               window_handle_, resync_attempts_, WidthOf(shorter),
               HeightOf(shorter), waited,
               again ? "tried again later"
                     : "tried again as the window is shown or activated");
    if (again) {
      ScheduleResync((std::min)(kMaxResyncDelayMilliseconds,
                                kResyncDelayMilliseconds << resync_attempts_));
    }
    return;
  }
  // Presented: the engine's surface is no longer the client's size, so the
  // move back is one it waits for too.
  const long long back = MoveContent(client);
  resync_pending_ = false;
  LogContent("%p: resynced: content %ldx%ld in %lldms, back to %ldx%ld in "
             "%lldms",
             window_handle_, WidthOf(shorter), HeightOf(shorter), waited,
             WidthOf(client), HeightOf(client), back);
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

void Win32Window::SetMinimumSize(const Size& size) {
  minimum_size_ = size;
}

void Win32Window::SetDarkAppearance(bool dark) {
  g_dark_appearance = dark;
  EnumThreadWindows(
      GetCurrentThreadId(),
      [](HWND window, LPARAM) -> BOOL {
        UpdateTheme(window);
        AskForSystemFrame(window);
        return TRUE;
      },
      0);
}

SIZE Win32Window::ResizeBorder() const {
  const UINT dpi = FlutterDesktopGetDpiForHWND(window_handle_);
  const int padding = ::GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
  return {::GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) + padding,
          ::GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) + padding};
}

std::optional<LRESULT> Win32Window::NonClientSize(WPARAM wparam,
                                                 LPARAM lparam) const {
  // Both forms of the message: the one with a proposed window rectangle, and
  // the one with a plain rectangle to fill in (sent as the window is
  // created).
  RECT* client = wparam == static_cast<WPARAM>(TRUE)
                     ? &reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam)->rgrc[0]
                     : reinterpret_cast<RECT*>(lparam);
  if (window_handle_ == nullptr) {
    return 0;
  }
  // Minimized, there is no client: the view is sized to nothing, which the
  // engine takes for a hidden window (it sends Flutter no size, and waits on
  // no frame). Less the border below, the minimized rectangle would leave a
  // strip of it instead — a window too narrow to keep the sidebar docked,
  // and a resize the engine waits on a frame of that size for, which a
  // hidden window may never present: until another resize, the engine then
  // drops every frame of any other size (the window seems frozen).
  if (::IsIconic(window_handle_)) {
    client->right = client->left;
    client->bottom = client->top;
    return 0;
  }
  if (::IsZoomed(window_handle_)) {
    // The monitor of the rectangle proposed, not of the window: the window
    // is still where it was. Restored from minimized, that is off every
    // screen (-32000, -32000), nearest the primary — whose work area, on
    // a second screen of another size, left the window not filling its own
    // and its content where the window was not, taking no input until it
    // was dragged. Moved to another screen maximized (Win+Shift+arrow), it
    // was the screen it left.
    MONITORINFO monitor = {};
    monitor.cbSize = sizeof(monitor);
    if (::GetMonitorInfoW(::MonitorFromRect(client, MONITOR_DEFAULTTONEAREST),
                          &monitor)) {
      *client = monitor.rcWork;
    }
    return 0;
  }
  const SIZE border = ResizeBorder();
  client->left += border.cx;
  client->right -= border.cx;
  client->bottom -= border.cy;
  return 0;
}

std::optional<LRESULT> Win32Window::ResizeHitTest(const POINT& point) const {
  if (window_handle_ == nullptr) {
    return std::nullopt;
  }
  // Maximized, the header drags the window back down instead (the system
  // does that itself for HTCAPTION), and there is no border to grab.
  if (::IsZoomed(window_handle_)) {
    return std::nullopt;
  }
  RECT client = {};
  if (!::GetClientRect(window_handle_, &client)) {
    return std::nullopt;
  }
  const SIZE border = ResizeBorder();
  // The top is a strip of the client (there is no frame above it), and its
  // corners reach in as far as the sides' border reaches out; the sides and
  // the bottom are the frame, outside the client.
  const bool top = point.y < border.cy;
  const LONG corner = top ? border.cx : 0;
  const bool left = point.x < corner;
  const bool right = point.x >= client.right - corner;
  const bool bottom = point.y >= client.bottom;
  if (left && top) {
    return HTTOPLEFT;
  }
  if (right && top) {
    return HTTOPRIGHT;
  }
  if (left && bottom) {
    return HTBOTTOMLEFT;
  }
  if (right && bottom) {
    return HTBOTTOMRIGHT;
  }
  if (left) {
    return HTLEFT;
  }
  if (right) {
    return HTRIGHT;
  }
  if (top) {
    return HTTOP;
  }
  if (bottom) {
    return HTBOTTOM;
  }
  return std::nullopt;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode = 1;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS || g_dark_appearance.has_value()) {
    BOOL enable_dark_mode = g_dark_appearance.value_or(light_mode == 0);
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
