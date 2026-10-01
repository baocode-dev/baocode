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
    // See-through, for the sidebar's material (see VibrantContent); light
    // or dark as the app's color theme is, whatever the system's appearance.
    // The last theme's until Flutter says (setAppearance).
    isOpaque = false
    backgroundColor = .clear
    appearance = NSAppearance(named: Self.keptDarkAppearance ? .darkAqua : .aqua)
    flutterViewController.backgroundColor = .clear

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

    self.contentViewController = VibrantContent(
      flutter: flutterViewController, size: windowFrame.size)
    self.setFrame(windowFrame, display: true)
    self.contentMinSize = Self.minimumSize

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Files dragged onto the window from other apps (see file_drop.dart).
    let drops = FileDropView(channel: FlutterMethodChannel(
      name: "baocode/drop",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    ))
    drops.frame = flutterViewController.view.frame
    drops.autoresizingMask = [.width, .height]
    flutterViewController.view.superview?.addSubview(
      drops, positioned: .above, relativeTo: flutterViewController.view)

    // Notifications, the Dock's badge and the menu bar icon (see
    // lib/notifications/).
    attention = Attention(
      messenger: flutterViewController.engine.binaryMessenger, window: self)

    // Window controls the Flutter side asks for (see window_controls.dart).
    let channel = FlutterMethodChannel(
      name: "baocode/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setAppearance":
        // The color theme's type: the material under the sidebar, the
        // traffic lights and system menus follow it. Kept for the next start.
        let dark = call.arguments as? Bool ?? true
        self?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        UserDefaults.standard.set(dark, forKey: Self.darkAppearanceKey)
        result(nil)
      case "setAlwaysOnTop":
        // Floating: above other apps' windows, as a pinned window should be.
        self?.level = (call.arguments as? Bool ?? false) ? .floating : .normal
        result(nil)
      case "windowRoom":
        // How much wider and taller the window can get on its screen (see
        // growWindow): none in full screen.
        guard let window = self, !window.styleMask.contains(.fullScreen),
              let visible = (window.screen ?? NSScreen.main)?.visibleFrame
        else {
          result(["width": 0.0, "height": 0.0])
          return
        }
        result([
          "width": max(0, visible.width - window.frame.width),
          "height": max(0, visible.height - window.frame.height),
        ])
      case "growWindow":
        // Room for conversations side by side (see chat_grid_view.dart).
        let arguments = call.arguments as? [String: Any]
        self?.grow(by: NSSize(
          width: arguments?["width"] as? Double ?? 0,
          height: arguments?["height"] as? Double ?? 0
        ))
        result(nil)
      case "handleTitleDoubleClick":
        // A double click on the empty part of the title bar Flutter draws
        // (see title_bar_double_click.dart): AppKit only handles its own.
        self?.titleBarDoubleClicked()
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
      case "readPasteboardFiles":
        // Files copied in Finder (or the IDE's explorer, see below).
        result(FileDropView.files(on: NSPasteboard.general))
      case "writePasteboardFiles":
        // As Finder copies files: pasted there they are copied, pasted in
        // the composer they are referred to.
        let urls = (call.arguments as? [String] ?? []).map {
          URL(fileURLWithPath: $0) as NSURL
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        result(!urls.isEmpty && pasteboard.writeObjects(urls))
      case "readImageFile":
        // An image file dropped or pasted, as the composer takes it.
        guard let path = call.arguments as? String else {
          result(nil)
          return
        }
        result(Self.image(at: URL(fileURLWithPath: path)))
      case "pickFiles":
        // Files and folders to put in the composer (Add Context…).
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard let window = self else {
          result([])
          return
        }
        panel.beginSheetModal(for: window) { response in
          result(response == .OK ? panel.urls.map(FileDropView.entry) : [])
        }
      case "writePasteboardImage":
        guard let arguments = call.arguments as? [String: Any],
              let bytes = arguments["bytes"] as? FlutterStandardTypedData
        else {
          result(false)
          return
        }
        result(Self.writePasteboardImage(
          bytes.data, png: arguments["type"] as? String == "image/png"))
      case "canPaste":
        let pasteboard = NSPasteboard.general
        result(pasteboard.canReadObject(
          forClasses: [NSString.self, NSURL.self, NSImage.self], options: nil))
      case "trashItem":
        // The IDE's Move to Trash (Finder's Put Back works on it).
        guard let path = call.arguments as? String else {
          result(false)
          return
        }
        do {
          try FileManager.default.trashItem(
            at: URL(fileURLWithPath: path), resultingItemURL: nil)
          result(true)
        } catch {
          result(FlutterError(
            code: "trash", message: error.localizedDescription, details: nil))
        }
      case "revealInFinder":
        // The IDE's Reveal in Finder: a Finder window with the item selected.
        if let path = call.arguments as? String {
          NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
        result(nil)
      case "showContextMenu":
        // A context menu of the system's own, where the user clicked;
        // answers the chosen item's id (nil for none) once it closes.
        guard let arguments = call.arguments as? [String: Any],
              let items = arguments["items"] as? [[String: Any]],
              let x = arguments["x"] as? Double, let y = arguments["y"] as? Double
        else {
          result(nil)
          return
        }
        let view = flutterViewController.view
        let point = NSPoint(x: x, y: view.isFlipped ? y : view.bounds.height - y)
        ContextMenu(items: items, answer: result).show(at: point, in: view)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  private var channel: FlutterMethodChannel?

  private var attention: Attention?

  /// The close button hides the window while the menu bar icon can bring
  /// it back (see Attention); without one, the window closes and the app
  /// quits.
  @objc func windowShouldClose(_ sender: NSWindow) -> Bool {
    if attention?.hidesOnClose ?? false {
      orderOut(sender)
      return false
    }
    return true
  }

  private static let darkAppearanceKey = "BaoCodeDarkAppearance"

  /// Whether the last color theme was dark; dark the first time.
  private static var keptDarkAppearance: Bool {
    UserDefaults.standard.object(forKey: darkAppearanceKey) as? Bool ?? true
  }

  /// Makes the window as much wider and taller, as far as its screen goes:
  /// its top left stays, unless the window would go past the screen's
  /// right or bottom edge, where it moves back onto it.
  private func grow(by extra: NSSize) {
    guard !styleMask.contains(.fullScreen) else { return }
    var frame = self.frame
    let visible = (screen ?? NSScreen.main)?.visibleFrame ?? frame
    let top = frame.maxY
    frame.size.width = min(frame.width + extra.width, max(frame.width, visible.width))
    frame.size.height = min(frame.height + extra.height, max(frame.height, visible.height))
    // AppKit's origin is the bottom left.
    frame.origin.y = top - frame.height
    if frame.maxX > visible.maxX {
      frame.origin.x = max(visible.minX, visible.maxX - frame.width)
    }
    if frame.minY < visible.minY {
      frame.origin.y = visible.minY
    }
    setFrame(frame, display: true, animate: true)
  }

  /// What System Settings' "Double-click a window's title bar to" says:
  /// fill, zoom (also when never set), minimize or nothing.
  ///
  /// VS Code 6a598d4a13031703d483d103c1d934a36ad27971 leaves this to its
  /// Electron (43, Chromium 150): -[NativeWidgetMacNSWindow sendEvent:] in
  /// components/remote_cocoa/app_shim/native_widget_mac_nswindow.mm, on the
  /// second click's mouse-up in a draggable region. As there, only
  /// AppleActionOnDoubleClick is read (not the older
  /// AppleMiniaturizeOnDoubleClick), and Fill is AppKit's private
  /// _zoomFill: (macOS 15), when it is there.
  private func titleBarDoubleClicked() {
    let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")
    let zoomFill = Selector(("_zoomFill:"))
    if action == "Fill" && responds(to: zoomFill) {
      _ = perform(zoomFill, with: nil)
    } else if action == nil || action == "Maximize" {
      performZoom(nil)
    } else if action == "Minimize" {
      performMiniaturize(nil)
    }
    // "None", or a value not known: nothing.
  }

  // The Edit menu's commands (see MainMenu.xib), for what has focus in
  // Flutter. The system's own (undo:, copy:, selectAll:…) would stop at the
  // engine's hidden text view, which edits nothing shown, or at nothing.
  // They come here too when a shortcut Flutter did not take matches them.

  @objc func baocodeUndo(_ sender: Any?) { editCommand("undo") }
  @objc func baocodeRedo(_ sender: Any?) { editCommand("redo") }
  @objc func baocodeCut(_ sender: Any?) { editCommand("cut") }
  @objc func baocodeCopy(_ sender: Any?) { editCommand("copy") }
  @objc func baocodePaste(_ sender: Any?) { editCommand("paste") }
  @objc func baocodeSelectAll(_ sender: Any?) { editCommand("selectAll") }

  private func editCommand(_ command: String) {
    channel?.invokeMethod("editCommand", arguments: command)
  }

  // The app menu's Preferences… (⌘,): the app's settings, which ⌘, opens
  // too while Flutter takes the key (it comes here when Flutter did not).
  @objc func baocodePreferences(_ sender: Any?) {
    channel?.invokeMethod("menuCommand", arguments: "workbench.action.openSettings")
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

  /// Puts an image's [data] on the clipboard, as PNG and TIFF: what apps
  /// paste a picture from. False when it is no image.
  private static func writePasteboardImage(_ data: Data, png: Bool) -> Bool {
    guard let tiff = NSImage(data: data)?.tiffRepresentation,
          let png = png ? data : pngData(tiff)
    else { return false }
    let item = NSPasteboardItem()
    item.setData(png, forType: .png)
    item.setData(tiff, forType: .tiff)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    return pasteboard.writeObjects([item])
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

/// The window's content: the system's sidebar material, blurring what is
/// behind the window, under the Flutter view. Flutter paints over it all
/// but the sidebar, which only tints it (see AppColors.sidebarSurface).
private class VibrantContent: NSViewController {
  private let flutter: FlutterViewController
  private let size: NSSize

  init(flutter: FlutterViewController, size: NSSize) {
    self.flutter = flutter
    self.size = size
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  override func loadView() {
    let material = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
    material.material = .sidebar
    material.blendingMode = .behindWindow
    // Dimmed while another window is in front, as the system's sidebars.
    material.state = .followsWindowActiveState
    addChild(flutter)
    flutter.view.frame = material.bounds
    flutter.view.autoresizingMask = [.width, .height]
    material.addSubview(flutter.view)
    view = material
  }
}

/// Takes the files other apps drag onto the window (Finder, Mail…) for
/// Flutter, which shows where they would go and puts them there (see
/// lib/chat/composer/file_drop.dart): over the Flutter view, it answers no
/// hit test, so clicks and the rest go on to Flutter; only drags stop here.
private class FileDropView: NSView {
  private let channel: FlutterMethodChannel

  /// What Flutter last said of the drag: whether what is under it takes it.
  /// It answers later than the system asks, so the system is told this.
  private var accepting = false

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init(frame: .zero)
    registerForDraggedTypes(
      [.fileURL]
        + NSFilePromiseReceiver.readableDraggedTypes.map {
          NSPasteboard.PasteboardType($0)
        })
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  /// Where the drag is, as Flutter counts: from the top left, in points.
  private func position(_ sender: NSDraggingInfo) -> [String: Any] {
    let point = convert(sender.draggingLocation, from: nil)
    return [
      "x": Double(point.x),
      "y": Double(isFlipped ? point.y : bounds.height - point.y),
    ]
  }

  private func update(_ arguments: [String: Any]) {
    channel.invokeMethod("dragUpdate", arguments: arguments) { [weak self] answer in
      self?.accepting = answer as? Bool ?? false
    }
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    accepting = false
    var arguments = position(sender)
    // None yet for files an app is still to write (a mail's attachment).
    arguments["files"] = Self.files(on: sender.draggingPasteboard)
    update(arguments)
    return accepting ? .copy : []
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    update(position(sender))
    return accepting ? .copy : []
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    accepting = false
    channel.invokeMethod("dragExit", arguments: nil)
  }

  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    accepting
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    accepting = false
    let at = position(sender)
    let pasteboard = sender.draggingPasteboard
    let files = Self.files(on: pasteboard)
    let promises = pasteboard.readObjects(
      forClasses: [NSFilePromiseReceiver.self], options: nil
    ) as? [NSFilePromiseReceiver] ?? []
    if !files.isEmpty || promises.isEmpty {
      drop(files, at: at)
      return true
    }
    // Files an app writes once they are let go: into a folder of their own.
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("baocode-drops", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(
      at: folder, withIntermediateDirectories: true)
    // One answer for each file promised; dropped once the last is in.
    var pending = promises.reduce(0) { $0 + max(1, $1.fileTypes.count) }
    var received: [URL] = []
    let lock = NSLock()
    let queue = OperationQueue()
    for promise in promises {
      promise.receivePromisedFiles(
        atDestination: folder, options: [:], operationQueue: queue
      ) { [weak self] url, error in
        lock.lock()
        if error == nil { received.append(url) }
        pending -= 1
        let done = pending == 0
        let files = received
        lock.unlock()
        if done {
          DispatchQueue.main.async { self?.drop(files.map(Self.entry), at: at) }
        }
      }
    }
    return true
  }

  private func drop(_ files: [[String: Any]], at position: [String: Any]) {
    var arguments = position
    arguments["files"] = files
    channel.invokeMethod("drop", arguments: arguments)
  }

  /// The files on [pasteboard], as Flutter takes them.
  static func files(on pasteboard: NSPasteboard) -> [[String: Any]] {
    let urls = pasteboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
    ) as? [URL] ?? []
    return urls.map(entry)
  }

  /// A file as Flutter takes it: its path, and whether it is a folder (not
  /// so a package, an app, which is one file to the user).
  static func entry(_ url: URL) -> [String: Any] {
    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
    let directory = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
    return ["path": url.path, "directory": directory]
  }
}

/// A menu of the items the Flutter side sends: `id`, `label`, `enabled`,
/// `key` (shown with ⌘), or `separator`. Answers the chosen item's id, or
/// nil, once.
private class ContextMenu: NSMenu {
  private var answer: FlutterResult?

  /// Itself, until it has answered: the chosen item's action can come
  /// after the menu has closed, and items hold their target weakly.
  private var keepAlive: ContextMenu?

  init(items: [[String: Any]], answer: @escaping FlutterResult) {
    self.answer = answer
    super.init(title: "")
    autoenablesItems = false
    for item in items {
      if item["separator"] as? Bool == true {
        addItem(.separator())
        continue
      }
      let menuItem = NSMenuItem(
        title: item["label"] as? String ?? "",
        action: #selector(choose(_:)),
        keyEquivalent: item["key"] as? String ?? ""
      )
      menuItem.keyEquivalentModifierMask = .command
      menuItem.target = self
      menuItem.representedObject = item["id"]
      menuItem.isEnabled = item["enabled"] as? Bool ?? true
      addItem(menuItem)
    }
  }

  required init(coder: NSCoder) {
    super.init(coder: coder)
  }

  func show(at point: NSPoint, in view: NSView) {
    keepAlive = self
    if popUp(positioning: nil, at: point, in: view) {
      // An item was chosen: its action answers, now or shortly.
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
        self?.finish(nil)
      }
    } else {
      finish(nil)
    }
  }

  @objc private func choose(_ sender: NSMenuItem) {
    finish(sender.representedObject as? String)
  }

  private func finish(_ id: String?) {
    answer?(id)
    answer = nil
    keepAlive = nil
  }
}
