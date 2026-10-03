import Cocoa
import FlutterMacOS

/// The app's windows for Flutter, over `baocode/windows` (see
/// lib/window/window_host.dart): the main one (the chat's, the engine's
/// implicit view) and the IDE's beside it, each a view of the one engine.
///
/// FlutterMacOS has the engine's multiple views, but no public way yet to
/// turn them on once the main window's view is there: `enableMultiView`
/// only works before. The flag it sets is set here instead (`start`), once
/// the main window's view is the engine's implicit one; each view added
/// after it gets the next id (1, 2…). The engine is told which view has the
/// keyboard as its own windows would tell it (`windowDidBecomeKey:`), for
/// Flutter's focus to follow the window in front.
///
/// Frames go as Flutter counts them: points, from the top left of the main
/// screen (the one with the menu bar).
final class AppWindows: NSObject {
  static var shared: AppWindows?

  private static let mainShownKey = "BaoCodeMainShownAtLaunch"

  /// Whether the main window shows at launch, as Flutter last said
  /// (`setMainShownAtLaunch`): not when only the IDE's windows come back.
  static var mainShownAtLaunch: Bool {
    UserDefaults.standard.object(forKey: mainShownKey) as? Bool ?? true
  }

  let engine: FlutterEngine
  let main: MainFlutterWindow
  private let channel: FlutterMethodChannel

  /// Whether Flutter opens windows of its own: it decides then what
  /// closing one does, and which shows at launch.
  private(set) var started = false

  /// The IDE's windows, by their views' ids.
  private var windows: [Int64: IdeWindow] = [:]

  /// What the menus list (`setWindowList`), and their labels.
  private var entries: [(viewId: Int64, title: String, edited: Bool)] = []
  private var labels: [String: String] = [:]

  /// The Window menu's Cycle Through Windows (⌘`).
  private var cycleItem: NSMenuItem?

  /// A frame changing is told once it has settled.
  private var frameTimers: [Int64: Timer] = [:]

  init(engine: FlutterEngine, main: MainFlutterWindow) {
    self.engine = engine
    self.main = main
    channel = FlutterMethodChannel(
      name: "baocode/windows", binaryMessenger: engine.binaryMessenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      self.handle(call, result: result)
    }
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(becameKey(_:)),
      name: NSWindow.didBecomeKeyNotification, object: nil)
    center.addObserver(
      self, selector: #selector(resignedKey(_:)),
      name: NSWindow.didResignKeyNotification, object: nil)
    for name in [
      NSWindow.didMoveNotification, NSWindow.didResizeNotification,
      NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification,
    ] {
      center.addObserver(self, selector: #selector(frameChanged(_:)), name: name, object: nil)
    }
    DispatchQueue.main.async { [weak self] in self?.installCycleItem() }
    // Hidden at launch, but Flutter never said what shows instead (it did
    // not start): the main window, rather than none.
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
      guard let self, !self.started, !self.main.isVisible else { return }
      self.show(self.main)
    }
  }

  // MARK: The channel

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      started = enableMultiView()
      if !started && !main.isVisible { show(main) }
      result(started)
    case "create":
      let arguments = call.arguments as? [String: Any] ?? [:]
      result(create(
        title: arguments["title"] as? String ?? "BaoCode",
        frame: arguments["frame"] as? [String: Any]))
    case "close":
      if let viewId = Self.id(call.arguments) { close(viewId) }
      result(nil)
    case "focus":
      if let viewId = Self.id(call.arguments), let window = window(viewId) {
        show(window)
      }
      result(nil)
    case "hide":
      if let viewId = Self.id(call.arguments) { window(viewId)?.orderOut(nil) }
      result(nil)
    case "setTitle":
      let arguments = call.arguments as? [String: Any] ?? [:]
      if let viewId = Self.id(arguments["viewId"]), let window = window(viewId) {
        window.title = arguments["title"] as? String ?? ""
        // The folder's icon beside it in the Window menu.
        window.representedURL = (arguments["path"] as? String).map {
          URL(fileURLWithPath: $0, isDirectory: true)
        }
      }
      result(nil)
    case "setEdited":
      let arguments = call.arguments as? [String: Any] ?? [:]
      if let viewId = Self.id(arguments["viewId"]) {
        window(viewId)?.isDocumentEdited = arguments["edited"] as? Bool ?? false
      }
      result(nil)
    case "frame":
      result(Self.id(call.arguments).flatMap(window).map(Self.frame(of:)))
    case "screens":
      result(NSScreen.screens.map { screen in
        var area = Self.flipped(screen.visibleFrame)
        area["id"] = Self.id(of: screen)
        return area
      })
    case "setWindowList":
      let arguments = call.arguments as? [String: Any] ?? [:]
      entries = (arguments["windows"] as? [[String: Any]] ?? []).compactMap { entry in
        guard let viewId = Self.id(entry["viewId"]) else { return nil }
        return (viewId, entry["title"] as? String ?? "", entry["edited"] as? Bool ?? false)
      }
      labels = arguments["labels"] as? [String: String] ?? [:]
      cycleItem?.title = labels["cycle"] ?? "Cycle Through Windows"
      Attention.shared?.refreshTray()
      result(nil)
    case "setMainShownAtLaunch":
      UserDefaults.standard.set(call.arguments as? Bool ?? true, forKey: Self.mainShownKey)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func id(_ value: Any?) -> Int64? {
    (value as? NSNumber)?.int64Value
  }

  /// Turns the engine's multiple views on (see above): false when this
  /// FlutterMacOS has not the flag looked for.
  private func enableMultiView() -> Bool {
    if started { return true }
    guard class_getInstanceVariable(FlutterEngine.self, "_multiViewEnabled") != nil,
          class_getInstanceVariable(FlutterEngine.self, "_nextViewIdentifier") != nil,
          engine.responds(to: NSSelectorFromString("removeViewController:")),
          engine.responds(to: NSSelectorFromString("windowDidBecomeKey:"))
    else { return false }
    engine.setValue(true, forKey: "multiViewEnabled")
    return engine.value(forKey: "multiViewEnabled") as? Bool ?? false
  }

  /// Tells the engine [viewId]'s window has the keyboard, or no longer
  /// (`windowDidBecomeKey:`, `windowDidResignKey:`).
  private func tellEngine(_ name: String, _ viewId: Int64) {
    let selector = NSSelectorFromString(name)
    guard engine.responds(to: selector) else { return }
    typealias Focus = @convention(c) (AnyObject, Selector, Int64) -> Void
    unsafeBitCast(engine.method(for: selector), to: Focus.self)(engine, selector, viewId)
  }

  // MARK: Windows

  private func window(_ viewId: Int64) -> BaoWindow? {
    viewId == 0 ? main : windows[viewId]
  }

  /// A window for a view of its own, shown in front: the view's id.
  private func create(title: String, frame: [String: Any]?) -> Int64? {
    guard started else { return nil }
    let flutter = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    let viewId = flutter.viewIdentifier
    let window = IdeWindow(
      contentRect: NSRect(origin: .zero, size: BaoWindow.defaultSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    // The app brings its windows back itself (windows.json).
    window.isRestorable = false
    window.setUp(flutter: flutter, suffix: ".\(viewId)", size: BaoWindow.defaultSize)
    window.title = title
    windows[viewId] = window
    var fullScreen = false
    if let frame, let rect = Self.unflipped(frame) {
      window.setFrame(rect, display: false)
      if frame["maximized"] as? Bool == true { window.zoom(nil) }
      fullScreen = frame["fullscreen"] as? Bool == true
    } else if let front = NSApp.keyWindow as? BaoWindow, front.isVisible,
              !front.styleMask.contains(.fullScreen) {
      // Down and right of the one in front, as a document window.
      window.setFrameTopLeftPoint(front.cascadeTopLeft(
        from: NSPoint(x: front.frame.minX, y: front.frame.maxY)))
    }
    show(window)
    if fullScreen { window.toggleFullScreen(nil) }
    return viewId
  }

  /// Closes [viewId]'s window, its view gone from the engine; the main
  /// one is only hidden.
  private func close(_ viewId: Int64) {
    if viewId == 0 {
      main.orderOut(nil)
      return
    }
    guard let window = windows.removeValue(forKey: viewId) else { return }
    frameTimers.removeValue(forKey: viewId)?.invalidate()
    window.tearDown()
    window.close()
    if let flutter = window.flutterViewController {
      _ = engine.perform(NSSelectorFromString("removeViewController:"), with: flutter)
    }
    window.contentViewController = nil
  }

  /// Brings [window] back, hidden or minimized, in front, the keyboard's.
  func show(_ window: NSWindow) {
    if window.isMiniaturized { window.deminiaturize(nil) }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  /// The window to ask in (quitting, a notification's sheet): the one in
  /// front, else the main one, shown.
  func bringFront() {
    let front = NSApp.keyWindow as? BaoWindow
      ?? NSApp.orderedWindows.first { $0 is BaoWindow && $0.isVisible } as? BaoWindow
      ?? main
    show(front)
  }

  /// Asks Flutter whether [window] may close (see BaoWindow).
  func closeRequested(_ window: BaoWindow) {
    channel.invokeMethod("closeRequested", arguments: window.viewId)
  }

  // MARK: The windows' events

  @objc private func becameKey(_ notification: Notification) {
    guard started, let window = notification.object as? BaoWindow else { return }
    tellEngine("windowDidBecomeKey:", window.viewId)
    channel.invokeMethod("focused", arguments: window.viewId)
    Attention.shared?.refreshTray()
  }

  @objc private func resignedKey(_ notification: Notification) {
    guard started, let window = notification.object as? BaoWindow else { return }
    tellEngine("windowDidResignKey:", window.viewId)
  }

  @objc private func frameChanged(_ notification: Notification) {
    guard started, let window = notification.object as? BaoWindow else { return }
    let viewId = window.viewId
    frameTimers[viewId]?.invalidate()
    frameTimers[viewId] = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) {
      [weak self, weak window] _ in
      guard let self, let window else { return }
      self.frameTimers.removeValue(forKey: viewId)
      var frame = Self.frame(of: window)
      frame["viewId"] = viewId
      self.channel.invokeMethod("frameChanged", arguments: frame)
    }
  }

  // MARK: Frames

  /// The main screen's height: AppKit counts from its bottom left.
  private static var mainScreenHeight: CGFloat {
    NSScreen.screens.first?.frame.height ?? 0
  }

  /// [rect] from the main screen's top left.
  private static func flipped(_ rect: NSRect) -> [String: Any] {
    [
      "x": Double(rect.minX),
      "y": Double(mainScreenHeight - rect.maxY),
      "width": Double(rect.width),
      "height": Double(rect.height),
    ]
  }

  /// A frame Flutter gave, as AppKit counts; nil without a size.
  private static func unflipped(_ frame: [String: Any]) -> NSRect? {
    guard let x = (frame["x"] as? NSNumber)?.doubleValue,
          let y = (frame["y"] as? NSNumber)?.doubleValue,
          let width = (frame["width"] as? NSNumber)?.doubleValue,
          let height = (frame["height"] as? NSNumber)?.doubleValue,
          width > 0, height > 0
    else { return nil }
    return NSRect(
      x: x, y: Double(mainScreenHeight) - y - height, width: width, height: height)
  }

  /// Where [window] is, and whether it is maximized (zoomed) or full
  /// screen.
  private static func frame(of window: NSWindow) -> [String: Any] {
    var frame = flipped(window.frame)
    frame["maximized"] = window.isZoomed
    frame["fullscreen"] = window.styleMask.contains(.fullScreen)
    if let screen = window.screen { frame["screen"] = id(of: screen) }
    return frame
  }

  /// A screen's id that stays while it is plugged in (its display's).
  private static func id(of screen: NSScreen) -> String {
    let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
    return (number as? NSNumber)?.stringValue ?? screen.localizedName
  }

  // MARK: Menus

  /// The Window menu's Cycle Through Windows (⌘`), before its list of
  /// windows, which AppKit keeps.
  private func installCycleItem() {
    guard let menu = NSApp.windowsMenu, cycleItem == nil else { return }
    let item = NSMenuItem(
      title: labels["cycle"] ?? "Cycle Through Windows",
      action: #selector(cycleWindows(_:)), keyEquivalent: "`")
    item.target = self
    let bringAll = menu.items.firstIndex { $0.action == #selector(NSApplication.arrangeInFront(_:)) }
    menu.insertItem(item, at: bringAll ?? menu.numberOfItems)
    cycleItem = item
  }

  /// The next of the app's windows shown, the one in front last.
  @objc private func cycleWindows(_ sender: Any?) {
    let shown = NSApp.orderedWindows.filter { $0 is BaoWindow && $0.isVisible && !$0.isMiniaturized }
    guard shown.count > 1, let next = shown.last else { return }
    show(next)
  }

  /// The windows as the menus list them, and the labels' in the app's
  /// language: the Dock's menu and the menu bar icon's.
  func menuItems(target: AnyObject, choose: Selector, newWindow: Selector) -> [NSMenuItem] {
    guard started else { return [] }
    var items: [NSMenuItem] = []
    let key = NSApp.keyWindow as? BaoWindow
    for entry in entries {
      let item = NSMenuItem(title: entry.title, action: choose, keyEquivalent: "")
      item.target = target
      item.representedObject = NSNumber(value: entry.viewId)
      if key?.viewId == entry.viewId { item.state = .on }
      items.append(item)
    }
    if !items.isEmpty { items.append(.separator()) }
    let new = NSMenuItem(
      title: labels["newWindow"] ?? "New Window", action: newWindow, keyEquivalent: "")
    new.target = target
    items.append(new)
    return items
  }

  /// The Dock's menu: the windows, then New Window.
  func dockMenu() -> NSMenu? {
    guard started else { return nil }
    let menu = NSMenu()
    for item in menuItems(
      target: self, choose: #selector(windowChosen(_:)), newWindow: #selector(newWindowChosen(_:)))
    {
      menu.addItem(item)
    }
    return menu
  }

  @objc func windowChosen(_ sender: NSMenuItem) {
    if let viewId = Self.id(sender.representedObject), let window = window(viewId) {
      show(window)
    }
  }

  @objc func newWindowChosen(_ sender: Any?) {
    NSApp.activate(ignoringOtherApps: true)
    channel.invokeMethod("newWindow", arguments: nil)
  }

  /// The Dock's icon clicked with no window shown: Flutter shows one.
  func reopen() {
    channel.invokeMethod("reopen", arguments: nil)
  }
}

/// A window the IDE opens: one folder's (or none's, its welcome page).
final class IdeWindow: BaoWindow {}
