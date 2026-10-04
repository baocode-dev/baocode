import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

/// What each of the app's windows is: the main one (the chat's, from
/// MainMenu.xib, the engine's implicit view) and those the IDE opens beside
/// it (see AppWindows.swift), each a view of the one engine. A see-through
/// title bar over Flutter's own, the sidebar's material under it, files
/// dragged onto it, and the window controls Flutter asks for over its
/// channel: `baocode/window` (the main one's) or `baocode/window.<viewId>`.
class BaoWindow: NSWindow {
  /// Opens wider than the 720 at which the sidebar docks beside the
  /// chat (below it, it is a drawer): room for the sidebar and the full
  /// chat column.
  static let defaultSize = NSSize(width: 1024, height: 760)

  /// Still fits the title bar (traffic lights, title, Open button) and the
  /// composer's toolbar.
  static let minimumSize = NSSize(width: 400, height: 540)

  private(set) var flutterViewController: FlutterViewController?

  private(set) var channel: FlutterMethodChannel?

  /// The window's view, as Flutter counts them; the main one's is 0.
  var viewId: Int64 { flutterViewController?.viewIdentifier ?? 0 }

  /// Sets the window up around [flutter]: its style, the material under
  /// the Flutter view, the drop view and the channels, named with
  /// [suffix] (none for the main window's). Sized [size], centered on its
  /// screen.
  func setUp(flutter flutterViewController: FlutterViewController, suffix: String, size: NSSize) {
    self.flutterViewController = flutterViewController
    // Keep the traffic lights, but let Flutter own the title bar appearance.
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    isMovableByWindowBackground = true
    // One window a folder: no system tabs (the IDE has its own).
    tabbingMode = .disallowed
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
        width: min(size.width, visible.width),
        height: min(size.height, visible.height - 40)
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

    let messenger = flutterViewController.engine.binaryMessenger

    // Files dragged onto the window from other apps (see file_drop.dart).
    let drops = FileDropView(channel: FlutterMethodChannel(
      name: "baocode/drop" + suffix, binaryMessenger: messenger))
    drops.frame = flutterViewController.view.frame
    drops.autoresizingMask = [.width, .height]
    flutterViewController.view.superview?.addSubview(
      drops, positioned: .above, relativeTo: flutterViewController.view)
    self.drops = drops

    // Window controls the Flutter side asks for (see window_controls.dart).
    let channel = FlutterMethodChannel(
      name: "baocode/window" + suffix, binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      self.handle(call, result: result)
    }
  }

  private var drops: FileDropView?

  /// Lets go of the channels (the window is gone).
  func tearDown() {
    channel?.setMethodCallHandler(nil)
    drops?.stop()
  }

  /// The window controls Flutter asks this window for.
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setAlwaysOnTop":
      // Floating: above other apps' windows, as a pinned window should be.
      level = (call.arguments as? Bool ?? false) ? .floating : .normal
      result(nil)
    case "windowRoom":
      // How much wider and taller the window can get on its screen (see
      // growWindow): none in full screen.
      guard !styleMask.contains(.fullScreen),
            let visible = (screen ?? NSScreen.main)?.visibleFrame
      else {
        result(["width": 0.0, "height": 0.0])
        return
      }
      result([
        "width": max(0, visible.width - frame.width),
        "height": max(0, visible.height - frame.height),
      ])
    case "growWindow":
      // Room for conversations side by side (see chat_grid_view.dart).
      let arguments = call.arguments as? [String: Any]
      grow(by: NSSize(
        width: arguments?["width"] as? Double ?? 0,
        height: arguments?["height"] as? Double ?? 0
      ))
      result(nil)
    case "handleTitleDoubleClick":
      // A double click on the empty part of the title bar Flutter draws
      // (see title_bar_double_click.dart): AppKit only handles its own.
      titleBarDoubleClicked()
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
      panel.beginSheetModal(for: self) { response in
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
      panel.beginSheetModal(for: self) { response in
        result(response == .OK ? panel.urls.map(FileDropView.entry) : [])
      }
    case "pickOpenFiles":
      // Files for the IDE to open (Open File…), in the folder given.
      let arguments = call.arguments as? [String: Any]
      let panel = NSOpenPanel()
      panel.canChooseFiles = true
      panel.canChooseDirectories = false
      panel.allowsMultipleSelection = arguments?["multiple"] as? Bool ?? true
      if let directory = arguments?["directory"] as? String {
        panel.directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
      }
      panel.beginSheetModal(for: self) { response in
        result(response == .OK ? panel.urls.map(\.path) : [])
      }
    case "pickSaveFile":
      // Where the IDE saves a file (Save As…, an untitled one's Save):
      // the panel asks itself before replacing one.
      let arguments = call.arguments as? [String: Any]
      let panel = NSSavePanel()
      panel.canCreateDirectories = true
      if let directory = arguments?["directory"] as? String {
        panel.directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
      }
      if let name = arguments?["name"] as? String {
        panel.nameFieldStringValue = name
      }
      panel.beginSheetModal(for: self) { response in
        result(response == .OK ? panel.url?.path : nil)
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
            let x = arguments["x"] as? Double, let y = arguments["y"] as? Double,
            let view = flutterViewController?.view
      else {
        result(nil)
        return
      }
      let point = NSPoint(x: x, y: view.isFlipped ? y : view.bounds.height - y)
      ContextMenu(items: items, answer: result).show(at: point, in: view)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static let darkAppearanceKey = "BaoCodeDarkAppearance"

  /// Whether the last color theme was dark; dark the first time.
  static var keptDarkAppearance: Bool {
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

  /// The close button, ⌘W from the menu, the Dock's or Mission Control's
  /// Close: with windows of the app's own, the app decides (unsaved files,
  /// terminals at work) and closes it itself (see AppWindows.swift).
  @objc func windowShouldClose(_ sender: NSWindow) -> Bool {
    if let windows = AppWindows.shared, windows.started {
      windows.closeRequested(self)
      return false
    }
    return true
  }

  // The Edit menu's commands (see MainMenu.xib), for what has focus in
  // Flutter. The system's own (undo:, copy:, selectAll:…) would stop at the
  // engine's hidden text view, which edits nothing shown, or at nothing.
  // They come here too when a shortcut Flutter did not take matches them:
  // to the key window, whose channel takes them.

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
    menuCommand("workbench.action.openSettings")
  }

  /// Runs a workbench command in this window (see
  /// WindowControls.onMenuCommand).
  func menuCommand(_ command: String) {
    channel?.invokeMethod("menuCommand", arguments: command)
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

/// The main window: the chat's, the engine's implicit view (MainMenu.xib).
/// It also answers for the app what is the app's, not a window's: the color
/// theme's appearance, the File menu.
class MainFlutterWindow: BaoWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    setUp(flutter: flutterViewController, suffix: "", size: Self.defaultSize)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let messenger = flutterViewController.engine.binaryMessenger

    // Notifications, the Dock's badge and the menu bar icon (see
    // lib/notifications/).
    attention = Attention(messenger: messenger, window: self)

    // Paths the system asks the app to open (see AppDelegate.swift).
    OpenRequests.shared.attach(to: messenger)

    // The IDE's windows, views of this one's engine (see AppWindows.swift).
    // Shown or not at launch as the app last said: the IDE's windows
    // alone, it stays hidden (Flutter shows it if it is to after all).
    AppWindows.shared = AppWindows(engine: flutterViewController.engine, main: self)
    holdingBack = !AppWindows.mainShownAtLaunch
    if holdingBack {
      DispatchQueue.main.async { [weak self] in self?.holdingBack = false }
    }

    // The menu bar's File menu, once the nib has made the menu bar (it
    // has none of its own; see FileMenu).
    let fileMenu = FileMenu()
    self.fileMenu = fileMenu
    DispatchQueue.main.async {
      if let mainMenu = NSApp.mainMenu { fileMenu.install(in: mainMenu) }
    }

    super.awakeFromNib()
  }

  override func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setAppearance":
      // The color theme's type: the material under the sidebar, the
      // traffic lights and system menus follow it, in every window. Kept
      // for the next start.
      let dark = call.arguments as? Bool ?? true
      UserDefaults.standard.set(dark, forKey: Self.darkAppearanceKey)
      for window in NSApp.windows where window is BaoWindow {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      }
      result(nil)
    case "setFileMenuTitles":
      fileMenu?.setTitles(call.arguments as? [String: String] ?? [:])
      result(nil)
    case "setRecentItems":
      fileMenu?.setRecent(call.arguments as? [String] ?? [])
      result(nil)
    default:
      super.handle(call, result: result)
    }
  }

  private var fileMenu: FileMenu?

  private var attention: Attention?

  /// Kept out of sight while the nib shows it at launch, when the app
  /// last said so (setMainShownAtLaunch).
  private var holdingBack = false

  override func makeKeyAndOrderFront(_ sender: Any?) {
    if holdingBack { return }
    super.makeKeyAndOrderFront(sender)
  }

  override func orderFront(_ sender: Any?) {
    if holdingBack { return }
    super.orderFront(sender)
  }

  /// The close button hides the window while the menu bar icon can bring
  /// it back (see Attention); without one, it quits as ⌘Q does, asking
  /// first: the window is the app's only one, and closed it would quit
  /// anyway, past the question. With the IDE's windows beside it, the app
  /// decides (see BaoWindow).
  override func windowShouldClose(_ sender: NSWindow) -> Bool {
    if AppWindows.shared?.started ?? false {
      return super.windowShouldClose(sender)
    }
    if attention?.hidesOnClose ?? false {
      orderOut(sender)
      return false
    }
    NSApp.terminate(sender)
    return false
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

  /// Takes no more drags (its window is gone).
  func stop() { unregisterDraggedTypes() }

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

/// The menu bar's File menu, which MainMenu.xib has none of: its items
/// are the workbench's commands, sent to Flutter as the app menu's
/// Preferences… is (`menuCommand`, see WindowControls.onMenuCommand), for
/// the window in front (the main one's, when none of the app's is). None
/// has a key equivalent: Flutter takes the keys (⌘O, ⌘S…) itself, and one
/// here would have them first. Titled in English until Flutter names them
/// in the app's language (`setFileMenuTitles`).
///
/// Open Recent lists what Flutter says (`setRecentItems`); one picked is
/// opened as a path the system asks the app to open (see OpenRequests), as
/// `code <path>` would.
private class FileMenu: NSObject {
  private let menu = NSMenu(title: "File")
  private let recentMenu = NSMenu(title: "Open Recent")
  private var titles: [String: String] = [
    "file": "File",
    "newUntitledFile": "New Text File",
    "openFile": "Open File…",
    "openFolder": "Open Folder…",
    "openRecent": "Open Recent",
    "save": "Save",
    "saveAs": "Save As…",
    "closeFolder": "Close Folder",
    "newWindow": "New Window",
    "closeWindow": "Close Window",
    "clearRecent": "Clear Recently Opened",
    "more": "More…",
    "checkForUpdates": "Check for Updates…",
  ]
  private var recent: [String] = []

  /// The menu's items: the key of each one's title and the command it
  /// runs (Open Recent's is its submenu); an empty key is a separator.
  private let layout: [(key: String, command: String)] = [
    ("newUntitledFile", "workbench.action.files.newUntitledFile"),
    ("newWindow", "workbench.action.newWindow"),
    ("", ""),
    ("openFile", "workbench.action.files.openFile"),
    ("openFolder", "workbench.action.files.openFolder"),
    ("openRecent", ""),
    ("", ""),
    ("save", "workbench.action.files.save"),
    ("saveAs", "workbench.action.files.saveAs"),
    ("", ""),
    ("closeFolder", "workbench.action.closeFolder"),
    ("closeWindow", "workbench.action.closeWindow"),
  ]

  override init() {
    super.init()
    recentMenu.autoenablesItems = false
  }

  /// The app menu's Check for Updates…, under About (see lib/update/).
  private let updatesItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

  /// Puts the menu after the app menu, before Edit; and Check for
  /// Updates… in the app menu.
  func install(in mainMenu: NSMenu) {
    let item = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
    item.submenu = menu
    mainMenu.insertItem(item, at: min(1, mainMenu.numberOfItems))
    if let appMenu = mainMenu.items.first?.submenu {
      updatesItem.action = #selector(runCommand(_:))
      updatesItem.target = self
      updatesItem.representedObject = "update.checkForUpdate"
      appMenu.insertItem(updatesItem, at: min(1, appMenu.numberOfItems))
    }
    build()
  }

  func setTitles(_ titles: [String: String]) {
    self.titles.merge(titles) { _, new in new }
    build()
  }

  func setRecent(_ paths: [String]) {
    recent = paths
    buildRecent()
  }

  private func title(_ key: String) -> String { titles[key] ?? key }

  private func build() {
    updatesItem.title = title("checkForUpdates")
    menu.title = title("file")
    menu.supermenu?.items.first(where: { $0.submenu === menu })?.title = title("file")
    menu.removeAllItems()
    for (key, command) in layout {
      if key.isEmpty {
        menu.addItem(.separator())
        continue
      }
      let item = NSMenuItem(title: title(key), action: nil, keyEquivalent: "")
      if key == "openRecent" {
        recentMenu.title = title(key)
        item.submenu = recentMenu
      } else {
        item.action = #selector(runCommand(_:))
        item.target = self
        item.representedObject = command
      }
      menu.addItem(item)
    }
    buildRecent()
  }

  private func buildRecent() {
    recentMenu.removeAllItems()
    let home = NSHomeDirectory()
    for path in recent {
      let shown = path == home || path.hasPrefix(home + "/")
        ? "~" + path.dropFirst(home.count) : path
      let item = NSMenuItem(title: shown, action: #selector(openRecent(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = path
      recentMenu.addItem(item)
    }
    if !recent.isEmpty { recentMenu.addItem(.separator()) }
    let more = NSMenuItem(
      title: title("more"), action: #selector(runCommand(_:)), keyEquivalent: "")
    more.target = self
    more.representedObject = "workbench.action.openRecent"
    recentMenu.addItem(more)
    recentMenu.addItem(.separator())
    let clear = NSMenuItem(
      title: title("clearRecent"), action: #selector(runCommand(_:)), keyEquivalent: "")
    clear.target = self
    clear.representedObject = "workbench.action.clearRecentlyOpened"
    clear.isEnabled = !recent.isEmpty
    recentMenu.addItem(clear)
  }

  @objc private func runCommand(_ sender: NSMenuItem) {
    guard let command = sender.representedObject as? String else { return }
    let window = NSApp.keyWindow as? BaoWindow
      ?? NSApp.mainWindow as? BaoWindow
      ?? AppWindows.shared?.main
    window?.menuCommand(command)
  }

  @objc private func openRecent(_ sender: NSMenuItem) {
    guard let path = sender.representedObject as? String else { return }
    OpenRequests.shared.deliver([path])
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
