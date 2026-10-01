import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Closing the window quits, unless the menu bar icon is up: the close
  /// button only hides the window then, and AppKit counts a window ordered
  /// out as closed (see Attention.swift).
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return !(Attention.shared?.hidesOnClose ?? false)
  }

  /// A click on the Dock icon brings back the window the close button hid
  /// (see Attention.swift).
  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag, let window = mainFlutterWindow, !window.isMiniaturized {
      window.makeKeyAndOrderFront(nil)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
