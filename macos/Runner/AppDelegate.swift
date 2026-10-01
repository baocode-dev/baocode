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

  /// The app asks before it quits (see quit_confirmation.dart), in its
  /// window: brought up for it, from the Dock's Quit too.
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    bringWindowFront()
    return super.applicationShouldTerminate(sender)
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

  /// Files and folders the system asks the app to open: the `code`
  /// command's (`open -b`), Finder's Open With, those dropped on the Dock
  /// icon (see CFBundleDocumentTypes in Info.plist). At launch they come
  /// before Flutter is ready for them, and wait (see OpenRequests).
  override func application(_ application: NSApplication, open urls: [URL]) {
    let paths = urls.filter(\.isFileURL).map { $0.standardizedFileURL.path }
    if !paths.isEmpty {
      OpenRequests.shared.deliver(paths)
      bringWindowFront()
    }
    super.application(application, open: urls)
  }

  private func bringWindowFront() {
    if let window = mainFlutterWindow {
      if window.isMiniaturized { window.deminiaturize(nil) }
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }
}

/// The paths the system asks the app to open, for Flutter, over
/// `baocode/open` (see open_requests.dart): kept until Flutter takes them
/// (`takePending`, which also says it is ready for each as it comes), sent
/// as they come after that (`open`). The app's own, not the window's: the
/// system can ask before the window has its channel.
final class OpenRequests {
  static let shared = OpenRequests()

  private var pending: [String] = []
  private var ready = false
  private var channel: FlutterMethodChannel?

  /// Answers Flutter over [messenger]'s `baocode/open` (see
  /// MainFlutterWindow.swift).
  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "baocode/open", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "takePending":
        result(self.pending)
        self.pending = []
        self.ready = true
      case "stop":
        // Flutter stopped listening: kept again until it next asks.
        self.ready = false
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Hands [paths] to Flutter, or keeps them until it is ready.
  func deliver(_ paths: [String]) {
    if ready, let channel {
      channel.invokeMethod("open", arguments: paths)
    } else {
      pending.append(contentsOf: paths)
    }
  }
}
