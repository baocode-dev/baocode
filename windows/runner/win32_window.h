#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <optional>
#include <string>

// A class abstraction for a high DPI-aware Win32 Window. Intended to be
// inherited from by classes that wish to specialize with custom
// rendering and input handling
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  // The window's style: an ordinary resizable window, minus the caption —
  // the app draws the header itself (see lib/workspace/window_header/), and
  // a window with a caption keeps one drawn for it over the top of the
  // client, whatever the client rectangle says.
  //
  // What is left is what the header needs from the system: the resize border
  // (WS_THICKFRAME, which also keeps the shadow and the rounded corners), the
  // system menu, and the two buttons' commands.
  static constexpr DWORD kStyle = WS_OVERLAPPEDWINDOW & ~WS_CAPTION;

  Win32Window();
  virtual ~Win32Window();

  // Creates a win32 window with |title| that is positioned and sized using
  // |origin| and |size|. New windows are created on the default monitor. Window
  // sizes are specified to the OS in physical pixels, hence to ensure a
  // consistent size this function will scale the inputted width and height as
  // as appropriate for the default monitor. The window is invisible until
  // |Show| is called. Returns true if the window was created successfully.
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // Show the current window. Returns true if the window was successfully shown.
  bool Show();

  // Release OS resources associated with window.
  void Destroy();

  // Inserts |content| into the window tree.
  void SetChildContent(HWND content);

  // Returns the backing Window handle to enable clients to set icon and other
  // window properties. Returns nullptr if the window has been destroyed.
  HWND GetHandle();

  // If true, closing this window will quit the application.
  void SetQuitOnClose(bool quit_on_close);

  // The smallest the client area may be, in logical pixels: the window's
  // frame and its dpi at the time are added to it. Zero means none.
  void SetMinimumSize(const Size& size);

  // Return a RECT representing the bounds of the current client area.
  RECT GetClientArea();

 protected:
  // Processes and route salient window messages for mouse handling,
  // size change and DPI. Delegates handling of these to member overloads that
  // inheriting classes can handle.
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // Called when CreateAndShow is called, allowing subclass window-related
  // setup. Subclasses should return false if setup fails.
  virtual bool OnCreate();

  // Called when Destroy is called.
  virtual void OnDestroy();

  // What the window answers with when |point|, in client pixels, is on its
  // resize border; nullopt when it is not, or the window is maximized (where
  // the system drags it back down by the header instead).
  //
  // The border is the system's at the left, right and bottom, outside the
  // client (see NonClientSize); at the top there is none, the header being
  // the app's, so a strip of the client as tall as the border stands in.
  std::optional<LRESULT> ResizeHitTest(const POINT& point) const;

  // The client rectangle for a window that draws its own caption: the window
  // less the system's resize border at the left, right and bottom (invisible,
  // it is what those edges are grabbed by, outside the content), up to its
  // top; the monitor's work area while maximized (Windows sizes a maximized
  // window to cover the monitor, and that is what keeps the content off the
  // taskbar); empty while minimized.
  //
  // Answered before the engine, which would otherwise have the window keep a
  // frame — and draw a caption over the top of the client, whatever the
  // client rectangle says.
  std::optional<LRESULT> NonClientSize(WPARAM wparam, LPARAM lparam) const;

  // Retrieves a class instance pointer for |window|, of a window it made (a
  // subclass handling a child window's messages this way finds the window
  // those messages are about).
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

 private:
  friend class WindowClassRegistrar;

  // OS callback called by message pump. Handles the WM_NCCREATE message which
  // is passed when the non-client area is being created and enables automatic
  // non-client DPI scaling so that the non-client area automatically
  // responds to changes in DPI. All other messages are handled by
  // MessageHandler.
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // Update the window frame's theme to match the system theme.
  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;

  // Client minimum, in logical pixels; see SetMinimumSize.
  Size minimum_size_ = Size(0, 0);

  // How wide the system's resize border is at the window's dpi: kept at the
  // left, right and bottom (see NonClientSize), and inside the client at the
  // top, where the app draws the header.
  SIZE ResizeBorder() const;

  // window handle for top level window.
  HWND window_handle_ = nullptr;

  // window handle for hosted content.
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
