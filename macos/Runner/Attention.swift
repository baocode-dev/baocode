import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers
import UserNotifications

/// What tells the user an agent wants them while they look elsewhere (see
/// lib/notifications/): the system's notifications, a sound, the Dock
/// icon's badge and bounce, and the menu bar icon, whose menu brings the
/// window — or an agent — back. Over `baocode/attention`.
final class Attention: NSObject, UNUserNotificationCenterDelegate {
  /// The window's, for the app delegate to ask (see hidesOnClose).
  private(set) static weak var shared: Attention?

  private let channel: FlutterMethodChannel
  private weak var window: NSWindow?

  /// The menu bar icon, while there is one (the `tray.enabled` setting).
  private var statusItem: NSStatusItem?

  /// The sound playing, kept until it is done: NSSound stops when let go.
  private var sound: NSSound?

  /// Whether notifications were asked leave for, this run.
  private var authorizationAsked = false

  init(messenger: FlutterBinaryMessenger, window: NSWindow) {
    channel = FlutterMethodChannel(name: "baocode/attention", binaryMessenger: messenger)
    self.window = window
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    UNUserNotificationCenter.current().delegate = self
    Attention.shared = self
  }

  /// The close button hides the window while the menu bar icon can bring it
  /// back; without one, closing it quits.
  var hidesOnClose: Bool { statusItem != nil }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "notify":
      notify(
        id: arguments?["id"] as? String ?? "",
        title: arguments?["title"] as? String ?? "",
        body: arguments?["body"] as? String ?? "")
      result(nil)
    case "playSound":
      play(
        path: arguments?["path"] as? String,
        bytes: (arguments?["bytes"] as? FlutterStandardTypedData)?.data)
      result(nil)
    case "requestAttention":
      // A bounce of the Dock icon, once; nothing while the app is in front.
      NSApp.requestUserAttention(.informationalRequest)
      result(nil)
    case "setBadge":
      let count = call.arguments as? Int ?? 0
      NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil
      result(nil)
    case "setTray":
      setTray(arguments)
      result(nil)
    case "pickSound":
      pickSound(result: result)
    case "quit":
      quitChosen()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Notifications

  private func notify(id: String, title: String, body: String) {
    let center = UNUserNotificationCenter.current()
    let post = {
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.threadIdentifier = id
      content.userInfo = ["thread": id]
      // Silent: the app plays the sound the user picked itself.
      content.sound = nil
      // One at a time for each agent: its newer news takes the place of
      // the older.
      let request = UNNotificationRequest(
        identifier: "agent.\(id)", content: content, trigger: nil)
      center.add(request)
    }
    if authorizationAsked {
      post()
      return
    }
    authorizationAsked = true
    center.requestAuthorization(options: [.alert]) { granted, _ in
      if granted { DispatchQueue.main.async(execute: post) }
    }
  }

  /// Shown in front of the app too: it only notifies then when the agent
  /// is not the one in view (or the user wants it always).
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list])
  }

  /// A click on one: the window, on the agent it is about.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let id = response.notification.request.content.userInfo["thread"] as? String
    open(id)
    completionHandler()
  }

  // MARK: Sound

  private func play(path: String?, bytes: Data?) {
    sound?.stop()
    if let bytes {
      sound = NSSound(data: bytes)
    } else if let path {
      sound = NSSound(contentsOf: URL(fileURLWithPath: path), byReference: true)
    } else {
      sound = nil
    }
    sound?.play()
  }

  /// A sound file of the user's for the notifications.
  private func pickSound(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.audio]
    let answer = { (response: NSApplication.ModalResponse) in
      result(response == .OK ? panel.url?.path : nil)
    }
    if let window, window.isVisible {
      panel.beginSheetModal(for: window, completionHandler: answer)
    } else {
      answer(panel.runModal())
    }
  }

  // MARK: Window

  /// Brings the window back, hidden or minimized, in front.
  func showWindow() {
    guard let window else { return }
    if window.isMiniaturized { window.deminiaturize(nil) }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  /// The window, on the agent [id] when there is one.
  private func open(_ id: String?) {
    showWindow()
    channel.invokeMethod("open", arguments: id)
  }

  // MARK: Menu bar

  /// The menu bar icon and its menu, as the Flutter side describes them;
  /// nil for none.
  private func setTray(_ state: [String: Any]?) {
    guard let state else {
      if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
      statusItem = nil
      return
    }
    let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem = item
    let dot = state["dot"] as? Bool ?? false
    item.button?.image = Self.trayImage(dot: dot)
    item.button?.toolTip = state["tooltip"] as? String
    item.menu = menu(state)
  }

  private func menu(_ state: [String: Any]) -> NSMenu {
    let labels = state["labels"] as? [String: String] ?? [:]
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.addItem(action(labels["show"] ?? "Show", #selector(showChosen)))
    let waiting = state["waiting"] as? [[String: Any]] ?? []
    if !waiting.isEmpty {
      menu.addItem(.separator())
      let header = NSMenuItem(title: labels["waiting"] ?? "", action: nil, keyEquivalent: "")
      header.isEnabled = false
      menu.addItem(header)
      for agent in waiting {
        let item = action(agent["title"] as? String ?? "", #selector(agentChosen(_:)))
        item.representedObject = agent["id"]
        item.indentationLevel = 1
        menu.addItem(item)
      }
    }
    if let running = labels["running"] {
      menu.addItem(.separator())
      let item = NSMenuItem(title: running, action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
    }
    menu.addItem(.separator())
    menu.addItem(action(labels["quit"] ?? "Quit", #selector(quitChosen)))
    return menu
  }

  private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
    item.target = self
    return item
  }

  @objc private func showChosen() { open(nil) }

  @objc private func agentChosen(_ sender: NSMenuItem) {
    open(sender.representedObject as? String)
  }

  /// Quits as ⌘Q does: the app asks first, in its window.
  @objc private func quitChosen() {
    showWindow()
    NSApp.terminate(nil)
  }

  /// The logo in the menu bar, a template the system draws light or dark
  /// as the bar is: the 56×42 pixel face of Subtract.svg, 16pt wide, its cells
  /// on whole pixels; with [dot], a dot at its top right, cut out of it.
  static func trayImage(dot: Bool) -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size)
    for scale in [1, 2, 3] {
      guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 18 * scale, pixelsHigh: 18 * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
      else { continue }
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
      if let context = NSGraphicsContext.current?.cgContext {
        drawTray(in: context, pixels: CGFloat(18 * scale), dot: dot)
      }
      NSGraphicsContext.restoreGraphicsState()
      // In points only once drawn: a context made for a rep of a size
      // draws in its points, not its pixels.
      rep.size = size
      image.addRepresentation(rep)
    }
    image.isTemplate = true
    return image
  }

  /// The logo, filled, in its own 56×42 units (Subtract.svg): its rows,
  /// then its eyes, which are cut out of them.
  static let logoRows: [CGRect] = [
    CGRect(x: 14, y: 0, width: 28, height: 7),
    CGRect(x: 7, y: 7, width: 42, height: 7),
    CGRect(x: 0, y: 14, width: 56, height: 21),
    CGRect(x: 7, y: 35, width: 42, height: 7),
  ]
  static let logoEyes: [CGRect] = [
    CGRect(x: 14, y: 21, width: 8, height: 7),
    CGRect(x: 35, y: 21, width: 8, height: 7),
  ]

  /// Draws the tray icon into a square of [pixels] (18pt of them), from its
  /// top left.
  private static func drawTray(in context: CGContext, pixels: CGFloat, dot: Bool) {
    let unit = pixels / 18
    // Flipped, as the logo is drawn: from the top left.
    context.translateBy(x: 0, y: pixels)
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(NSColor.black.cgColor)
    // 16pt wide from 1pt in, 12pt high from 3pt down: centered, on whole
    // pixels.
    let k = 16 * unit / 56
    func snapped(_ cell: CGRect) -> CGRect {
      let x0 = (unit + cell.minX * k).rounded()
      let y0 = (3 * unit + cell.minY * k).rounded()
      let x1 = (unit + cell.maxX * k).rounded()
      let y1 = (3 * unit + cell.maxY * k).rounded()
      return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
    context.fill(logoRows.map(snapped))
    for eye in logoEyes { context.clear(snapped(eye)) }
    guard dot else { return }
    let center = CGPoint(x: 15.5 * unit, y: 2.5 * unit)
    context.setBlendMode(.clear)
    context.fillEllipse(in: CGRect(
      x: center.x - 3.5 * unit, y: center.y - 3.5 * unit,
      width: 7 * unit, height: 7 * unit))
    context.setBlendMode(.normal)
    context.fillEllipse(in: CGRect(
      x: center.x - 2.5 * unit, y: center.y - 2.5 * unit,
      width: 5 * unit, height: 5 * unit))
  }
}
