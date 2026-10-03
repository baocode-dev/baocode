#include "app_windows.h"

#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <utility>

#include "attention.h"
#include "utils.h"

// The engine's own header for these (flutter_windows_internal.h) is not
// among those the tool hands the app; flutter_windows.dll exports them all
// the same.
extern "C" {
typedef struct {
  // The view's initial size, in physical pixels.
  int width;
  int height;
} FlutterDesktopViewControllerProperties;

// A view of |engine| beside those it has, for a window of the app's own;
// the engine stays with whoever owns it.
FLUTTER_EXPORT FlutterDesktopViewControllerRef
FlutterDesktopEngineCreateViewController(
    FlutterDesktopEngineRef engine,
    const FlutterDesktopViewControllerProperties* properties);

// The engine Flutter knows as |engine_id| (PlatformDispatcher.engineId).
FLUTTER_EXPORT FlutterDesktopEngineRef
FlutterDesktopEngineForId(int64_t engine_id);
}

namespace {

// As main.cpp's: a new window's size, and the least its client may be, in
// logical pixels.
constexpr int kDefaultWidth = 1024;
constexpr int kDefaultHeight = 760;
constexpr unsigned int kMinClientWidth = 400;
constexpr unsigned int kMinClientHeight = 540;

// How far below and right of the window in front a new one goes, in
// logical pixels.
constexpr int kCascade = 30;

// Where the main window's word on showing at launch is kept.
constexpr wchar_t kSettingsKey[] = L"Software\\BaoCode";
constexpr wchar_t kMainShownValue[] = L"MainShownAtLaunch";

// How long the main window, held back at launch, waits for Flutter's
// windows before it shows after all.
constexpr UINT_PTR kHoldBackTimer = 0x4242;
constexpr UINT kHoldBackMilliseconds = 10000;

// The one AppWindows (the main window's), for the timer above.
AppWindows* g_app_windows = nullptr;

const flutter::EncodableValue* Find(const flutter::EncodableMap& map,
                                    const char* key) {
  const auto found = map.find(flutter::EncodableValue(key));
  return found == map.end() ? nullptr : &found->second;
}

std::optional<int64_t> IntOf(const flutter::EncodableValue* value) {
  if (value == nullptr) {
    return std::nullopt;
  }
  // Not "small": rpcndr.h defines that as a macro for char, and the
  // declaration would not survive it.
  if (const auto* narrow = std::get_if<int32_t>(value)) {
    return *narrow;
  }
  if (const auto* wide = std::get_if<int64_t>(value)) {
    return *wide;
  }
  return std::nullopt;
}

std::optional<double> NumberOf(const flutter::EncodableValue* value) {
  if (value == nullptr) {
    return std::nullopt;
  }
  if (const auto* number = std::get_if<double>(value)) {
    return *number;
  }
  if (const std::optional<int64_t> whole = IntOf(value)) {
    return static_cast<double>(*whole);
  }
  return std::nullopt;
}

std::string StringOf(const flutter::EncodableValue* value) {
  const auto* string =
      value == nullptr ? nullptr : std::get_if<std::string>(value);
  return string == nullptr ? std::string() : *string;
}

bool BoolOf(const flutter::EncodableValue* value) {
  const auto* flag = value == nullptr ? nullptr : std::get_if<bool>(value);
  return flag != nullptr && *flag;
}

// The name the system gives |monitor| (\\.\DISPLAY1…): a frame's screen.
std::string MonitorName(HMONITOR monitor) {
  MONITORINFOEXW info = {};
  info.cbSize = sizeof(info);
  if (!::GetMonitorInfoW(monitor, &info)) {
    return std::string();
  }
  return Utf8FromUtf16(info.szDevice);
}

// |window| shown and in front, the keyboard's.
void BringToFront(HWND window, int show = SW_SHOW) {
  if (::IsIconic(window)) {
    show = SW_RESTORE;
  }
  ::ShowWindow(window, show);
  ::SetForegroundWindow(window);
}

// |bounds| (physical pixels) kept inside |work|, as far as it fits.
RECT Within(RECT bounds, const RECT& work) {
  const LONG width = (std::min)(bounds.right - bounds.left,
                                work.right - work.left);
  const LONG height = (std::min)(bounds.bottom - bounds.top,
                                 work.bottom - work.top);
  LONG left = bounds.left, top = bounds.top;
  if (left + width > work.right) {
    left = work.left;
  }
  if (top + height > work.bottom) {
    top = work.top;
  }
  left = (std::max)(left, work.left);
  top = (std::max)(top, work.top);
  return {left, top, left + width, top + height};
}

}  // namespace

// --- IdeWindow ---------------------------------------------------------------

IdeWindow::IdeWindow(FlutterDesktopEngineRef engine,
                     flutter::BinaryMessenger* messenger)
    : engine_(engine),
      messenger_(messenger),
      taskbar_button_created_(
          ::RegisterWindowMessageW(L"TaskbarButtonCreated")) {}

IdeWindow::~IdeWindow() {
  // Here, where OnDestroy is still this window's: the view goes before the
  // window does.
  Destroy();
}

bool IdeWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }
  const RECT frame = GetClientArea();
  FlutterDesktopViewControllerProperties properties = {};
  properties.width = frame.right - frame.left;
  properties.height = frame.bottom - frame.top;
  controller_ = FlutterDesktopEngineCreateViewController(engine_, &properties);
  if (controller_ == nullptr) {
    return false;
  }
  view_id_ = static_cast<int64_t>(
      FlutterDesktopViewControllerGetViewId(controller_));
  const HWND view = FlutterDesktopViewGetHWND(
      FlutterDesktopViewControllerGetView(controller_));
  const std::string suffix = "." + std::to_string(view_id_);
  HostView(messenger_, view, "baocode/window" + suffix,
           "baocode/drop" + suffix);
  return true;
}

void IdeWindow::OnDestroy() {
  SetObserver(nullptr, 0);
  ReleaseView();
  if (controller_ != nullptr) {
    // Out of sight first, the window and its view, as the engine's own
    // windows go (see its window_manager.cc): taking the view away waits
    // on the raster thread, which is then not presenting to a window on
    // the screen, whose thread — this one — is the one waiting.
    if (const HWND window = GetHandle()) {
      ::ShowWindow(window, SW_HIDE);
    }
    ::ShowWindow(FlutterDesktopViewGetHWND(
                     FlutterDesktopViewControllerGetView(controller_)),
                 SW_HIDE);
    // Its view goes from the engine, and its window with it.
    FlutterDesktopViewControllerDestroy(controller_);
    controller_ = nullptr;
  }
  Win32Window::OnDestroy();
}

void IdeWindow::ShowInFront() {
  const HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }
  if (maximize_on_show_) {
    maximize_on_show_ = false;
    BringToFront(window, SW_SHOWMAXIMIZED);
    return;
  }
  BringToFront(window);
}

std::optional<LRESULT> IdeWindow::EngineMessage(HWND hwnd, UINT message,
                                                WPARAM wparam,
                                                LPARAM lparam) {
  LRESULT result = 0;
  if (controller_ != nullptr &&
      FlutterDesktopViewControllerHandleTopLevelWindowProc(
          controller_, hwnd, message, wparam, lparam, &result)) {
    return result;
  }
  return std::nullopt;
}

void IdeWindow::ReloadSystemFonts() {
  FlutterDesktopEngineReloadSystemFonts(engine_);
}

LRESULT IdeWindow::MessageHandler(HWND hwnd, UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept {
  // Its taskbar button, made, carries the app's count too.
  if (message == taskbar_button_created_ && taskbar_button_created_ != 0 &&
      attention_ != nullptr) {
    attention_->BadgeWindow(hwnd);
  }
  return ViewWindow::MessageHandler(hwnd, message, wparam, lparam);
}

// --- AppWindows --------------------------------------------------------------

AppWindows::AppWindows(flutter::BinaryMessenger* messenger, HWND main)
    : messenger_(messenger),
      main_(main),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "baocode/windows",
          &flutter::StandardMethodCodec::GetInstance())) {
  g_app_windows = this;
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleMethodCall(call, std::move(result)); });
}

AppWindows::~AppWindows() {
  channel_->SetMethodCallHandler(nullptr);
  ::KillTimer(main_, kHoldBackTimer);
  // The views go while the engine is still there (see FlutterWindow).
  windows_.clear();
  if (g_app_windows == this) {
    g_app_windows = nullptr;
  }
}

void AppWindows::SetAttention(Attention* attention) {
  attention_ = attention;
  for (auto& [id, window] : windows_) {
    window->SetAttention(attention);
  }
}

std::wstring AppWindows::NewWindowLabel() const {
  const auto found = labels_.find("newWindow");
  return found == labels_.end() || found->second.empty() ? L"New Window"
                                                         : found->second;
}

HWND AppWindows::HandleOf(int64_t view_id) const {
  if (view_id == 0) {
    return main_;
  }
  const auto found = windows_.find(view_id);
  return found == windows_.end() ? nullptr : found->second->GetHandle();
}

std::vector<HWND> AppWindows::ShownWindows() const {
  std::vector<HWND> shown;
  if (::IsWindowVisible(main_)) {
    shown.push_back(main_);
  }
  for (const auto& [id, window] : windows_) {
    if (const HWND handle = window->GetHandle();
        handle != nullptr && ::IsWindowVisible(handle)) {
      shown.push_back(handle);
    }
  }
  return shown;
}

HWND AppWindows::FrontWindow() const {
  const std::vector<HWND> shown = ShownWindows();
  const HWND foreground = ::GetForegroundWindow();
  if (std::find(shown.begin(), shown.end(), foreground) != shown.end()) {
    return foreground;
  }
  // The highest of them on the screen.
  for (HWND window = ::GetTopWindow(nullptr); window != nullptr;
       window = ::GetWindow(window, GW_HWNDNEXT)) {
    if (std::find(shown.begin(), shown.end(), window) != shown.end()) {
      return window;
    }
  }
  return main_;
}

void AppWindows::Focus(int64_t view_id) {
  if (view_id == 0) {
    BringToFront(main_);
    return;
  }
  const auto found = windows_.find(view_id);
  if (found != windows_.end()) {
    found->second->ShowInFront();
  }
}

void AppWindows::RequestNewWindow() {
  Send("newWindow", flutter::EncodableValue());
}

void AppWindows::RequestQuit() {
  Send("quit", flutter::EncodableValue());
}

void AppWindows::RequestReopen() {
  Send("reopen", flutter::EncodableValue());
}

bool AppWindows::MainShownAtLaunch() {
  DWORD shown = 1;
  DWORD size = sizeof(shown);
  if (::RegGetValueW(HKEY_CURRENT_USER, kSettingsKey, kMainShownValue,
                     RRF_RT_REG_DWORD, nullptr, &shown,
                     &size) != ERROR_SUCCESS) {
    return true;
  }
  return shown != 0;
}

void AppWindows::HoldMainBack() {
  ::SetTimer(main_, kHoldBackTimer, kHoldBackMilliseconds,
             &AppWindows::HoldBackTimer);
}

void CALLBACK AppWindows::HoldBackTimer(HWND window, UINT message,
                                        UINT_PTR id, DWORD time) {
  ::KillTimer(window, id);
  AppWindows* windows = g_app_windows;
  if (windows == nullptr) {
    return;
  }
  // Flutter never started its windows, or none of them showed: the main
  // window is what the user has.
  if (!windows->started_ || windows->ShownWindows().empty()) {
    BringToFront(windows->main_, SW_SHOWNORMAL);
  }
}

void AppWindows::WindowActivated(int64_t view_id) {
  if (started_) {
    Send("focused", flutter::EncodableValue(view_id));
  }
}

void AppWindows::WindowFrameChanged(int64_t view_id) {
  const HWND window = HandleOf(view_id);
  if (!started_ || window == nullptr || !::IsWindowVisible(window)) {
    return;
  }
  flutter::EncodableValue frame = FrameOf(window);
  auto* map = std::get_if<flutter::EncodableMap>(&frame);
  if (map == nullptr) {
    return;
  }
  (*map)[flutter::EncodableValue("viewId")] = flutter::EncodableValue(view_id);
  Send("frameChanged", std::move(frame));
}

bool AppWindows::WindowCloseRequested(int64_t view_id) {
  if (!started_) {
    return false;
  }
  Send("closeRequested", flutter::EncodableValue(view_id));
  return true;
}

void AppWindows::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  static const flutter::EncodableMap kNone;
  const std::string& method = call.method_name();
  const flutter::EncodableValue* argument = call.arguments();
  const auto* found = argument == nullptr
                          ? nullptr
                          : std::get_if<flutter::EncodableMap>(argument);
  const flutter::EncodableMap& arguments = found == nullptr ? kNone : *found;
  const std::optional<int64_t> id =
      found == nullptr ? IntOf(argument) : IntOf(Find(arguments, "viewId"));

  if (method == "start") {
    started_ = true;
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "create") {
    const std::optional<int64_t> created = Create(arguments);
    result->Success(created ? flutter::EncodableValue(*created)
                            : flutter::EncodableValue());
    return;
  }
  if (method == "quit") {
    // Not here, inside the engine's own call: from the loop (see
    // kQuitMessage).
    ::PostMessageW(main_, kQuitMessage, 0, 0);
    result->Success();
    return;
  }
  if (method == "close") {
    if (id) {
      Close(*id);
    }
    result->Success();
    return;
  }
  if (method == "focus") {
    if (id) {
      Focus(*id);
    }
    result->Success();
    return;
  }
  if (method == "hide") {
    if (id) {
      Hide(*id);
    }
    result->Success();
    return;
  }
  if (method == "setTitle") {
    if (const HWND window = id ? HandleOf(*id) : nullptr) {
      ::SetWindowTextW(window,
                       Utf16FromUtf8(StringOf(Find(arguments, "title"))).c_str());
    }
    result->Success();
    return;
  }
  if (method == "setEdited") {
    // macOS' dot in the close button; Windows has none.
    result->Success();
    return;
  }
  if (method == "frame") {
    const HWND window = id ? HandleOf(*id) : nullptr;
    result->Success(window == nullptr ? flutter::EncodableValue()
                                      : FrameOf(window));
    return;
  }
  if (method == "screens") {
    result->Success(Screens());
    return;
  }
  if (method == "setWindowList") {
    entries_.clear();
    const auto* windows =
        std::get_if<flutter::EncodableList>(Find(arguments, "windows"));
    if (windows != nullptr) {
      for (const flutter::EncodableValue& value : *windows) {
        const auto* window = std::get_if<flutter::EncodableMap>(&value);
        if (window == nullptr) {
          continue;
        }
        const std::optional<int64_t> view_id = IntOf(Find(*window, "viewId"));
        if (!view_id) {
          continue;
        }
        entries_.push_back(
            {*view_id, Utf16FromUtf8(StringOf(Find(*window, "title")))});
      }
    }
    labels_.clear();
    const auto* labels =
        std::get_if<flutter::EncodableMap>(Find(arguments, "labels"));
    if (labels != nullptr) {
      for (const auto& [key, value] : *labels) {
        const auto* name = std::get_if<std::string>(&key);
        if (name != nullptr) {
          labels_[*name] = Utf16FromUtf8(StringOf(&value));
        }
      }
    }
    result->Success();
    return;
  }
  if (method == "setMainShownAtLaunch") {
    const DWORD shown = BoolOf(argument) ? 1 : 0;
    ::RegSetKeyValueW(HKEY_CURRENT_USER, kSettingsKey, kMainShownValue,
                      REG_DWORD, &shown, sizeof(shown));
    result->Success();
    return;
  }
  result->NotImplemented();
}

std::optional<int64_t> AppWindows::Create(
    const flutter::EncodableMap& arguments) {
  const std::optional<int64_t> engine_id = IntOf(Find(arguments, "engineId"));
  const FlutterDesktopEngineRef engine =
      engine_id ? FlutterDesktopEngineForId(*engine_id) : nullptr;
  if (engine == nullptr) {
    return std::nullopt;
  }
  auto window = std::make_unique<IdeWindow>(engine, messenger_);
  const std::wstring title =
      Utf16FromUtf8(StringOf(Find(arguments, "title")));
  // Made hidden, at the default size, then put in place (in physical
  // pixels, which Create does not take); shown when Flutter focuses it,
  // once it has drawn.
  if (!window->Create(title.empty() ? L"BaoCode" : title,
                      Win32Window::Point(10, 10),
                      Win32Window::Size(kDefaultWidth, kDefaultHeight))) {
    return std::nullopt;
  }
  const HWND handle = window->GetHandle();
  window->SetMinimumSize(Win32Window::Size(kMinClientWidth, kMinClientHeight));

  RECT bounds = {};
  bool placed = false;
  const auto* frame =
      std::get_if<flutter::EncodableMap>(Find(arguments, "frame"));
  if (frame != nullptr) {
    const std::optional<double> x = NumberOf(Find(*frame, "x"));
    const std::optional<double> y = NumberOf(Find(*frame, "y"));
    const std::optional<double> width = NumberOf(Find(*frame, "width"));
    const std::optional<double> height = NumberOf(Find(*frame, "height"));
    if (x && y && width && height && *width > 0 && *height > 0) {
      bounds = {static_cast<LONG>(*x), static_cast<LONG>(*y),
                static_cast<LONG>(*x + *width),
                static_cast<LONG>(*y + *height)};
      placed = true;
      // Windows has no full screen of the app's: maximized stands in.
      if (BoolOf(Find(*frame, "maximized")) ||
          BoolOf(Find(*frame, "fullscreen"))) {
        window->ShowMaximizedFirst();
      }
    }
  }
  if (!placed) {
    // Below and right of the window in front, at the default size for its
    // monitor; centred on it when there is none.
    const HWND front = FrontWindow();
    RECT front_bounds = {};
    const bool has_front = front != nullptr && ::IsWindowVisible(front) &&
                           !::IsIconic(front) &&
                           ::GetWindowRect(front, &front_bounds);
    const HMONITOR monitor =
        has_front ? ::MonitorFromWindow(front, MONITOR_DEFAULTTONEAREST)
                  : ::MonitorFromWindow(main_, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO info = {};
    info.cbSize = sizeof(info);
    ::GetMonitorInfoW(monitor, &info);
    const double scale = ::FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
    // An agent's window (AppWindows.openAgent) asks to be narrower.
    const std::optional<double> asked = NumberOf(Find(arguments, "width"));
    const LONG width = static_cast<LONG>(
        (asked && *asked > 0 ? *asked : kDefaultWidth) * scale);
    const LONG height = static_cast<LONG>(kDefaultHeight * scale);
    const RECT& work = info.rcWork;
    LONG left = (work.left + work.right - width) / 2;
    LONG top = (work.top + work.bottom - height) / 2;
    if (has_front && !::IsZoomed(front)) {
      left = front_bounds.left + static_cast<LONG>(kCascade * scale);
      top = front_bounds.top + static_cast<LONG>(kCascade * scale);
    }
    bounds = Within({left, top, left + width, top + height}, work);
  }
  ::SetWindowPos(handle, nullptr, bounds.left, bounds.top,
                 bounds.right - bounds.left, bounds.bottom - bounds.top,
                 SWP_NOZORDER | SWP_NOACTIVATE);

  const int64_t view_id = window->view_id();
  window->SetAttention(attention_);
  window->SetObserver(this, view_id);
  windows_[view_id] = std::move(window);
  return view_id;
}

void AppWindows::Close(int64_t view_id) {
  if (view_id == 0) {
    Hide(0);
    return;
  }
  const auto found = windows_.find(view_id);
  if (found == windows_.end()) {
    return;
  }
  // Out of the list first: the window, going, may be asked about.
  std::unique_ptr<IdeWindow> window = std::move(found->second);
  windows_.erase(found);
  window = nullptr;
}

void AppWindows::Hide(int64_t view_id) {
  if (const HWND window = HandleOf(view_id)) {
    ::ShowWindow(window, SW_HIDE);
  }
}

flutter::EncodableValue AppWindows::FrameOf(HWND window) const {
  WINDOWPLACEMENT placement = {};
  placement.length = sizeof(placement);
  if (!::GetWindowPlacement(window, &placement)) {
    return flutter::EncodableValue();
  }
  const bool zoomed = ::IsZoomed(window) != 0;
  const bool iconic = ::IsIconic(window) != 0;
  RECT bounds = {};
  if (zoomed || iconic) {
    // Its normal place, which the placement keeps in the work area's
    // coordinates: to the screen's.
    bounds = placement.rcNormalPosition;
    MONITORINFO info = {};
    info.cbSize = sizeof(info);
    if (::GetMonitorInfoW(::MonitorFromRect(&bounds, MONITOR_DEFAULTTONEAREST),
                          &info)) {
      ::OffsetRect(&bounds, info.rcWork.left - info.rcMonitor.left,
                   info.rcWork.top - info.rcMonitor.top);
    }
  } else if (!::GetWindowRect(window, &bounds)) {
    return flutter::EncodableValue();
  }
  const bool maximized =
      zoomed || (iconic && (placement.flags & WPF_RESTORETOMAXIMIZED) != 0);
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("x"),
       flutter::EncodableValue(static_cast<double>(bounds.left))},
      {flutter::EncodableValue("y"),
       flutter::EncodableValue(static_cast<double>(bounds.top))},
      {flutter::EncodableValue("width"),
       flutter::EncodableValue(static_cast<double>(bounds.right - bounds.left))},
      {flutter::EncodableValue("height"),
       flutter::EncodableValue(static_cast<double>(bounds.bottom - bounds.top))},
      {flutter::EncodableValue("maximized"), flutter::EncodableValue(maximized)},
      {flutter::EncodableValue("fullscreen"), flutter::EncodableValue(false)},
      {flutter::EncodableValue("screen"),
       flutter::EncodableValue(MonitorName(
           ::MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST)))},
  });
}

flutter::EncodableValue AppWindows::Screens() {
  flutter::EncodableList screens;
  ::EnumDisplayMonitors(
      nullptr, nullptr,
      [](HMONITOR monitor, HDC, LPRECT, LPARAM data) -> BOOL {
        auto* list = reinterpret_cast<flutter::EncodableList*>(data);
        MONITORINFO info = {};
        info.cbSize = sizeof(info);
        if (!::GetMonitorInfoW(monitor, &info)) {
          return TRUE;
        }
        const RECT& work = info.rcWork;
        list->push_back(flutter::EncodableValue(flutter::EncodableMap{
            {flutter::EncodableValue("id"),
             flutter::EncodableValue(MonitorName(monitor))},
            {flutter::EncodableValue("x"),
             flutter::EncodableValue(static_cast<double>(work.left))},
            {flutter::EncodableValue("y"),
             flutter::EncodableValue(static_cast<double>(work.top))},
            {flutter::EncodableValue("width"),
             flutter::EncodableValue(static_cast<double>(work.right - work.left))},
            {flutter::EncodableValue("height"),
             flutter::EncodableValue(
                 static_cast<double>(work.bottom - work.top))},
        }));
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&screens));
  return flutter::EncodableValue(std::move(screens));
}

void AppWindows::Send(const char* method, flutter::EncodableValue arguments) {
  channel_->InvokeMethod(
      method, std::make_unique<flutter::EncodableValue>(std::move(arguments)));
}
