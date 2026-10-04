# Windows

The app was first a macOS Flutter desktop app. This note is what Windows
does the same way, and where it differs.

## Layout

```
windows/
  runner/
    main.cpp                 window size, centre, minimum size
    flutter_window.cpp       hosts Flutter; wires baocode/window; the window's
                             parts: hit test, move, resize, its buttons
    window_channel.cpp       setAlwaysOnTop, pickDirectory, clipboard,
                             context menu, open (CreateProcess / ShellExecute)
    caption_areas.*          where Flutter's header and its controls are
    clipboard_images.cpp     CF_HDROP / CF_DIB → PNG for the composer
    context_menu.cpp         TrackPopupMenu for the composer's right click
    drop_target.cpp          IDropTarget: files dragged in from other apps
    win32_window.cpp         DPI-aware frame without a caption; WM_GETMINMAXINFO
lib/
  platform/app_paths.dart    home / app data / temp, by platform
  workspace/window_controls.dart
  workspace/window_header/   the strip Windows draws itself, over everything
  workspace/editor_launcher*.dart
  kernel/claude_code/        CLI find + start, config and temp dirs
```

## Same channel as macOS: `baocode/window`

| Method | Windows |
| --- | --- |
| `setAlwaysOnTop` | `SetWindowPos` TOPMOST / NOTOPMOST |
| `pickDirectory` | `IFileOpenDialog` with `FOS_PICKFOLDERS` |
| `canPaste` | text, HDROP, or DIB on the clipboard |
| `readPasteboardImages` | image files from HDROP; else DIB→PNG when there is no text |
| `readPasteboardFiles` | the paths in HDROP, each with whether it is a folder |
| `writePasteboardFiles` | HDROP + `Preferred DropEffect` = copy, as Explorer's Copy |
| `readImageFile` | an image file as the composer takes it (WIC → PNG for other formats) |
| `pickFiles` | `IFileOpenDialog` with `FOS_ALLOWMULTISELECT` |
| `showContextMenu` | system popup; shortcuts shown as Ctrl+… |
| `open` | an app (`code` / `cursor` / `wt`) found on PATH + PATHEXT: `CreateProcessW` with `CREATE_NO_WINDOW` (`.cmd` / `.bat` through `cmd.exe /d /s /c`, so no console flashes up); otherwise `ShellExecuteW` |

Files dragged onto the window from other apps come over a channel of their
own, `baocode/drop` (`dragUpdate` / `dragExit` / `drop`, see
`lib/chat/composer/file_drop.dart`): `drop_target.cpp` is registered on the
Flutter view with `RegisterDragDrop`, which is why `main.cpp` initializes
COM through `OleInitialize`. Flutter answers whether the composer is under
the pointer later than OLE asks, so `DragOver` tells OLE the last answer (it
is asked again while the drag rests).

Edit-menu bridging (`editCommand` / `baocodeSelectAll:` …) is **macOS only**.
Windows has no app menu bar for those; Flutter handles Ctrl+A/C/V itself
(`WindowControls.hasEditMenu`).

## Window chrome

Windows draws **no title bar of its own**: the app draws the strip at the top
of the window (`lib/workspace/window_header/`), and the window answers the
cursor's hit test for the parts that are its own
(`windows/runner/flutter_window.cpp`):

| Part of the window | Who answers | What happens |
| --- | --- | --- |
| the strip, between Flutter's controls | the window (`HTCAPTION`) | the system's own move loop: dragging, edge snapping, double click to maximize |
| Flutter's controls in it (toggle, menus, pin, editor) | Flutter (`HTCLIENT`) | its own widgets, as anywhere else |
| the three window buttons | the window (`HTMINBUTTON` / `HTMAXBUTTON` / `HTCLOSE`) | the system's hover, commands and Snap Layouts |
| the frame, on all four sides | the view (`WM_LBUTTONDOWN`) | the window's own sizing loop |

The Flutter view is a child window over the whole client area, and the system
asks *it* where the cursor is: it hands the parts above up to the window
(`HTTRANSPARENT`) and keeps every other pixel, which is what leaves Flutter's
own controls working.

The window's frame — its shadow, its rounded corners, the line along its edge
— is DWM's, asked for at creation (`windows/runner/win32_window.cpp`), since
the non-client area the system would draw it in is empty (the app paints the
whole window).

Default client size 1024×760, minimum 400×540 — same numbers as
`MainFlutterWindow.swift`.

## Paths and Claude Code

| Concern | Windows |
| --- | --- |
| Preferences | `%APPDATA%\baocode\preferences.json` |
| Claude config | `%USERPROFILE%\.claude` (or `BAOCODE_CLAUDE_PATH` / `CLAUDE_CONFIG_DIR`) |
| Task temp | `Directory.systemTemp` (not `/tmp`) |
| Finding `claude` | PATH (`claude.cmd` / `.exe`), `%APPDATA%\npm\claude.cmd`, … |
| Starting CLI | `Process.start(..., runInShell: true)` for `.cmd` / `.bat` shims |
| Login shell env | not used; the process already has the user's environment |

## Editors in the title bar

`Editor.availableEditors` drops Xcode on Windows. Labels: File Explorer,
Windows Terminal. Open starts the app found on the PATH without a console
(`wt -d <folder>` for Terminal), or goes through `ShellExecute` when it is
not found there.

## Fonts

`AppFonts.mono` is still Menlo; Windows falls back to Consolas /
Cascadia Mono via `fontFamilyFallback` (`AppFonts.windowsFallbacks`).

Chinese is the other half of that chain. Segoe UI (the theme's family on
Windows) and both monospaced families carry no Han glyphs, and where they run
out Skia picks DengXian, whose Han sit smaller on the body than the rest of
Windows draws them. `windowsFallbacks` therefore names **Microsoft YaHei UI**
— the same face Windows' own FontLink table points Segoe UI at — after the
monospaced families, so it answers for Han without taking the Latin in code
away from `mono`.

One difference that stays: Flutter draws with grayscale antialiasing, where
GDI apps use ClearType, so our text is a shade lighter than a native app's at
the same size.

## Build / run

Flutter SDK on this machine: `C:\flutter` (stable 3.47.5).

```
flutter pub get
flutter run -d windows
flutter build windows
```

MSVC Build Tools 2022 and a Windows 10 SDK are required (`flutter doctor`).

## Window Close Regression

The Windows view controller destroys its child HWND synchronously. Clear the
runner's controller reference before calling its destructor: child destruction
can re-enter the parent's message handler, which must not forward messages to
a controller whose view is already being reset. Secondary views are closed from
the Win32 message loop, outside Flutter's method-channel callback; the channel
reply is sent after removal completes.

Run the real embedder regression (temporary app data, five IDE/agent cycles and
quit cleanup):

```
flutter run -d windows -t tool/windows_close_smoke.dart
```

For clicking the IDE's close button manually while the agent remains open:

```
flutter run -d windows -t tool/windows_close_smoke.dart --dart-define=WINDOW_SMOKE_MANUAL=true
```

The watchdog writes and flushes its text report before attempting a minidump,
because an in-process dump can itself block. It continues watching after the
main HWND becomes invalid, until engine teardown and the message loop finish.
