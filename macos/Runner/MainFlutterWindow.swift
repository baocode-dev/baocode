import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

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
      case "pickDirectory":
        // A project folder to run agents in.
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Open"
        panel.message = "Choose a project folder"
        guard let window = self else {
          result(nil)
          return
        }
        panel.beginSheetModal(for: window) { response in
          result(response == .OK ? panel.url?.path : nil)
        }
      case "readPasteboardImages":
        result(Self.pasteboardImages())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  /// Types sent as they are; others are converted to PNG.
  private static let sentAsIs: [UTType: String] = [
    .png: "image/png", .jpeg: "image/jpeg", .gif: "image/gif", .webP: "image/webp",
  ]

  /// An image file as the Flutter side takes it: its bytes, media type and
  /// name; nil if it is not a readable image.
  private static func image(at url: URL) -> [String: Any]? {
    let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
    if let type, let mime = sentAsIs[type], let data = try? Data(contentsOf: url) {
      return ["bytes": FlutterStandardTypedData(bytes: data), "type": mime,
              "name": url.lastPathComponent]
    }
    guard let data = try? Data(contentsOf: url), let png = pngData(data) else { return nil }
    return ["bytes": FlutterStandardTypedData(bytes: png), "type": "image/png",
            "name": url.lastPathComponent]
  }

  private static func pngData(_ data: Data) -> Data? {
    NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
  }

  /// Images on the clipboard: copied image files, or, when there is no
  /// text to paste, copied image data (a screenshot, an image from a
  /// browser). Text wins over image data: apps put a picture of copied
  /// text (e.g. cells) beside it.
  private static func pasteboardImages() -> [[String: Any]] {
    let pasteboard = NSPasteboard.general
    let urls = pasteboard.readObjects(
      forClasses: [NSURL.self],
      options: [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: [UTType.image.identifier],
      ]
    ) as? [URL] ?? []
    let files = urls.compactMap(image(at:))
    if !files.isEmpty { return files }
    if pasteboard.string(forType: .string) != nil { return [] }
    if let png = pasteboard.data(forType: .png) {
      return [["bytes": FlutterStandardTypedData(bytes: png), "type": "image/png"]]
    }
    if let tiff = pasteboard.data(forType: .tiff), let png = pngData(tiff) {
      return [["bytes": FlutterStandardTypedData(bytes: png), "type": "image/png"]]
    }
    return []
  }
}
