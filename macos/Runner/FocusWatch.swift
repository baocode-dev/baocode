import Cocoa

/// Writes to the event log (`[focus]`) who took the front from the app when
/// it went in a way no switch to another app goes: the main window still
/// key, or the front taken by an app with no windows of its own to show
/// (an input method, the Dock), or by no app. With it, the windows on top
/// of the main window (whose process, their layer, place and opacity): what
/// covers it, when the system says it is out of sight while it is there.
///
/// For 711AFV0C / QWC9FB1T (Intel Mac, macOS 15.7.7, the system's Pinyin):
/// a space that commits Chinese, the app is told at once it is inactive
/// and hidden (Flutter then draws no frames), its window staying key; clicks
/// on it neither reach Flutter nor bring the app back, the cursor an arrow
/// over the composer, until the user switches to another app and back.
/// The log had the lifecycle only, not who had the front.
///
/// A switch to another app writes nothing: the window resigns key with it.
final class FocusWatch {
  static let shared = FocusWatch()

  /// How long after the app leaves the front it is looked at: the app the
  /// system activates is known a moment after.
  static let settle: TimeInterval = 0.5

  /// The most lines a run writes.
  static let maxLines = 100

  private weak var window: NSWindow?
  private var started = false
  private var lines = 0

  /// The last app the system said it activated, but this one, and when.
  private var activated: (app: NSRunningApplication, at: Date)?

  /// When the app left the front in the way written, until it is back.
  private var odd: Date?

  /// Starts watching [window], the main window, once. From the main thread.
  func start(window: NSWindow) {
    self.window = window
    if started { return }
    started = true
    let center = NotificationCenter.default
    center.addObserver(
      forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.resigned() }
    center.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.becameActive() }
    center.addObserver(
      forName: NSApplication.didChangeOcclusionStateNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.occlusionChanged() }
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] notification in
      guard
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
          as? NSRunningApplication,
        app.processIdentifier != getpid()
      else { return }
      self?.activated = (app, Date())
    }
  }

  private func resigned() {
    let left = Date()
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle) { [weak self] in
      guard let self, !NSApp.isActive, let window = self.window else { return }
      let front = NSWorkspace.shared.frontmostApplication
      let foreign = front.map { $0.processIdentifier != getpid() } ?? false
      let regular = front?.activationPolicy == .regular
      guard window.isKeyWindow || !foreign || !regular else { return }
      self.odd = left
      var parts = [
        "left the front, the window still \(window.isKeyWindow ? "key" : "not key")",
        "front: \(Self.describe(front))",
      ]
      if let (app, at) = self.activated, app != front, at >= left.addingTimeInterval(-1) {
        parts.append("activated: \(Self.describe(app))")
      }
      if let owner = NSWorkspace.shared.menuBarOwningApplication, owner != front {
        parts.append("menu bar: \(Self.describe(owner))")
      }
      parts.append(Self.sight(window))
      parts.append("over it: \(Self.windowsOver(window))")
      parts.append("own windows: \(Self.ownWindows())")
      self.write(parts.joined(separator: "; "))
    }
  }

  private func becameActive() {
    guard let since = odd else { return }
    odd = nil
    write(String(format: "back at the front after %.1f s", Date().timeIntervalSince(since)))
  }

  /// Told out of sight while the window is up and key: what is over it.
  private func occlusionChanged() {
    guard let window, !NSApp.occlusionState.contains(.visible), window.isVisible,
          !window.isMiniaturized, window.isKeyWindow
    else { return }
    write(
      "out of sight, the window key; \(Self.sight(window)); "
        + "front: \(Self.describe(NSWorkspace.shared.frontmostApplication)); "
        + "over it: \(Self.windowsOver(window)); own windows: \(Self.ownWindows())")
  }

  private func write(_ message: String) {
    guard lines < Self.maxLines else { return }
    lines += 1
    HangWatchdog.shared.appendEvent("focus", message)
  }

  private static func describe(_ app: NSRunningApplication?) -> String {
    guard let app else { return "none" }
    if app.processIdentifier == getpid() { return "this app" }
    let name = app.localizedName ?? "?"
    let policy: String
    switch app.activationPolicy {
    case .regular: policy = "regular"
    case .accessory: policy = "accessory"
    case .prohibited: policy = "background"
    @unknown default: policy = "policy \(app.activationPolicy.rawValue)"
    }
    return "\(name) (\(app.bundleIdentifier ?? "no bundle id"), pid \(app.processIdentifier), \(policy))"
  }

  /// The app's own windows by class, the most first, with how many of each
  /// are visible and which is key: AppKit's text cursor indicator
  /// (TUINSWindow, macOS 14 on) is said to leave its windows behind.
  private static func ownWindows() -> String {
    var counts: [String: (all: Int, visible: Int, key: Bool)] = [:]
    for window in NSApp.windows {
      let name = String(describing: type(of: window))
      var count = counts[name] ?? (0, 0, false)
      count.all += 1
      if window.isVisible { count.visible += 1 }
      if window.isKeyWindow { count.key = true }
      counts[name] = count
    }
    return counts.sorted { $0.value.all > $1.value.all }.prefix(8).map {
      "\($0.key) \($0.value.all) (\($0.value.visible) visible\($0.value.key ? ", key" : ""))"
    }.joined(separator: ", ")
  }

  private static func sight(_ window: NSWindow) -> String {
    let app = NSApp.occlusionState.contains(.visible) ? "visible" : "not visible"
    let own = window.occlusionState.contains(.visible) ? "visible" : "not visible"
    return "app \(app), window \(own)"
  }

  /// The on-screen windows above [window] that cover some of it: each one's
  /// process, layer, place and opacity. Their titles need a permission the
  /// app does not have, and are not wanted.
  private static func windowsOver(_ window: NSWindow) -> String {
    guard window.windowNumber > 0 else { return "unknown" }
    let id = CGWindowID(window.windowNumber)
    guard
      let own = (CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]])?
        .first,
      let ownBounds = bounds(own),
      let above = CGWindowListCopyWindowInfo(
        [.optionOnScreenAboveWindow, .excludeDesktopElements], id) as? [[String: Any]]
    else { return "unknown" }
    let over = above.compactMap { info -> String? in
      guard let rect = bounds(info), rect.intersects(ownBounds) else { return nil }
      let owner = info[kCGWindowOwnerName as String] as? String ?? "?"
      let pid = info[kCGWindowOwnerPID as String] as? Int ?? 0
      let layer = info[kCGWindowLayer as String] as? Int ?? 0
      // The menu bar and its icons, over a window up against it.
      let menuBar = Int(CGWindowLevelForKey(.mainMenuWindow))
      let status = Int(CGWindowLevelForKey(.statusWindow))
      if (layer == menuBar || layer == status) && rect.height <= 40 { return nil }
      let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
      return String(
        format: "%@ (pid %d, layer %d, %.0f,%.0f %.0fx%.0f, alpha %.2f)",
        owner, pid, layer, rect.minX, rect.minY, rect.width, rect.height, alpha)
    }
    if over.isEmpty { return "none" }
    let shown = over.prefix(8).joined(separator: ", ")
    return over.count > 8 ? "\(shown), \(over.count - 8) more" : shown
  }

  private static func bounds(_ info: [String: Any]) -> CGRect? {
    guard let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
          let rect = CGRect(dictionaryRepresentation: dictionary),
          rect.width > 0, rect.height > 0
    else { return nil }
    return rect
  }
}
