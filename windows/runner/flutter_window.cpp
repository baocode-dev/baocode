#include "flutter_window.h"

#include <flutter_windows.h>
#include <windows.h>
#include <windowsx.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

// The point the hit test at |window| names, in the window's own pixels (the
// hit test names the screen; the mouse messages already name the client).
POINT ClientPointOf(HWND window, LPARAM lparam) {
  POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
  ::ScreenToClient(window, &point);
  return point;
}

// The loop that resizes the window from |part| of its frame (what WindowPart
// answers with), or nullopt for everything that is not the frame.
std::optional<WPARAM> SizeCommand(LRESULT part) {
  switch (part) {
    case HTLEFT:
      return SC_SIZE | WMSZ_LEFT;
    case HTRIGHT:
      return SC_SIZE | WMSZ_RIGHT;
    case HTTOP:
      return SC_SIZE | WMSZ_TOP;
    case HTTOPLEFT:
      return SC_SIZE | WMSZ_TOPLEFT;
    case HTTOPRIGHT:
      return SC_SIZE | WMSZ_TOPRIGHT;
    case HTBOTTOM:
      return SC_SIZE | WMSZ_BOTTOM;
    case HTBOTTOMLEFT:
      return SC_SIZE | WMSZ_BOTTOMLEFT;
    case HTBOTTOMRIGHT:
      return SC_SIZE | WMSZ_BOTTOMRIGHT;
    default:
      return std::nullopt;
  }
}

// The cursor the pointer shows over |part| of the window's frame: the one the
// system shows over its own, since this window's frame is drawn by the app
// (the system would answer for a frame of its own to point at).
LPCWSTR CursorFor(LRESULT part) {
  switch (part) {
    case HTLEFT:
    case HTRIGHT:
      return IDC_SIZEWE;
    case HTTOP:
    case HTBOTTOM:
      return IDC_SIZENS;
    case HTTOPLEFT:
    case HTBOTTOMRIGHT:
      return IDC_SIZENWSE;
    case HTTOPRIGHT:
    case HTBOTTOMLEFT:
      return IDC_SIZENESW;
    default:
      return nullptr;
  }
}

// What the system runs when |part| of the window's caption (what WindowPart
// answers with, less the frame) is pressed: the loop that moves it, or the
// command one of its buttons stands for. nullopt for the parts there are no
// such commands for.
std::optional<WPARAM> CommandForPress(HWND window, LRESULT part) {
  switch (part) {
    case HTCAPTION:
      return SC_MOVE | HTCAPTION;
    case HTMINBUTTON:
      return SC_MINIMIZE;
    case HTMAXBUTTON:
      return ::IsZoomed(window) ? SC_RESTORE : SC_MAXIMIZE;
    default:
      return std::nullopt;
  }
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // The view covers the whole client area, and the cursor's hit test goes to
  // the window under it — the view, which would answer "the client" for every
  // pixel of the window. Its own procedure is what hands up the parts that
  // are this window's own (see ViewProc and WindowPart).
  view_ = flutter_controller_->view()->GetNativeWindow();
  view_proc_ = reinterpret_cast<WNDPROC>(
      ::SetWindowLongPtrW(view_, GWLP_WNDPROC,
                          reinterpret_cast<LONG_PTR>(&FlutterWindow::ViewProc)));

  // Window controls the Flutter side asks for (see window_controls.dart).
  window_channel_ = std::make_unique<WindowChannel>(
      flutter_controller_->engine()->messenger(), GetHandle());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // The view goes with the controller below: its own procedure is put back
  // first, so that what is left of its life is not spent in ViewProc (which
  // would look for a window that is on its way out).
  if (view_ != nullptr && view_proc_ != nullptr) {
    ::SetWindowLongPtrW(view_, GWLP_WNDPROC,
                        reinterpret_cast<LONG_PTR>(view_proc_));
  }
  view_ = nullptr;
  view_proc_ = nullptr;

  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT CALLBACK FlutterWindow::ViewProc(HWND hwnd, UINT const message,
                                         WPARAM const wparam,
                                         LPARAM const lparam) noexcept {
  auto* that =
      static_cast<FlutterWindow*>(GetThisFromHandle(::GetParent(hwnd)));

  // The cursor's position, over the parts of the window that are the
  // window's own, is this window's to answer — its buttons, and the strip
  // Flutter draws the header in. The view is a child window over the whole
  // client area, and the system asks it, so its own answer would be "the
  // client" for every pixel: the strip would never drag anything, and the
  // buttons would never be the system's. HTTRANSPARENT is how the view is
  // asked to put the question to this window instead, and only for those
  // parts: every other pixel stays the view's, which is what keeps Flutter's
  // own controls working — and what leaves the window's frame to the view to
  // take (below).
  if (message == WM_NCHITTEST) {
    if (that != nullptr) {
      const POINT point = ClientPointOf(hwnd, lparam);
      if (const std::optional<LRESULT> part = that->WindowPart(point)) {
        if (SizeCommand(*part) == std::nullopt) {
          return HTTRANSPARENT;
        }
      }
    }
    return HTCLIENT;
  }

  // A press on the window's frame. The view keeps those pixels (see above),
  // and the system sizes a window by a frame of its own to press: this one
  // has none (the app draws the window's whole top, see NonClientSize), so
  // the loop that sizes it is the window's to start — from the press, and at
  // the pointer, which is where the loop takes the window's edge from.
  if (message == WM_LBUTTONDOWN) {
    if (that != nullptr) {
      const POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      if (const std::optional<LRESULT> part = that->WindowPart(point)) {
        if (const std::optional<WPARAM> command = SizeCommand(*part)) {
          POINT at = point;
          ::ClientToScreen(hwnd, &at);
          ::ReleaseCapture();
          ::SendMessageW(::GetParent(hwnd), WM_SYSCOMMAND, *command,
                         MAKELPARAM(at.x, at.y));
          return 0;
        }
      }
    }
  }

  // The cursor over the frame is the system's to show, and it shows it for a
  // frame of its own that it can see; this is the frame to point at here.
  if (message == WM_SETCURSOR && LOWORD(lparam) == HTCLIENT) {
    if (that != nullptr) {
      POINT point = {};
      ::GetCursorPos(&point);
      ::ScreenToClient(hwnd, &point);
      if (const std::optional<LRESULT> part = that->WindowPart(point)) {
        if (const LPCWSTR cursor = CursorFor(*part)) {
          ::SetCursor(::LoadCursorW(nullptr, cursor));
          return TRUE;
        }
      }
    }
  }

  if (that == nullptr || that->view_proc_ == nullptr) {
    return ::DefWindowProcW(hwnd, message, wparam, lparam);
  }
  return ::CallWindowProcW(that->view_proc_, hwnd, message, wparam, lparam);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // What each part of the window is, and what it is around what the app
  // paints, are this window's own answers (the header is Flutter's; see
  // lib/workspace/window_header/), and they come before the engine, which
  // would otherwise have the window keep a frame and take the hit test.
  if (message == WM_NCCALCSIZE) {
    if (const std::optional<LRESULT> size = NonClientSize(wparam, lparam)) {
      return *size;
    }
  }
  if (message == WM_NCHITTEST) {
    POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
    ::ScreenToClient(hwnd, &point);
    if (const std::optional<LRESULT> part = WindowPart(point)) {
      return *part;
    }
  }

  // A press on a part of the window that is not the client (see WindowPart):
  // where it has a frame of its own to press, the system runs these itself,
  // and this window has none (see NonClientSize). The same commands are run
  // here — the move and the resizes as their modal loops, and the buttons as
  // the commands they stand for.
  if (message == WM_NCLBUTTONDOWN || message == WM_NCLBUTTONDBLCLK) {
    const LRESULT part = static_cast<LRESULT>(wparam);
    if (part == HTCLOSE) {
      ::PostMessageW(hwnd, WM_CLOSE, 0, 0);
      return 0;
    }
    // A double click on the strip is the system's own shortcut for
    // maximizing, and its other way round again.
    const std::optional<WPARAM> command =
        part == HTCAPTION && message == WM_NCLBUTTONDBLCLK
            ? std::optional<WPARAM>(::IsZoomed(hwnd) ? SC_RESTORE : SC_MAXIMIZE)
            : CommandForPress(hwnd, part);
    if (command.has_value()) {
      ::SendMessageW(hwnd, WM_SYSCOMMAND, *command, lparam);
      return 0;
    }
  }


  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    // The system hit-tests the window's own buttons, so Flutter hears
    // nothing of the pointer over them: this is how its header knows which
    // one to paint as hovered. Tracking is what makes the leave message come
    // once the pointer goes elsewhere.
    case WM_NCMOUSEMOVE: {
      if (window_channel_ == nullptr) {
        break;
      }
      window_channel_->ReportHover(static_cast<LRESULT>(wparam));
      TRACKMOUSEEVENT track = {};
      track.cbSize = sizeof(track);
      track.dwFlags = TME_LEAVE | TME_NONCLIENT;
      track.hwndTrack = hwnd;
      ::TrackMouseEvent(&track);
      break;
    }

    case WM_NCMOUSELEAVE:
      if (window_channel_ != nullptr) {
        window_channel_->ReportHover(HTNOWHERE);
      }
      break;

    case WM_SIZE:
      if (window_channel_ != nullptr) {
        window_channel_->ReportMaximized(
            wparam == static_cast<WPARAM>(SIZE_MAXIMIZED));
      }
      break;

    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

std::optional<LRESULT> FlutterWindow::WindowPart(POINT point) const {
  if (window_channel_ == nullptr) {
    return std::nullopt;
  }
  // The window's own buttons first: they sit in the header's top right,
  // where the corner would otherwise resize.
  if (const std::optional<LRESULT> button = window_channel_->ButtonAt(point)) {
    return *button;
  }
  if (const std::optional<LRESULT> edge = ResizeHitTest(point)) {
    return *edge;
  }
  // The controls Flutter kept in the header are Flutter's: the strip is the
  // window's only where they are not.
  if (window_channel_->IsHeaderControl(point)) {
    return std::nullopt;
  }
  if (window_channel_->IsInHeader(point)) {
    return HTCAPTION;
  }
  return std::nullopt;
}
