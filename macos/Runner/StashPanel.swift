import Carbon
import Cocoa
import FlutterMacOS
import Vision

/// A window that is a view of the app's one engine: the app's own windows
/// (BaoWindow) and the stash's panel, which is not one of them.
protocol FlutterHostWindow: NSWindow {
  var viewId: Int64 { get }
}

extension BaoWindow: FlutterHostWindow {}

/// The stash's panel (see lib/stash/, docs/stash.md): a view of the app's
/// engine in a panel shown in front of every app, on every Space, without
/// bringing the app in front (an ordinary window's level, not kept above
/// the others once the user goes on in another app, unless pinned): the app the user was in stays the active one,
/// and has the keyboard back once the panel goes. Not in the Dock's or the
/// Window menu's lists. Made once, hidden, and shown again at once each
/// time the shortcut is pressed.
final class StashPanel: NSPanel, FlutterHostWindow {
  static let defaultSize = NSSize(width: 560, height: 420)
  static let minimumSize = NSSize(width: 380, height: 220)

  /// Where its place and size are kept (the user defaults'), for the next
  /// launch.
  private static let frameName = "BaoCodeStashPanel"

  /// The app's one panel, once made.
  private(set) static weak var current: StashPanel?

  /// Whether it has a place of its own yet (kept, or given once):
  /// centered on the screen until it does.
  private var placed = false

  private(set) var flutterViewController: FlutterViewController?
  private var channel: FlutterMethodChannel?
  private var drops: FileDropView?

  var viewId: Int64 { flutterViewController?.viewIdentifier ?? -1 }

  init(flutter: FlutterViewController) {
    super.init(
      contentRect: NSRect(origin: .zero, size: Self.defaultSize),
      styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    flutterViewController = flutter
    isReleasedWhenClosed = false
    isRestorable = false
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      standardWindowButton(button)?.isHidden = true
    }
    isMovableByWindowBackground = true
    level = .normal
    hidesOnDeactivate = false
    isFloatingPanel = false
    becomesKeyOnlyIfNeeded = false
    worksWhenModal = true
    isExcludedFromWindowsMenu = true
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    animationBehavior = .utilityWindow
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    appearance = NSAppearance(named: BaoWindow.keptDarkAppearance ? .darkAqua : .aqua)
    flutter.backgroundColor = .clear
    // The main window's material under it, as the conversation has it
    // there (AppColors.conversationSurface tints it).
    contentViewController = StashContent(flutter: flutter, size: Self.defaultSize)
    setContentSize(Self.defaultSize)
    contentMinSize = Self.minimumSize

    let messenger = flutter.engine.binaryMessenger
    let suffix = ".\(flutter.viewIdentifier)"
    let drops = FileDropView(channel: FlutterMethodChannel(
      name: "baocode/drop" + suffix, binaryMessenger: messenger))
    drops.frame = flutter.view.bounds
    drops.autoresizingMask = [.width, .height]
    flutter.view.addSubview(drops)
    self.drops = drops

    // Where the user left it, as big as they made it.
    placed = setFrameUsingName(Self.frameName)
    setFrameAutosaveName(Self.frameName)
    Self.current = self

    let channel = FlutterMethodChannel(name: "baocode/window" + suffix, binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      self.handle(call, result: result)
    }
  }

  /// Takes the keyboard without the app coming in front.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  /// Where it was left (moved or resized by the user, kept across
  /// launches); in the middle of the screen the mouse is on the first
  /// time, or when where it was is on no screen now.
  func present() {
    let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    if !placed || !onScreen {
      let mouse = NSEvent.mouseLocation
      let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
      if let visible = screen?.visibleFrame {
        let origin = NSPoint(
          x: visible.midX - frame.width / 2,
          y: max(visible.minY, min(visible.midY - frame.height / 2, visible.maxY - frame.height)))
        setFrameOrigin(origin)
        placed = true
      }
    }
    syncScale()
    // Light or dark as the color theme is now, as the app's windows are.
    appearance = NSAppearance(named: BaoWindow.keptDarkAppearance ? .darkAqua : .aqua)
    makeKeyAndOrderFront(nil)
    orderFrontRegardless()
  }

  /// ⌘W, ⌘S and ⌘N are the panel's (close, save, a new stash), ahead of
  /// the app's menu, whose commands go to its windows.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
    if flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
      let commands = ["w": "baocode.stash.close", "s": "baocode.stash.save", "n": "baocode.stash.new"]
      if let command = commands[key] {
        menuCommand(command)
        return true
      }
    }
    return super.performKeyEquivalent(with: event)
  }

  /// A command of the app's menu, or one of its own, for Flutter.
  func menuCommand(_ command: String) {
    channel?.invokeMethod("menuCommand", arguments: command)
  }

  /// Hidden; the app that was in front has the keyboard again, as it never
  /// lost being the active one.
  func dismiss() {
    orderOut(nil)
  }

  /// Escape, as a panel's: Flutter decides (it saves first).
  override func cancelOperation(_ sender: Any?) {
    menuCommand("baocode.stash.close")
  }

  private func syncScale() {
    guard let flutter = flutterViewController,
          flutter.responds(to: NSSelectorFromString("flutterView")),
          let view = flutter.value(forKey: "flutterView") as? NSView,
          let layer = view.layer
    else { return }
    let scale = backingScaleFactor
    guard layer.contentsScale != scale else { return }
    layer.contentsScale = scale
    view.viewDidChangeBackingProperties()
  }

  func tearDown() {
    channel?.setMethodCallHandler(nil)
    drops?.stop()
  }

  // The Edit menu's commands, as BaoWindow's.
  @objc func baocodeUndo(_ sender: Any?) { editCommand("undo") }
  @objc func baocodeRedo(_ sender: Any?) { editCommand("redo") }
  @objc func baocodeCut(_ sender: Any?) { editCommand("cut") }
  @objc func baocodeCopy(_ sender: Any?) { editCommand("copy") }
  @objc func baocodePaste(_ sender: Any?) { editCommand("paste") }
  @objc func baocodeSelectAll(_ sender: Any?) { editCommand("selectAll") }

  private func editCommand(_ command: String) {
    channel?.invokeMethod("editCommand", arguments: command)
  }

  /// What the panel's view asks of its window: the clipboard's pictures
  /// and files, files to pick, a context menu; the rest as BaoWindow
  /// answers it, where it applies to a panel.
  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "readPasteboardImages":
      result(BaoWindow.pasteboardImages())
    case "readPasteboardFiles":
      result(FileDropView.files(on: NSPasteboard.general))
    case "readImageFile":
      guard let path = call.arguments as? String else {
        result(nil)
        return
      }
      result(BaoWindow.image(at: URL(fileURLWithPath: path)))
    case "canPaste":
      result(NSPasteboard.general.canReadObject(
        forClasses: [NSString.self, NSURL.self, NSImage.self], options: nil))
    case "writePasteboardMarkdown":
      result(BaoWindow.writePasteboardMarkdown(call.arguments as? [String: Any] ?? [:]))
    case "readPasteboardMarkdown":
      result(BaoWindow.readPasteboardMarkdown())
    case "writePasteboardImage":
      guard let arguments = call.arguments as? [String: Any],
            let bytes = arguments["bytes"] as? FlutterStandardTypedData
      else {
        result(false)
        return
      }
      result(BaoWindow.writePasteboardImage(
        bytes.data, png: arguments["type"] as? String == "image/png"))
    case "pickFiles":
      let panel = NSOpenPanel()
      panel.canChooseFiles = true
      panel.canChooseDirectories = true
      panel.allowsMultipleSelection = true
      panel.beginSheetModal(for: self) { response in
        result(response == .OK ? panel.urls.map(FileDropView.entry) : [])
      }
    case "armFileDrag":
      let paths = (call.arguments as? [String: Any])?["paths"] as? [String]
      drops?.arm(paths, flutter: flutterViewController)
      result(drops != nil)
    case "disarmFileDrag":
      drops?.disarm()
      result(nil)
    case "startFileDrag":
      let paths = (call.arguments as? [String: Any])?["paths"] as? [String] ?? []
      result(drops?.drag(paths, flutter: flutterViewController) ?? false)
    case "revealInFinder":
      if let path = call.arguments as? String {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
      }
      result(nil)
    case "showContextMenu":
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
    case "dragWindow":
      // Its top bar, pressed: moved as a title bar moves its window.
      if let event = NSApp.currentEvent,
         [.leftMouseDown, .leftMouseDragged].contains(event.type) {
        performDrag(with: event)
      }
      result(nil)
    case "setAlwaysOnTop":
      // Pinned (its top bar's pin): over other apps' windows; else an
      // ordinary window's level, in front as it shows.
      level = (call.arguments as? Bool ?? false) ? .floating : .normal
      result(nil)
    case "windowRoom":
      result(["width": 0.0, "height": 0.0])
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// The panel's content: the system's sidebar material, blurring what is
/// behind it, under the Flutter view. Active
/// always: the panel takes the keyboard without the app coming in front.
private final class StashContent: NSViewController {
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
    material.state = .active
    // The window's own corners and edge, as the main window's: the
    // system's, which clips the content to them.
    addChild(flutter)
    flutter.view.frame = material.bounds
    flutter.view.autoresizingMask = [.width, .height]
    material.addSubview(flutter.view)
    view = material
  }
}

// MARK: - The shortcut

/// The shortcut that shows the panel from any app: a hot key of the
/// system's (Carbon's: no leave asked, unlike watching all keys).
final class StashHotkey {
  static let shared = StashHotkey()

  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?

  /// Called on the main thread as it is pressed.
  var onPress: (() -> Void)?

  /// Takes [spec] (`ctrl+shift+space`, `cmd+alt+n`…) in place of the one
  /// it had; none for an empty one. Whether the system gave it (another
  /// app may hold it).
  func register(_ spec: String) -> Bool {
    unregister()
    guard let (code, modifiers) = Self.parse(spec) else { return spec.isEmpty }
    installHandler()
    let id = EventHotKeyID(signature: OSType(0x4241_4F53), id: 1)  // 'BAOS'
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(code, modifiers, id, GetEventDispatcherTarget(), 0, &ref)
    guard status == noErr else { return false }
    hotKey = ref
    return true
  }

  func unregister() {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    hotKey = nil
  }

  private func installHandler() {
    guard handler == nil else { return }
    var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetEventDispatcherTarget(),
      { _, _, _ -> OSStatus in
        DispatchQueue.main.async { StashHotkey.shared.onPress?() }
        return noErr
      },
      1, &type, nil, &handler)
  }

  /// [spec]'s key and modifiers, as Carbon counts them; nil when it names
  /// no key, or no modifier (a key alone would be taken from every app).
  static func parse(_ spec: String) -> (UInt32, UInt32)? {
    var modifiers: UInt32 = 0
    var key: UInt32?
    for part in spec.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
      switch part {
      case "cmd", "command", "meta", "⌘": modifiers |= UInt32(cmdKey)
      case "ctrl", "control", "⌃": modifiers |= UInt32(controlKey)
      case "alt", "option", "opt", "⌥": modifiers |= UInt32(optionKey)
      case "shift", "⇧": modifiers |= UInt32(shiftKey)
      default: key = keyCodes[part]
      }
    }
    guard let key, modifiers != 0 else { return nil }
    return (key, modifiers)
  }

  private static let keyCodes: [String: UInt32] = {
    var codes: [String: UInt32] = [
      "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
      "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
      "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
      "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
      "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
      "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "`": 0x32,
      "space": 0x31, "enter": 0x24, "return": 0x24, "tab": 0x30, "escape": 0x35, "esc": 0x35,
      "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
      "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60, "f6": 0x61, "f7": 0x62,
      "f8": 0x64, "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
    ]
    codes["backquote"] = 0x32
    return codes
  }()
}

// MARK: - The channel

/// `baocode/stash` (see lib/stash/stash_host.dart): the shortcut, and the
/// text in pictures. Pressed, it tells whether that was in BaoCode itself
/// (`self`) and whether the panel was what the keyboard was in (`panel`).
final class StashChannel {
  static var shared: StashChannel?

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "baocode/stash", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result) ?? result(nil)
    }
    StashHotkey.shared.onPress = { [weak self] in self?.pressed() }
  }

  private func pressed() {
    // The panel, what the keyboard is in: it hides then, and is given the
    // keyboard back otherwise.
    let inApp = NSWorkspace.shared.frontmostApplication?.processIdentifier
      == ProcessInfo.processInfo.processIdentifier
    channel.invokeMethod("pressed", arguments: [
      "self": inApp,
      "panel": StashPanel.current?.isKeyWindow ?? false,
    ])
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setHotkey":
      result(StashHotkey.shared.register(call.arguments as? String ?? ""))
    case "recognizeText":
      guard let path = call.arguments as? String else {
        result(nil)
        return
      }
      Self.recognizeText(at: URL(fileURLWithPath: path), result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// The text in the picture at [url], read by Vision, in the
  /// background; nil when there is none or it cannot be read.
  private static func recognizeText(at url: URL, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .utility).async {
      guard let image = NSImage(contentsOf: url),
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
      else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP"]
      let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
      var text: String?
      do {
        try handler.perform([request])
        text = (request.results ?? [])
          .compactMap { $0.topCandidates(1).first?.string }
          .joined(separator: "\n")
      } catch {
        text = nil
      }
      DispatchQueue.main.async { result(text) }
    }
  }
}
