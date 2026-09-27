import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Opens wider than the 720 at which the sidebar docks beside the
  /// chat (below it, it is a drawer): room for the sidebar and the full
  /// chat column.
  private static let defaultSize = NSSize(width: 1024, height: 760)

  /// Still fits the title bar (traffic lights, title, Open button) and the
  /// composer's toolbar.
  private static let minimumSize = NSSize(width: 400, height: 540)

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Keep the traffic lights, but let Flutter own the title bar appearance.
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    isMovableByWindowBackground = true

    // Sized after the style: with the full-size content view, the content
    // is the whole window.
    var windowFrame = self.frame
    if let visible = (self.screen ?? NSScreen.main)?.visibleFrame {
      let content = NSSize(
        width: min(Self.defaultSize.width, visible.width),
        height: min(Self.defaultSize.height, visible.height - 40)
      )
      windowFrame.size = self.frameRect(
        forContentRect: NSRect(origin: .zero, size: content)
      ).size
      windowFrame.origin = NSPoint(
        x: visible.midX - windowFrame.width / 2,
        y: visible.midY - windowFrame.height / 2
      )
    }

    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.contentMinSize = Self.minimumSize

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Window controls the Flutter side asks for (see window_controls.dart).
    let channel = FlutterMethodChannel(
      name: "monad/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setAlwaysOnTop":
        // Floating: above other apps' windows, as a pinned window should be.
        self?.level = (call.arguments as? Bool ?? false) ? .floating : .normal
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
